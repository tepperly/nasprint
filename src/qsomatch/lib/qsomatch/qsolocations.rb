#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'yaml'
require 'csv'
require 'nokogiri'
require 'set'
require 'rubygems'
require 'rgeo'
require 'rgeo-shapefile'
require_relative 'dxmap'
require_relative 'cabrillo'
require_relative 'dxmap'
require_relative 'qrzdb'
require_relative 'crossmatch'
require_relative 'report'

def qsoInfo(num) # 5 items
  num = num.to_i
  return "q#{num}.time, coalesce(q#{num}.judged_band, q#{num}.band), coalesce(q#{num}.judged_mode, q#{num}.fixedMode), c#{num}.basecall, m#{num}.abbrev"
end

def receivedInfo
  return "c2.basecall, m2.abbrev, q1.recvd_entityID"
end

def checkOverrides(overrides, callsign, multiplier, time)
  if overrides and overrides.has_key?("callsigns") and overrides["callsigns"].has_key?(callsign)
    calloverride = overrides["callsigns"][callsign]
    if calloverride.has_key?("location") and calloverride["location"].has_key?(multiplier)
      if calloverride["location"][multiplier].kind_of?(String)
        return interpretMaidenhead(calloverride["location"][multiplier]) << true
      else
        return calloverride["location"][multiplier][0..1] << true
      end
    end
  end
  nil
end

# XML_NAMESPACE = {'qrz' => 'http://xmldata.qrz.com'}
FIRST_CHARACTERS = /^[A-R][A-R]/i
SECOND_CHARACTERS = /^[A-X][A-X]/i
A_ORD='A'.ord.freeze
ZERO_ORD='0'.ord.freeze

def interpretMaidenhead(str)
  if not str.empty? and str.length.even?
    first = true
    letterRegex= FIRST_CHARACTERS
    numberRegex=/^[0-9][0-9]/
    characterNumber = 18
    latitude=-90.0
    latitudeMult = 180.0/characterNumber
    longitudeMult = 360.0/characterNumber
    longitude=-180.0
    letters=true
    while not str.empty?
      if letters
        if letterRegex =~ str
          longitude += longitudeMult*(str[0].upcase.ord-A_ORD)
          latitude += latitudeMult*(str[1].upcase.ord-A_ORD)
          letterRegex = SECOND_CHARACTERS
          characterNumber = 24
          longitudeMult /= 10.0
          latitudeMult /= 10.0
        else
          return nil,nil
        end
      else
        if numberRegex =~ str
          longitude += longitudeMult*(str[0].ord-ZERO_ORD)
          latitude += latitudeMult*(str[1].ord-ZERO_ORD)
          longitudeMult /= characterNumber
          latitudeMult /= characterNumber
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
        if (countyAbbrevs.has_key?(multiplier) and (countyAbbrevs[multiplier][0] == county)) # California county
          return [latitude, longitude, true]
        end
      }
    end
  }
  nil
end

def addEntry(hash, callsign, mult, loc)
  if not hash.has_key?(callsign)
    hash[callsign] = Hash.new
  end
  hash[callsign][mult] = loc[0..1]
end

def calcDistance(geo, point)
  geo.distance(point)
end

def checkStationLocation(callsign, multiplier, dxid, location, dxloc, na, ca, dx, alreadyReported, csv)
  if ca.has_key?(multiplier)
    geo = ca[multiplier]
    point = geo.factory.point(location[1], location[0])
    if not geo.contains?(point)
      if not alreadyReported.include?("#{callsign}-#{multiplier}")
        distance = calcDistance(geo, point)
        print "#{callsign} is not in the boundaries of county #{multiplier} distance = #{distance}\n"
        csv << [ callsign, multiplier, dxid, "CA County", location[0], location[1],  distance]
        alreadyReported << "#{callsign}-#{multiplier}"
      end
    end
  elsif na.has_key?(multiplier)
    geo = na[multiplier]
    point = geo.factory.point(location[1], location[0])
    if not geo.contains?(point)
      if not alreadyReported.include?("#{callsign}-#{multiplier}")
        distance = calcDistance(geo, point)
        print "#{callsign} is not in the boundaries of state/province #{multiplier} distance = #{distance}\n"
        csv << [ callsign, multiplier, dxid, "State/Province", location[0], location[1],  distance]
        alreadyReported << "#{callsign}-#{multiplier}"
      end
    end
  elsif multiplier == "DX"
    ent = dxloc.lookupByID(dxid)
    if ent
      if dx.has_key?(ent.name)
        geo = dx[ent.name]
      elsif  dx.has_key?(COUNTRIES[ent.name])
        geo = dx[COUNTRIES[ent.name]]
      end
      if geo
        point = geo.factory.point(location[1], location[0])
        if not geo.contains?(point)
          if not alreadyReported.include?("#{callsign}-#{multiplier}")
            distance = calcDistance(geo, point)
            print "#{callsign} is not in the boundaries of DX country #{ent.name} distance = #{distance}\n"
            csv << [ callsign, multiplier, dxid, ent.name, location[0], location[1],  distance]
            alreadyReported << "#{callsign}-#{multiplier}"
          end
        end
      end
    end
  else
    if not alreadyReported.include?("#{callsign}-#{multiplier}")
      print "#{callsign} in #{multiplier} doesn't have a category\n"
      alreadyReported << "#{callsign}-#{multiplier}"
    end
  end
