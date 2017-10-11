#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#

require_relative 'contestdb'
require_relative 'logset'
require 'qsomatch'
require 'jaro_winkler'
require 'set'

def hillFunc(value, full, none)
  value = value.abs
  (value <= full) ? 1.0 : 
    ((value >= none) ? 0 : (1.0 - ((value.to_f - full)/(none.to_f - full))))
end


EXCHANGE_FIELD_TYPES = %w{ _callID _entityID _multiplierID _serial }
EXCHANGE_EXTRA_FIELD_TYPES = %w{ _callsign _location }

def lookupBase(db, callID)
  db.query("select basecall from Callsign where id = ? limit 1;", [callID]) { |row|
    return row[0]
  }
  nil
end

def lookupMult(db, mID)
  db.query("select abbrev from Multiplier where id = ? limit 1;", [mID]) { | row|
    return row[0]
  }
  nil
end

def lookupQSO(db, id, timeadj=0)
  db.query("select q.logID, q.frequency, q.band, q.fixedMode, q.time, " +
           EXCHANGE_FIELD_TYPES.sort.map { |f| "q.sent" + f }.join(", ") + ", " +
           EXCHANGE_FIELD_TYPES.sort.map { |f| "q.recvd" + f }.join(", ") + " , " +
           EXCHANGE_EXTRA_FIELD_TYPES.sort.map { |f| "qe.sent" + f}.join(", ") + ", " +
           EXCHANGE_EXTRA_FIELD_TYPES.sort.map { |f| "qe.recvd" + f}.join(", ") +
           " from QSO as q join QSOExtra as qe where q.id = ? and qe.id = ? limit 1;",
           [id, id]) { |row|
    return QSO.new(id, row[0].to_i, row[1].to_i, row[2], row[3], 
                   db.toDateTime(row[4])+timeadj,
                   lookupBase(db,row[5]), row[13], row[8], lookupMult(db, row[7]),
                   row[14],
                   lookupBase(db,row[9]), row[15], row[12], lookupMult(db, row[11]),
                   row[16])
  }
  nil
end


class Match
  include Comparable
  def initialize(q1, q2, metric=0, metric2=0)
    @q1 = q1
    @q2 = q2
    @metric = metric
    @metric2 = metric2
  end

  attr_reader :metric, :metric2, :q1, :q2

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
    type1 = @q1.fullMatch?(@q2, time) ?  "Full" : "Partial"
    type2 = @q2.fullMatch?(@q1, time) ? "Full" : "Partial"
    begin
      db.begin_transaction
      db.query("update QSO set matchID = ?, matchType = ? where id = ? and matchType = 'None' and matchID is NULL limit 1;", [@q2.id, type1, @q1.id]) { }
      if 1 == db.affected_rows
        db.query("update QSO set matchID = ?, matchType = ? where id = ? and matchType = 'None' and matchID is NULL limit 1;", [@q1.id, type2, @q2.id]) { }
        if 1 == db.affected_rows
          return type1, type2
        else
          db.rollback
          return nil
        end
      end
    ensure
      db.end_transaction
    end
    return nil
  end
end

