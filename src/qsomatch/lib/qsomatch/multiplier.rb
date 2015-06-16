#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'nokogiri'
require_relative 'qrzdb'

class Multiplier
  def initialize(db, contestID, cdb)
    @db = db
    @contestID = contestID
    @logs = cdb.logsForContest(contestID)
    @callDB = readXMLDb
    lookupStates
  end

  def lookupStates
    res = @db.query("select id from Multiplier where abbrev='HI' limit 1;")
    res.each { |row| @hawaiiID = row[0].to_i }
    res = @db.query("select id from Multiplier where abbrev='AK' limit 1;")
    res.each { |row| @alaskaID = row[0].to_i }
  end

  XML_NAMESPACE = {'qrz' => 'http://xmldata.qrz.com'}
  def lookupEntity(filename)
    open(filename, "r:iso8859-1:utf-8") { |io|
      xml = Nokogiri::XML(io)
      xml.xpath("//qrz:Callsign/qrz:dxcc", XML_NAMESPACE).each { |match|
        return match.text.strip.to_i
      }
    }
    nil
  end

  def checkOverride(call)
    res = @db.query("select entityID from Overrides where contestID = #{@contestID} and callsign = \"#{call}\" limit 1;")
    res.each { |row| 
      return row[0].to_i 
    }
    nil
  end

  def resolveDX
    res = @db.query("select distinct c.id, c.basecall from QSO as q, Callsign as c, Multiplier as m where q.matchType in ('Full', 'Bye') and m.abbrev='DX' and c.id = q.recvd_callID and m.entityID is null and m.id = q.recvd_multiplierID and q.logID in (#{@logs.join(", ")});")
    res.each { |row|
      entity = checkOverride(row[1])
      override = entity
      if not entity and @callDB.has_key?(row[1])
        entity = lookupEntity(@callDB[row[1]])
      end
      if not entity
        print "Please enter entity ID # for #{row[1]}:"
        entity = STDIN.gets.to_i
      end
      if entity
        case entity
        when 6 # Alaska
          @db.query("update QSO set recvd_entityID = #{entity}, recvd_multiplierID = #{@alaskaID} where recvd_callID = #{row[0]};")
          @db.query("update QSO set sent_entityID = #{entity}, sent_multiplierID = #{@alaskaID} where sent_callID = #{row[0]};")
        when 110 # Hawaii
          @db.query("update QSO set recvd_entityID = #{entity}, recvd_multiplierID = #{@hawaiiID} where recvd_callID = #{row[0]};")
          @db.query("update QSO set sent_entityID = #{entity}, sent_multiplierID = #{@hawaiiID} where sent_callID = #{row[0]};")
        else
          if override
            @db.query("update QSO set recvd_entityID = #{entity} where recvd_callID = #{row[0]};")
            @db.query("update QSO set sent_entityID = #{entity} where sent_callID = #{row[0]};")
          else
            @db.query("update QSO set recvd_entityID = #{entity} where recvd_callID = #{row[0]} and recvd_entityID is null;")
            @db.query("update QSO set sent_entityID = #{entity} where sent_callID = #{row[0]} and sent_entityID is null;")
          end
        end
      else
        print "Skipping callsign #{row[1]}\n"
      end
    }

    res = @db.query("select distinct l.id, c.basecall, l.callsign, m.entityID from Log as l join Callsign as c on l.callID = c.id left join Multiplier as m on m.id = l.multiplierID where l.entityID is null;")
    res.each { |row|
      if row[3]
        @db.query("update Log set entityID = #{row[3].to_i} where id = #{row[0].to_i} limit 1;")
      else                      # multiplier entity is NULL
        entity = checkOverride(row[1])
        override = entity
        if not entity and @callDB.has_key?(row[1])
          entity = lookupEntity(@callDB[row[1]])
        end
        if not entity and @callDB.has_key?(row[2])
          entity = lookupEntity(@callDB[row[2]])
        end
        if entity
          @db.query("update Log set entityID = #{entity.to_i} where id = #{row[0].to_i} limit 1;")
        end
      end
    }
  end

  def toArray(res)
    list = Array.new
    total = 0
    res.each  {|row|
      list << [ row[0], row[1], row[2] ]
      total = total + row[2]
    }
    return list, total
  end


  def twoThirdsMajority(list, total)
    list.each { |item|
      if (item[2].to_f/total.to_f) >= 2.0/3.0 # two-third majority
        return item[0], item[1]
      end
    }
    nil
  end

  def askUser(list)
    list = list.sort { |x,y| y[2] <=> x[2] }
    list.each { |item|
      print "ID #{item[0]} #{item[1]} #{item[2]}\n"
    }
    print "Please enter the ID number: "
    item = STDIN.gets
    num = item.strip.to_i
    list.each { |item|
      if item[0] == num
        return num, item[1]
      end
    }
    return num, nil
  end

  def markDiscentingQSOasRemoved(id, choice, name)
    qlist = Array.new
    res = @db.query("select q.id from QSO as q where q.recvd_callID = #{id} and q.matchType='Bye' and q.recvd_multiplierID != #{choice};")
    res.each { |row|
      qlist << row[0].to_i
    }
    if not qlist.empty?
      @db.query("update QSO set matchType='Removed', comment='Location mismatch #{name}' where id in (#{qlist.join(", ")});")
      return @db.affected_rows
    end
    0
  end
  

  def resolveAmbiguous(id, res)
    list, total = toArray(res)
    choice, name = twoThirdsMajority(list, total)
    if not choice
      choice, name = askUser(list)
    end
    if choice
      return markDiscentingQSOasRemoved(id, choice, name)
    end
    0
  end

  def checkByeMultipliers
    print "Checking Bye multipliers\n"
    res = @db.query("select c.id, c.basecall, count(*) as numQ from Callsign as c, QSO as q where q.logID in (#{@logs.join(", ")}) and q.matchType = 'Bye' and c.id = q.recvd_callID group by c.id having numQ > 1;")
    count = 0
    res.each { |row|
      multres = @db.query("select m.id, m.abbrev, count(*) from QSO as q, Multiplier as m where q.recvd_callID=#{row[0]} and q.recvd_multiplierID=m.id and q.matchType = 'Bye' group by m.id;")
      if multres.count > 1
        count = count + resolveAmbiguous(row[0], multres)
      end
    }
    print "#{count} Bye QSOs changed to Removed\n"
  end
end