end

def callsignLocation(callsign, multiplier, awayFromHome, time, overrides, locator, dxid, dxloc, foundCallsigns, xmlDB, countyAbbrevs, stateAbbrevs)
  if foundCallsigns.has_key?(callsign) and foundCallsigns[callsign].has_key?(multiplier)
    return foundCallsigns[callsign][multiplier]
  end
  loc = checkOverrides(overrides, callsign, multiplier, time)
  if loc
    if loc[2]
      addEntry(foundCallsigns, callsign, multiplier, loc)
    end
    return loc[0..1]
  end
  # location from log
  if not locator.nil? and not locator.empty?
    loc = interpretMaidenhead(locator)
    if not loc.nil? and not (loc[0].nil? or loc[1].nil?)
      addEntry(foundCallsigns, callsign, multiplier, loc)
      return loc[0..1]
    end
  end
  # location from QRZ
  if not awayFromHome and xmlDB.has_key?(callsign)
    loc = checkXML(callsign, multiplier, xmlDB[callsign], countyAbbrevs)
    if loc
      if loc[2]
        addEntry(foundCallsigns, callsign, multiplier, loc)
      end
      return loc[0..1]
    end
  end
  # location based on the county 
  if countyAbbrevs.has_key?(multiplier) and countyAbbrevs[multiplier].length >= 3
    return countyAbbrevs[multiplier][1..2]
  end
  # location based on the state
  if stateAbbrevs.has_key?(multiplier) and stateAbbrevs[multiplier].length >= 3
    return stateAbbrevs[multiplier][1..2]
  end
  # by DX location
  entity = dxloc.lookupByID(dxid)
  if entity and entity.dx?
    # use default lat/long for entity
    return entity.latitude, entity.longitude
  end

  nil
end

def logQInfo(num) # 5 items
  num = num.to_i
  return "l#{num}.clockadj, l#{num}.trustedclock, l#{num}.isCCE or l#{num}.isMOBILE or l#{num}.isONEDAY or l#{num}.isCOUNTYLINE, l#{num}.locator, l#{num}.entityID"
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

def convertTime(db, time, adj)
  db.toDateTime(time) + adj.to_i
end

def resolveTime(db, time1, adj1, trusted1, time2, adj2, trusted2)
  adjustedTime1 = convertTime(db, time1, adj1)
  adjustedTime2 = convertTime(db, time2, adj2)
  trusted1 = db.toBool(trusted1)
  trusted2 = db.toBool(trusted2)
  if trusted1 and not trusted2
    result = adjustedTime1
  elsif trusted2 and not trusted1
    result = adjustedTime2
  else
    # either both trusted or neither trusted
    result = adjustedTime1 + 0.5*(adjustedTime2 - adjustedTime1) # neither is trusted
  end
  [[CONTEST_START, result].max, CONTEST_END].min
end


def matchTypeConst(num)
  return "q#{num}.matchType in ('Full', 'Partial', 'Dupe')"
end

STATE_FILE="/home/tepperly/cqp_video/epsf/ne_10m_admin_1_states_provinces.shp"
COUNTY_FILE="/home/tepperly/cqp_video/epsf/ne_10m_admin_2_counties.shp"
ADM0_SET=%w{ CAN USA }.to_set.freeze
COUNTRY_FILE="/home/tepperly/cqp_video/epsf/ne_10m_admin_0_countries.shp"

COUNTRIES = {
  "Fed. Rep. of Germany" => "Germany",
  "Curacao" => "Curaçao",
}.freeze


