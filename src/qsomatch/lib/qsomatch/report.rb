#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'set'
require 'csv'
require_relative 'logset'

class Log
  CA_QTH = Set.new(%w{ ALAM ALPI AMAD BUTT CALA CCOS COLU DELN ELDO
FRES GLEN HUMB IMPE INYO KERN KING LAKE LANG LASS MADE MARN MARP MEND
MERC MODO MONO MONT NAPA NEVA ORAN PLAC PLUM RIVE SACR SBAR SBEN SBER
SCLA SCRU SDIE SFRA SHAS SIER SISK SJOA SLUI SMAT SOLA SONO STAN SUTT
TEHA TRIN TULA TUOL VENT YOLO YUBA }).freeze
  US_QTH = Set.new(%w{  AK AL AR AZ CO CT DE FL GA HI IA ID
IL IN KS KY LA MA MD ME MI MN MO MS MT NC ND NE NH NJ NM NV
NY OH OK OR PA RI SC SD TN TX UT VA VT WA WI WV WY
}).freeze
  CAN_QTH = Set.new(%w{ AB BC MB MR NT ON QC SK }).freeze
  CA_STATION_CREDITS = (US_QTH + CAN_QTH + Set.new(%w{ CA })).freeze

  def qthClass
    if US_QTH.include?(@qth)
      "USA"
    elsif CA_QTH.include?(@qth)
      "CA"
    elsif CAN_QTH.include?(@qth)
      "CAN"
    else 
      "DX"
    end
  end

  def greenArea
    if US_QTH.include?(@qth)
      "US"
    elsif CA_QTH.include?(@qth)
      "CA"
    elsif CAN_QTH.include?(@qth)
      "VE"
    else 
      "DX"
    end
  end
  
  def initialize(call, email, opclass, qth, power, isCCE, isYOUTH, isYL, isNEW, isSCHOOL,isMOBILE, entity, id, clockadj)
    @id = id
    @clockadj = clockadj
    @call = call
    @entity = entity
    @qth = qth
    @email = email
    @opclass = opclass
    @power = power
    @numClaimed = 0
    @greenPH = nil
    @greenCW = nil
    @greenChecked = 0
    @numD1 = 0
    @numD2 = 0
    @numPH = 0
    @numCW = 0
    @numUnique = 0
    @numDupe = 0
    @numRemoved = 0
    @numNIL = 0
    @numOutsideContest = 0
    @isCCE = isCCE
    @isYOUTH = isYOUTH
    @isYL = isYL
    @isNEW = isNEW
    @isSCHOOL = isSCHOOL
    @isMOBILE = isMOBILE
    @multipliers = Set.new
    @claimedMults = 0
  end

  attr_reader :numPH, :numCW, :numUnique, :numDupe, :numRemoved, :numNIL, 
    :numOutsideContest, :numClaimed, :numD1, :numD2, :claimedMults,
    :greenPH, :greenCW, :greenChecked,:call,:qth, :clockadj, :id
  attr_writer :numPH, :numCW, :numUnique, :numDupe, :numRemoved, :numNIL, 
        :numOutsideContest, :numClaimed, :numD1, :numD2, :claimedMults,
    :greenPH, :greenCW, :greenChecked

  def addMultiplier(name)
    @multipliers.add(name)
  end

  def nummultipliers
    @multipliers.size
  end

  def score
    ( numPH*2 + numCW*3) * nummultipliers
  end

  def ls_line
    print "!! #{@call}: numPH != claimedPH - 0.5*d1PH - d2PH : #{numPH} != #{@greenPH[0]} - 0.5*#{@greenPH[2]} - #{@greenPH[1]}\n" if numPH != (@greenPH[0] - @greenPH[1] -0.5* @greenPH[2]).to_i
    print "!! #{@call}: numCW != claimedCW - 0.5*d1CW - d2CW : #{numCW} != #{@greenCW[0]} - 0.5*#{@greenCW[2]} - #{@greenCW[1]}\n" if numCW != (@greenCW[0] - @greenCW[1] - 0.5*@greenCW[2]).to_i
    "LS,#{@call},,#{@numClaimed},#{@numDupe},#{@claimedMults},#{@greenCW[0]},#{@greenPH[0]},#{(@greenCW[0]*3+2*@greenPH[0])*@claimedMults},#{@greenChecked},#{@greenCW[1]},#{@greenCW[2]},#{@greenPH[1]},#{@greenPH[2]},#{@multipliers.length},#{score},#{@qth},#{greenArea},#{@entity}"
  end

  def to_s
    "\"#{@call}\",\"#{@qth}\",#{@email ? ("\"" + @email + "\"") : ""},\"#{@opclass}\",\"#{qthClass}\",\"#{@power}\",\"#{@isCCE}\",\"#{@isYOUTH}\",\"#{@isYL}\",\"#{@isNEW}\",\"#{@isSCHOOL}\",\"#{@isMOBILE}\",#{@numClaimed},#{@numPH},#{@numCW},#{@numUnique},#{@numDupe},#{@numRemoved},#{@numNIL},#{@numOutsideContest},#{@numD1},#{@numD2},#{@multipliers.size},#{score},\"#{@multipliers.to_a.sort.join(", ")}\""
  end
