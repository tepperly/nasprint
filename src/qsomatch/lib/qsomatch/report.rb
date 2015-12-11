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
  CAN_QTH = Set.new(%w{ AB BC MB MR NT ON QC SK })

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
  
  def initialize(call, email, opclass, qth, isCCE, isYOUTH, isYL, isNEW, isSCHOOL,isMOBILE)
    @call = call
    @qth = qth
    @email = email
    @opclass = opclass
    @numClaimed = 0
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
  end

  attr_reader :numPH, :numCW, :numUnique, :numDupe, :numRemoved, :numNIL, 
        :numOutsideContest, :numClaimed, :numD1, :numD2
  attr_writer :numPH, :numCW, :numUnique, :numDupe, :numRemoved, :numNIL, 
        :numOutsideContest, :numClaimed, :numD1, :numD2

  def addMultiplier(name)
    @multipliers.add(name)
  end

  def nummultipliers
    @multipliers.size
  end

  def score
    ( numPH*2 + numCW*3) * nummultipliers
  end

  def to_s
    "\"#{@call}\",\"#{@qth}\",#{@email ? ("\"" + @email + "\"") : ""},\"#{@opclass}\",\"#{qthClass}\",\"#{@isCCE}\",\"#{@isYOUTH}\",\"#{@isYL}\",\"#{@isNEW}\",\"#{@isSCHOOL}\",\"#{@isMOBILE}\",#{@numClaimed},#{@numPH},#{@numCW},#{@numUnique},#{@numDupe},#{@numRemoved},#{@numNIL},#{@numOutsideContest},#{@numD1},#{@numD2},#{@multipliers.size},#{score},\"#{@multipliers.to_a.sort.join(", ")}\""
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

  def totalClaimed(id, multID)
    @db.query("select count(*) from QSO where logID = ? and sent_multiplierID = ? limit 1;", [id, multID]) { |row|
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

  def calcMultipliers(id, log, multID)
    isCA = @db.true
    @db.query("select m.isCA from Multiplier as m join Log as l on l.multiplierID = m.id where l.id = ? limit 1;", [ id ]) { |row|
      isCA = row[0]
    }
    @db.query("select distinct m.abbrev from Multiplier as m join (Log as l join QSO as q on l.id = q.logID) on q.judged_multiplierID = m.id where l.id = ? and q.matchType in ('Full','Partial','Bye', 'PartialBye') and q.sent_multiplierID = ? and q.score >= 1 and m.ismultiplier and m.isCA != ?; ", 
              [id, multID, isCA]) { |row|
      log.addMultiplier(row[0])
    }
    if @db.toBool(isCA)
      # for CA stations any CA county counts as a CA multiplier
      @db.query("select m.id from Multiplier as m join (Log as l join QSO as q on l.id = q.logID) on q.judged_multiplierID = m.id where l.id = ? and q.matchType in ('Full','Partial','Bye', 'PartialBye') and q.sent_multiplierID = ? and q.score >= 1 and m.ismultiplier and m.isCA limit 1;", [ id, multID ]) { |row|
        log.addMultiplier("CA")
      }
    end
  end

  MULTIPLIER_CREDIT = Set.new(%w( Full Partial Bye PartialBye)).freeze
  def scoreLog(id, multID, log)
    log.numD1 = numPartial(id, multID, 1)
    log.numD2 = numPartial(id, multID, 0)
    log.numClaimed = totalClaimed(id, multID)
    log.numPH = qsoTotal(id, "PH", multID)
    log.numCW = qsoTotal(id, "CW", multID)
    log.numNIL = modeTotal(id, "NIL", multID)
    log.numUnique = modeTotal(id, "Unique", multID)
    log.numDupe = modeTotal(id, "Dupe", multID)
    log.numRemoved = modeTotal(id, "Removed", multID)
    log.numOutsideContest = modeTotal(id, "OutsideContest", multID)
    calcMultipliers(id, log, multID)
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

  def makeReport(out = $stdout, contestID)
    logs = Array.new
    @db.query("select distinct l.callsign, l.email, l.opclass, l.id, m.id, m.abbrev, l.isCCE, l.isYOUTH, l.isYL, l.isNEW, l.isSCHOOL, l.isMOBILE from Log as l join QSO as q on l.id = q.logID join Multiplier as m on m.id = q.sent_multiplierID  where contestID = ? order by callsign asc;", [contestID]) { |row|
      log = Log.new(row[0], row[1], row[2], row[5], @db.toBool(row[6]), @db.toBool(row[7]), @db.toBool(row[8]), @db.toBool(row[9]), @db.toBool(row[10]), @db.toBool(row[11]))
      scoreLog(row[3], row[4], log)
      @db.query("update Log set verifiedscore = #{log.score}, verifiedCWQSOs = ?, verifiedPHQSOs = ?, verifiedMultipliers = ? where id = ? limit 1;",
                [log.numCW, log.numPH, log.nummultipliers, row[3]]) { }
      logs << log
    }
    out.write("\"Callsign\",\"QTH\",\"Email\",\"Operator Class\",\"QTH Class\",\"CCE?\",\"YOUTH?\",\"YL?\",\"NEW?\",\"SCHOOL?\",\"MOBILE?\",\"#Claimed QSOs\",\"#Verified PH QSOs\",\"#Verified CW QSOs\",\"# Unique\",\"# Dupe\",\"# Incorrectly copied\",\"# NIL\",\"# Outside contest period\",\"# D1\",\"# D2\",\"# Verified Multipliers\",\"Verified Score\",\"Multipliers\"\r\n")
    logs.each { |log|
      out.write(log.to_s + "\r\n")
    }
  end
end
