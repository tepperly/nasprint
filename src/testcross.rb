#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'getoptlong'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'crossmatch'

$name = nil
$year = nil
$restart = false

opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--restart', '-R', GetoptLong::NO_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      )
opts.each { |opt,arg|
  case opt
  when '--help'
    print "Help\n"
  when '--name'
    $name = arg
  when '--restart'
    $restart = true
  when '--year'
    $year = arg.to_i
  end
}
    

db = makeDB
contestDB = ContestDatabase.new(db)
contestID = contestDB.addOrLookupContest($name, $year)
cm = CrossMatch.new(db, contestID)

begin
  if $restart
    cm.restartMatch
  end
  cm.perfectMatch
  cm.partialMatch
rescue Mysql2::Error => e
  print e.to_s + "\n"
end
