#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'set'

class Log
  WAS = %w(AK AL AR AZ CA CO CT DE FL GA HI IA ID IL IN KS KY LA MA ME MI 
           MN MO MS MT NC ND NE NH NJ NM NV NY OH OK OR PA RI SC SD TN TX 
           UT VA VT WA WI WV WY ).freeze

  def initialize(call, email, opclass, location, entity, continent)
    @call = call
    @email = email
    @opclass = opclass
    @location = location
    @entity = entity
    @continent = continent
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

  def numqsos
    @numFull+@numBye-@numNIL
  end

  def nummultipliers
    @multipliers.size
  end

  def was?
    WAS.each { |state| 
      if not @multipliers.include?(state)
        return false
      end
    }
    return (@multipliers.include?("MD") or @multipliers.include?("DC"))
  end

  def score
    numqsos * nummultipliers
  end

  def to_s
    "\"#{@call}\",#{@email ? ("\"" + @email + "\"") : ""},\"#{@opclass}\",\"#{@location}\",\"#{@entity}\",\"#{@continent}\",#{@numFull},#{@numBye},#{@numUnique},#{@numDupe},#{@numPartial+@numRemoved},#{@numNIL},#{@numOutsideContest},#{was? ? 1 : 0},#{@numFull+@numBye-@numNIL},#{@multipliers.size},#{(@numFull+@numBye-@numNIL)*@multipliers.size},\"#{@multipliers.to_a.sort.join(", ")}\""
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

  def makeReport(out = $stdout)
    logs = Array.new
    res = @db.query("select l.callsign, l.email, l.opclass, l.id, m.abbrev, e.name, e.continent from Log as l, Multiplier as m, Entity as e where contestID = #{@contestID} and l.multiplierID = m.id  and e.id = l.entityID order by callsign asc;")
    res.each(:as => :array) { |row|
      log = Log.new(row[0], row[1], row[2], row[4], row[5], row[6])
      scoreLog(row[3],log)
      @db.query("update Log set verifiedscore = #{log.score}, verifiedQSOs = #{log.numqsos}, verifiedMultipliers = #{log.nummultipliers} where id = #{row[3]} limit 1;")
      logs << log
    }
    out.write("\"Callsign\",\"Email\",\"Operator Class\",\"Location\",\"Entity\",\"Continent\",\"#Fully matched QSOs\",\"# Bye QSOs\",\"# Unique\",\"# Dupe\",\"# Incorrectly copied\",\"# NIL\",\"# Outside contest period\",\"WAS?\",\"# Verified QSOs (full+bye-NIL)\",\"# Verified Multipliers\",\"Verified Score\",\"Multipliers\"\r\n")
    logs.each { |log|
      out.write(log.to_s + "\r\n")
    }
  end
end