end

class Report
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
  end

  def lookupMultiplier(id)
    @db.query("select m.abbrev, q.recvd_entityID from Multiplier as m, QSO as q where q.id = #{id} and  q.recvd_multiplierID = m.id limit 1;") { |row|
      return row[0], row[1]
    }
    return nil, nil
  end

  def addMultiplier(log, qsoID)
    abbrev, entity = lookupMultiplier(qsoID)
    if "DX" == abbrev
      if entity
        @db.query("select name, continent from Entity where id = ? limit 1;",
                        [entity]) { |row|
          if "NA" == row[1]     # it's a NA DX entity
            log.addMultiplier(row[0])
          end
        }
      else
        print "Log entry missing an entity number #{qsoID}.\n"
      end
    else
      if abbrev
        log.addMultiplier(abbrev)
      end
    end
  end

  def modeSet(str)
    case str
    when "PH"
      return "('PH', 'FW')"
    when "CW"
      return "('CW')"
    end
  end

  def totalClaimed(id, multID, mode=nil)
    @db.query("select count(*) from QSO where logID = ? and sent_multiplierID = ? #{mode ? " and fixedMode in " + modeSet(mode) + " " : ""} limit 1;", [id, multID]) { |row|
      return row[0]
    }
    0
  end

  def numPartial(id, multID, score)
    @db.query("select count(*) from QSO where logID = ? and sent_multiplierID = ? and score = ?  and matchType in ('Full', 'Bye', 'Partial', 'PartialBye') limit 1;", [id, multID, score] ) { |row|
      return row[0]
    }
    0
  end

  def qsoTotal(id, mode, multID)
    @db.query("select sum(q.score) from QSO as q where q.logID = ? and q.judged_mode = ? and q.sent_multiplierID = ? and q.matchType in ('Full', 'Bye', 'Partial', 'PartialBye') limit 1;",[id, mode, multID]) { |row|
      return (row[0].to_i / 2).to_i
    }
    0
  end

  def modeTotal(id, mode, multID)
    @db.query("select count(*) from QSO as q where q.logID = ? and q.matchType = ? and q.sent_multiplierID = ? limit 1;",[id, mode, multID]) { |row|
      return row[0].to_i
    }
    0
  end

  def greenModeStats(id, mode, multID)
    @db.query("select count(*), sum(q.score = 0), sum(q.score = 1), sum(q.score=2) from QSO as q where q.logID = ? and q.sent_multiplierID = ? and q.judged_mode in (#{mode.map { |x| "'" + x + "'"}.join(', ')}) and NOT q.matchType in ('None', 'Dupe', 'OutsideContest', 'TimeShiftFull', 'TimeShiftPartial');", [ id, multID ] ) {|row|
      print "!! Don't add up\n" if row[0] and (row[0] > 0) and (row[0] != row[1]+row[2]+row[3])
      return row[0].to_i, row[1].to_i, row[2].to_i
    }
    return nil, nil, nil
  end

  def calcGreenChecked(id, multID)
    @db.query("select count(*) from QSO where matchType in ('Full', 'Partial') and logID = ? and sent_multiplierID = ?;", [id, multID]) { |row|
      return row[0]
    }
    0
  end

  def calcMultipliers(id, log, multID, claimed = nil)
    if claimed
      matchType = %w{ None Full Partial Bye PartialBye Unique Dupe NIL OutsideContest Removed }
    else
      matchType = %w{ Full Partial Bye PartialBye }
    end
    isCA = @db.true
    @db.query("select m.isCA from Multiplier as m where m.id = ? limit 1;", [ multID ]) { |row|
      isCA = row[0]
    }
    @db.query("select distinct m.abbrev from Multiplier as m join (Log as l join QSO as q on l.id = q.logID) on q.#{claimed ? "recvd_multiplierID" : "judged_multiplierID" } = m.id where l.id = ? and q.matchType in (#{matchType.map { |x| "'" + x + "'"}.join(", ")}) and q.sent_multiplierID = ? and q.score >= 1 and m.ismultiplier and m.isCA != ?; ", 
              [id, multID, isCA]) { |row|
      if claimed
        claimed << row[0]
      else
        log.addMultiplier(row[0])
      end
    }
    if @db.toBool(isCA)
      # for CA stations any CA county counts as a CA multiplier
      @db.query("select m.id from Multiplier as m join (Log as l join QSO as q on l.id = q.logID) on q.#{claimed ? "recvd_multiplierID" : "judged_multiplierID" } = m.id where l.id = ? and q.matchType in (#{matchType.map { |x| "'" + x + "'"}.join(", ")}) and q.sent_multiplierID = ? and q.score >= 1 and m.ismultiplier and m.isCA limit 1;", [ id, multID ]) { |row|
        if claimed
          claimed << "CA"
        else
          log.addMultiplier("CA")
        end
      }
    end
  end

  MULTIPLIER_CREDIT = Set.new(%w( Full Partial Bye PartialBye)).freeze
  def scoreLog(id, multID, log)
    log.numD1 = numPartial(id, multID, 1)
    log.numD2 = numPartial(id, multID, 0)
    log.numClaimed = totalClaimed(id, multID)
    log.greenPH = greenModeStats(id, %w{ FM PH }, multID)
    log.greenCW = greenModeStats(id, %w{ CW }, multID)
    log.greenChecked = calcGreenChecked(id, multID)
    log.numPH = qsoTotal(id, "PH", multID)
    log.numCW = qsoTotal(id, "CW", multID)
    log.numNIL = modeTotal(id, "NIL", multID)
    log.numUnique = modeTotal(id, "Unique", multID)
    log.numDupe = modeTotal(id, "Dupe", multID)
    log.numRemoved = modeTotal(id, "Removed", multID)
    log.numOutsideContest = modeTotal(id, "OutsideContest", multID)
    calcMultipliers(id, log, multID)
    claimed = Set.new
    calcMultipliers(id, log, multID, claimed)
    log.claimedMults = claimed.length
  end

  def scoredLogs(contestID)
    logs = Array.new
    @db.query("select distinct l.callsign, l.email, l.opclass, l.id, m.id, m.abbrev, l.isCCE, l.isYOUTH, l.isYL, l.isNEW, l.isSCHOOL, l.isMOBILE, l.entityID, l.powclass, l.clockadj from Log as l join QSO as q on l.id = q.logID join Multiplier as m on m.id = q.sent_multiplierID  where contestID = ? order by callsign asc;", [contestID]) { |row|
      log = Log.new(row[0], row[1], row[2], row[5], row[13], @db.toBool(row[6]), @db.toBool(row[7]), @db.toBool(row[8]), @db.toBool(row[9]), @db.toBool(row[10]), @db.toBool(row[11]), row[12], row[3].to_i, row[14].to_i)
      scoreLog(row[3], row[4], log)
      logs << log
    }
    return logs
  end

  def logCheckReport(dir, contestID)
    logs = scoredLogs(contestID)
    logs.each { |log|
      open(File.join(dir, log.call.gsub(/[^a-z0-9]/i,"_") +"_" + log.qth + ".lcr"), "w") { |out|
        lcrHeader(out, log)
        lcrQSOReport(out, log)
        lcrScoreSummary(out, log)
        lcrMultiplierHistogram(out, log)
      }
    }
  end

  def multHistogram(id, multID, counts, claimed)
    if claimed
      matchType = %w{ None Full Partial Bye PartialBye Unique Dupe NIL OutsideContest Removed }
    else
      matchType = %w{ Full Partial Bye PartialBye }
    end
    isCA = @db.true
    @db.query("select m.isCA from Multiplier as m  where m.id = ? limit 1;", [ multID ]) { |row|
      isCA = row[0]
    }
    @db.query("select m.abbrev, count(*) from Multiplier as m join (Log as l join QSO as q on l.id = q.logID) on q.#{claimed ? "recvd_multiplierID" : "judged_multiplierID" } = m.id where l.id = ? and q.matchType in (#{matchType.map { |x| "'" + x + "'"}.join(", ")}) and q.sent_multiplierID = ? #{claimed ? "" : "and q.score >= 1"}  and m.ismultiplier group by m.abbrev order by m.abbrev asc; ", 
              [id, multID]) { |row|
      counts[row[0]] = row[1].to_i
    }
    catotal = 0
    Log::CA_QTH.each { |county| catotal += counts[county] }
    counts["CA"] = catotal
  end

  def lcrHeader(out, log)
    out << log.call << "  QTH:" << log.qth << "\r\nCQP LOG CHECKING RESULTS\r\n\r\n"
  end

  def validQSOsByMode(id, multID, mode)
    scores = [0, 0, 0]
    @db.query("select score, count(*) from QSO where logID = ? and sent_multiplierID = ? and matchType in ('Full', 'Bye', 'Partial', 'PartialBye', 'NIL', 'Removed', 'OutsideContest', 'Unique') and fixedMode in " + modeSet(mode) + " group by score order by score asc;", [id, multID] ) { |row|
      if row[0].to_i >= 0 and row[0].to_i < 3
        scores[row[0].to_i] = row[1].to_i
      end
    }
    return scores
  end

  def lcrScoreSummary(out, log)
    multID = nil
    isCA = nil
    @db.query("select id, isCA from Multiplier where abbrev=? limit 1;", [log.qth]) { |row|
      multID = row[0].to_i
      isCA = @db.toBool(row[1])
    }
    out << "Score Summary:\r\n" << log.call << "  QTH: " << log.qth << "\r\n\r\nBefore Log Checking:\r\n"
    claimedCW = totalClaimed(log.id, multID, "CW")
    claimedPH = totalClaimed(log.id, multID, "PH")
    cwScored = validQSOsByMode(log.id, multID, "CW")
    phScored = validQSOsByMode(log.id, multID, "PH")
    out << ("  Total Raw QSO's: %4d  CW: %4d  PH: %4d\r\n" % [log.numClaimed, claimedCW, claimedPH])
    out << ("  Claimed Mults:   %4d\r\n" % log.claimedMults)
    out << "  QSO Points Claimed: " << (3*claimedCW + 2*claimedPH) << "\r\n"
    out << "  Claimed Score: " << log.claimedMults * (3*claimedCW + 2*claimedPH) << "\r\n"
    out << "After Log Checking:\r\n"
    out << "  Duplicate QSO's: " << log.numDupe << "\r\n"
    out << "  Number of QSO's earning full or partial credit: " 
    out << (cwScored[1] + cwScored[2] + phScored[1] + phScored[2]) << "\r\n"
    out << ("  CW QSO's: Full Credit: %4d Half-Credit: %4d No-credit (NIL or Multiple Errors): %d\r\n" %
            [cwScored[2], cwScored[1], cwScored[0]])
    out << ("  PH QSO's: Full Credit: %4d Half-Credit: %4d No-credit (NIL or Multiple Errors): %d\r\n" %
            [phScored[2], phScored[1], phScored[0]])
    out << "  Checked Mults: " << log.nummultipliers << "\r\n"
    out << "  QSO Points granted: " << (log.numPH*2 + log.numCW*3) << "\r\n"
    out << "  FINAL SCORE: " << log.score << "\r\n"
    out << "\r\n"
  end

  def histReport(out, id, multID, desc, claimed, isCA)
    counts = Hash.new(0)
    multHistogram(id, multID, counts, claimed)
    out << "Histogram shows the number of #{desc} QSOs with each mult:\r\n\r\n"
    mults = isCA ? Log::CA_STATION_CREDITS : Log::CA_QTH
    count = 0
    mults.sort.each { |mult|
      out << (" %4d %-4s" % [counts[mult], mult])
      count += 1
      if ((count % 8) == 0)
        out << "\r\n"
      end
    }
    out << "\r\n\r\n"
  end
  
  def lcrMultiplierHistogram(out, log)
    multID = nil
    isCA = nil
    @db.query("select id, isCA from Multiplier where abbrev=? limit 1;", [log.qth]) { |row|
      multID = row[0].to_i
      isCA = @db.toBool(row[1])
    }
    if multID and not isCA.nil?
      histReport(out, log.id, multID, "claimed", true, isCA)
      histReport(out, log.id, multID, "verified", false, isCA)
    else 
      $stderr << "Unknown multiplier: '" << log.qth << "'\n"
    end
  end

  def serialNum(num)
    num ? num.to_i : 9999
  end

  def judgedLocation(qsoID)
    @db.query("select m.abbrev from Multiplier as m join QSO as q on m.id = q.judged_multiplierID where q.id = ? limit 1;", [ qsoID ]) { |row|
      return row[0]
    }
    return "XXXX"
  end

  def lcrQSOReport(out, log)
    @db.query("select q.frequency, q.fixedMode, q.time, qe.sent_callsign, q.sent_serial, coalesce(m1.abbrev,qe.sent_location) as sentmult,  qe.recvd_callsign, q.recvd_serial, coalesce(m2.abbrev,qe.recvd_location) as recvdmult, q.matchType, qe.comment, q.score, q.id from (QSO as q left join Multiplier as m1 on m1.id = q.sent_multiplierID) left join Multiplier as m2 on m2.id = q.recvd_multiplierID, QSOExtra as qe on q.id = qe.id where q.logID = ? and m1.abbrev = ? and (q.matchType in ('None','PartialBye','Unique', 'Partial', 'Dupe', 'NIL', 'OutsideContest', 'Removed') or (q.score != 2) or (q.recvd_multiplierID != q.judged_multiplierID)) order by q.time asc, q.sent_serial asc;",
             [ log.id, log.qth ]) { |row|
      td = @db.toDateTime(row[2]) + log.clockadj
      out << ("QSO: %5d %2s %4d-%02d-%02d %02d%02d %-10s %4d %-4s %-10s %4d %-4s\r\n" %
              [row[0], row[1], td.year, td.month, td.mday, td.hour, td.min, row[3], 
               serialNum(row[4]), row[5], row[6], serialNum(row[7]), row[8] ])
      case row[9]
      when 'Dupe'
        out << "   Duplicate QSO....removed without penalty...\r\n"
      when 'PartialBye'
        out << "   Half credit due received location mismatch (judged location is "
        out << judgedLocation(row[12]) << ")\r\n"
      when 'Unique'
        out << "   QSO removed because unique callsign and high serial number (most likely a busted call)\r\n"
      when 'OutsideContest'
        out << "   QSO removed because it is outside the contest time period.\r\n"
      when 'NIL'
        out << "   This QSO was removed without penalty because it is not in the received stations log (NIL)\r\n"
      when 'Removed'
        out << "   This QSO was removed without penalty: " << row[10] << "\r\n"
      when 'None'
        out << "   This QSO was removed (may indicate bug in scoring program): " << row[10] << "\r\n"
      when 'Full'
        if row[10].index("time mismatch")
          out << "   After inter-local clock reconciliation, the time in this log differs from the received stations log by more than 15 minutes.\r\n"
          if row[11] == 1
            out << "   Half-credit awarded for this QSO: " << row[10] << "\r\n"
          elsif row[11] == 0
            out << "   No credit awarded for this QSO: " << row[10] << "\r\n"
          end
        else
          if row[11] == 1
            out << "   Half-credit awarded for this QSO: " << row[10] << "\r\n"
          elsif row[11] == 0
            out << "   No credit awarded for this QSO: " << row[10] << "\r\n"
          end
        end
      when 'Partial'
        if row[11] == 1
          out << "  Half-credit awarded for this QSO: " << row[10] << "\r\n"
        elsif row[11] == 0
          out << "  No credit award for this QSO: "  << row[10] << "\r\n"
        end
      end
    }
    out << "\r\n"
  end
    

  def toxicLogReport(out = $stdout, contestID)
    logs = Array.new
    @db.query("select l.callsign, l.callID, count(*) from Log as l, QSO as q where q.logID = l.id and contestID = ? group by l.id order by l.callsign asc;", [contestID]) { |row|
      item = Array.new(3)
      item[0] = row[0]
      item[1] = row[1].to_i
      item[2] = row[2].to_i
      logs << item
    }
    csv = CSV.new(out)
    csv << ["Callsign", "Claimed QSOs", "# in other logs", "# Full", "# Partial", "# NIL", "# Removed" ]
    logs.each { |l|
      @db.query("select count(*), sum(matchType = 'Full'), sum(matchType = 'Partial'), sum(matchType = 'NIL'), sum(matchType = 'Removed') from QSO where recvd_callID = ? group by recvd_callID limit 1;", [ l[1] ]) { |row|
        csv << [ l[0], l[2], row[0], row[1], row[2], row[3], row[4] ]
      }
    }
  end

  def makeGreenReport(out = $stdout, contestID)
    logs = scoredLogs(contestID)
    logs.each { |log|
      out.write(log.ls_line + "\r\n")
    }
  end

  def makeReport(out = $stdout, contestID)
    logs = scoredLogs(contestID)
    logs.each { |log|
      @db.query("update Log set verifiedscore = ?, verifiedCWQSOs = ?, verifiedPHQSOs = ?, verifiedMultipliers = ? where id = ? limit 1;",
                [log.score, log.numCW, log.numPH, log.nummultipliers, log.id]) { }
    }
    out.write("\"Callsign\",\"QTH\",\"Email\",\"Operator Class\",\"QTH Class\",\"Power\",\"CCE?\",\"YOUTH?\",\"YL?\",\"NEW?\",\"SCHOOL?\",\"MOBILE?\",\"#Claimed QSOs\",\"#Verified PH QSOs\",\"#Verified CW QSOs\",\"# Unique\",\"# Dupe\",\"# Incorrectly copied\",\"# NIL\",\"# Outside contest period\",\"# D1\",\"# D2\",\"# Verified Multipliers\",\"Verified Score\",\"Multipliers\"\r\n")
    logs.each { |log|
      out.write(log.to_s + "\r\n")
    }
  end


  def timeTo58(id, multID, isCA)
    result = nil
    @db.query("select q.judged_multiplierID, min(q.time) as ftime from QSO as q join Multiplier as m on m.id = q.judged_multiplierID where q.logID = #{id} and q.sent_multiplierID = #{multID} and q.matchType in ('Full', 'Partial', 'Bye', 'PartialBye', 'Dupe') and m.ismultiplier and m.isCA = #{isCA ? @db.false : @db.true} group by q.judged_multiplierID order by ftime desc limit 1;") { |row|
      result = @db.toDateTime(row[1])
    }
    if result and isCA
      @db.query("select min(q.time) as ftime from QSO as q join Multiplier as m on m.id = q.judged_multiplierID where q.logID = #{id} and q.sent_multiplierID = #{multID} and q.matchTYpe in ('Full', 'Partial', 'Bye', 'PartialBye', 'Dupe') and m.ismultiplier and m.isCA limit 1;") { |row|
        newtime = @db.toDateTime(row[0])
        if newtime > result
          result = newtime
        end
      }
    end
    return result
  end

  def firstTo58(out = $stdout, contestID)
    results = Array.new
    @db.query("select distinct l.id, q.sent_multiplierID, m.isCA, m.abbrev, l.callsign from Log as l join QSO as q  on q.logID = l.id join Multiplier as m on m.id = q.sent_multiplierID where l.contestID = #{contestID} and l.verifiedMultipliers = 58 order by l.id asc;") { |row|
      results << [row[4], row[3], timeTo58(row[0], row[1], @db.toBool(row[2]))]
    }
    results.sort! { |x,y| x[2] <=> y[2] }
    results.each { |row|
      out.write("\"" + row[0] + "\",\"" + row[1] + "\",\"" + row[2].to_s + "\"\n")
    }
  end
end
