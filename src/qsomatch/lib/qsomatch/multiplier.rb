#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'nokogiri'
require 'csv'
require_relative 'dxmap'
require_relative 'qrzdb'
require_relative 'logset'
require_relative 'cabrillo'

class Multiplier
  def initialize(db, contestID, cdb)
    @db = db
    @contestID = contestID
    @cdb = cdb
    @logs = LogSet.new(cdb.logsForContest(contestID))
    @previousDecisions = readPrevious
    @tojson = Hash.new
    @callDB = readXMLDb
    lookupStates
  end

  def readPrevious
    if File.readable?("callmults.json")
      result = JSON.parse(File.read("callmults.json"))
    elsif File.readable?("callmults.csv")
      result = Hash.new
      CSV.foreach("callmults.csv") {|row|
        result[row[0]] = row[1]
      }
    end
    result
  end

  def savePrevious(filename)
    File.write(filename, @tojson)
  end

  def lookupStates
    @hawaiiID = nameToID('HI')
    @alaskaID = nameToID('AK')
    @dxID = nameToID('DX')
  end

  def nameToID(str)
    @db.query("select id from Multiplier where abbrev = ? limit 1;", [str]) { |row|
      return row[0].to_i
    }
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

  def callLocation(callsign)
    county = nil
    state = nil
    dxcc = nil
    begin
      if @callDB.has_key?(callsign) and File.readable?(@callDB[callsign])
        filename = @callDB[callsign]
      elsif File.readable?("xml_db/" + callsign.upcase.gsub(/[^a-z0-9]/i,"_") +
                           ".xml")
        filename = "xml_db/" + callsign.upcase.gsub(/[^a-z0-9]/i,"_") +
                           ".xml"
      else
        filename = nil
      end
      if (filename) 
        open(filename, "r:iso8859-1:utf-8") { |io|
          xml = Nokogiri::XML(io)
          xml.xpath("//qrz:Callsign/qrz:county", XML_NAMESPACE).each { |match|
            county = match.text.strip
          }
          xml.xpath("//qrz:Callsign/qrz:state", XML_NAMESPACE).each { |match|
            state = match.text.strip
          }
          xml.xpath("//qrz:Callsign/qrz:dxcc", XML_NAMESPACE).each { |match|
            dxcc = match.text.strip.to_i
            if dxcc == 0
              dxcc = nil
            end
          }
        }
      end
    rescue
      $stderr.write("Exception caught: #{$!}\n" + $!.backtrace.join("\n") + "\n")
    end
    return state, county, dxcc
  end

  def checkOverride(call)
    @db.query("select entityID from Overrides where contestID = ? and callsign = ? limit 1;",
              [@contestID, call]) { |row|
      return row[0].to_i 
    }
    nil
  end

  def resolveDX
    dxlookup = CallsignLocator.new
    @db.query("select distinct c.id, c.basecall from QSO as q, Callsign as c, Multiplier as m where q.matchType in ('Full', 'Bye', 'Partial', 'PartialBye') and m.abbrev='DX' and c.id = q.recvd_callID and q.recvd_entityID is null and m.id = q.recvd_multiplierID and #{@logs.membertest("q.logID")};") { |row|
      entity = checkOverride(row[1])
      override = entity
      if not entity and @callDB.has_key?(row[1])
        entity = lookupEntity(@callDB[row[1]])
      end
      if not entity
        ent = dxlookup.lookup(row[1])
        if ent
          if ent.dx?
            entity = ent.entityID
          end
        end
        if not entity
          print "Please enter entity ID # for #{row[1]}:"
          entity = STDIN.gets.to_i
        end
      end
      if entity
        case entity
        when 6 # Alaska
          @db.query("update QSO set recvd_entityID = ?, judged_multiplierID = ? where recvd_callID = ?;",
                    [entity, @alaskaID, row[0]]) { }
          @db.query("update QSO set sent_entityID = ?, sent_multiplierID = ? where sent_callID = ?;",
                    [entity, @alaskaID, row[0]]) { }
        when 110 # Hawaii
          @db.query("update QSO set recvd_entityID = ?, judged_multiplierID = ? where recvd_callID = ?;",
                    [entity, @hawaiiID, row[0]]) { }
          @db.query("update QSO set sent_entityID = ?, sent_multiplierID = ? where sent_callID = ?;",
                    [entity, @hawaiiID, row[0]]) { }
        else
          if override
            @db.query("update QSO set recvd_entityID = ? where recvd_callID = ?;",
                      [entity, row[0]]) { }
            @db.query("update QSO set sent_entityID = ? where sent_callID = ?;",
                      [entity, row[0]]) { }
            
          else
            @db.query("update QSO set recvd_entityID = ? where recvd_callID = ? and recvd_entityID is null;",
                      [entity, row[0]]) { }
            @db.query("update QSO set sent_entityID = ? where sent_callID = ? and sent_entityID is null;",
                      [entity, row[0]]) { }
          end
        end
      else
        print "Skipping callsign #{row[1]}\n"
      end
    }

    @db.query("select distinct l.id, c.basecall, l.callsign, m.entityID from Log as l join Callsign as c on l.callID = c.id left join Multiplier as m on m.id = l.multiplierID where l.entityID is null;") { |row|
      if row[3]
        @db.query("update Log set entityID = ? where id = ? limit 1;",
                  [row[3].to_i, row[0].to_i]) { }
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
          @db.query("update Log set entityID = ? where id = ? limit 1;",
                    [entity.to_i, row[0].to_i]) { }
        end
      end
    }
  end

  def toHash(res)
    result = Hash.new
    total = 0
    res.each  {|row|
      result[row[0].to_i] = [ row[0].to_i, row[1], row[2] ]
      total = total + row[2]
    }
    return result, total
  end


  def twoThirdsMajority(hash, total)
    hash.each { |k,item|
      if (item[2].to_f/total.to_f) >= 2.0/3.0 # two-third majority
        return item[0], item[1]
      end
    }
    nil
  end


  def qrzMostPopular(qrzId, hash)
    if hash.include?(qrzId)
      value = hash[qrzId][2]
      hash.each { |k,v|
        if v[2] > value
          return false
        end
      }
      return true
    end
    false
  end

  def askUser(callsign,hash)
    state, county, dxcc = callLocation(callsign)
    if dxcc and not [ 291, 110, 6 ].include?(dxcc)
      if hash.include?(@dxID)
        if qrzMostPopular(@dxID, hash)
          return @dxID, "DX"
        end
      else
        hash[@dxID] = [ @dxID, 'DX', 0]
      end
    else
      if state
        if county
          print "State: #{state}   County: #{county}\n"
          if state == "CA"
            id, entity = @cdb.lookupMultiplier(county)
            if id 
              if hash.include?(id)
                if qrzMostPopular(id, hash)
                  return id, @cdb.lookupMultiplierByID(id)
                end
              else
                hash[id] = [id, @cdb.lookupMultiplierByID(id), 0]
              end
            end
          else
          end
        else
          print "State: #{state}\n"
        end
        if not (state == "CA" and county)
          id, entity = @cdb.lookupMultiplier(state)
          if id
            if hash.include?(id)
              if qrzMostPopular(id, hash)
                return id, @cdb.lookupMultiplierByID(id)
              end
            else
              hash[id] = [id, @cdb.lookupMultiplierByID(id), 0]
            end
          end
        end
      end
    end
    list = hash.keys.sort { |x,y| hash[y][2] <=> hash[x][2] }
    print "Possible locations for callsign: #{callsign}\n"
    list.each { |item|
      print "ID #{item} #{hash[item][1]} #{hash[item][2]}\n"
    }
    if @previousDecisions.has_key?(callsign)
      @tojson[callsign] = @previousDecisions[callsign]
      num, entID = @cdb.lookupMultiplier(@previousDecisions[callsign])
      return num, @previousDecisions[callsign]
    else
      print "Please enter the ID number: "
      item = STDIN.gets
      num = item.strip.to_i
      list.each { |item|
        if item[0] == num
          return num, item[1]
        end
      }
    end
    return num, nil
  end

  def updateByeQSOs(id, choice, name)
    @db.query("update QSO set judged_multiplierID = ? where matchType='Bye' and recvd_callID = ? and recvd_multiplierID = ? and judged_multiplierID is null and #{@logs.membertest("logID")};",
              [ choice, id, choice ] )
    @db.query("update QSO set judged_multiplierID = ?, matchType='PartialBye' where matchType='Bye' and recvd_callID = ? and recvd_multiplierID != ? and judged_multiplierID is null and #{@logs.membertest("logID")};",
              [choice, id, choice] )
    return @db.affected_rows
  end
  

  def resolveAmbiguous(id, res, callsign)
    hash, total = toHash(res)
    choice, name = twoThirdsMajority(hash, total)
    if not choice
      choice, name = askUser(callsign,hash)
    end
    if choice and choice > 0
      return updateByeQSOs(id, choice, name)
    end
    0
  end

  def checkByeMultipliers
    print "Checking Bye multipliers\n"
    count = 0
    @db.query("select c.id, c.basecall, count(*) as numQ from Callsign as c, QSO as q where #{@logs.membertest("q.logID")} and q.matchType = 'Bye' and q.judged_multiplierID is null and c.id = q.recvd_callID group by c.id having numQ >= 1;") { |row|
      multres = @db.query("select m.id, m.abbrev, count(*) from QSO as q, Multiplier as m where q.recvd_callID=? and q.recvd_multiplierID=m.id and q.matchType = 'Bye' and q.judged_multiplierID is null group by m.id;",
                          [row[0]])
      if multres.count > 1
        count = count + resolveAmbiguous(row[0], multres, row[1])
      else
        multres.each { |mrow|
          @db.query("update QSO set judged_multiplierID = ? where recvd_callID = ? and judged_multiplierID is null and #{@logs.membertest("logID")} and matchType='Bye';",
                    [ mrow[0], row[0] ]) { }
        }
      end
      multres = nil
    }
    print "#{count} Bye QSOs are partial matches\n"
  end

  def transferJudged
    count = 0
    @db.query("select q1.id, q2.sent_multiplierID from QSO as q1 join QSO as q2 on q2.id = q1.matchID where #{@logs.membertest("q1.logID")} and q1.matchID is not null and q1.judged_multiplierID is null and q2.sent_multiplierID is not null;") { |row|
      @db.query("update QSO set judged_multiplierID = ? where id = ? limit 1;",
                [ row[1], row[0] ]) { }
      count += @db.affected_rows
    }
    count
  end

  def checkSentMultIDs
    count = 0
    @db.query("select q.logID, q.sent_callID from QSO as q where #{@logs.membertest("q.logID")} and (q.sent_multiplierID is null) group by q.logID, q.sent_callID order by q.logID asc;") { |row|
      print "Station #{@cdb.logCallsign(row[0])} has missing sent multiplier information\n"
    }
    count
  end

  def rarestMults(limit, isCA)
    result = Array.new
    @db.query("select m.id, count(*) as num from Multiplier as m join QSO as q on q.judged_multiplierID = m.id where #{@logs.membertest("q.logID")} and #{isCA ? "m.isCA" : "not m.isCA"} and m.ismultiplier and q.matchType in ('Full','Bye','PartialBye','Partial') group by m.id order by num asc limit #{limit.to_i};") { |row|
      result << row[0].to_i
    }
    result
  end

  def allCallsigns(id, multID)
    result = Array.new
    @db.query("select distinct qe.recvd_callsign from QSOExtra as qe join QSO as q on q.id = qe.id and q.recvd_callID = ? and q.judged_multiplierID = ? where #{@logs.membertest("q.logID")} order by qe.recvd_callsign asc;", [ id, multID ]) { |row|
      result << row[0]
    }
    result.join(" ")
  end

  def qLoc(isQRZ, callsign)
    if isQRZ
      state, county, dcxx = callLocation(callsign)
      if "CA" == state
        return Cabrillo.normalMult(county)
      else
        return state
      end
    else
      "????"
    end
  end
  
  def rareMultGroupReport(ids)
    prev = nil
    @db.query("select m.abbrev, c.basecall, c.logrecvd, c.validcall, count(*) as num, c.id, m.id from Multiplier as m join QSO as q on q.judged_multiplierID = m.id join Callsign as c on c.id = q.recvd_callID where #{@logs.membertest("q.logID")} and q.matchType in ('Full','Bye','PartialBye','Partial') and m.id in (#{ids.join(", ")}) group by m.id, c.id order by m.id asc, num desc;") { |row|
      if (row[0] != prev) 
        print "Multiplier: " + row[0] + "\n"
        print "    %-8s %-5s %-5s %-4s %-4s %s\n" % ["Station", "Log?", "QRZ?",
                                               "QLOC", "#", "Callsigns"]
        prev = row[0]
      end
      print "    %-8s %-5s %-5s %-4s %4d %s\n" % 
        [row[1], @db.toBool(row[2]).to_s,
         @db.toBool(row[3]).to_s,
         qLoc(@db.toBool(row[3]), row[1]),
         row[4].to_i, 
         allCallsigns(row[5].to_i, 
                      row[6].to_i) ]
    }
  end

  def rareMultReport
    topFiveCA = rarestMults(5, true)
    topFiveNonCA = rarestMults(5, false)
    print "Top Five Rarest CA Multipliers\n"
    rareMultGroupReport(topFiveCA)
    print "\nTop Five Rarest non-CA Multipliers\n"
    rareMultGroupReport(topFiveNonCA)
  end
end
