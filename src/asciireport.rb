#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Make SSB Sprint report
# By Tom Epperly
# ns6t@arrl.net

require 'set'
require 'getoptlong'
require 'humanize'
require_relative 'database'
require_relative 'ContestDB'

MULTIPLIERS_BY_CALLAREA = {
  "0" => [ "ND", "SD", "NE", "CO", "KS", "MO", "IA", "MN"].to_set.freeze,
  "1" => [ "ME", "VT", "NH", "MA", "CT", "RI", "VT" ].to_set.freeze,
  "2" => [ "NY", "NJ" ].to_set.freeze,
  "3" => [ "PA", "DE", "DC", "MD" ].to_set.freeze,
  "4" => [ "KY", "VA", "TN", "NC", "SC", "AL", "GA", "FL" ].to_set.freeze,
  "5" => [ "NM", "TX", "OK", "AR", "LA", "MS" ].to_set.freeze,
  "6" => [ "CA" ].to_set.freeze,
  "7" => [ "AZ", "UT", "NV", "WY", "WA", "OR", "ID", "MT" ].to_set.freeze,
  "8" => [ "MI", "OH", "WV" ].to_set.freeze,
  "9" => [ "WI", "IL", "IN" ].to_set.freeze,
  "KH6" => [ "HI" ].to_set.freeze,
  "KL7" => [ "AK" ].to_set.freeze,
  "VE1" => [ "NS" ].to_set.freeze,     # Nova Scotia
  "VE2" => [ "QC" ].to_set.freeze,     # Quebec
  "VE3" => [ "ON" ].to_set.freeze,     # Ontario
  "VE4" => [ "MB" ].to_set.freeze,     # Manitoba
  "VE5" => [ "SK" ].to_set.freeze,     # Saskatchewan
  "VE6" => [ "AB" ].to_set.freeze,     # Alberta
  "VE7" => [ "BC" ].to_set.freeze,     # British Columbia
  "VE8" => [ "NT" ].to_set.freeze,     # Northwest Territories
  "VE9" => [ "NB" ].to_set.freeze,     # New Brunswick
  "VO1" => [ "NF" ].to_set.freeze,     # Newfoundland
  "VO2" => [ "LB" ].to_set.freeze,     # Labrador
  "VY0" => [ "NU" ].to_set.freeze,     # Nunavut
  "VY1" => [ "YT" ].to_set.freeze,     # Yukon Territory
  "VY2" => [ "PE" ].to_set.freeze      # Prince Edward Island
}
MULTIPLIERS_BY_CALLAREA.freeze
CONTINENTS = [ "AS", "EU", "AF", "OC", "NA", "SA", "AN" ].to_set.freeze

total = Set.new
MULTIPLIERS_BY_CALLAREA.each { |key, value|
  if total.intersect?(value)
    print "#{key} has a duplicate entry: #{total & value}\n"
  end
  total.merge(value)
}

$name = nil
$year = nil
opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      )
opts.each { |opt, arg| 
  case opt
  when '--help'
    print "Help\n"
  when '--name'
    $name = arg
  when '--year'
    $year = arg.to_i
  end
}

def commaScore(num)
  num = num.to_s
  result = ""
  while num.length > 3
    result = num[-3..-1] + ((result.length>0) ? "," : "") + result
    num = num[0..-4]
  end
  num + ((result.length > 0) ? "," : "") + result
end

def printArea(cdb, logs, key)
  print "\n" + key + "\n"
  count = 0
  print "CALL   NAME        CLS  LOC  20m  40m  80m #QSOs #Mults  Score    BandChgs  Team\n"
  print "====== =========== ===  ===  ===  ===  === ===== ====== ========= ========  ==================================================\n"
  logs.each { |log|
    callsign, name, location, dxprefix, team, qsos, mults, score, opclass = cdb.logInfo(log)
    bandQSOs = cdb.qsosByBand(log)
    bandChanges = cdb.numBandChanges(log)
    values = [callsign.upcase, name, opclass[0], location.to_s,  bandQSOs["20m"], bandQSOs["40m"],
              bandQSOs["80m"], qsos, mults, commaScore(score.to_i), bandChanges, team.to_s.upcase]
    print ("%-6s %-11s  %1s   %-3s %4d %4d %4d %5d %6d %8s    %3d     %s\n" % values)
    count += 1
    if (count % 10) == 0
      print "\n"
    end
  }
