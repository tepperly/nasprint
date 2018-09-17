#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#

require 'jaro_winkler'
require_relative 'homophone'

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

  def initialize(basecall, callsign, serial, name, mult, location, namecmp)
    @basecall = @@stringspace.register(basecall)
    @callsign = @@stringspace.register(callsign)
    @serial = serial.to_i
    @name = @@stringspace.register(name)
    @mult = @@stringspace.register(mult)
    @location = @@stringspace.register(location)
    @namecmp = namecmp
  end

  attr_reader :basecall, :callsign, :serial, :name, :mult, :location

  def probablyMatch(exch)
    callProb(exch) *
      (@namecmp.namesEqual?(@name, exch.name) ? 1.0 :
       JaroWinkler.distance(@name, exch.name)) *
      [ hillFunc(@serial-exch.serial, 1, 10),
        JaroWinkler.distance(@serial.to_s,exch.serial.to_s) ].max *
      [ JaroWinkler.distance(@mult, exch.mult),
        JaroWinkler.distance(@location, exch.location) ].max
  end

  def fullMatch?(exch)
    @basecall == exch.basecall and 
      ((@serial - exch.serial).abs <= 1) and
      @mult == exch.mult and 
      @namecmp.namesEqual?(@name, exch.name)
  end

  def callProb(exch)
    [ JaroWinkler.distance(@basecall, exch.basecall),
      JaroWinkler.distance(@callsign, exch.callsign) ].max
  end

  def to_s
    "%-6s %-7s %4d %-12s %-2s %-4s" % [@basecall, @callsign, @serial,
                                  @name, @mult, @location]
  end

  def self.lookupExchange(db, id, namecmp)
    res = db.query("select c.basecall, e.callsign, e.serial, e.name, e.location, e.multiplierID from Exchange as e join Callsign as c on c.id = e.callID where e.id = #{id} limit 1;")
    res.each(:as => :array) { |row|
      if row[5]
        mq = db.query("select abbrev from Multiplier where id = #{row[5]} limit 1;")
        mq.each(:as => :array) { |mrow|
          return Exchange.new(row[0], row[1], row[2].to_i, row[3], mrow[0], row[4], namecmp)
        }
      end
      return Exchange.new(row[0], row[1], row[2].to_i, row[3], nil, row[4], namecmp)
    }
    print "Unable to find exchange #{id}\n"
    nil
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
    (qso.logID == @logID) ? 0 :
      (@sent.probablyMatch(qso.recvd) *
       @recvd.probablyMatch(qso.sent) *
       ((@band == qso.band) ? 1.0 : 0.85) *
       hillFunc(@datetime - qso.datetime, 15*60, 24*60*60))
  end

  def callProbability(qso)
    @sent.callProb(qso.recvd) *
      @recvd.callProb(qso.sent)
  end

  def fullMatch?(qso, time)
    @band == qso.band and @mode == qso.mode and 
