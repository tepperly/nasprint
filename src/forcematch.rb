#!/usr/bin/env ruby

require_relative 'cabrillo'
require_relative 'database'
require_relative 'ContestDB'
require_relative 'addlog'

require 'getoptlong'
require 'tempfile'

$name = nil
$year = nil

opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      )
opts.each { |opt,arg|
  case opt
  when '--help'
    print "Help\n"
  when '--name'
    $name = arg
  when '--year'
    $year = arg.to_i
  end
}

def findQSO(q, db, cdb)
  res = db.query("select q.id from QSO as q join (Log as l, Exchange as sent, Exchange as recv) on (l.id = q.logID and sent.id = q.sentID and recv.id = q.recvdID) where l.contestID = #{cdb.contestID.to_i} and q.frequency = #{q.freq.to_i} and q.band = \"#{band(q.freq.to_i)}\" and q.fixedMode = \"#{q.mode}\" and q.time = #{cdb.dateOrNull(q.datetime)} and sent.callsign = \"#{q.sentExch.callsign}\" and sent.serial = #{q.sentExch.serial} and sent.name = \"#{q.sentExch.name}\" and sent.location = \"#{q.sentExch.qth}\" and recv.callsign = \"#{q.recdExch.callsign}\" and recv.serial = #{q.recdExch.serial} and recv.name = \"#{q.recdExch.name}\" and recv.location = \"#{q.recdExch.qth}\" limit 1;")
  res.each(:as => :array) { |row|
    return row[0].to_i
  }
  nil
end

def unlinkQSOs(db, q0, q1)
  db.query("update QSO set matchType = 'None', matchID = null, comment=null where id in (#{q0.to_i}, #{q1.to_i}) or matchID in (#{q0.to_i}, #{q1.to_i}) limit 4;")
end

LEGAL=%w{ Full Partial }.to_set.freeze
def linkQSO(db, id0, id1, matchtype)
  db.query("update QSO set matchID = #{id1}, matchType='#{LEGAL.include?(matchtype) ? matchtype : "Partial" }' where id = #{id0} and matchID is null limit 1;")
end

def matchType(db, q0, q1)
  res = db.query("select if((ex1.serial = 9999 or ex0.serial between ex1.serial-1 and ex1.serial+1) and (ex1.multiplierID is null or ex0.multiplierID = ex1.multiplierID) and (ex1.name is null or ex1.name = ex0.name or h.id is not null),'Full','Partial') from (QSO as q0, QSO as q1, Exchange as ex0, Exchange as ex1) left outer join Homophone as h on (h.name1 = ex1.name and h.name2 = ex0.name) where q0.id = #{q0} and q1.id = #{q1} and ex0.id = q0.recvdID and ex1.id = q1.sentID limit 1;")
  res.each(:as => :array) { |row|
    return row[0]
  }
  "Partial"
end

def checkBandMode(qso0, qso1)
  if qso0.mode != qso1.mode
    print "Warning QSO between #{qso0.sentExch.callsign} (#{qso0.mode}) and #{qso1.sentExch.callsign} (#{qso1.mode}) has a mode mismatch\n"
  end
  if band(qso0.freq) != band(qso1.freq)
    print "Warning QSO between #{qso0.sentExch.callsign} (#{band(qso0.freq)}) and #{qso1.sentExch.callsign} (#{band(qso1.freq)}) has a mode mismatch\n"
  end
end

def linkQSOs(qso0, qso1, db, cdb)
  qid0 = findQSO(qso0, db, cdb)
  qid1 = findQSO(qso1, db, cdb)
  if qid0 and qid1
    checkBandMode(qso0, qso1)
    unlinkQSOs(db, qid0, qid1)
    mt0 =matchType(db, qid0, qid1)
    linkQSO(db, qid0, qid1, mt0)
    mt1 = matchType(db, qid1, qid0)
    linkQSO(db, qid1, qid0, mt1)
    print "#{qso0.sentExch.callsign} got a #{mt0} match\n"
    print "#{qso1.sentExch.callsign} got a #{mt1} match\n"
  else
    print qso0.to_s + "\n" if not qid0
    print qso1.to_s + "\n" if not qid1
  end
end

begin
  db = makeDB
  contestDB = ContestDatabase.new(db)
  contestID = contestDB.addOrLookupContest($name, $year, false)
  if not contestID
    print "Unkown contest #{$name} #{$year}\n"
    exit 2
  end
  file = Tempfile.new("forcematch")
  file.write(ARGF.read)
  file.close
  cab = Cabrillo.new(file.path)
  cab.trans(0,2)
  print "Read in #{cab.qsos.length} QSO(s)\n"
  if cab.qsos.length > 0 and cab.qsos.length.even?
    (cab.qsos.length / 2).times { |i|
      linkQSOs(cab.qsos[2*i], cab.qsos[2*i+1], db, contestDB)
    }
  else
    print "Standard input must have a positive and even number of QSOs\n"
    exit 2
  end
ensure
  db.close
end
