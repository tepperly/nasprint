#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'getoptlong'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'crossmatch'
require_relative 'fetch'
require_relative 'qrzdb'
require_relative 'calctimeadj'
require_relative 'singletons'
require_relative 'multiplier'
require_relative 'report'
require_relative 'errors'
require_relative 'dumplog'

$name = nil
$year = nil
$restart = false
$qrzuser = nil
$qrzpwd = nil
$create = false

opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--new', '-N', GetoptLong::NO_ARGUMENT],
                      [ '--qrzuser', '-u', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--qrzpwd', '-p', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--restart', '-R', GetoptLong::NO_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      )
opts.each { |opt,arg|
  case opt
  when '--help'
    print "Help\n"
  when '--new'
    $create = true
  when '--name'
    $name = arg
  when '--restart'
    $restart = true
  when '--qrzuser'
    $qrzuser = arg
  when '--qrzpwd'
    $qrzpwd = arg
  when '--year'
    $year = arg.to_i
  end
}

begin
  db = makeDB
  contestDB = ContestDatabase.new(db)
  contestID = contestDB.addOrLookupContest($name, $year, $create)
  if not contestID
    print "Unknown contest #{$name} #{$year}\n"
    exit 2
  end
  contestDB.randomDoorPrize(contestID)
ensure
  db.close
end
