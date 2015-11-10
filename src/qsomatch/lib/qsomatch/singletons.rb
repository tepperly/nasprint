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
    @cdb = cdb
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

  def queryCallsigns
    callList = Array.new
    @db.query("select c.id, c.basecall, c.validcall, c.logrecvd, count(*) as num from Callsign as c, QSO as q where c.contestID = ? and q.recvd_callID = c.id group by c.id order by c.basecall asc;", [@contestID]) { |row|
      callList << Call.new(row[0].to_i, row[1], toBool(row[2]), toBool(row[3]), row[4].to_i)
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
      @db.query("update QSOExtra set comment='No received serial number or multiplier for this QSO.' where id = ? limit 1;", [row[0]]) { }
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
  
  MATCHTYPE_ORDERING = {
    'Full' => 0,
    'Bye' => 1,
    'Partial' => 2,
    'PartialBye' => 3,
    'Dupe' => 4,
    'OutsideContest' => 5,
    'Removed' => 6,
    'TimeShiftFull' => 7,
    'TimeShiftPartial' => 8,
    'Unique' => 9,
    'NIL' => 10,
    'None' => 11
  }.freeze

  def retainMostValuable(callID, band, mode, logID)
    print "Log #{@cdb.logCallsign(logID)} has a DUPE\n"
    qsos = Array.new
    @db.query("select id, score, time from QSO where " +
              "logID = ? and band = ? and fixedMode = ? and " +
              "recvd_callID = ? " +
              "order by time asc, id asc;", [logID, band, mode, callID] ) { |row|
      qsos << [ row[0].to_i, row[1], @db.toDateTime(row[2]) ]
    }
    qsos.each { |q|
      print lookupQSO(@db, q[0]).to_s + "\n"
    }
    if (qsos.length > 1)
      qsos.sort! { |x,y| 
        t = y[1] <=> x[1]
        if (t == 0)
          t = (x[2] <=> y[2])
          if (t == 0)
            t = (x[0] <=> y[0])
          end
        end
        t
      }
      # the first element of qsos is the most valuable
      # the following should be turned into dupes
      qsos.shift  # remove the first element to prevent marking it as a dupe
      print "update QSO set matchType = 'Dupe', score=0 where id in (" +
                qsos.map { |i| i[0] }.join(", ") +
                ") limit #{qsos.length};\n"
      @db.query("update QSO set matchType = 'Dupe', score=0 where id in (" +
                qsos.map { |i| i[0] }.join(", ") +
                ") limit #{qsos.length};")
      ar = @db.affected_rows
      print "Rows affected: #{ar}\n"
      return ar
    end
    0
  end

  def finalDupeCheck
    print "Starting final dupe check: #{Time.now.to_s}\n"
    count = 0
    @db.query("select min(q1.id), q1.recvd_callID, q1.band, q1.fixedMode, q1.logID, " + 
              "count(*) as numDupe from QSO as q1, QSO as q2 where " +
              @logIDs.membertest("q1.logID") + " and " + @logIDs.membertest("q2.logID") + 
              " and q1.logID = q2.logID and q1.matchType in ('Full','Bye', 'Partial', 'PartialBye') and " +
              "q2.matchType in ('Full','Bye','Partial', 'PartialBye') and q1.band = q2.band and " +
              "q1.fixedMode = q2.fixedMode and q1.recvd_callID = q2.recvd_callID and " +
              "q1.id < q2.id  and " +
              " q1.sent_multiplierID = q2.sent_multiplierID and " +
              " q1.judged_multiplierID = q2.judged_multiplierID " +
              "group by q1.logID, q1.sent_multiplierID, q1.recvd_callID, " +
              " q1.judged_multiplierID, q1.band, q1.fixedMode having numDupe > 1 " +
              "order by q1.logID asc;") { |row|
      count += retainMostValuable(row[1], row[2], row[3], row[4])
    }
    print "Done final dupe check (#{count} maked as dupes): #{Time.now.to_s}\n"
    count
  end
end
