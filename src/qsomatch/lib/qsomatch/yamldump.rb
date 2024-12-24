#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'contestdb'
require 'set'
require 'operatingtime'

def simpleOpList(list, callsign)
  if 1 == list.length and list[0] == callsign
    []
  else
    list
  end
end

CATEGORY_MAP = {
  "E" => "isCCE", "1E" => "isONEDAY", "CL" => "isCOUNTYLINE", "YL" => "isYL", "M" => "isMOBILE", "N" => "isNEW",  "Y" => "isYOUTH", "S" => "isSCHOOL"
}.freeze
CATEGORY_REVERSEMAP = CATEGORY_MAP.invert.freeze

def addSpecialCategories(db, result, year)
  possibleCategories = [ "E", "1E",  "CL", "YL", "M", "N", "Y"].to_set
  possibleCategories << 'S' if year <= 2019
  recordedCategories = Set.new
  db.query("pragma table_info(Log);") { |column|
    recordedCategories << CATEGORY_REVERSEMAP[column[1].to_s]
  }
  actualCategories = possibleCategories.intersection(recordedCategories).to_a.sort
  result.each { |contest|
    contest["categories"] = actualCategories
  }
  return actualCategories
end

def categoryValues(categories)
  if not categories.empty?
    ", " + (categories.map { |cat| "l." +  CATEGORY_MAP[cat] }.join(','))
  else
    ""
  end
end

def logSpecialCategories(db, values, categories)
  if values.length != categories.length
    $stderr.write("Incorrect number of values or categories\n")
  end
  result = Array.new
  categories.each_index { |i|
    if db.toBool(values[i])
      result << categories[i]
    end
  }
  result
end

def makeContestYaml(db, contestID, cdb, year)
  result = [ ]
  db.query("select name, start, end from Contest where id = ?;",[contestID]) {|row|
    result << { "abbreviation" => row[0], "start" => db.toDateTime(row[1]).iso8601, "end" => db.toDateTime(row[2]).iso8601,
                "fullname" => "California QSO Party", "modes" => ["CW", "PH"], "opclasses" => Array.new, "multipliers" => Array.new,
                "powerlevels" => ["QRP", "LOW", "HIGH"] , "entries" => Array.new }
  }
  db.query("select distinct opclass from Log where contestID = ?;", [contestID]) {|row|
    result.each { |contest|
      contest["opclasses"] << row[0].gsub('_','-')
    }
  }
  categories = addSpecialCategories(db, result, year).freeze
  db.query("select distinct abbrev, fullname, isCA, entityID from Multiplier;") { |row|
    fullname = row[1].to_s
    if row[0].to_s == "DX" and fullname.empty?
      fullname = "DX"
    end
    result.each { |contest|
      contest["multipliers"] << { "abbreviation" => row[0].to_s, "fullName" => fullname,
                                  "locationType" => db.toBool(row[2]) ? "CA" :
                                                      ([ 6, 291, 110].include?(row[3].to_i) ? "US"                                                                                                                       : ((1 == row[3].to_i) ? "VE" : "DX")) }
    }
  }
  db.query("select distinct l.id, l.callsign, l.entityID, m.abbrev, l.opclass, l.powclass, m.id " + categoryValues(categories) +
           "  from Log as l, QSO as q on l.id = q.logID, Multiplier as m on q.sent_multiplierID where l.contestID = ? order by callsign asc, m.abbrev asc;", [contestID]) { |row|
    specialCategories = logSpecialCategories(db, row[7..-1], categories)
    db.query("select verified_mult, verified_score, verified_cw, verified_ph from Scores where logID = ? and multID = ? limit 1;",
             [row[0].to_i, row[6].to_i]) { |score|
      result.each { |contest|
        fixedOpClass = row[4].gsub("_","-")
        if "CHECKLOG" != fixedOpClass
          contest["entries"] << { "callsign" => row[1].to_s, "location" => row[3].to_s, "dxcc" => row[2].to_i,
                                  "opclass" => fixedOpClass, "power" => row[5],
                                  "verified_multipliers" => score[0].to_i, "verified_score" => score[1].to_i,
                                  "qso_per_mode" => { "CW" => score[2].to_i, "PH" => score[3].to_i },
                                  "categories" => specialCategories, "optime" => operatingTime(db, row[0].to_i, row[6].to_i),
                                  "operators" => simpleOpList(cdb.opList(row[0].to_i), row[1].to_s)}
        else
          contest["entries"] << { "callsign" => row[1].to_s, "location" => row[3].to_s, "dxcc" => row[2].to_i,
                                  "opclass" => fixedOpClass, "operators" => simpleOpList(cdb.opList(row[0].to_i), row[1].to_s)}
        end
      }
    }
  }
  db.query("select call.basecall, m.abbrev, m.entityID from Checklog as c, Callsign as call on call.id=c.callID and call.contestID=c.contestID, Multiplier as m on m.id = c.multiplierID where c.contestID = ?;", [ contestID ]) { |row|
    result.each { |contest|
      contest["entries"] << { "callsign" => row[0].to_s, "location" => row[1].to_s, "dxcc" => row[2].to_i, "opclass" => "CHECKLOG",
                              "operators" => Array.new }
    }
  }
  result.each { |contest|
    contest["entries"].sort! { |x,y|
      [ x["callsign"], x["location"] ] <=> [ y["callsign"], y["location"] ]
    }
  }
  result
end
