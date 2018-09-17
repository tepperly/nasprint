#!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
require 'getoptlong'
require 'set'
require 'yaml'
require_relative 'cabrillo'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'addlog'

$overwritefile = false
$makeoutput = true
$overrides = nil
$year = nil
$name = nil
$addToDB = false
$create = false
$totallydestroy = false
$restart = false
$logsinhand = nil
$stationsworked = nil

opts = GetoptLong.new(
                      [ '--overwrite', '-O', GetoptLong::NO_ARGUMENT],
                      [ '--overrides', '-J', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--checkonly', '-C', GetoptLong::NO_ARGUMENT],
                      [ '--missing', '-M', GetoptLong::NO_ARGUMENT],
                      [ '--new', '-N', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--populate', '-p', GetoptLong::NO_ARGUMENT],
                      [ '--restart', '-R', GetoptLong::NO_ARGUMENT],
                      [ '--destroy', '-D', GetoptLong::NO_ARGUMENT]
                      )
opts.each { |opt,arg|
  case opt
  when '--overwrite'
    $overwritefile = true
  when '--checkonly'
    $makeoutput = false
  when '--overrides'
    $overrides = arg
  when '--missing'
    $stationsworked = Hash.new(0)
    $logsinhand = Set.new
  when '--new'
    $create = true
  when '--name'
    $name = arg
  when '--populate'
    $addToDB = true
  when '--destroy'
    $totallydestroy = true
  when '--restart'
    $restart = true
  when '--year'
    $year = arg.to_i
  when '--help'
    print "testcab.rb [--overwrite] [--overrides foo.yaml] [--checkonly] [--help] filenames"
  end
}

def addOverrides(filename, cdb, cid)
  print "Loading #{filename}...\n"
  obj = YAML.load_file(filename)
  if obj
    obj.each { |override|
      if override.has_key?("basecall") and
        override.has_key?("multiplier") and
        override.has_key?("entity")
        print "Adding override #{override["basecall"]}\n"
        mid = cdb.lookupMultiplier(override["multiplier"])[0]
        eid = override["entity"].to_i
        cdb.addOverride(cid, override["basecall"], mid, eid)
      end
    }
  end
  print "Done #{filename}\n"
end

$addToDB = ($addToDB and $year and $name)
if $addToDB
  db = makeDB
  contestDB = ContestDatabase.new(db)
  contestID = contestDB.addOrLookupContest($name, $year, $create)
  if $totallydestroy
    print "Please confirm complete destruction of contest: "
    ans = STDIN.gets
    if "YES" == ans.upcase.strip
      print "Removing contest\n"
      contestDB.removeWholeContest(contestID)
      print "Done\n"
      if $create
        contestID = contestDB.addOrLookupContest($name, $year, $create)
      end
    else
      print "NOT CONFIRMED\n"
      exit 2
    end
  end
  contestDB.contestID = contestID
  if $restart
    print "Please confirm removal of contest logs & QSOs: "
    ans = STDIN.gets
    if "YES" == ans.upcase.strip
      print "Removing contest logs & QSOs\n"
      contestDB.removeContestQSOs(contestID)
      print "Done\n"
    else
      print "NOT CONFIRMED\n"
      exit 2
    end
    
  end
  if $overrides
    addOverrides($overrides, contestDB, contestID)
  end
end

count = 0
total = 0
ARGV.each { |arg|
  total = total + 1
  begin
    print "Starting #{arg}\n"
    $stdout.flush
    cab = Cabrillo.new(arg)
    if $logsinhand and cab.logCall
      $logsinhand << cab.logCall
    end
    if $stationsworked
      cab.each { |qso|
        if qso.recdExch and qso.recdExch.callsign
          $stationsworked[qso.recdExch.callsign] += 1
        end
      }
    end
    $stderr.flush
    if cab.cleanparse
      count = count + 1
      if $makeoutput
        if $overwritefile
          open(arg, "w:us-ascii") { |out|
            cab.write(out)
          }
        else
          cab.write($stdout)
        end
      else
        print "#{arg} is clean\n"
      end
    else
      if not $makeoutput
        print "#{arg} is not clean\n"
      end
    end
    if cab and $addToDB
      addLog(contestDB, contestID, cab)
    end
  rescue ArgumentError => e
    print "Filename: #{arg}\nException: #{e}\nBacktrace: #{e.backtrace}"
  end
  $stdout.flush
}

print "#{count} clean logs\n"
print "#{total} total logs\n"

if $stationsworked
  print "\n\nMissing Logs\n============\n"
  signs = $stationsworked.keys.sort { |x, y| $stationsworked[y] <=> $stationsworked[x] }
  signs.each { |sign|
    if not $logsinhand.include?(sign) and $stationsworked[sign] > 1
      print "%-10s %d\n" % [ sign, $stationsworked[sign].to_s ]
    end
  }
end
