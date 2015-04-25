#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'jaro_winkler'

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
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
    @logIDs = queryContestLogs
    @callsigns = queryCallsigns
    @callFromID = Hash.new
    @callsigns.each { |call|
      @callFromID[call.id] = call
    }
  end

  def queryContestLogs
    logList = Array.new
    res = @db.query("select id from Log where contestID = #{@contestID} order by id asc;")
    res.each(:as => :array) { |row|
      logList << row[0].to_i
    }
    return logList
  end

  def toBool(val)
    (val and (val.to_i != 0))
  end

  ONE_BY_ONE = /\A[A-Z][0-9][A-Z]\Z/

  def queryCallsigns
    callList = Array.new
    res = @db.query("select c.id, c.basecall, c.validcall, c.logrecvd, count(*) as num from Callsign as c, Exchange as e, QSO as q where c.contestID = #{@contestID} and e.callID = c.id and e.id = q.recvdID group by c.id order by c.basecall asc;")
    res.each(:as => :array) { |row|
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
      sorted = list.sort { |x,y| y.numQSOS <=> x.numQSOs }
      if (sorted[0].numQSOs >= 10) and (sorted[0].numQSOs >= 5*count)
        return sorted[0]
      end
    end
    nil
  end

  def resolve
    res = @db.query("select q.id, e.callID, e.serial from QSO as q, Exchange as e where q.logID in (#{@logIDs.join(", ")}) and q.matchType = 'None' and e.id = q.recvdID order by q.id asc;")
    res.each(:as => :array) { |row|
      call = @callFromID[row[1]]
      if call
        if row[2] >= 10 and call.numQSOs <= 2
          @db.query("update QSO set matchType = 'Unique', comment='High serial number a station only worked #{call.numQSOs} time(s).' where id = #{row[0]} limit 1;")
        else
          if not call.valid and call.numQSOs <= 5
            # illegal callsign
            list = possibleMatches(call.id, call.callsign)
            if list
              @db.query("update QSO set matchType = 'Removed', comment='Busted callsign - potential matches: #{list.join(" ")}.' where id = #{row[0]} limit 1;")
            else
              @db.query("update QSO set matchType = 'Removed', comment='Illegal callsign not close to known participants.' where id = #{row[0]} limit 1;")
            end
          else
            if call.numQSOs >= 10 or (call.valid and call.numQSOs >= 5)
              @db.query("update QSO set matchType = 'Bye' where id = #{row[0]} limit 1;")
            else
              list = possibleMatches(call.id, call.callsign)
              mc = farMoreCommon(list, call.numQSOs)
              if mc
                @db.query("update QSO set matchType = 'Removed', comment='Busted call - likely match: #{mc.callsign}.'  where id = #{row[0]} limit 1;")
              else
                @db.query("update QSO set matchType = 'Bye' where id = #{row[0]} limit 1;")
              end
            end
          end
        end
      else
        @db.query("update QSO set matchType = 'Removed', comment='Unknown callsign ID in record.' where id = #{row[0]} limit 1;")
      end
    }
  end
end
