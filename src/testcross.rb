#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'getoptlong'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'crossmatch'
require_relative 'fetch'
require_relative 'qrzdb'

$name = nil
$year = nil
$restart = false
$qrzuser = nil
$qrzpwd = nil

opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--qrzuser', '-u', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--qrzpwd', '-p', GetoptLong::REQUIRED_ARGUMENT],
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
  when '--qrzuser'
    $qrzuser = arg
  when '--qrzpwd'
    $qrzpwd = arg
  when '--year'
    $year = arg.to_i
  end
}

def checkCallsigns(db, cid, user, pwd)
  qrz = QRZLookup.new(user, pwd)
  xmldb = readXMLDb()
  res = db.query("select id, basecall from Callsign where contestID = #{cid.to_i} and validcall is null;")
  res.each(:as => :array) { |row|
    result = (xmldb.has_key?(row[1]) or lookupCall(qrz, xmldb, row[1]))
    if result
      db.query("update Callsign set validcall = 1 where id = #{row[0].to_i} limit 1;")
    else
      print "Callsign #{row[1]} is unknown to QRZ.\n"
    end
  }
end
    

db = makeDB
contestDB = ContestDatabase.new(db)
contestID = contestDB.addOrLookupContest($name, $year)
cm = CrossMatch.new(db, contestID)

begin
  if $restart
    cm.restartMatch
  end
  if $qrzuser and $qrzpwd
    checkCallsigns(db, contestID, $qrzuser, $qrzpwd)
  end
  num1, num2 = cm.perfectMatch
  print "Perfect matches: #{num1}\n"
  print "Perfect matches with homophones: #{num2}\n"
  num3, partial = cm.partialMatch
  print "Full matches partial: #{num3}\n"
  print "Partial matches full: #{partial}\n"
  p1, p2 = cm.basicMatch
  print "Basic QSO matches: #{p1+p2}\n"
  cm.probMatch
rescue Mysql2::Error => e
  print e.to_s + "\n"
  print e.backtrace.join("\n")
end