end

def columnReport(logs, title, full, columnHeading)
  print "Top " + logs.length.humanize.capitalize + " " + title + "\n"
  if full
    print "Call Sign  %-13s  Bnd Chgs  Qs Lost    00Z    01Z    02Z    03Z\n=========  =============  ========  =======  =====  =====  =====  =====\n" % [columnHeading]
  else
    print "Call Sign  %-13s\n=========  =============\n" % [columnHeading]
  end
  logs.each { |row|
    print "%-9s  %13s" % [row[0], commaScore(row[1])]
    if full
      print "   %4d       %3d  " %  [ row[2], row[3] ]
      row[4].each { |hour|
        print "  %5d" % hour
      }
    end
    print "\n"
  }
  print "\n"
end

def topReport(cdb, cid, num, title, full=true, opclass=nil, criteria="l.verifiedscore", columnHeading="Score")
  logs = cdb.topLogs(cid, num, opclass, criteria)
  if not logs.empty?
    columnReport(logs, title, full, columnHeading)
  end
end

def wasReport(cdb, contestID, num)
  logs = cdb.topNumStates(contestID, num)
  if not logs.empty?
    columnReport(logs, "States Worked", false, "#States Worked")
  end
end

def goldenReport(cdb, contestID)
  goldlogs = cdb.goldenLogs(contestID)
  if not goldlogs.empty?
    print "\nGolden Logs\n"
    print "Call Sign  %-13s\n=========  =============\n" % [ "Num QSOs" ]
    goldlogs.each { |log|
      print "%-9s  %13s\n" % [ log["callsign"], log["numQSOs"] ]
    }
  end
end

def teamReport(cdb, contestID)
  teams = cdb.reportTeams(contestID)
  print "\n\nTEAM REPORTS\n============\n\n"
  teams.each { |team|
    print "\n#{team["name"]}\n"
    team["members"].each { |mem|
      print "  %-9s %9s\n" % [ mem["callsign"], commaScore(mem["score"]) ]
    }
    print "  " + ("-"*9) + "-" + ("-"*9) + "\n"
    print "  %-9s %9s\n" % [ "TOTAL", commaScore(team["score"]) ]
  }
end

if $name and $year
  begin
    db = makeDB
    cdb = ContestDatabase.new(db)
    contestID = cdb.addOrLookupContest($name, $year, nil)
    if not contestID
      print "Unknown contest #{$name} #{$year}\n"
      exit 2
    end
    MULTIPLIERS_BY_CALLAREA.keys.sort.each { |key|
      logs = cdb.logsByMultipliers(contestID, MULTIPLIERS_BY_CALLAREA[key])
      if not logs.empty?
        printArea(cdb, logs, key.start_with?("V") ? "Canadian Call Area #{key}" : "US Call Area #{key}")
      end
    }
    CONTINENTS.each { |continent|
      logs = cdb.logsByContinent(contestID, continent)
      if not logs.empty?
        printArea(cdb, logs, "DX Entries #{continent} Continent")
      end
    }
    print "\n"
    topReport(cdb, contestID, 10, "Scores")
    topReport(cdb, contestID, 10, "High Power", true, "High")
    topReport(cdb, contestID, 10, "Low Power", true, "Low")
    topReport(cdb, contestID, 10, "QRP", true, "QRP")
    topReport(cdb, contestID, 10, "QSO Totals", false, nil, "l.verifiedqsos", "# QSOs")
    topReport(cdb, contestID, 10, "Multipliers", false, nil, "l.verifiedMultipliers", "# Multipliers")
    wasReport(cdb, contestID, 10)
    goldenReport(cdb, contestID)
    teamReport(cdb, contestID)
  ensure
    db.close
  end
end