CA_COUNTIES = {
  "Alameda" => "ALAM",
  "Alpine" => "ALPI",
  "Amador" => "AMAD",
  "Butte" => "BUTT",
  "Calaveras" => "CALA",
  "Contra Costa" => "CCOS",
  "Colusa" => "COLU",
  "Del Norte" => "DELN",
  "El Dorado" => "ELDO",
  "Fresno" => "FRES",
  "Glenn" => "GLEN",
  "Humboldt" => "HUMB",
  "Imperial" => "IMPE",
  "Inyo" => "INYO",
  "Kern" => "KERN",
  "Kings" => "KING",
  "Lake" => "LAKE",
  "Los Angeles" => "LANG",
  "Lassen" => "LASS",
  "Madera" => "MADE",
  "Marin" => "MARN",
  "Mariposa" => "MARP",
  "Mendocino" => "MEND",
  "Merced" => "MERC",
  "Modoc" => "MODO",
  "Mono" => "MONO",
  "Monterey" => "MONT",
  "Napa" => "NAPA",
  "Nevada" => "NEVA",
  "Orange" => "ORAN",
  "Placer" => "PLAC",
  "Plumas" => "PLUM",
  "Riverside" => "RIVE",
  "Sacramento" => "SACR",
  "Santa Barbara" => "SBAR",
  "San Benito" => "SBEN",
  "San Bernardino" => "SBER",
  "Santa Clara" => "SCLA",
  "Santa Cruz" => "SCRU",
  "San Diego" => "SDIE",
  "San Francisco" => "SFRA",
  "Shasta" => "SHAS",
  "Sierra" => "SIER",
  "Siskiyou" => "SISK",
  "San Joaquin" => "SJOA",
  "San Luis Obispo" => "SLUI",
  "San Mateo" => "SMAT",
  "Solano" => "SOLA",
  "Sonoma" => "SONO",
  "Stanislaus" => "STAN",
  "Sutter" => "SUTT",
  "Tehama" => "TEHA",
  "Trinity" => "TRIN",
  "Tulare" => "TULA",
  "Tuolumne" => "TUOL",
  "Ventura" => "VENT",
  "Yolo" => "YOLO",
  "Yuba" => "YUBA"
}.freeze

def loadGeoBoundaries
  na_boundaries = Hash.new
  dx_boundaries = Hash.new
  county_boundaries = Hash.new
  RGeo::Shapefile::Reader.open(STATE_FILE, allow_unsafe: true) { |file|
    file.each { |record|
      if ADM0_SET.include?(record.attributes["adm0_a3"]) and Log::CA_STATION_CREDITS.include?(record.attributes["postal"])
        na_boundaries[record.attributes["postal"]] = record.geometry
      end
    }
  }
  RGeo::Shapefile::Reader.open(COUNTY_FILE, allow_unsafe: true) { |file|
    file.each { |record|
      if ADM0_SET.include?(record.attributes["ADM0_A3"]) and record.attributes["REGION"] == "CA"
        county_boundaries[CA_COUNTIES[record.attributes["NAME"]]] = record.geometry
      end
    }
  }
  RGeo::Shapefile::Reader.open(COUNTRY_FILE, allow_unsafe: true) { |file|
    file.each { |record|
      dx_boundaries[record.attributes["NAME"]] = record.geometry
      dx_boundaries[record.attributes["FORMAL_EN"]] = record.geometry
    }
  }
  return na_boundaries, county_boundaries, dx_boundaries
end

