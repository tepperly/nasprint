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

def checkCallsigns(db, cid, user, pwd)
  if user and pwd
    qrz = QRZLookup.new(user, pwd)
  else
    qrz = nil
  end
  xmldb = readXMLDb()
  res = db.query("select id, basecall from Callsign where contestID = #{cid.to_i} and validcall is null;")
  res.each(:as => :array) { |row|
    if xmldb.has_key?(row[1]) or lookupCall(qrz, xmldb, row[1])
      db.query("update Callsign set validcall = 1 where id = #{row[0].to_i} limit 1;")
    else
      db.query("update Callsign set validcall = 0 where id = #{row[0].to_i} limit 1;");
      print "Callsign #{row[1]} is unknown to QRZ.\n"
    end
  }
end

NUMSECS=5
NUMDOTS=3
if $restart
  print "Restarting in 5 seconds: "
  NUMSECS.times { |i|
    print (NUMSECS-i).to_s
    NUMDOTS.times { 
      sleep (1.0/NUMDOTS)
      print "."
    }
  }
  print "0  Done.\n"
end    

db = makeDB
contestDB = ContestDatabase.new(db)
contestID = contestDB.addOrLookupContest($name, $year, $create)
if not contestID
  print "Unknown contest #{$name} #{$year}\n"
  exit 2
end
cm = CrossMatch.new(db, contestID)

begin
  if $restart
    cm.restartMatch
  end
  checkCallsigns(db, contestID, $qrzuser, $qrzpwd)
  num1, num2 = cm.perfectMatch
  print "Perfect matches: #{num1}\n"
  print "Perfect matches with homophones: #{num2}\n"
  $stdout.flush
  num3, partial = cm.partialMatch
  print "Full matches partial: #{num3}\n"
  print "Partial matches full: #{partial}\n"
  $stdout.flush
  num1, num2 = cm.perfectMatch(CrossMatch::MAXIMUM_TIME_MATCH, 'TimeShiftFull')
  print "Time shifted perfect matches: #{num1}\n"
  print "Time shifted perfect matches with homophones: #{num2}\n"
  $stdout.flush
  num3, partial = cm.partialMatch(CrossMatch::MAXIMUM_TIME_MATCH, 'TimeShiftFull', 'TimeShiftPartial')
  print "Time shifted full matches partial: #{num3}\n"
  print "Time shifted partial matches full: #{partial}\n"
  $stdout.flush
  p1, p2 = cm.basicMatch(CrossMatch::MAXIMUM_TIME_MATCH)
  print "Basic QSO matches within 24 hours: #{p1+p2}\n"
  $stdout.flush
  cm.probMatch
  print "Calculating clock drift\n"
  ct = CalcTimeAdj.new(db, contestID)
  ct.buildVariables
  ct.buildMatrix
  timeviolation = ct.markOutOfContest
  print "QSOs outside contest time period: #{timeviolation}\n"
  $stdout.flush
  num1, num2 = cm.resolveShifted
  print "Time shift resolved #{num1} full and #{num2} partial\n"
  $stdout.flush
  d1 = cm.ignoreDups
  print "Duplicates of matches: #{d1}\n"
  ct = nil
  nil1 = cm.markNIL
  print "Not In Log penalties: #{nil1}\n"
  singles = ResolveSingletons.new(db, contestID)
  print "Resolving singletons\n"
  $stdout.flush
  singles.resolve
  num = singles.finalDupeCheck
  print "#{num} Dupe QSOs identified during final check\n."
  m = Multiplier.new(db, contestID)
  m.resolveDX
  m.checkByeMultipliers
  fillInComment(db, contestID)
  r = Report.new(db, contestID)
  r.makeReport
  dumpLogs(db, contestID)
  # 0.94 similarity is good for comparisons
rescue Mysql2::Error => e
  print e.to_s + "\n"
  print e.backtrace.join("\n")
end