# do not require time match
#      (qso.datetime >= (@datetime - 60*time) and qso.datetime <= (@datetime + 60*time)) and
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

  def self.lookupQSO(db, id, namecmp, timeadj=0)
    res = db.query("select logID, frequency, band, fixedMode, time, sentID, recvdID from QSO where id = #{id} limit 1;")
    res.each(:as => :array) { |row|
      sent = Exchange.lookupExchange(db, row[5].to_i, namecmp)
      recvd = Exchange.lookupExchange(db, row[6].to_i, namecmp)
      if sent and recvd
        return QSO.new(id, row[0].to_i, row[1], row[2], row[3], row[4]+timeadj,
                       sent, recvd)
      end
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
    @namecmp = NameCompare.new(db)
  end

  def logSet
    return "(" + @logs.join(",") + ")"
  end

  def restartMatch
    @db.query("update QSO set matchID = NULL, matchType = 'None', comment = NULL where logID in #{logSet};")
    @db.query("update Log set clockadj = 0, verifiedscore = null, verifiedQSOs = null, verifiedMultipliers = null where id in #{logSet};")
  end

  def linkConstraints(qso, sent, recvd)
    return "#{qso}.recvdID = #{recvd}.id and #{qso}.sentID = #{sent}.id"
  end

  def notMatched(qso)
    return "#{qso}.matchID is null and #{qso}.matchType = \"None\""
  end

  def timeMatch(t1, t2, timediff)
    return "(" + t1 + " between date_sub(" + t2 +", interval " +
      timediff.to_s + " minute) and date_add(" + t2 + ",  interval " +
      timediff.to_s + " minute))"
  end

  def qsoMatch(q1, q2, timediff=PERFECT_TIME_MATCH)
    return q1 + ".band = " + q2 + ".band and " + q1 + ".fixedMode = " +
      q2 + ".fixedMode and " + timeMatch("q1.time", "q2.time", timediff) +
      " and " + timeMatch("q2.time", "q1.time", timediff)
  end

  def serialCmp(s1, s2, range)
    return "(" + s1 + " between (" + s2 + " - " + range.to_s +
      ") and (" + s2 + " + " + range.to_s + "))"
  end

  def exchangeMatch(e1, e2, homophone = nil)
    result = e1 + ".callID = " + e2 + ".callID and " +
      e1 + ".multiplierID = " + e2 + ".multiplierID and "
    if homophone
      result << e1 + ".name = " + homophone + ".name1 and " +
        e2 + ".name = " + homophone + ".name2 and "
    else
      result << e1 + ".name = " + e2 + ".name and "
    end
    return result + serialCmp(e1 + ".serial", e2 + ".serial", 1) + " and " +
      serialCmp(e1 + ".serial", e2 + ".serial", 1)
  end

  def qsosFromDB(res, qsos = Array.new)
    res.each(:as => :array) { |row|
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10], row[11], 
                       @namecmp)
      r = Exchange.new(row[12], row[13], row[14], row[15], row[16], row[17],
                       @namecmp)
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    row[5], s, r)
      qsos << qso
    }
    qsos
  end

  def printDupeMatch(id1, id2)
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, s.callsign, s.serial, s.name, ms.abbrev, s.location, cr.basecall, r.callsign, r.serial, r.name, mr.abbrev, r.location " +
                    " from QSO as q, Exchange as s, Exchange as r, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
                    linkConstraints("q", "s", "r") + " and " +
                    linkCallsign("s","cs") + " and " + linkCallsign("r", "cr") + " and " +
                    linkMultiplier("s","ms") + " and " + linkMultiplier("r", "mr") + " and " +
                    " q.id in (#{id1}, #{id2});"
    res = @db.query(queryStr)
    qsos = qsosFromDB(res)
    if qsos.length != 2
      ids = [id1, id2]
      qsos.each { |q|
        ids.delete(q.id)
      }
      queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, s.callsign, s.serial, s.name, 'NULL', s.location, cr.basecall, r.callsign, r.serial, r.name, 'NULL', r.location " +
                    " from QSO as q, Exchange as s, Exchange as r, Callsign as cr, Callsign as cs where " +
                    linkConstraints("q", "s", "r") + " and " +
                    linkCallsign("s","cs") + " and " + linkCallsign("r", "cr") + " and " +
                    " q.id in (#{ids.join(',')});"
      qsos = qsosFromDB(@db.query(queryStr), qsos)
      if qsos.length != 2
        print "query #{queryStr}\n"
        print "Match of QSOs #{id1} #{id2} produced #{qsos.length} results\n"
        return nil
      end
    end
    m = Match.new(qsos[0], qsos[1], qsos[0].probablyMatch(qsos[1]), qsos[0].callProbability(qsos[1]))
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
    $stdout.flush
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID and q1.id < q2.id and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    qsoMatch("q1", "q2", timediff) + " and " +
                    exchangeMatch("r1", "s2") + " and " +
                    exchangeMatch("r2", "s1") + 
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    num1, num2 = linkQSOs(@db.query(queryStr), matchType, matchType, true)
    num1 = num1 + num2
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Homophone as h where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    exchangeMatch("r1", "s2", "h") + " and " +
                    exchangeMatch("r2", "s1") +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print "Perfect match test phase 2: #{Time.now.to_s}\n"
    $stdout.flush
    num2, num3 = linkQSOs(@db.query(queryStr), matchType, matchType, true)
    num2 = num2 + num3
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Homophone as h1, Homophone as h2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    exchangeMatch("r1", "s2", "h1") + " and " +
                    exchangeMatch("r2", "s1", "h2") + " and q1.id < q2.id " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print "Perfect match test phase 3: #{Time.now.to_s}\n"
    $stdout.flush
    num3, num4 = linkQSOs(@db.query(queryStr), matchType, matchType, true)
    num2 = num2 + num3 + num4
    print "Ending perfect match test: #{Time.now.to_s}\n"
    return num1, num2
  end

  def partialMatch(timediff = PERFECT_TIME_MATCH, fullType="Full",  partialType="Partial")
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    exchangeMatch("r1", "s2") + " and " +
                    " r2.callID = s1.callID " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print "Partial match test phase 1: #{Time.now.to_s}\n"
    $stdout.flush
    full1, partial1 = linkQSOs(@db.query(queryStr), fullType, partialType, true)
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Homophone as h where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    exchangeMatch("r1", "s2", "h") + " and " +
                    " r2.callID = s1.callID " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print "Partial match test phase 2: #{Time.now.to_s}\n"
    $stdout.flush
    full2, partial2 = linkQSOs(@db.query(queryStr), fullType, partialType, true)
    print "Partial match end: #{Time.now.to_s}\n"
    return full1 + full2, partial1 + partial2
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
    queryStr = "select distinct q3.id from QSO as q1, QSO as q2, QSO as q3, Exchange as e2, Exchange as e3 where q1.matchID is not null and q1.matchType in ('Partial', 'Full','Unique') and q1.logID in #{logSet} and q2.matchID is not null and q2.matchType in ('Partial', 'Full') and q2.logID in #{logSet} and q2.id = q1.matchID and q1.id = q2.matchID and q1.band = q2.band and q3.band = q1.band and q1.logID = q3.logID and q3.matchID is null and q3.matchType = 'None' and e2.id = q2.recvdID and e3.id = q3.recvdID and e2.callID = e3.callID;"
    res = @db.query(queryStr)
    res.each(:as => :array) { |row|
      @db.query("update QSO set matchType = 'Dupe' where id = #{row[0].to_i} and matchType = 'None' and matchID is null limit 1;")
      count = count + @db.affected_rows
    }
    count
  end
  
  def markNIL
    count = 0
    queryStr = "select q.id from QSO as q,Exchange as e,Callsign as c where q.matchID is null and q.matchType = 'None' and q.logID in #{logSet} and q.recvdID = e.id and e.callID = c.id and c.logrecvd;"
    res = @db.query(queryStr)
    res.each(:as => :array) { |row|
      @db.query("update QSO set matchType = 'NIL' where id = #{row[0].to_i} and matchType = 'None' and matchID is null limit 1;")
      count = count + @db.affected_rows
    }
    count
  end


  def basicMatch(timediff = PERFECT_TIME_MATCH)
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID < q2.logID " +
                    " and " + qsoMatch("q1", "q2", timediff) + " and " +
                    " (s1.callsign = r2.callsign or s1.callID = r2.callID) and " +
                    " (s2.callID = r1.callID or s2.callsign = r1.callsign) " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
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
      "jaro_winkler_similarity(#{s1}.name, #{r2}.name)*" +
      "jaro_winkler_similarity(#{s2}.name, #{r1}.name)*" +
      hillFunc("#{s1}.serial - #{r2}.serial", 1, 10) + "*" +
      hillFunc("#{s2}.serial - #{r1}.serial", 1, 10) + "*" +
      "jaro_winkler_similarity(#{ms1}.abbrev,#{mr2}.abbrev)*" +
      "jaro_winkler_similarity(#{ms2}.abbrev,#{mr1}.abbrev)"
  end

  def linkCallsign(exch, call)
    return "#{exch}.callID = #{call}.id"
  end

  def linkMultiplier(exch, mult)
    return "#{exch}.multiplierID = #{mult}.id"
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
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, s.callsign, s.serial, s.name, ms.abbrev, s.location, cr.basecall, r.callsign, r.serial, r.name, mr.abbrev, r.location " +
      " from QSO as q, Exchange as s, Exchange as r, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
      linkConstraints("q", "s", "r") + " and " +
      linkCallsign("s","cs") + " and " + linkCallsign("r", "cr") + " and " +
      linkMultiplier("s","ms") + " and " + linkMultiplier("r", "mr") + " and " +
      notMatched("q") + " and " +
      "q.logID in " + logSet + " " +
      "order by q.logID asc, q.time asc;"
    res = @db.query(queryStr)
    qsos = Array.new
    res.each(:as => :array) { |row|
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10], row[11],
                       @namecmp)
      r = Exchange.new(row[12], row[13], row[14], row[15], row[16], row[17],
                       @namecmp)
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    row[5], s, r)
      qsos << qso
    }
    print "#{qsos.length} unmatched QSOs read in\n"
    print "Starting probability-based cross match: #{Time.now.to_s}\n"
    $stdout.flush
    matches = Array.new
    alreadyseen = Hash.new
    qsos.each { |q1|
      qsos.each { |q2|
        metric = q1.probablyMatch(q2)
        if metric > 0.20
          ids = [ q1.id, q2.id ].sort
          if not alreadyseen[ids]
            alreadyseen[ids] = true
            matches << Match.new(q1, q2, metric, q1.callProbability(q2))
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
            if matchtypes
              print matchtypes.join(" ") + "\n\n"
            end
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
