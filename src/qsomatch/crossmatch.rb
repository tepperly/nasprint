#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#

require_relative 'ContestDB'
require 'jaro_winkler'

CW_MAPPING = {
  "A" => ".-",
  "B" => "-...",
  "C" => "-.-.",
  "D" => "-..",
  "E" => ".",
  "F" => "..-.",
  "G" => "--.",
  "H" => "...",
  "I" => "..",
  "J" => ".---",
  "K" => "-.-",
  "L" => ".-..",
  "M" => "--",
  "N" => "-.",
  "O" => "---",
  "P" => ".--.",
  "Q" => "--.-",
  "R" => ".-.",
  "S" => "...",
  "T" => "-",
  "U" => "..-",
  "V" => "...-",
  "W" => ".--",
  "X" => "-..-",
  "Y" => "-.--",
  "Z" => "--..",
  " " => "  ",
  "1" => ".----",
  "2" => "..---",
  "3" => "...--",
  "4" => "....-",
  "5" => ".....",
  "6" => "-....",
  "7" => "--...",
  "8" => "---..",
  "9" => "----.",
  "0" => "-----",
  "." => ".-.-.-",
  "?" => "..--..",
  "," => "--..--",
  ":" => "---...",
  "'" => ".----.",
  "-" => "-....-",
  "/" => "-..-.",
  "@" => ".--.-.",
  "=" => "-...-"
}
CW_MAPPING.default = " "

def toCW(str)
  result = ""
  space = false
  str.upcase.each_char { |char|
    if space
      result << " "
    end
    result << CW_MAPPING[char]
  }
  result
end

class StringSpace
  def initialize
    @space = Hash.new
  end

  def register(str)
    if @space.has_key?(str)
      return @space[str]
    else
      @space[str] = str
    end
    return str
  end
end

def hillFunc(value, full, none)
  value = value.abs
  (value <= full) ? 1.0 : 
    ((value >= none) ? 0 : (1.0 - ((value.to_f - full)/(none.to_f - full))))
end

class Exchange
  @@stringspace = StringSpace.new

  def initialize(basecall, callsign, serial, mult, location)
    @basecall = @@stringspace.register(basecall)
    @callsign = @@stringspace.register(callsign)
    @serial = serial.to_i
    @mult = @@stringspace.register(mult)
    @location = @@stringspace.register(location)
  end

  attr_reader :basecall, :callsign, :serial, :mult, :location

  def crossProbs(l1, l2, isCW)
    result = Array.new
    l1.each { |s1|
      l2.each { |s2|
        result << JaroWinkler.distance(s1, s2)
        if isCW
          result << JaroWinkler.distance(toCW(s1),toCW(s2))
        end
      }
    }
    result.max
  end

  def probablyMatch(exch, isCW = false)
    cp = callProb(exch, isCW)
    if @mult == @location
      m1 = [ @mult ]
    else
      m1 = [ @mult, @location ]
    end
    if exch.mult == exch.location
      m2 = [ exch.mult ]
    else
      m2 = [ exch.mult, exch.location ]
    end
     return cp*
      [ hillFunc(@serial-exch.serial, 1, 10),
      JaroWinkler.distance(@serial.to_s,exch.serial.to_s),
      isCW ? JaroWinkler.distance(toCW(@serial.to_s),toCW(exch.serial.to_s)) : 0].max *
      crossProbs(m1, m2, isCW), cp
  end

  def fullMatch?(exch)
    @basecall == exch.basecall and 
      ((@serial - exch.serial).abs <= 1) and
      @mult == exch.mult
  end

  def callProb(exch, isCW=false)
    if @basecall == @callsign
      l1 = [ @basecall ]
    else
      l1 = [ @basecall, @callsign ]
    end
    if exch.basecall == exch.callsign
      l2 = [ exch.basecall ]
    else
      l2 = [ exch.basecall, exch.callsign ]
    end
    return crossProbs(l1, l2, isCW)
  end

  def to_s
    "%-6s %-7s %4d %-4s %-4s" % [@basecall, @callsign, @serial,
                                  @mult, @location]
  end

end

