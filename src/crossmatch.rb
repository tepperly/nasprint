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
    matches.each(:as => :array) { |row|
      chk = @db.query("select q1.id, q2.id from QSO as q1, QSO as q2 where q1.id = #{row[0].to_i} and q2.id = #{row[1].to_i} and q1.matchID is null and q2.matchID is null and q1.matchType = 'None' and q2.matchType = 'None' limit 1;")
      chk.each { |chkrow|
        @db.query("update QSO set matchID = #{row[1].to_i}, matchType = '#{match1}' where id = #{row[0].to_i} and matchID is null and matchType = 'None' limit 1;")
        @db.query("update QSO set matchID = #{row[0].to_i}, matchType = '#{match2}' where id = #{row[1].to_i} and matchID is null and matchType = 'None' limit 1;")
      }
    }
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
      ", abs(timediff(q1.time, q2.time)) asc;"
    linkQSOs(@db.query(queryStr), 'Full', 'Full')
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
      ", abs(timediff(q1.time, q2.time)) asc;"
    linkQSOs(@db.query(queryStr), 'Full', 'Full')
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
      ", abs(timediff(q1.time, q2.time)) asc;"
    linkQSOs(@db.query(queryStr), 'Full', 'Partial')
  end
end
