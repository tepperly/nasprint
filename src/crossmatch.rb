#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#

class CrossMatch
  PERFECT_TIME_MATCH = 10

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
 
  def linkQSOs(matches, match1, match2)
    count1 = 0
    count2 = 0
    matches.each(:as => :array) { |row|
      chk = @db.query("select q1.id, q2.id from QSO as q1, QSO as q2 where q1.id = #{row[0].to_i} and q2.id = #{row[1].to_i} and q1.matchID is null and q2.matchID is null and q1.matchType = 'None' and q2.matchType = 'None' limit 1;")
      chk.each { |chkrow|
        @db.query("update QSO set matchID = #{row[1].to_i}, matchType = '#{match1}' where id = #{row[0].to_i} and matchID is null and matchType = 'None' limit 1;")
        count1 = count1 + 1
        @db.query("update QSO set matchID = #{row[0].to_i}, matchType = '#{match2}' where id = #{row[1].to_i} and matchID is null and matchType = 'None' limit 1;")
        count2 = count2 + 1
      }
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
                    exchangeMatch("r1", "s2") +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    return linkQSOs(@db.query(queryStr), 'Full', 'Partial')
  end

  def partialMatch
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID != q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    exchangeMatch("r1", "s2") +
                    " order by (abs(r1.serial - s2.serial) + abs(r2.serial - s1.serial)) asc" +
      ", abs(timestampdiff(MINUTE,q1.time, q2.time)) asc;"
    return linkQSOs(@db.query(queryStr), 'Full', 'Partial')
  end

  def basicMatch
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2 where " +
                    linkConstraints("q1", "s1", "r1") + " and " +
                    linkConstraints("q2", "s2", "r2") + " and " +
                    notMatched("q1") + " and " + notMatched("q2") + " and " +
                    "q1.logID in " + logSet + " and q2.logID in " + logSet +
                    " and q1.logID < q2.logID " +
                    " and " + qsoMatch("q1", "q2") + " and " +
                    " s1.callsign = r2.callsign and s2.callsign = r1.callsign " +
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
    queryStr = "select q1.id, q2.id, " +
      probFunc("q1","q2","s1","s2","r1","r2","cs1","cs2", "cr1", "cr2",
               "ms1","ms2","mr1","mr2") +
      " as probmatch from QSO as q1, QSO as q2, Exchange as s1, Exchange as s2, Exchange as r1, Exchange as r2, Callsign as cr1, Callsign as cs1, Callsign as cr2, Callsign as cs2, Multiplier as ms1, Multiplier as ms2, Multiplier as mr1, Multiplier as mr2 where " +
      linkConstraints("q1", "s1", "r1") + " and " +
      linkConstraints("q2", "s2", "r2") + " and " +
      linkCallsign("s1","cs1") + " and " + linkCallsign("r1", "cr1") + " and " +
      linkCallsign("s2","cs2") + " and " + linkCallsign("r2", "cr2") + " and " +
      linkMultiplier("s1","ms1") + " and " + linkMultiplier("r1", "mr1") + " and " +
      linkMultiplier("s2","ms2") + " and " + linkMultiplier("r2", "mr2") + " and " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      "q1.logID in " + logSet + " and q2.logID in " + logSet +
      " and q1.logID < q2.logID and " +
      probFunc("q1","q2","s1","s2","r1","r2","cs1","cs2", "cr1", "cr2",
               "ms1","ms2","mr1","mr2") +
      " >= 0.5 order by probmatch desc;"
    print queryStr + "\n"
  end
end