class QSO
  def initialize(id, logID, freq, band, mode, datetime, sent, recvd)
    @id = id
    @logID = logID
    @freq = freq
    @band = band
    @mode = mode
    @datetime = datetime
    @sent = sent
    @recvd = recvd
  end

  attr_reader :id, :logID, :freq, :band, :mode, :datetime, :sent, :recvd

  def probablyMatch(qso)
    sp, scp = @sent.probablyMatch(qso.recvd)
    rp, rcp = @recvd.probablyMatch(qso.sent)
    return ((qso.logID == @logID) ? 0 :
            ( sp * rp *
              ((@band == qso.band) ? 1.0 : 0.90) *
              ((@mode == qso.mode) ? 1.0 : 0.90) *
              hillFunc(@datetime - qso.datetime, 15*60, 24*60*60))), scp*rcp
  end

  def callProbability(qso)
    isCW = (("CW" == @mode) or ("CW" == qso.mode))
    return @sent.callProb(qso.recvd, isCW) *
        @recvd.callProb(qso.sent, isCW)
  end

  def fullMatch?(qso, time)
    @band == qso.band and @mode == qso.mode and 
      @mode == qso.mode and
      (qso.datetime >= (@datetime - 60*time) and
       qso.datetime <= (@datetime + 60*time)) and
      @recvd.fullMatch?(qso.sent)
  end

  def to_s(reversed = false)
    ("%7d %5d %5d %-4s %-2s %s " % [@id, @logID, @freq, @band, @mode,
                                  @datetime.strftime("%Y-%m-%d %H%M")]) +
      (reversed ?  (@recvd.to_s + " " + @sent.to_s):
       (@sent.to_s + " " + @recvd.to_s))
  end

  def basicLine
    ("%5d %-4s %-2s %s " % [@freq, @band, @mode,
                                  @datetime.strftime("%Y-%m-%d %H%M")]) +
      @sent.to_s + " " + @recvd.to_s
  end

  def self.lookupQSO(db, id, timeadj=0)
    res = db.query("select q.logID, q.frequency, q.band, q.fixedMode, q.time, " +
                   ContestDB.EXCHANGE_FIELD_TYPES.keys.sort.map { |f| "q.sent" + f }.join(", ") + ", " +
                   ContestDB.EXCHANGE_FIELD_TYPES.keys.sort.map { |f| "q.recvd" + f }.join(", ") + " , " +
                   ContestDB.EXCHANGE_EXTRA_FIELD_TYPES.keys.sort.map { |f| "qe.sent" + f}.join(", ") + ", " +
                   ContestDB.EXCHANGE_EXTRA_FIELD_TYPES.keys.sort.map { |f| "qe.recvd" + f}.join(", ") +
                   " from QSO as q join QSOExtra as qe where q.id = #{id} and qe.id = #{id} limit 1;")
    res.each(:as => :array) { |row|
      sent = Exchange.new(db.baseCall(row[5]), row[13], row[8], db.lookupMultiplierByID(row[7]),
                          row[14])
      recvd = Exchange.new(db.baseCall(row[9]), row[15], row[14], db.lookupMultiplierByID(row[11]),
                           row[16])
      return QSO.new(id, row[0].to_i, row[1], row[2], row[3], row[4]+timeadj,
                     sent, recvd)
    }
    nil
  end
end

class Match
  include Comparable
  def initialize(q1, q2, metric=0, metric2=0)
    @q1 = q1
    @q2 = q2
    @metric = metric
    @metric2 = metric2
  end

  attr_reader :metric, :metric2

  def qsoLines 
    return @q1.basicLine, @q2.basicLine
  end

  def <=>(match)
      @metric <=> match.metric
  end

  def to_s
    "Metric: #{@metric} #{@metric2}\n" + @q1.to_s + "\n" + (@q2  ? @q2.to_s(true): "nil") + "\n"
  end

  def record(db, time)
    res = db.query("select count(*) from QSO where id in (#{@q1.id}, #{@q2.id}) and matchType = 'None' and matchID is NULL;")
    res.each(:as => :array) { |row|
      if row[0].to_i == 2
        type1 = @q1.fullMatch?(@q2, time) ?  "Full" : "Partial"
        type2 = @q2.fullMatch?(@q1, time) ? "Full" : "Partial"
        db.query("update QSO set matchID = #{@q2.id}, matchType = '#{type1}' where id = #{@q1.id} and matchType = 'None' and matchID is NULL limit 1;")
        db.query("update QSO set matchID = #{@q1.id}, matchType = '#{type2}' where id = #{@q2.id} and matchType = 'None' and matchID is NULL limit 1;")
        return type1, type2
      end
    }
    return nil
  end
