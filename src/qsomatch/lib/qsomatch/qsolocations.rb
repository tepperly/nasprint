#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'yaml'
require 'csv'
require 'nokogiri'
require_relative 'dxmap'
require_relative 'qrzdb'

def qsoInfo(num)
  num = num.to_i
  return "q#{num}.time, coalesce(q#{num}.judged_band, q#{num}.band), coalesce(q#{num}.judged_mode, q#{num}.fixedMode), c#{num}.basecall, m#{num}.abbrev"
end

def receivedInfo
  return "c2.basecall, m2.abbrev"
end

def checkOverrides(overrides, callsign, multiplier, time)
  if overrides and overrides.has_key?("callsigns") and overrides["callsigns"].has_key?(callsign)
    calloverride = overrides["callsigns"][callsign]
    if calloverride.has_key?("location") and calloverride["location"].has_key?(multiplier)
      return calloverride["location"][multiplier][0..1] << true
    end
  end
  nil
end

# XML_NAMESPACE = {'qrz' => 'http://xmldata.qrz.com'}
FIRST_CHARACTERS = /^[A-R][A-R]/i
SECOND_CHARACTERS = /^[A-X][A-X]/i

def interpretMaidenhead(str)
  if not str.empty? and str.length.even?
    first = true
    letterRegex= FIRST_CHARACTERS
    numberRegex=/^[0-9][0-9]/
    characterNumber = 18
    latitude=-90.0
    latitudeMult = 180/characterNum
    longtudeMult = 360.0/characterNum
    longitude=-180.0
    letters=true
    while not str.empty?
      if letters
        if letterRegex =~ str
          longitude += longitudeMult*(str[0].upcase.ord-'A'.ord)
          latitude += latitudeMult*(str[1].upcase.ord-'A'.ord)
          letterRegex = SECOND_CHARACTERS
          characterNumber = 24
          longitudeMult /= characterNumber
          latitudeMult /= characterNumber
        else
          return nil,nil
        end
      else
        if numberRegex =~ str
          longitude += longitudeMult*(str[0].ord-'0'.ord)
          latitude += latitudeMult*(str[1].ord-'0'.ord)
          longitudeMult /= 10
          latitudeMult /= 10
        else
          return nil, nil
        end
      end
      letters = (not letters)
      str = str[2..-1]          # remove first two characters
    end
    return latitude+0.5*latitudeMult, longitude+0.5*longitudeMult
  end
  return nil, nil
end

def checkXML(callsign, multiplier, filename, countyAbbrevs)
  open(filename, "r:iso8859-1:utf-8") { |io|
    xml = Nokogiri::XML(io)
    latitude=nil
    longitude=nil
    maidenhead=nil
    county=nil
    state=nil
    xml.xpath("//qrz:Callsign/qrz:lat", XML_NAMESPACE).each { |match|
      latitude = match.text.strip.to_f
    }
    xml.xpath("//qrz:Callsign/qrz:lon", XML_NAMESPACE).each { |match|
     longitude = match.text.strip.to_f
    }
    xml.xpath("//qrz:Callsign/qrz:grid", XML_NAMESPACE).each { |match|
     maidenhead = match.text.strip
    }
    if maidenhead and not (latitude and longitude)
      latitude, longitude = interpretMaidenhead(maidenhead)
    end
    if (latitude and longitude)
      xml.xpath("//qrz:Callsign/qrz:state", XML_NAMESPACE).each { |match|
        state = match.text.strip
      }
      if state == multiplier and state != "CA"
        return [latitude, longitude, true]
      end
      xml.xpath("//qrz:Callsign/qrz:county", XML_NAMESPACE).each { |match|
        county = match.text.strip
        if (countyAbbrevs.has_key?(multiplier) and (countyAbbrevs[multiplier] == county)) # California county
          return [latitude, longitude, true]
        end
      }
    end
  }
  nil
end

def callsignLocation(callsign, multiplier, awayFromHome, time, overrides, dxloc, foundCallsigns, xmlDB, countyAbbrevs)
  if foundCallsigns.has_key?(callsign) and foundCallsigns[callsign].has_key?(multiplier)
    return foundCallsigns[callsign][multiplier]
  end
  loc = checkOverrides(overrides, callsign, multiplier, time)
  if loc
    if loc[2]
      foundCallsigns[callsign] = Hash.new
      foundCallsigns[callsign][multiplier] = loc[0..1]
    end
    return loc[0..1]
  end
  if not awayFromHome and xmlDB.has_key?(callsign)
    loc = checkXML(callsign, multiplier, xmlDB[callsign], countyAbbrevs)
    if loc
      if loc[2]
        foundCallsigns[callsign] = Hash.new
        foundCallsigns[callsign][multiplier] = loc[0..1]
      end
      return loc[0..1]
    end
  end
  