class CrossMatch
  NOBANDMODE_TIME_MATCH = 5     # in minutes
  PERFECT_TIME_MATCH = 15       # in minutes
  MAXIMUM_TIME_MATCH = 30*60    # 30 hours in minutes

  def initialize(db, contestID, cdb)
    @db = db
    @cdb = cdb
    @contestID = contestID.to_i
    @logs = LogSet.new(cdb.logsForContest(contestID))
  end

  def restartMatch
    begin
      @db.begin_transaction
      @db.query("update QSO set matchID = NULL, matchType = 'None', judged_multiplierID = NULL, judged_band = NULL, judged_mode = NULL, score = NULL where #{@logs.membertest("logID")};") { }
      @db.query("update QSOExtra set comment = NULL where #{@logs.membertest("logID")};") { }
      @db.query("update Log set verifiedscore = null, verifiedPHQSOs = null, verifiedCWQSOs = null, verifiedMultipliers = null where #{@logs.membertest("id")};") { }
    ensure
      @db.end_transaction
    end
  end

  def notMatched(qso)
    return "#{qso}.matchID is null and #{qso}.matchType = \"None\""
  end

  def timeMatch(t1, t2, timediff)
    return "(abs(" +
      @db.timediff("MINUTE", t1, t2) + ") <= " + timediff.to_s + ")"
  end

  def qsoExactMatch(q1,q2)
    return q1 + ".band = " + q2 + ".band and " + q1 + ".fixedMode = " +
      q2 + ".fixedMode"
  end

  def qsoInexactMatch(q1,q2)
    return "((" + q1 + ".band = " + q2 + ".band) or (" + q1 + ".fixedMode = " +
      q2 + ".fixedMode))"
  end

  def qsoMatch(q1, q2, timediff=PERFECT_TIME_MATCH)
    return timeMatch("q1.time", "q2.time", timediff) 
  end

  def serialCmp(s1, s2, range)
    return "(" + s1 + " between (" + s2 + " - " + range.to_s +
      ") and (" + s2 + " + " + range.to_s + "))"
  end

  def exchangeExactMatch(recvd, sent)
    return " (" + recvd + "_callID = " + sent + "_callID and (" +
      recvd + "_multiplierID = " + sent + "_multiplierID or " +
      sent + "_multiplierID is null)) "
  end

  def exchangeMatch(recvd, sent)
    return "((" +
      serialCmp(recvd + "_serial", sent + "_serial", 1) + ") or " +
      sent + "_serial is null)"
  end

  def qsoFromDBRow(row, qsos = Array.new)
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    @db.toDateTime(row[5]),
                    row[6], row[7], row[8], row[9], row[10],
                    row[11], row[12], row[13], row[14], row[15])
      qsos << qso
  end

  def printDupeMatch(id1, id2)
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, ms.abbrev, qe.sent_location, cr.basecall, qe.recvd_callsign, q.recvd_serial, mr.abbrev, qe.recvd_location " +
                    " from QSO as q join QSOExtra as qe on qe.id = q.id, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
                    linkCallsign("q.sent_","cs") + " and " + linkCallsign("q.recvd_", "cr") + " and " +
                    linkMultiplier("q.sent_","ms") + " and " + linkMultiplier("q.recvd_", "mr") + " and " +
      " q.id in (#{id1.to_i}, #{id2.to_i});"
    qsos = Array.new
    @db.query(queryStr) { |row|
      qsoFromDBRow(row, qsos)
    }
    if qsos.length != 2
      ids = [id1, id2]
      qsos.each { |q|
        ids.delete(q.id)
      }
      queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, 'NULL', qe.sent_location, cr.basecall, qe.recvd_callsign, q.recv_serial, 'NULL', qe.recvd_location " +
                    " from QSO as q, Callsign as cr, Callsign as cs where " +
                    linkCallsign("q.sent_","cs") + " and " + linkCallsign("q.recvd_", "cr") + " and " +
        " q.id in (#{ids.join(',')});"
      qsos = Array.new
      @db.query(queryStr) { |row|
        qsoFromDBRow(row, qsos)
      }
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
 
  def linkQSOs(queryStr, match1, match2, quiet=true, markDupe=true)
    count1 = 0
    count2 = 0
    dupeCount = 0
    if not quiet
      print "linkQSOs #{match1} #{match2}\n"
    end
    @db.query(queryStr).each { |row|
      begin
        @db.begin_transaction
        found = false
        @db.query("update QSO set matchID = ?, matchType = ? where id = ? and matchID is null and matchType = 'None' limit 1;", [row[1].to_i, match1, row[0].to_i]) { }
        if 1 == @db.affected_rows
          @db.query("update QSO set matchID = ?, matchType = ? where id = ? and matchID is null and matchType = 'None' limit 1;",
                    [row[0].to_i, match2, row[1].to_i]) { }
          if 1 != @db.affected_rows
            @db.rollback
          else
            count1 += 1
            count2 += 1
            found = true
          end
        end
        if markDupe and not found
          @db.query("update QSO set matchType = 'Dupe' where matchID is null and matchType = 'None' and id in (?, ?) limit 2;", [row[0].to_i, row[1].to_i]) { }
          dupeCount += @db.affected_rows
        end
      ensure
        @db.end_transaction
      end
      if not quiet
        printDupeMatch(row[0].to_i, row[1].to_i)
      end
    }
    return count1, count2, dupeCount
  end

  def modeBandDesc(setting)
    case setting
    when :perfect
      return ""
    when :one
      return "requiring band or mode to match"
    else
      return "without requiring band or mode to match"
    end
  end

  def modeBandMatch(q1, q2, setting)
    case setting
    when :perfect
      return qsoExactMatch(q1, q2)
    when :one
      return qsoInexactMatch(q1, q2)
    end
    return @db.true.to_s
  end

  def perfectMatch(timediff = PERFECT_TIME_MATCH, 
                   matchType="Full",
                   modeAndBand=:perfect)
    print "Staring perfect match #{modeBandDesc(modeAndBand)}(#{timediff} minute tolerance): #{Time.now.to_s}\n"
    queryStr = "select q1.id, q2.id from QSO as q1 join QSO as q2 " +
      " on (" +  exchangeExactMatch("q1.recvd", "q2.sent") + " and " +
      exchangeExactMatch("q2.recvd", "q1.sent") + " and " +
      modeBandMatch("q1", "q2", modeAndBand)  +
      ") where " +
      @logs.membertest("q1.logID") + " and " +
      @logs.membertest("q2.logID") + " and " +
      "q1.logID != q2.logID and q1.id < q2.id and "  +
      exchangeMatch("q1.recvd", "q2.sent") + " and " +
      exchangeMatch("q2.recvd", "q1.sent") + " and " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      qsoMatch("q1", "q2", timediff) +
      " order by (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.sent_serial)) asc" +
      ", abs(" +
      @db.timediff("MINUTE", "q1.time", "q2.time") + ") asc;"
    print queryStr + "\n"
    if $explain
      @db.query("explain " + queryStr) { |row|
        print row.join(", ") + "\n"
      }
    end
    $stdout.flush
    num1, num2, dupeCount = linkQSOs(queryStr, matchType, matchType, true, true)
    num1 = num1 + num2
    print "Ending perfect match test: #{Time.now.to_s}\n"
    return num1, dupeCount
  end

  def partialMatch(timediff = PERFECT_TIME_MATCH, 
                   fullType="Full",  
                   partialType="Partial",
                   modeAndBand = :perfect)
    queryStr = "select q1.id, q2.id from QSO as q1 join QSO as q2 on (" +
      exchangeExactMatch("q1.recvd", "q2.sent") + " and " +
      modeBandMatch("q1", "q2", modeAndBand) +
      " and q2.recvd_callID = q1.sent_callID ) " +
      "where " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      @logs.membertest("q1.logID") + " and " +
      @logs.membertest("q2.logID") + " and " +
      " q1.logID != q2.logID " +
      " and " + qsoMatch("q1", "q2", timediff) + " and " +
      exchangeMatch("q1.recvd", "q2.sent") +
      " order by (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.sent_serial)) asc" +
      ", abs(" +
      @db.timediff("MINUTE", "q1.time", "q2.time") + ") asc;"
    print "Partial match test #{modeBandDesc(modeAndBand)}(#{timediff} min tolerance): #{Time.now.to_s}\n"
    print queryStr + "\n"
    if $explain
      @db.query("explain " + queryStr) { |row|
        print row.join(", ") + "\n"
      }
    end
    $stdout.flush
    full1, partial1, dupeCount = linkQSOs(queryStr, fullType, partialType, true, 
                                          false)
    print "Partial match end: #{Time.now.to_s}\n"
    return full1, partial1, dupeCount
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
    queryStr = "select q1.id, q1.matchType, q2.id, q2.matchType from QSO as q1, QSO as q2, Log as l1, Log as l2 where q1.matchType in ('TimeShiftFull', 'TimeShiftPartial') and q1.matchID = q2.id and q1.id = q2.matchID and q2.matchType in ('TimeShiftFull', 'TimeShiftPartial') and q1.id < q2.id and l1.id = q1.logID and l2.id = q2.logID and l1.contestID = ? and l2.contestID = ? and " +
      @db.dateAdd("q1.time", "l1.clockadj", "second") +
      " between " +
      @db.dateSub(@db.dateAdd("q2.time", "l2.clockadj", "second"),
                  PERFECT_TIME_MATCH, "minute") + " and " +
      @db.dateAdd(@db.dateAdd("q2.time", "l2.clockadj", "second"),
                  PERFECT_TIME_MATCH, "minute") +
      " order by q1.id asc;"
    @db.query(queryStr, [@contestID, @contestID])  { |row|
      oneType, num1, num2 = chooseType(row[1], num1, num2)
      twoType, num1, num2 = chooseType(row[3], num1, num2)
      @db.query("update QSO set matchType=? where id = ? limit 1;", [oneType, row[0].to_i])
      @db.query("update QSO set matchType=? where id = ? limit 1;", [twoType, row[2].to_i])
    }
    @db.query("update QSO set matchType='Partial' where matchType in ('TimeShiftFull', 'TimeShiftPartial') and " +
              @logs.membertest("logID") + ";") { }
    num2 = num2 + @db.affected_rows
    return num1, num2
  end

  def ignoreDups
    queryStr = "select distinct q3.id from QSO as q1, QSO as q2, QSO as q3 where q1.matchID is not null and q1.matchType in ('Partial', 'Full') and " +
      @logs.membertest("q1.logID") +
      " and q2.matchID is not null and q2.matchType in ('Partial', 'Full') and " +
      @logs.membertest("q2.logID") +
      " and q2.id = q1.matchID and q1.band = q2.band and q3.band = q1.band and q1.logID = q3.logID and q3.matchID is null and q3.matchType = 'None' and q2.sent_callID = q3.recvd_callID;"
    list = Array.new
    @db.query(queryStr) { |row|
      list << row[0].to_i
    }
    
    @db.query("update QSO set matchType = 'Dupe' where id in (#{list.join(",")}) and matchType = 'None' and matchID is null limit 1;") { }
    return @db.affected_rows
  end
  
  def markNIL
    count = 0
    queryStr = "select q.id from QSO as q, Callsign as c where q.matchID is null and q.matchType = 'None' and " +
      @logs.membertest("q.logID") +
      " and q.recvd_callID = c.id and c.logrecvd;"
    @db.query(queryStr) { |row|
      @db.query("update QSO set matchType = 'NIL' where id = ? and matchType = 'None' and matchID is null limit 1;", [ row[0].to_i] ) { }
      count = count + @db.affected_rows
    }
    count
  end


  def basicMatch(timediff = PERFECT_TIME_MATCH,
                 modeAndBand = :perfect)
    queryStr = "select q1.id, q2.id from QSO as q1, QSO as q2 where " +
      notMatched("q1") + " and " + notMatched("q2") + " and " +
      @logs.membertest("q1.logID") + " and " +
      @logs.membertest("q2.logID") + " and " +
      "q1.logID < q2.logID " +
      " and " + qsoMatch("q1", "q2", timediff) + " and " +
      modeBandMatch("q1", "q2", modeAndBand) + " and " +
      " q1.sent_callID = q2.recvd_callID and q2.sent_callID = q1.recvd_callID " +
      " order by abs(" +
      @db.timediff("MINUTE", "q1.time", "q2.time") + ") asc, " +
      " (abs(q1.recvd_serial - q2.sent_serial) + abs(q2.recvd_serial - q1.sent_serial)) asc;"
    print "Basic match test phase #{modeBandDesc(modeAndBand)}(#{timediff} min tolerance): #{Time.now.to_s}\n"
    print queryStr + "\n"
    $stdout.flush
    num1, num2, dupeCount = linkQSOs(queryStr, 'Partial', 'Partial', true, false)
    print "Basic match end: #{Time.now.to_s}\n"
    return num1, num2, dupeCount
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
    @db.query("select ismatch from Pairs where (line1 = ? and line2 = ?) or (line1 = ? and line2 = ?) limit 1;",
                    [line1, line2, line2, line1]) { |row|
      return row[0] == 1 ? "YES" : "NO"
    }
    return nil
  end

  def recordPair(m, matched)
    line1, line2 = m.qsoLines
    @db.query("insert into Pairs (contestID, line1, line2, ismatch) values (?, ?, ?, ?)",
              [@contestID, line1, line2, matched ? 1 : 0]) { }
  end

  def serialMetric(sent, recvd)
    if sent
      if recvd
        return (sent - recvd).abs
      else
        return sent.abs
      end
    else
      return 0
    end
  end

  def strMetric(sentStr, recvdStr, isCW)
    if isCW
      return QSO.cwJaroWinkler(sentStr, recvdStr)
    else
      return QSO.phJaroWinkler(sentStr, recvdStr)
    end
  end

  def serialStrMetric(q1, q2)
    isCW = ("CW" == q1.mode and "CW" == q2.mode)
    return strMetric(q1.sent_serial.to_s, q2.recvd_serial.to_s, isCW) *
      strMetric(q2.sent_serial.to_s, q1.recvd_serial.to_s, isCW)
  end

  def qthMetric(q1, q2)
    isCW = ("CW" == q1.mode and "CW" == q2.mode)
    return strMetric(q1.sent_multiplier, q2.recvd_multiplier, isCW) *
      strMetric(q2.sent_multiplier, q1.recvd_multiplier, isCW)
  end

  def locationMetric(q1, q2)
    isCW = ("CW" == q1.mode and "CW" == q2.mode)
    return strMetric(q1.sent_location, q2.recvd_location, isCW) *
      strMetric(q2.sent_location, q1.recvd_location, isCW)
  end

  def greenInfo(id)
    @db.query("select status, score, uniqueQSO, correctQTH, correctNum, correctMode, correctBand, correctCall, NILqso, isDUPE, comment from QSOGreen where id = ? limit 1;", [id]) { |row|
      return {'status' => row[0], 'score' => row[1], 'uniqueQSO' => row[2],
        'correctQTH' => row[3], 'correctNum' => row[4],
        'correctMode' => row[5], 'correctBand' => row[6],
        'correctCall' => row[7], 'NILqso' => row[8],
        'isDUPE' => row[9], 'comment' => row[10] }
    }
    nil
  end

  GREEN_MATCH = { 'FullMatch' => true,
    'MatchZero' => true,
    'MatchOne' => true,
    'Dupe' => true }.freeze

  def greenScore?(g)
    GREEN_MATCH[g["score"]] and
      (not g["NILqso"] or (g["NILqso"].to_i == 0)) and
      (not g["uniqueQSO"] or (g["uniqueQSO"].to_i == 0))
  end

  GREEN_NOMATCH = { 'Bye' => true,
    'Unscored' => true
  }

  def possibleRecvdCallsigns(q, gi)
    result = Set.new
    if q.recvd_basecall
      result << q.recvd_basecall
    end
    if q.recvd_callsign
      result << q.recvd_callsign
    end
    if gi.has_key?("correctCall") and gi["correctCall"]
      result << gi["correctCall"]
    end
    return result
  end

  def possibleRecvdSerial(q, gi)
    result = Set.new
    if q.recvd_serial
      result << q.recvd_serial
    end
    if gi.has_key?("correctNum") and gi["correctNum"]
      result << gi["correctNum"].to_i
    end
    return result
  end

  def possibleSentCallsigns(q, gi)
    result = Set.new
    if q.sent_basecall
      result << q.sent_basecall
    end
    if q.sent_callsign
      result << q.sent_callsign
    end
    return result
  end

  def possibleMode(q, g)
    result = Set.new
    if q.mode
      result << q.mode.upcase
    end
    if g.has_key?("correctMode") and g["correctMode"]
      result << g["correctMode"].upcase
    end
    result
  end

  def possibleBand(q, g)
    result = Set.new
    if q.band
      result << q.band
    end
    if g.has_key?("correctBand") and g["correctBand"]
      result << (g["correctBand"] + "m")
    end
    result
  end

  def possibleSentMult(q, g)
    result = Set.new
    if q.sent_multiplier
      result << q.sent_multiplier
    end
    if q.sent_location
      result << q.sent_location
    end
    result
  end

  def possibleRecvdMult(q, g)
    result = Set.new
    if q.recvd_multiplier
      result << q.recvd_multiplier
    end
    if q.recvd_location
      result << q.recvd_location
    end
    if g.has_key?("correctQTH") and g["correctQTH"]
      result << g["correctQTH"]
    end
    result
  end

  def greenCallMatch(q1, g1, q2, g2)
    possibleSentCallsigns(q1, g1).intersect?(possibleRecvdCallsigns(q2, g2)) and
      possibleSentCallsigns(q2, g2).intersect?(possibleRecvdCallsigns(q1, g1))
  end

  def greenSerialMatch(q1, g1, q2, g2)
    ((not q1.sent_serial) or
      (possibleRecvdSerial(q2, g2).include?(q1.sent_serial))) and
      ((not q2.sent_serial) or (possibleRecvdSerial(q1, g1).include?(q2.sent_serial)))
  end

  def greenQTHMatch(q1, g1, q2, g2)
    possibleSentMult(q1, g1).intersect?(possibleRecvdMult(q2, g2)) and
      possibleSentMult(q2, g2).intersect?(possibleRecvdMult(q1, g1))
  end

  def greenBandMatch(q1, g1, q2, g2)
    possibleBand(q1, g1).intersect?(possibleBand(q2, g2))
  end

  def greenModeMatch(q1, g1, q2, g2)
    possibleMode(q1, g1).intersect?(possibleMode(q2, g2))
  end

  def printGreenInfo(g)
    print "STATUS=#{g['status']}; SCORE=#{g['score']}; "
    [ 'correctQTH', 'correctNum', 'correctMode',
      'correctBand', 'correctCall' ].each { |f|
      if g.has_key?(f)
        print "Err_" + f.gsub(/^correct/, "").downcase + "=" + g[f].to_s + "; "
      end
    }
    [ 'uniqueQSO', 'NILqso', 'isDUPE' ].each { |f|
      if g.has_key?(f)
        print f + "=" + g[f].to_s + "; "
      end
    }
    if g.has_key?('comment')
      print "COMMENT=#{g['comment']};"
    end
    print "\n"
  end

  def greenMatch?(q1, q2, m1, m2)
    result = "No"
    g1 = greenInfo(q1.id)
    g2 = greenInfo(q2.id)
    if not GREEN_NOMATCH[g1['score']]
      if not GREEN_NOMATCH[g2['score']]
        if greenScore?(g1) and greenScore?(g2) and
            greenCallMatch(q1, g1, q2, g2) and
            greenSerialMatch(q1, g1, q2, g2) and
            greenQTHMatch(q1, g1, q2, g2) and
            greenBandMatch(q1, g1, q2, g2) and
            greenModeMatch(q1, g1, q2, g2)
          result = "Yes"
        end
      end
    end
    m = Match.new(q1, q2, m1, m2)
    print m.to_s + "\n"
    printGreenInfo(g1)
    printGreenInfo(g2)
    print "Green data suggests " + result + "\n"
    if (("No" == result and m1 >= 0.5) or
        ("Yes" == result and m1 <= 0.4))
      print "Is this a match (y/n): "
      answer = STDIN.gets
      if [ "Y", "YES"].include?(answer.strip.upcase)
        return "Yes"
      else
        return "No"
      end
    end
    return result
  end

  def probMatch
    queryStr = "select q.id, q.logID, q.frequency, q.band, q.fixedMode, q.time, cs.basecall, qe.sent_callsign, q.sent_serial, ms.abbrev, qe.sent_location, cr.basecall, qe.recvd_callsign, q.recvd_serial, mr.abbrev, qe.recvd_location " +
      " from QSO as q join QSOExtra qe on q.id = qe.id, Callsign as cr, Callsign as cs, Multiplier as ms, Multiplier as mr where " +
      linkCallsign("q.sent","cs") + " and " + linkCallsign("q.recvd", "cr") + " and " +
      linkMultiplier("q.sent","ms") + " and " + linkMultiplier("q.recvd", "mr") + " and " +
      notMatched("q") + " and " +
      @logs.membertest("q.logID") +
      " order by q.id asc;"
    print "Probability match read start: #{Time.now.to_s}\n"
    $stdout.flush
    qsos = Array.new
    res = @db.query(queryStr) { |row|
      qso = QSO.new(row[0].to_i, row[1].to_i, row[2].to_i, row[3], row[4],
                    @db.toDateTime(row[5]),
                    row[6], row[7], row[8], row[9], row[10],
                    row[11], row[12], row[13], row[14], row[15])
      qsos << qso
    }
    res = nil
    print "#{qsos.length} unmatched QSOs read in: #{Time.now.to_s}\n"
    print "Starting probability-based cross match: #{Time.now.to_s}\n"
    $stdout.flush
    matches = Array.new
    qsos.each { |q1|
      qsos.each { |q2|
        if not q1.impossibleMatch?(q2)
          if q1.svmMatch(q2)
            metric, cp = q1.probablyMatch(q2)
            if metric > 0.1
              matches << Match.new(q1, q2, metric, cp)
            end
          end
        end
      }
    }
    print matches.length.to_s + " potential matches to evaluate\n"
    $stdout.flush
    matches.sort! { |a,b| b <=> a }
    print "Done ranking potential matches: #{Time.now.to_s}\n"
    print matches.length.to_s + " possible matches selected\n"
    $stdout.flush
    matches.each { |m|
      print m.to_s + "\n"
      matchtypes = m.record(@db, CrossMatch::PERFECT_TIME_MATCH)
      if matchtypes
        print matchtypes.join(" ") + "\n\n"
      end
    }
  end

  def logAdj(id)
    @db.query("select clockadj from Log where id = ?;", [ id ]) { |row|
      return row[0]
    }
    return 0
  end

  def findUnreliable
    unreliableClock = Set.new
    # logs with more than max(2,0.05*numQ) time mismatches are considered unreliable
    @db.query("select q1.logID, count(*) as numQ, sum(abs(#{@db.timediff('SECOND','q1.time','q2.time')} + l1.clockadj - l2.clockadj) > 60 * #{CrossMatch::PERFECT_TIME_MATCH}) as clockMis from (QSO as q1 join Log as l1 on q1.logID = l1.id) join (QSO as q2 join Log as l2 on q2.logID = l2.id) on q2.id = q1.matchID and q1.id = q2.matchID where #{@logs.membertest('q1.logID')} and #{@logs.membertest('q2.logID')} group by q1.logID having clockMis > max(2,0.05*numQ) order by q1.logID asc;") { |row|
      unreliableClock << row[0].to_i
    }
    unreliableClock.freeze
    unreliableBand = Set.new
    # logs with more than 4% band mismatches are consider unreliable
    @db.query("select q.logID, count(*) as numQ, sum(q.band != q2.band) as bandMis from QSO as q join QSO as q2 on (q.matchID=q2.id and q2.matchID = q.id) join Log as l1 on q.logID = l1.id where #{@logs.membertest("q.logID")} group by q.logID having bandMis > 0.04*numQ order by q.logID asc;") { |row|
      unreliableBand << row[0].to_i
    }
    unreliableBand.freeze
    unreliableMode = Set.new
    # logs with more than 0.5% band mismatches are consider unreliable
    @db.query("select q.logID, count(*) as numQ, sum(q.fixedMode != q2.fixedMode) as modeMis from QSO as q join QSO as q2 on (q.matchID=q2.id and q2.matchID = q.id) join Log as l1 on q.logID = l1.id where #{@logs.membertest("q.logID")} group by q.logID having modeMis > 1 and modeMis > 0.005*numQ order by q.logID asc;") { |row|
      unreliableMode << row[0].to_i
    }
    unreliableMode.freeze
    return unreliableClock, unreliableBand, unreliableMode
  end

  def initialScore
    unreliableClock, unreliableBand, unreliableMode = findUnreliable
    @db.query("select q1.id, q1.time, q1.logID, q1.recvd_callID, q1.recvd_multiplierID, q1.judged_multiplierID, q1.recvd_serial, q1.matchType, q1.band, q1.fixedMode, q2.id, q2.time, q2.logID, q2.sent_callID, q2.sent_serial, q1.judged_band, q1.judged_mode from QSO as q1 join QSO as q2 on (q2.matchID = q1.id and q1.matchID = q2.id) where q1.matchID is not null and q2.matchID is not null and #{@logs.membertest("q1.logID")} and #{@logs.membertest("q2.logID")} order by q1.id asc;") { |row|
      row[2] = row[2].to_i
      log1Adj = logAdj(row[2])
      row[12] = row[12].to_i
      log2Adj = logAdj(row[12])
      comment = ""
      notMatch = 0
      if ((@db.toDateTime(row[1])+log1Adj) - (@db.toDateTime(row[11])+log2Adj)).abs > PERFECT_TIME_MATCH*60
        if unreliableClock.include?(row[2].to_i) or not unreliableClock.include?(row[12])
          notMatch += 1
          comment << " clock"
        end
      end
      if row[3].nil? or (row[3] != row[13]) # call signs mismatch
        notMatch += 1
        comment << " callsign"
      end
      if row[4].nil? or (row[4] != row[5]) # multiplier mismatch
        notMatch += 1
        comment << " multiplier"
      end
      if row[8].nil? or ((not (row[15].nil?)) and (row[8] != row[15]))
        if unreliableBand.include?(row[2]) or not unreliableBand.include?(row[12])
          notMatch += 1
          comment << " band"
        end
      end
      if row[9].nil? or ((not (row[16].nil?)) and (row[9] != row[16]))
        if unreliableMode.include?(row[2]) or not unreliableMode.include?(row[12])
          notMatch += 1
          comment << " mode"
        end
      end
      if row[6].nil? or ((not (row[14].nil?)) and ((row[6] < (row[14]-1)) or (row[6] > (row[14]+1)))) # serial mismatch
        notMatch += 1
        comment << " serial"
      end
      if (notMatch == 0 and row[7] != "Full")
        @db.query("update QSO set matchType='Full' where id = ? limit 1;",
                  [ row[0] ])
      end
      if (notMatch != 0 and row[7] == "Full")
        print "QSO ID #{row[0]} is a #{row[7]} match with #{notMatch} mismatches #{comment}\n"
        @db.query("update QSO set matchType='Partial' where id = ? limit 1;",
                  [ row[0] ])
      end
      case notMatch
      when 0
        score = 2
      when 1
        score = 1
      else
        score = 0
      end
      @db.query("update QSO set score = ? where id = ? limit 1;",
                [ score, row[0]])
    }
    @db.query("update QSO set score = 2 where #{@logs.membertest("logID")} and matchType = 'Bye';")
    @db.query("update QSO set score = 1 where #{@logs.membertest("logID")} and matchType='PartialBye';")
    @db.query("update QSO set score = 0 where #{@logs.membertest("logID")} and matchType in ('None', 'Unique', 'Dupe', 'OutsideContest', 'Removed');")
    @db.query("update QSO set score = 0 where #{@logs.membertest("logID")} and matchType = 'NIL';")
  end
end