end

class CrossMatch
  PERFECT_TIME_MATCH = 15       # in minutes
  MAXIMUM_TIME_MATCH = 24*60    # one day in minutes

  def initialize(db, contestID, cdb)
    @db = db
    @cdb = cdb
    @contestID = contestID.to_i
    @logs = cdb.logsForContest(contestID)
  end

  def logSet
    return "(" + @logs.join(",") + ")"
  end

  def restartMatch
    @db.query("update QSO set matchID = NULL, matchType = 'None', comment = NULL where logID in #{logSet};")
    @db.query("update Log set clockadj = 0, verifiedscore = null, verifiedQSOs = null, verifiedMultipliers = null where id in #{logSet};")
  end

  def notMatched(qso)
    return "#{qso}.matchID is null and #{qso}.matchType = \"None\""
  end

  def timeMatch(t1, t2, timediff)
    return "(abs(timestampdiff(MINUTE," + t1 + ", " + t2 + ")) <= " + timediff.to_s + ")"
  end

  def qsoExactMatch(q1,q2)
    return q1 + ".band = " + q2 + ".band and " + q1 + ".fixedMode = " +
      q2 + ".fixedMode"
  end

  def qsoMatch(q1, q2, timediff=PERFECT_TIME_MATCH)
    return timeMatch("q1.time", "q2.time", timediff) 
  end

  def serialCmp(s1, s2, range)
    return "(" + s1 + " between (" + s2 + " - " + range.to_s +
      ") and (" + s2 + " + " + range.to_s + "))"
  end

  def exchangeExactMatch(e1, e2)
    return e1 + "_callID = " + e2 + "_callID and " +
      e1 + "_multiplierID = " + e2 + "_multiplierID"
  end

  def exchangeMatch(e1, e2)
    return serialCmp(e1 + "_serial", e2 + "_serial", 1)
  end

  def qsosFromDB(res, qsos = Array.new)
    res.each(:as => :array) { |row|
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10]) 
      r = Exchange.new(row[11], row[12], row[13], row[14], row[15])
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    row[5], s, r)
      qsos << qso
    }
    qsos
  end

  def printDupeMatch(id1, id2)
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, ms.abbrev, qe.sent_location, cr.basecall, qe.recvd_callsign, q.recvd_serial, mr.abbrev, qe.recvd_location " +
                    " from QSO as q join QSOExtra as qe on qe.id = q.id, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
                    linkCallsign("q.sent_","cs") + " and " + linkCallsign("q.recvd_", "cr") + " and " +
                    linkMultiplier("q.sent_","ms") + " and " + linkMultiplier("q.recvd_", "mr") + " and " +
                    " q.id in (#{id1}, #{id2});"
    res = @db.query(queryStr)
    qsos = qsosFromDB(res)
    if qsos.length != 2
      ids = [id1, id2]
      qsos.each { |q|
        ids.delete(q.id)
      }
      queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, 'NULL', qe.sent_location, cr.basecall, qe.recvd_callsign, q.recv_serial, 'NULL', qe.recvd_location " +
                    " from QSO as q, Callsign as cr, Callsign as cs where " +
                    linkCallsign("q.sent_","cs") + " and " + linkCallsign("q.recvd_", "cr") + " and " +
                    " q.id in (#{ids.join(',')});"
      qsos = qsosFromDB(@db.query(queryStr), qsos)
      if qsos.length != 2
        print "query #{queryStr}\n"
        print "Match of QSOs #{id1} #{id2} produced #{qsos.length} results\n"
        return nil
      end
    end
    pm, cp = qsos[0].probablyMatch(qsos[1])
    m = Match.new(qsos[0], qsos[1], pm, cp)
    print m.to_s + "\n"
  end
 
  def linkQSOs(matches, match1, match2, quiet=true)
    count1 = 0
    count2 = 0
    if not quiet
      print "linkQSOs #{match1} #{match2}\n"
    end
    matches.each(:as => :array) { |row|
      chk = @db.query("select q1.id, q2.id from QSO as q1, QSO as q2 where q1.id = #{row[0].to_i} and q2.id = #{row[1].to_i} and q1.matchID is null and q2.matchID is null and q1.matchType = 'None' and q2.matchType = 'None' limit 1;")
      found = false
      chk.each(:as => :array) { |chkrow|
        found = true
        @db.query("update QSO set matchID = #{row[1].to_i}, matchType = '#{match1}' where id = #{row[0].to_i} and matchID is null and matchType = 'None' limit 1;")
        count1 = count1 + 1
        @db.query("update QSO set matchID = #{row[0].to_i}, matchType = '#{match2}' where id = #{row[1].to_i} and matchID is null and matchType = 'None' limit 1;")
        if not quiet
          printDupeMatch(row[0].to_i, row[1].to_i)
        end
        count2 = count2 + 1
      }
      if not found
        @db.query("update QSO set matchType = 'Dupe' where matchID is null and matchType = 'None' and id in (#{row[0].to_i}, #{row[1].to_i}) limit 2;")
        if not quiet
          printDupeMatch(row[0].to_i, row[1].to_i)
        end
      end
    }
    return count1, count2
  end

  def perfectMatch(timediff = PERFECT_TIME_MATCH, matchType="Full")
    print "Staring perfect match test phase 1: #{Time.now.to_s}\n"
    queryStr = "select q1.id, q2.id from QSO as q1 join QSO as q2 " +
      " on (" +  exchangeExactMatch("q1.recvd", "q2.sent") + " and " +
      exchangeExactMatch("q2.recvd", "q1.sent") + " and " +
      qsoExactMatch("q1", "q2") +
      ") where " +
      "q1.logID in " + logSet + " and q2.logID in " + logSet + " and " +
      "q1.logID != q2.logID and q1.id < q2.id and " +
      exchangeMatch("q1.recvd", "q2.sent") + " and " +
      exchangeMatch("q2.recvd", "q1.sent") + " and " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      qsoMatch("q1", "q2", timediff) +
      " order by (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.recvd_serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print queryStr + "\n"
    @db.query("explain " + queryStr).each(:as => :array) { |row|
      print row.join(", ") + "\n"
    }
    $stdout.flush
    num1, num2 = linkQSOs(@db.query(queryStr), matchType, matchType, true)
    num1 = num1 + num2
    print "Ending perfect match test: #{Time.now.to_s}\n"
    return num1
  end

  def partialMatch(timediff = PERFECT_TIME_MATCH, fullType="Full",  partialType="Partial")
    queryStr = "select q1.id, q2.id from QSO as q1 join QSO as q2 on (" +
      exchangeExactMatch("q1.recvd", "q2.sent") + " and " +
      qsoExactMatch("q1", "q2") + " and q2.recvd_callID = q1.sent_callID )" +
      "where " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      "q1.logID in " + logSet + " and q2.logID in " + logSet +
      " and q1.logID != q2.logID " +
      " and " + qsoMatch("q1", "q2", timediff) + " and " +
      exchangeMatch("q1.recvd", "q2.sent") +
      " order by (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.sent_serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print "Partial match test phase 1: #{Time.now.to_s}\n"
    print queryStr + "\n"
    @db.query("explain " + queryStr).each(:as => :array) { |row|
      print row.join(", ") + "\n"
    }
    $stdout.flush
    full1, partial1 = linkQSOs(@db.query(queryStr), fullType, partialType, true)
    print "Partial match end: #{Time.now.to_s}\n"
    return full1, partial1
  end



  def chooseType(str, num1, num2)
      if str == "TimeShiftFull"
        return "Full", num1 + 1, num2
      else
        return "Partial", num1, num2 + 1
      end
  end
  
  def resolveShifted
    num1 = 0
    num2 = 0
    queryStr = "select q1.id, q1.matchType, q2.id, q2.matchType from QSO as q1, QSO as q2, Log as l1, Log as l2 where q1.matchType in ('TimeShiftFull', 'TimeShiftPartial') and q1.matchID = q2.id and q1.id = q2.matchID and q2.matchType in ('TimeShiftFull', 'TimeShiftPartial') and q1.id < q2.id and l1.id = q1.logID and l2.id = q2.logID and l1.contestID = #{@contestID} and l2.contestID = #{@contestID} and DATE_ADD(q1.time, interval l1.clockadj second) between DATE_SUB(DATE_ADD(q2.time, interval l2.clockadj second), interval #{PERFECT_TIME_MATCH} minute) and DATE_ADD(DATE_ADD(q2.time, interval l2.clockadj second), interval #{PERFECT_TIME_MATCH} minute) order by q1.id asc;"
    res = @db.query(queryStr) 
    res.each(:as => :array) { |row|
      oneType, num1, num2 = chooseType(row[1], num1, num2)
      twoType, num1, num2 = chooseType(row[3], num1, num2)
      @db.query("update QSO set matchType='#{oneType}' where id = #{row[0].to_i} limit 1;")
      @db.query("update QSO set matchType='#{twoType}' where id = #{row[2].to_i} limit 1;")
    }
    @db.query("update QSO set matchType='Partial' where matchType in ('TimeShiftFull', 'TimeShiftPartial') and logID in #{logSet};")
    num2 = num2 + @db.affected_rows
    return num1, num2
  end

  def ignoreDups
    count = 0
    queryStr = "select distinct q3.id from QSO as q1, QSO as q2, QSO as q3 where q1.matchID is not null and q1.matchType in ('Partial', 'Full') and q1.logID in #{logSet} and q2.matchID is not null and q2.matchType in ('Partial', 'Full') and q2.logID in #{logSet} and q2.id = q1.matchID and q1.band = q2.band and q3.band = q1.band and q1.logID = q3.logID and q3.matchID is null and q3.matchType = 'None' and q2.sent_callID = q3.recvd_callID;"
    res = @db.query(queryStr)
    res.each(:as => :array) { |row|
      @db.query("update QSO set matchType = 'Dupe' where id = #{row[0].to_i} and matchType = 'None' and matchID is null limit 1;")
      count = count + @db.affected_rows
    }
    count
  end
  
  def markNIL
    count = 0
    queryStr = "select q.id from QSO as q, Callsign as c where q.matchID is null and q.matchType = 'None' and q.logID in #{logSet} and q.recvd_callID = c.id and c.logrecvd;"
    res = @db.query(queryStr)
    res.each(:as => :array) { |row|
      @db.query("update QSO set matchType = 'NIL' where id = #{row[0].to_i} and matchType = 'None' and matchID is null limit 1;")
      count = count + @db.affected_rows
    }
    count
  end


  def basicMatch(timediff = PERFECT_TIME_MATCH)
    queryStr = "select q1.id, q2.id from QSO as q1 join QSOExtra as qe1 on q1.id = qe1.id, QSO as q2 join QSOExtra as qe2 on q2.id = qe2.id where " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID < q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    " (qe1.sent_callsign = qe2.recvd_callsign or q1.sent_callID = q2.recvd_callID) and " +
                    " (q2.sent_callID = q1.recvd_callID or qe2.sent_callsign = qe1.recvd_callsign) " +
                    " order by (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.sent_serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    return linkQSOs(@db.query(queryStr), 'Partial', 'Partial', true)
  end

  def hillFunc(quantity, fullrange, zerorange)
    "(if(abs(#{quantity}) <= #{fullrange},1.0,if(abs(#{quantity}) >= #{zerorange},0.0,1.0-((abs(#{quantity})-#{fullrange})/(#{zerorange}-#{fullrange})))))"
  end

  def probFunc(q1,q2,s1,s2,r1,r2,cs1,cs2,cr1,cr2,mr1,mr2,ms1,ms2)
    return hillFunc("timestampdiff(MINUTE,#{q1}.time,#{q2}.time)", 15, 60) +
      "*jaro_winkler_similarity(#{cs1}.basecall, #{cr2}.basecall)*" +
      "jaro_winkler_similarity(#{cs2}.basecall, #{cr1}.basecall)*" +
      hillFunc("#{s1}.serial - #{r2}.serial", 1, 10) + "*" +
      hillFunc("#{s2}.serial - #{r1}.serial", 1, 10) + "*" +
      "jaro_winkler_similarity(#{ms1}.abbrev,#{mr2}.abbrev)*" +
      "jaro_winkler_similarity(#{ms2}.abbrev,#{mr1}.abbrev)"
  end

  def linkCallsign(exch, call)
    return "#{exch}_callID = #{call}.id"
  end

  def linkMultiplier(exch, mult)
    return "#{exch}_multiplierID = #{mult}.id"
  end

  def alreadyPaired?(m)
    line1, line2 = m.qsoLines
    line1 = @db.escape(line1)
    line2 = @db.escape(line2)
    res = @db.query("select ismatch from Pairs where (line1 = \"#{line1}\" and line2 = \"#{line2}\") or (line1 = \"#{line2}\" and line2 = \"#{line1}\") limit 1;")
    res.each(:as => :array) { |row|
      return row[0] == 1 ? "YES" : "NO"
    }
    return nil
  end

  def recordPair(m, matched)
    line1, line2 = m.qsoLines
    @db.query("insert into Pairs (contestID, line1, line2, ismatch) values (#{@contestID}, \"#{@db.escape(line1)}\", \"#{@db.escape(line2)}\", #{matched ? 1 : 0});")
  end

  def probMatch
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, ms.abbrev, qe.sent_location, cr.basecall, qe.recvd_callsign, q.recvd_serial, mr.abbrev, qe.recvd_location " +
      " from QSO as q join QSOExtra qe on q.id = qe.id, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
      linkCallsign("q.sent","cs") + " and " + linkCallsign("q.recvd", "cr") + " and " +
      linkMultiplier("q.sent","ms") + " and " + linkMultiplier("q.recvd", "mr") + " and " +
      notMatched("q") + " and " +
      "q.logID in " + logSet + " " +
      "order by q.id asc;"
    res = @db.query(queryStr)
    qsos = Array.new
    res.each(:as => :array) { |row|
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10])
      r = Exchange.new(row[11], row[12], row[13], row[14], row[15])
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    row[5], s, r)
      qsos << qso
    }
    res = nil
    print "#{qsos.length} unmatched QSOs read in\n"
    print "Starting probability-based cross match: #{Time.now.to_s}\n"
    $stdout.flush
    matches = Array.new
    qsos.each { |q1|
      qsos.each { |q2|
        break if (q2.id >= q1.id)
        if (q1.logID != q2.logID)
          metric, cp = q1.probablyMatch(q2)
          if metric > 0.20
            matches << Match.new(q1, q2, metric, cp)
          end
        end
      }
    }
    print "Done ranking potential matches: #{Time.now.to_s}\n"
    print matches.length.to_s + " possible matches selected\n"
    $stdout.flush
    matches.sort! { |a,b| b <=> a }
    matches.each { |m|
      print m.to_s + "\n"
      if m.metric >= 0.5 and m.metric2 >= 0.8
        matchtypes = m.record(@db, CrossMatch::PERFECT_TIME_MATCH)
        if matchtypes
          print matchtypes.join(" ") + "\n\n"
        end
      else
        answer = alreadyPaired?(m)
        if answer
          if "YES" == answer
            matchtypes = m.record(@db, CrossMatch::PERFECT_TIME_MATCH)
            print matchtypes.join(" ") + "\n\n"
          else
            print "Not a match.\n"
          end
        else
          print "Is this a match (y/n): "
          answer = STDIN.gets
          if [ "Y", "YES" ].include?(answer.strip.upcase)
            matchtypes = m.record(@db, CrossMatch::PERFECT_TIME_MATCH)
            if matchtypes
              print matchtypes.join(" ") + "\n\n"
            end
            recordPair(m, true)
          else
            print "Not a match.\n"
            recordPair(m, false)
          end
        end
      end
    }
  end
end
