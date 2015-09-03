#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'jaro_winkler'
require 'crossmatch'

class Call
  def initialize(id, callsign, valid, haveLog, numQSOs)
    @id = id
    @callsign = callsign
    @valid = valid
    @haveLog = haveLog
    @numQSOs = numQSOs
  end
  
  attr_reader :id, :callsign, :valid, :haveLog, :numQSOs

  def to_s
    callsign.to_s
  end
end

class ResolveSingletons
  def initialize(db, contestID, cdb)
    @db = db
    @contestID = contestID
    @logIDs = LogSet.new(cdb.logsForContest(contestID))
    @callsigns = queryCallsigns
    @callFromID = Hash.new
    @callsigns.each { |call|
      @callFromID[call.id] = call
    }
  end

  def toBool(val)
    (val and (val.to_i != 0))
  end

  ONE_BY_ONE = /\A[A-Z][0-9][A-Z]\Z/

  def queryCallsigns
    callList = Array.new
    @db.query("select c.id, c.basecall, c.validcall, c.logrecvd, count(*) as num from Callsign as c, QSO as q where c.contestID = ? and q.recvd_callID = c.id group by c.id order by c.basecall asc;", [@contestID]) { |row|
      callList << Call.new(row[0].to_i, row[1], (toBool(row[2]) or ONE_BY_ONE.match(row[1])), toBool(row[3]), row[4].to_i)
    }
    return callList
  end

  def possibleMatches(id, callsign, tolerance = 0.94)
    results = Array.new
    @callsigns.each { |call|
      if call.id != id and call.valid and (call.numQSOs >= 10 or call.haveLog) and JaroWinkler.distance(call.callsign, callsign) >= tolerance
        results << call
      end
    }
    results.empty? ? nil : results
  end

  def farMoreCommon(list, count)
    if list
      sorted = list.sort { |x,y| y.numQSOs <=> x.numQSOs }
      if (sorted[0].numQSOs >= 10) and (sorted[0].numQSOs >= 10*count) and sorted[0].haveLog
        return sorted[0]
      end
    end
    nil
  end

  def exchangeClose(qid, callsign)
    @db.query("select m.abbrev from QSO as q left join Multiplier as m on m.id = q.recvd_multiplierID where q.id = ? limit 1;", [qid]) { |row|
      print "exchangeClose0 #{@contestID} #{callsign}\n"
      print "exchangeClose1 #{row[0]}\n"
      @db.query("select m.abbrev from Callsign as c join Log as l on c.id = l.callID join QSO as q left join Multiplier as m on m.id = q.recvd_multiplierID where l.contestID = ? and c.basecall = ? limit 1;",
                [@contestID.to_i, callsign.to_s]) { |refrow|
        print "exchangeClose2 #{row[0]} #{refrow[0]}\n"
        if refrow[0]
          if JaroWinkler.distance(row[0], refrow[0]) >= 0.92
            return true
          end
        end
      }
    }
    false
  end


  def resolve
    @db.query("select distinct q.id from QSO as q where matchType = 'None' and (q.recvd_multiplierID is null or q.recvd_serial is null);") { |row|
      @db.query("update QSO set matchType = 'Removed'  where id = ? limit 1;", [row[0]]) { }
      @db.query("update QSOExtra set comment='Incomplete exchanged received.' where id = ? limit 1;", [row[0]]) { }
    }
    @db.query("select q.id, q.recvd_callID, q.recvd_serial from QSO as q where " +
                    @logIDs.membertest("q.logID") +
              " and q.matchType = 'None' order by q.id asc;"){ |row|
      call = @callFromID[row[1]]
      if call
        if row[2] >= 10 and call.numQSOs <= 2
          @db.query("update QSO set matchType = 'Unique' where id = ? limit 1;", [row[0]]) { }
          @db.query("update QSOExtra set comment='High serial number a station only worked #{call.numQSOs.to_i} time(s).' where id = ? limit 1;", [row[0]]) { }
        else
          if not call.valid and call.numQSOs <= 5
            # illegal callsign
            list = possibleMatches(call.id, call.callsign)
            if list
              @db.query("update QSO set matchType = 'Removed' where id = ? limit 1;", [row[0]]) { }
              @db.query("update QSOExtra set comment='Busted callsign - potential matches: #{list.join(" ")}.' where id = ? limit 1;", [row[0]]) { }
            else
              @db.query("update QSO set matchType = 'Removed' where id = ? limit 1;", [row[0]]) { }
              @db.query("update QSOExtra set comment='Illegal callsign not close to known participants.' where id = ? limit 1;", [row[0]]) { }
            end
          else
            if call.numQSOs >= 10 or (call.valid and call.numQSOs >= 5)
              @db.query("update QSO set matchType = 'Bye' where id = ? limit 1;", [row[0]]) { }
            else
              list = possibleMatches(call.id, call.callsign)
              mc = farMoreCommon(list, call.numQSOs)
              if mc and exchangeClose(row[0],mc)
                @db.query("update QSO set matchType = 'Removed' where id = ? limit 1;", [row[0]]) { }
                @db.query("update QSOExtra set comment='Busted call - likely match: #{mc.callsign}.'  where id = ? limit 1;", [row[0]]) { }
              else
                @db.query("update QSO set matchType = 'Bye' where id = ? limit 1;", [row[0]]) { }
              end
            end
          end
        end
      else
        @db.query("update QSO set matchType = 'Removed' where id = ? limit 1;", [row[0]]) { }
        @db.query("update QSOExtra set comment='Unknown callsign ID in record.' where id = ? limit 1;", [row[0]]) { }
      end
    }
  end

  def finalDupeCheck
    print "Starting final dupe check: #{Time.now.to_s}\n"
    count = 0
    @db.query("select q1.id, q2.id from QSO as q1, QSO as q2 where " +
                    @logIDs.membertest("q1.logID") + " and " +
                    @logIDs.membertest("q2.logID") +
              " and q1.id < q2.id and q1.logID = q2.logID and q1.matchType in ('Full','Bye') and q2.matchType in ('Full','Bye') and q1.band = q2.band and q1.recvd_callID = q2.recvd_callID order by q1.id;") { |row|
      @db.query("update QSO set matchType = 'Dupe' where id = ? and matchType in ('Full','Bye') limit 1;", [row[1]]) { }
      count = count + @db.affected_rows
    }
    print "Done final dupe check: #{Time.now.to_s}\n"
    count
  end
end
