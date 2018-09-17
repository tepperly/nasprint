#!/usr/bin/env ruby

require 'getoptlong'
require 'csv'
require 'date'
require_relative 'database'
require_relative 'ContestDB'

$name = nil
$year = nil
$restart = false
opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--restart', '-R', GetoptLong::NO_ARGUMENT],
                      )
opts.each { |opt, arg| 
  case opt
  when '--help'
    print "Help\n"
  when '--name'
    $name = arg
  when '--year'
    $year = arg.to_i
  when '--restart'
    $restart = true
  end
}

def parseDateTime(str)
  if str
    begin
      return DateTime.strptime(str, "%Y-%m-%d %H:%M:%S")
    rescue ArgumentError
    end
  end
  nil
end

def addMember(cdb, cid, name, tid, call1, call2)
  logID = cdb.findLog(call1)
  print "Lookup 1: " + call1 + " in contest " + cdb.contestID.to_s + " => " + logID.to_s + "\n"
  if not logID and call2
    logID = cdb.findLog(call2)
    print call2 + " => " + logID.to_s + "\n"
  end
  if logID
    cdb.addTeamMember(cid, tid, logID)
  else
    print "Trouble adding member #{call1}/#{call2} to team #{name}\n"
  end
end

if $name and $year
  db = makeDB
  cdb = ContestDatabase.new(db)
  contestID = cdb.addOrLookupContest($name, $year, nil)
  if not contestID
    print "Unknown contest #{$name} #{$year}\n"
    exit 2
  else
    cdb.contestID = contestID
  end
  if $restart
    cdb.clearTeams(contestID)
  end
  ARGV.each { |arg|
    count = 1
    open(arg, "r:bom|utf-8") { |inf|
      csv = CSV.new(inf, {:quote_char => '"'})
      csv.each { |row|
        if count > 1
          tid = cdb.addTeam(row[2], row[0].upcase.strip, row[1], parseDateTime(row[14]), contestID)
          5.times { |i|
            call1 = (row[4+i*2] ? row[4+i*2].upcase.strip : nil)
            call2 = (row[5+i*2] ? row[5+i*2].upcase.strip : nil)
            if (call1 and call1.length > 0) or (call2 and call2.length > 0)
              begin
                addMember(cdb, contestID, row[2], tid, call1, call2)
              rescue Mysql2::Error => e
                print "Exception addding #{call1}/#{call2} to team #{row[2]}\n"
                raise e
              end
            end
          }
        end
        count += 1
      }
    }
  }
end