end

def logInfo(num)
  num = num.to_i
  return "l#{num}.clockadj, l#{num}.trustedclock, l#{num}.isCCE or l#{num}.isMOBILE or l#{num}.isONEDAY or l#{num}.isCOUNTYLINE"
end

def tableSources(num)
  num = num.to_i
  return "QSO as q#{num}, Log as l#{num}, Callsign as c#{num}, Multiplier as m#{num}"
end

def basicLinks(num, contestID)
  num = num.to_i
  return "l#{num}.contestID = #{contestID.to_i} and l#{num}.id = q#{num}.logID and m#{num}.id = q#{num}.sent_multiplierID " +
         " and c#{num}.id = q#{num}.sent_callID"
end

def resolveTime(db, time1, adj1, trusted1, time2, adj2, trusted2)
  adjustedTime1 = db.toDateTime(time1) + adj1.to_i
  adjustedTime2 = db.toDateTime(time2) + adj2.to_i
  trusted1 = db.toBool(trusted1)
  trusted2 = db.toBool(trusted2)
    if trusted1 and not trusted2
      return adjustedTime1
    elsif trusted2 and not trusted1
      return adjustedTime2
    end
    # either both trusted or neither trusted
    return adjustedTime1 + 0.5*(adjustedTime2 - adjustedTime1) # neither is trusted
end


def matchTypeConst(num)
  return "q#{num}.matchType in ('Full', 'Partial', 'Dupe')"
end

def qsolocations(db, contestID)
  countyAbbrevs = Hash.new
  CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
    if (row[0].strip == row[1].strip) and (row[0].strip.length == 4) and row.length >= 6
      countyAbbrevs[row[0].strip] = [row[3].strip, row[4].strip.to_f, row[5].strip.to_f]
    end
  }
  countyAbbrevs.freeze
  if File.exist?("overrides.yml")
    yml = YAML.safe_load_file("overrides.yml", permitted_classes: [Time])
  end
  foundCallsigns = Hash.new
  loc = CallsignLocator.new
  xmlDB =  readXMLDb()
  contestID = contestID.to_i
  db.query("select " + qsoInfo(1) + ", " + logInfo(1) + ", " + qsoInfo(2) + ", " + logInfo(2) +
           " from " + tableSources(1) + ", " + tableSources(2) + 
           " where " + basicLinks(1, contestID) + " and " + basicLinks(2, contestID) + " and " +
           " q1.id = q2.matchID and q2.id = q1.matchID  and q1.id < q2.id and " +
           matchTypeConst(1) + " and " + matchTypeConst(2) +  " order by " +
           "iif(l1.trustedclock>=l2.trustedclock,q1.time,q2.time) asc, iif(l1.trustedclock>=l2.trustedclock,q2.time,q1.time) asc") { |row|
    qsoTimeDate = resolveTime(db, row[0], row[5], row[6], row[8], row[13], row[14])
    loc1 = callsignLocation(row[3].to_s, row[4].to_s, db.toBool(row[7]), qsoTimeDate, yml, loc, foundCallsigns, xmlDB, countyAbbrevs)
    loc2 = callsignLocation(row[11].to_s,  row[12].to_s, db.toBool(row[15]), qsoTimeDate, yml, loc, foundCallsigns, xmlDB, countyAbbrevs)
    print row.join(", ") + "\n"
  }
  db.query("select " + qsoInfo(1) + ", " + receivedInfo() + ", " + logInfo(1) + 
           " from " + tableSources(1) + ", Callsign as c2, Multiplier as m2" +
           " where " + basicLinks(1, contestID) + " and c2.id = coalesce(q1.judged_recvdID,q1.recvd_callID) and " +
           "m2.id = coalesce(q1.judged_multiplierID,q1.recvd_multiplierID) and " +
           " q1.matchID is null and q1.matchType in ('Bye', 'PartialBye') order by " +
           "q1.time asc;") { |row|
    print row.join(", ") + "\n"
  }
  
end