def qsolocations(db, contestID)
  countyAbbrevs = Hash.new
  stateAbbrevs = Hash.new
  alreadyReported = Set.new
  csv = CSV.open("location_check.csv", "w")
  naBoundaries, countyBoundaries, dxBoundaries = loadGeoBoundaries
  CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
    if (row[0].strip == row[1].strip)
      if (row[0].strip.length == 4) and row.length >= 6
        countyAbbrevs[row[0].strip] = [row[3].strip, row[4].strip.to_f, row[5].strip.to_f]
      elsif (row[0].strip.length == 2) and row.length >= 6
        stateAbbrevs[row[0].strip] = [row[3].strip, row[4].strip.to_f, row[5].strip.to_f]
      end
    end
  }
  stateAbbrevs.freeze
  countyAbbrevs.freeze
  if File.exist?("overrides.yml")
    yml = YAML.safe_load_file("overrides.yml", permitted_classes: [Time])
  end
  foundCallsigns = Hash.new
  loc = CallsignLocator.new
  xmlDB =  readXMLDb()
  results = Array.new
  contestID = contestID.to_i
  db.query("select " + qsoInfo(1) + ", " + logQInfo(1) + ", " + qsoInfo(2) + ", " + logQInfo(2) +
           " from " + tableSources(1) + ", " + tableSources(2) + 
           " where " + basicLinks(1, contestID) + " and " + basicLinks(2, contestID) + " and " +
           " q1.id = q2.matchID and q2.id = q1.matchID  and q1.id < q2.id and " +
           " (m1.isCA or m2.isCA) and " + # at least one of the stations must be a CA station
           matchTypeConst(1) + " and " + matchTypeConst(2) +  " order by " +
           "iif(l1.trustedclock>=l2.trustedclock,q1.time,q2.time) asc, iif(l1.trustedclock>=l2.trustedclock,q2.time,q1.time) asc") { |row|
    qsoTimeDate = resolveTime(db, row[0], row[5], row[6], row[10], row[15], row[16])
    loc1 = callsignLocation(row[3].to_s, row[4].to_s, db.toBool(row[7]), qsoTimeDate, yml, row[8].to_s, row[9].to_i, loc, foundCallsigns, xmlDB, countyAbbrevs, stateAbbrevs)
    loc2 = callsignLocation(row[13].to_s,  row[14].to_s, db.toBool(row[17]), qsoTimeDate, yml, row[18].to_s, row[19].to_i, loc, foundCallsigns, xmlDB, countyAbbrevs, stateAbbrevs)
    if loc1 and loc2 and CrossMatch::ALLOWED_BANDS.include?(row[1].to_s) and CrossMatch::ALLOWED_MODES.include?(row[2].to_s)
      checkStationLocation(row[3].to_s, row[4].to_s, row[9].to_i, loc1, loc, naBoundaries, countyBoundaries, dxBoundaries, alreadyReported,csv)
      checkStationLocation(row[13].to_s, row[14].to_s, row[19].to_i, loc2, loc, naBoundaries, countyBoundaries, dxBoundaries, alreadyReported,csv)
      results << [ qsoTimeDate, row[1].to_s, row[2].to_s, row[3].to_s, row[13].to_s, loc1[0], loc1[1], loc2[0], loc2[1] ]
    end
  }
  db.query("select " + qsoInfo(1) + ", " + logQInfo(1) + ", " + receivedInfo() +
           " from " + tableSources(1) + ", Callsign as c2, Multiplier as m2" +
           " where " + basicLinks(1, contestID) + " and c2.id = coalesce(q1.judged_recvdID,q1.recvd_callID) and " +
           "(m1.isCA or m2.isCA) and " +
           "m2.id = coalesce(q1.judged_multiplierID,q1.recvd_multiplierID) and " +
           " q1.matchID is null and q1.matchType in ('Bye', 'PartialBye') order by " +
           "q1.time asc;") { |row|
    qsoTimeDate = [[convertTime(db, row[0], row[5]), CONTEST_START].max, CONTEST_END].min
    loc1 = callsignLocation(row[3].to_s, row[4].to_s, db.toBool(row[7]), qsoTimeDate, yml, row[8].to_s, row[9].to_i, loc, foundCallsigns, xmlDB, countyAbbrevs, stateAbbrevs)
    loc2 = callsignLocation(row[10].to_s, row[11].to_s, true, qsoTimeDate, yml, nil, row[12].to_i, loc, foundCallsigns, xmlDB, countyAbbrevs, stateAbbrevs)
    if loc1 and loc2 and CrossMatch::ALLOWED_BANDS.include?(row[1].to_s) and CrossMatch::ALLOWED_MODES.include?(row[2].to_s)
      checkStationLocation(row[3].to_s, row[4].to_s, row[9].to_i, loc1, loc, naBoundaries, countyBoundaries, dxBoundaries, alreadyReported, csv)
      checkStationLocation(row[10].to_s, row[11].to_s, row[12].to_i, loc2, loc, naBoundaries, countyBoundaries, dxBoundaries, alreadyReported, csv)
      results << [ qsoTimeDate, row[1].to_s, row[2].to_s, row[3].to_s, row[10].to_s, loc1[0], loc1[1], loc2[0], loc2[1] ]
    end
  }
  results = results.to_set.to_a
  results.sort! { |i1, i2|
    cmp = 0
    [ 0, 3, 4, 1, 2, 5, 6, 7, 8].each { |i|
      cmp = (i1[i] <=> i2[i])
      break if cmp != 0
    }
    cmp
  }
  results.each { |entry|
    entry[0] = entry[0].iso8601
  }
  open("qsolocations.yaml", "w") { |out| out.write(results.to_yaml) }
end
