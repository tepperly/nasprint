#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'set'

class Log
  def initialize(call, email, opclass)
    @call = call
    @email = email
    @opclass = opclass
    @numFull = 0
    @numBye = 0
    @numUnique = 0
    @numDupe = 0
    @numPartial = 0
    @numRemoved = 0
    @numNIL = 0
    @numOutsideContest = 0
    @multipliers = Set.new
  end

  # 
  def incCount(type)
    sym = ("@num" + type).to_s
    if instance_variable_defined?(sym)
      instance_variable_set(sym,1+instance_variable_get(sym))
    else
      print "Unknown QSO type #{type}\n"
    end
  end

  def addMultiplier(name)
    @multipliers.add(name)
  end

  def to_s
    "\"#{@call}\",#{@email ? ("\"" + @email + "\"") : ""},\"#{@opclass}\",#{@numFull},#{@numBye},#{@numUnique},#{@numDupe},#{@numPartial+@numRemoved},#{@numNIL},#{@numOutsideContest},#{@numFull+@numBye-@numNIL},#{@multipliers.size},#{(@numFull+@numBye-@numNIL)*@multipliers.size},\"#{@multipliers.to_a.sort.join(", ")}\""
  end
end

class Report
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
  end

  def lookupMultiplier(id)
    res = @db.query("select m.abbrev, e.entityID from Multiplier as m, QSO as q, Exchange as e where q.id = #{id} and q.recvdID = e.id and e.multiplierID = m.id limit 1;")
    res.each(:as => :array) { |row|
      return row[0], row[1]
    }
    return nil, nil
  end

  def addMultiplier(log, qsoID)
    abbrev, entity = lookupMultiplier(qsoID)
    if "DX" == abbrev
      if entity
        res = @db.query("select name, continent from Entity where id = #{entity} limit 1;")
        res.each(:as => :array) { |row|
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

  def scoreLog(id, log)
    res = @db.query("select q.matchType, q.id from QSO as q where q.logID = #{id} order by q.time asc;")
    res.each(:as => :array) { |row|
      log.incCount(row[0])
      if ["Full", "Bye"].include?(row[0]) # QSO counts for credit
        addMultiplier(log, row[1])
      end
    }
  end

  def makeReport
    logs = Array.new
    res = @db.query("select callsign, email, opclass, id from Log where contestID = #{@contestID} order by callsign asc;")
    res.each(:as => :array) { |row|
      log = Log.new(row[0], row[1], row[2])
      scoreLog(row[3],log)
      logs << log
    }
    print "\"Callsign\",\"Email\",\"Operator Class\",\"#Fully matched QSOs\",\"# Bye QSOs\",\"# Unique\",\"# Dupe\",\"# Incorrectly copied\",\"# NIL\",\"# Outside contest period\",\"# Verified QSOs (full+bye-NIL)\",\"# Verified Multipliers\",\"Verified Score\",\"Multipliers\"\n"
    logs.each { |log|
      print log.to_s + "\n"
    }
  end
end
