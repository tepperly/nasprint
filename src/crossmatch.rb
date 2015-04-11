#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#

require 'jaro_winkler'

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

  def initialize(basecall, callsign, serial, name, mult, location)
    @basecall = @@stringspace.register(basecall)
    @callsign = @@stringspace.register(callsign)
    @serial = serial.to_i
    @name = @@stringspace.register(name)
    @mult = @@stringspace.register(mult)
    @location = @@stringspace.register(location)
  end

  attr_reader :basecall, :callsign, :serial, :name, :mult, :location

  def probablyMatch(exch)
    [ JaroWinkler.distance(@basecall, exch.basecall),
      JaroWinkler.distance(@callsign, exch.callsign) ].max *
      JaroWinkler.distance(@name, exch.name) *
      [ hillFunc(@serial-exch.serial, 1, 10),
        JaroWinkler.distance(@serial.to_s,exch.serial.to_s) ].max *
      [ JaroWinkler.distance(@mult, exch.mult),
        JaroWinkler.distance(@location, exch.location) ].max
  end

  def to_s
    "%-6s %-7s %4d %-12s %-2s %-4s" % [@basecall, @callsign, @serial,
                                  @name, @mult, @location]
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
       hillFunc(@datetime - qso.datetime, 15*60, 60*60))
  end

  def to_s(reversed = false)
    ("%7d %5d %5d %-4s %-2s %s " % [@id, @logID, @freq, @band, @mode,
                                  @datetime.strftime("%Y-%m-%d %H%M")]) +
      (reversed ?  (@recvd.to_s + " " + @sent.to_s):
       (@sent.to_s + " " + @recvd.to_s))
  end
end

class Match
  include Comparable
  def initialize(q1, q2, metric=0)
    @q1 = q1
    @q2 = q2
    @metric = metric
  end

  attr_reader :metric

  def <=>(match)
      @metric <=> match.metric
  end

  def to_s
    "Metric: #{@metric}\n" + @q1.to_s + "\n" + (@q2  ? @q2.to_s(true): "nil") + "\n"
  end
end

class CrossMatch
  PERFECT_TIME_MATCH = 15

  def initialize(db, contestID)
    @db = db
    @contestID = contestID.to_i
    @logs = queryContestLogs
  end

  def queryContestLogs
    logList = Array.new
    res = @db.query("select id from Log where contestID = #{@contestID} order by id asc;")
    res.each(:as => :array) { |row|
      logList << row[0].to_i
    }
    return logList
  end

  def logSet
    return "(" + @logs.join(",") + ")"
  end

  def restartMatch
    @db.query("update QSO set matchID = NULL, matchType = 'None' where logID in #{logSet};")
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
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10], row[11])
      r = Exchange.new(row[12], row[13], row[14], row[15], row[16], row[17])
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
      print "query #{queryStr}\n"
      qsos = qsosFromDB(@db.query(queryStr), qsos)
      print "Match of QSOs #{id1} #{id2} produced #{qsos.length} results\n"
    end
    m = Match.new(qsos[0], qsos[1])
    print m.to_s + "\n"
  end
 
  def linkQSOs(matches, match1, match2)
    count1 = 0
    count2 = 0
    print "linkQSOs #{match1} #{match2}\n"
    matches.each(:as => :array) { |row|
      chk = @db.query("select q1.id, q2.id from QSO as q1, QSO as q2 where q1.id = #{row[0].to_i} and q2.id = #{row[1].to_i} and q1.matchID is null and q2.matchID is null and q1.matchType = 'None' and q2.matchType = 'None' limit 1;")
      found = false
      chk.each { |chkrow|
        found = true
        @db.query("update QSO set matchID = #{row[1].to_i}, matchType = '#{match1}' where id = #{row[0].to_i} and matchID is null and matchType = 'None' limit 1;")
        count1 = count1 + 1
        @db.query("update QSO set matchID = #{row[0].to_i}, matchType = '#{match2}' where id = #{row[1].to_i} and matchID is null and matchType = 'None' limit 1;")
        printDupeMatch(row[0].to_i, row[1].to_i)
        count2 = count2 + 1
      }
      if not found
        @db.query("update QSO set matchType = 'Dupe' where matchID is null and matchType = 'None' and id in (#{row[0].to_i}, #{row[1].to_i}) limit 2;")
        printDupeMatch(row[0].to_i, row[1].to_i)
      end
    }
    return count1, count2
  end

  def perfectMatch
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    exchangeMatch("r1", "s2") + " and " +
                    exchangeMatch("r2", "s1") + " and q1.id < q2.id" +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    num1, num2 = linkQSOs(@db.query(queryStr), 'Full', 'Full')
    num1 = num1 + num2
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Homophone as h1, Homophone as h2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    exchangeMatch("r1", "s2", "h1") + " and " +
                    exchangeMatch("r2", "s1", "h2") + " and q1.id < q2.id" +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    print queryStr + "\n"
    num2, num3 = linkQSOs(@db.query(queryStr), 'Full', 'Full')
    num2 = num2 + num3
    return num1, num2
  end

  def partialMatch
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    exchangeMatch("r1", "s2") + " and " +
                    " r2.callID = s1.callID " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    full1, partial1 = linkQSOs(@db.query(queryStr), 'Full', 'Partial')
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Homophone as h where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    exchangeMatch("r1", "s2", "h") + " and " +
                    " r2.callID = s1.callID " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    full2, partial2 = linkQSOs(@db.query(queryStr), 'Full', 'Partial')
    return full1 + full2, partial1 + partial2
  end

  def basicMatch
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID < q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    " (s1.callsign = r2.callsign or s1.callID = r2.callID) and " +
                    " (s2.callID = r1.callID or s2.callsign = r1.callsign) " +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    return linkQSOs(@db.query(queryStr), 'Partial', 'Partial')
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
      s = Exchange.new(row[6], row[7], row[8], row[9], row[10], row[11])
      r = Exchange.new(row[12], row[13], row[14], row[15], row[16], row[17])
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    row[5], s, r)
      qsos << qso
    }
    print "#{qsos.length} unmatched QSOs read in\n"
    print "Starting probability-based cross match: #{Time.now.to_s}\n"
    matches = Array.new
    alreadyseen = Hash.new
    qsos.each { |q1|
      qsos.each { |q2|
        metric = q1.probablyMatch(q2)
        if metric > 0.20
          ids = [ q1.id, q2.id ].sort
          if not alreadyseen[ids]
            alreadyseen[ids] = true
            matches << Match.new(q1, q2, metric)
          end
        end
      }
    }
    print "Done ranking potential matches: #{Time.now.to_s}\n"
    print matches.length.to_s + " possible matches selected\n"
    matches.sort! { |a,b| b <=> a }
    matches.each { |m|
      print m.to_s + "\n"
    }
  end
end
