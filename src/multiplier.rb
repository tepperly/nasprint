#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'nokogiri'
require_relative 'qrzdb'

class Multiplier
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
    @logs = queryContestLogs
    @callDB = readXMLDb
    lookupStates
  end

  def queryContestLogs
    logList = Array.new
    res = @db.query("select id from Log where contestID = #{@contestID} order by id asc;")
    res.each(:as => :array) { |row|
      logList << row[0].to_i
    }
    return logList
  end

  def lookupStates
    res = @db.query("select id from Multiplier where abbrev='HI' limit 1;")
    res.each(:as => :array) { |row| @hawaiiID = row[0].to_i }
    res = @db.query("select id from Multiplier where abbrev='AK' limit 1;")
    res.each(:as => :array) { |row| @alaskaID = row[0].to_i }
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

  def resolveDX
    res = @db.query("select distinct c.id, c.basecall from QSO as q, Exchange as e, Callsign as c, Multiplier as m where q.matchType in ('Full', 'Bye') and q.recvdID = e.id and m.abbrev='DX' and c.id = e.callID and m.entityID is null and m.id = e.multiplierID and q.logID in (#{@logs.join(", ")});")
    res.each(:as => :array) { |row|
      entity = nil
      if @callDB.has_key?(row[1])
        entity = lookupEntity(@callDB[row[1]])
      end
      if not entity
        print "Please enter entity ID # for #{row[1]}:"
        entity = STDIN.gets.to_i
      end
      if entity
        case entity
        when 6 # Alaska
          @db.query("update Exchange set entityID = #{entity}, multiplierID = #{@alaskaID} where callID = #{row[0]};")
        when 110 # Hawaii
          @db.query("update Exchange set entityID = #{entity}, multiplierID = #{@hawaiiID} where callID = #{row[0]};")
        else
          @db.query("update Exchange set entityID = #{entity} where callID = #{row[0]} and entityID is null;")
        end
      else
        print "Skipping callsign #{row[1]}\n"
      end
    }
  end

  def toArray(res)
    list = Array.new
    total = 0
    res.each(:as => :array)  {|row|
      list << [ row[0], row[1], row[2] ]
      total = total + row[2]
    }
    return list, total
  end


  def twoThirdsMajority(list, total)
    list.each { |item|
      if (item[2].to_f/total.to_f) >= 2.0/3.0 # two-third majority
        return item[0]
      end
    }
    nil
  end

  def askUser(list)
    list = list.sort { |x,y| y[2] <=> x[2] }
    last.each { |item|
      print "ID #{item[0]} #{item[1]} #{item[2]}\n"
    }
    print "Please enter the ID number: "
    item = STDIN.gets
    item.strip.to_i
  end

  def markDiscentingQSOasRemoved(id, choice)
    qlist = Array.new
    res = @db.query("select q.id from QSO as q, Exchange as e where e.id = q.recvdID and e.callID = #{id} and q.matchType='Bye' and e.multiplierID != #{choice};")
    res.each(:as => :array) { |row|
      qlist << row[0].to_i
    }
    if not qlist.empty?
      @db.query("update QSO set matchType='Removed' where id in (#{qlist.join(", ")});")
      return @db.affected_rows
    end
    0
  end
  

  def resolveAmbiguous(id, res)
    list, total = toArray(res)
    choice = twoThirdsMajority(list, total)
    if not choice
      choice = askUser(list)
    end
    if choice
      return markDiscentingQSOasRemoved(id, choice)
    end
    0
  end

  def checkByeMultipliers
    print "Checking Bye multipliers\n"
    res = @db.query("select c.id, c.basecall, count(*) as numQ from Callsign as c, QSO as q, Exchange as e where q.logID in (#{@logs.join(", ")}) and q.matchType = 'Bye' and q.recvdID = e.id and c.id = e.callID group by c.id having numQ > 1;")
    count = 0
    res.each(:as => :array) { |row|
      multres = @db.query("select m.id, m.abbrev, count(*) from QSO as q, Exchange as e, Multiplier as m where e.callID=#{row[0]} and e.multiplierID=m.id and q.recvdID=e.id and q.matchType = 'Bye' group by m.id;")
      if multres.count > 1
        count = count + resolveAmbiguous(row[0], multres)
      end
    }
    print "#{count} Bye QSOs changed to Removed\n"
  end
end
