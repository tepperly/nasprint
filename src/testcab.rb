#!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
require 'getoptlong'
require_relative 'cabrillo'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'addlog'

$overwritefile = false
$makeoutput = true
$year = nil
$name = nil
$addToDB = false

opts = GetoptLong.new(
                      [ '--overwrite', '-O', GetoptLong::NO_ARGUMENT],
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--checkonly', '-C', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--populate', '-p', GetoptLong::NO_ARGUMENT]
                      )
opts.each { |opt,arg|
  case opt
  when '--overwrite'
    $overwritefile = true
  when '--checkonly'
    $makeoutput = false
  when '--name'
    $name = arg
  when '--populate'
    $addToDB = true
  when '--year'
    $year = arg.to_i
  when '--help'
    print "testcab.rb [--overwrite] [--checkonly] [--help] filenames"
  end
}

$addToDB = ($addToDB and $year and $name)
if $addToDB
  db = makeDB
  contestDB = ContestDatabase.new(db)
  contestID = contestDB.addOrLookupContest($name, $year)
  contestDB.contestID = contestID
end

count = 0
total = 0
ARGV.each { |arg|
  total = total + 1
  begin
    cab = Cabrillo.new(arg)
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
