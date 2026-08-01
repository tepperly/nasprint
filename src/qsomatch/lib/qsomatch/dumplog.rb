#!/usr/bin/env
# -*- encoding: utf-8; -*-
#
# Code to dump a log from the database in pseudo-Cabrillo format.
#
require 'callsign'
require 'set'

def dumpLogs(db, contestID, translateCA=false)
  alreadySeen = Set.new
  db.query("select l.id, l.callsign, m.abbrev from Log as l, Multiplier as m where l.contestID = ? and m.id = l.multiplierID order by l.callsign asc, l.multiplierID asc;",
           [contestID]) { |row|
    filenameStart = row[1].gsub(/[^a-z0-9]/i,'_').to_s.upcase
    if (alreadySeen.include?(filenameStart))
      filenameStart = filenameStart + "_" + row[2].upcase
    end
    alreadySeen.add(filenameStart)
    if (not Dir.exist?("output"))
      Dir.mkdir("output")
    end
    open("output/" + filenameStart + "_cab.txt", "w:ascii") { |out|
      if translateCA
        dumpTranslatedLog(out, db, row[0])
      else
        dumpLog(out, db, row[0])
      end
    }
  }
end

def serialNum(num)
  num ? num.to_i : 9999
end

def location(str)
  str ? str.to_s : "XXXX"
end


FULL_TYPES = Set.new(%w{Full Bye}).freeze
PARTIAL_TYPES = Set.new(%w{Partial PartialBye}).freeze
def matchType(qsoType, score)
  if FULL_TYPES.include?(qsoType)
    return (score < 2) ? ("%s (D%d)" % [qsoType, (2-score)]) : qsoType
  elsif PARTIAL_TYPES.include?(qsoType)
    return "%s (D%d)" % [qsoType, (2-score)]
  elsif score > 0
    return "%s (credit %d out of 2)" % [qsoType, score]
  else
    return qsoType
  end
end


def dumpLog(out, db, logID)
  clockAdj = 0
  out << "START-OF-LOG: 3.0\r\nCONTEST: CA-QSO-PARTY\r\nCREATED-BY: CQP Score Program\r\n"
  out << "\
SOAPBOX: This file is not your original log. It is created by the\r\n\
SOAPBOX: CQP Scoring program after log normalization and\r\n\
SOAPBOX: analysis. It shows how each QSO in your log was judged.\r\n\
SOAPBOX: The text of your log may have been changed to an\r\n\
SOAPBOX: equivalent form to make it easier to score.\r\n"
  db.query("select l.id, l.callsign, c.basecall, l.email, l.opclass, l.clockadj, l.verifiedscore, l.verifiedPHQSOs, l.verifiedCWQSOs, l.verifiedMultipliers, m.abbrev, l.name, l.club from Log as l join Callsign as c on c.id = l.callID left join Multiplier as m on m.id = l.multiplierID where l.id = ? limit 1;",
                 [logID]) { |row|
    out << ("CLAIMED-SCORE: %d\r\nEMAIL: %s\r\nCALLSIGN: %s\r\nCATEGORY-POWER: %s\r\nLOCATION: %s\r\nNAME: %s\r\nCLUB-NAME: %s\r\nX-CQP-CLOCKADJ: %d\r\nX-CQP-BASECALL: %s\r\nX-CQP-ID: %d\r\nX-CQP-SSB-QSOS: %d\r\nX-CQP-CW_QSOS: %d\r\nX-CQP-MULTIPLIERS: %d\r\nX-CQP-SCORE: %d\r\n" %
            [row[6].to_i, row[3].to_s, row[1], row[4], row[10].to_s, row[11].to_s, row[12].to_s, row[5], row[2], row[0].to_i, row[7].to_i, row[8].to_i, row[9].to_i, row[6].to_i])
    clockAdj = row[5].to_i
  }
  db.query("select q.frequency, q.fixedMode, q.time, qe.sent_callsign, q.sent_serial, coalesce(m1.abbrev,qe.sent_location) as sentmult,  qe.recvd_callsign, q.recvd_serial, coalesce(m2.abbrev,qe.recvd_location) as recvdmult, q.matchType, qe.comment, q.score, m3.abbrev from (QSO as q left join Multiplier as m1 on m1.id = q.sent_multiplierID) left join Multiplier as m2 on m2.id = q.recvd_multiplierID, Multiplier as m3 on m3.id = coalesce(q.judged_multiplierID,q.recvd_multiplierID), QSOExtra as qe on q.id = qe.id where q.logID = ? order by q.time asc, q.sent_serial asc;",
           [logID]) { |row|
    td = db.toDateTime(row[2]) + clockAdj
    out << ("QSO: %5d %2s %4d-%02d-%02d %02d%02d %-10s %4d %-4s %-10s %4d %-4s %%{%s: %s%s}%%\r\n" %
            [row[0], row[1], td.year, td.month, td.mday, td.hour, td.min, row[3], serialNum(row[4]), location(row[5]),
             row[6], serialNum(row[7]), location(row[8]), matchType(row[9], row[11].to_i),
             row[10].to_s, ((row[12] and row[12] != row[8])?( " judged location: " + row[12]):"")])
  }
  out << "END-OF-LOG:\r\n"
end

def tweek(location, keep)
  if not keep
    if rand() < 0.2
      location="MR"
    else
      r = rand()
      if r > 0.45
        location[1] = ('A'.ord + rand(0..25)).chr
      end
      if r <= 0.45 or r > 0.95
        location[0] = ('A'.ord + rand(0..25)).chr
      end
    end
  end
  location
end

def translateLocation(original, callsign, correct)
  case callsign
  when /^V[EA]1/
    tweek("NS", correct)
  when /^V[EA]2/
    tweek("QC", correct)
  when /^V[EA]3/
    tweek("ON", correct)
  when /^V[EA]4/
    tweek("MB", correct)
  when /^V[EA]5/
    tweek("SK", correct)
  when /^V[EA]6/
    tweek("AB", correct)
  when /^V[EA]7/
    tweek("BC", correct)
  when /^VE8/
    tweek("NT", correct)
  when /^VE9/
    tweek("NB", correct)
  when /^VO1/
    tweek("NL", correct)
  when /^VO2/
    tweek("NL", correct)
  when /^VY0/
    tweek("NU", correct)
  when /^VY1/
    tweek("YK", correct)
  when /^VY2/
    tweek("PE", correct)
  else
    original
  end
end

def dumpTranslatedLog(out, db, logID)
  clockAdj = 0
  out << "START-OF-LOG: 3.0\r\nCONTEST: CA-QSO-PARTY\r\nCREATED-BY: CQP Score Program\r\n"
  basecallsign = nil
  db.query("select l.id, l.callsign, c.basecall, l.email, l.opclass, l.clockadj, l.verifiedscore, l.verifiedPHQSOs, l.verifiedCWQSOs, l.verifiedMultipliers, m.abbrev, l.name, l.club from Log as l join Callsign as c on c.id = l.callID left join Multiplier as m on m.id = l.multiplierID where l.id = ? limit 1;",
                 [logID]) { |row|
    out << ("CLAIMED-SCORE: %d\r\nEMAIL: %s\r\nCALLSIGN: %s\r\nCATEGORY-POWER: %s\r\nLOCATION: %s\r\nNAME: %s\r\nCLUB-NAME: %s\r\nX-CQP-CLOCKADJ: %d\r\nX-CQP-BASECALL: %s\r\nX-CQP-ID: %d\r\nX-CQP-SSB-QSOS: %d\r\nX-CQP-CW_QSOS: %d\r\nX-CQP-MULTIPLIERS: %d\r\nX-CQP-SCORE: %d\r\n" %
            [row[6].to_i, row[3].to_s, row[1], row[4], translateLocation(row[10].to_s, row[2], true), row[11].to_s, row[12].to_s, row[5], row[2], row[0].to_i, row[7].to_i, row[8].to_i, row[9].to_i, row[6].to_i])
    basecallsign  = row[2]
    clockAdj = row[5].to_i
  }
  tools = CallsignTools.new
  db.query("select q.frequency, q.fixedMode, q.time, qe.sent_callsign, q.sent_serial, coalesce(m1.abbrev,qe.sent_location) as sentmult,  qe.recvd_callsign, q.recvd_serial, coalesce(m2.abbrev,qe.recvd_location) as recvdmult, q.matchType, qe.comment, q.score from (QSO as q left join Multiplier as m1 on m1.id = q.sent_multiplierID) left join Multiplier as m2 on m2.id = q.recvd_multiplierID, QSOExtra as qe on q.id = qe.id where q.logID = ? order by q.time asc, q.sent_serial asc;",
           [logID]) { |row|
    td = db.toDateTime(row[2]) + clockAdj
    correct = (row[9] != "PartialBye") and (%w{Full Bye Dupe NIL OutsideContest}.include?(row[9]) or ((row[9] == "Partial") and rand() >= 0.6))
    out << ("QSO: %5d %2s %4d-%02d-%02d %02d%02d %-10s %4d %-4s %-10s %4d %-4s\r\n" %
            [row[0], row[1], td.year, td.month, td.mday, td.hour, td.min, row[3], serialNum(row[4]), translateLocation(row[5], basecallsign, true),
             row[6], serialNum(row[7]), translateLocation(row[8],tools.callBase(row[6]),correct)])
  }
  out << "END-OF-LOG:\r\n"
end

def tweek(location, keep)
  if not keep
    if rand() < 0.2
      location="MR"
    else
      r = rand()
      if r > 0.45
        location[1] = ('A'.ord + rand(0..25)).chr
      end
      if r <= 0.45 or r > 0.95
        location[0] = ('A'.ord + rand(0..25)).chr
      end
    end
  end
  location
end

def translateLocation(original, callsign, correct)
  case callsign
  when /^V[EA]1/
    tweek("NS", correct)
  when /^V[EA]2/
    tweek("QC", correct)
  when /^V[EA]3/
    tweek("ON", correct)
  when /^V[EA]4/
    tweek("MB", correct)
  when /^V[EA]5/
    tweek("SK", correct)
  when /^V[EA]6/
    tweek("AB", correct)
  when /^V[EA]7/
    tweek("BC", correct)
  when /^VE8/
    tweek("NT", correct)
  when /^VE9/
    tweek("NB", correct)
  when /^VO1/
    tweek("NL", correct)
  when /^VO2/
    tweek("NL", correct)
  when /^VY0/
    tweek("NU", correct)
  when /^VY1/
    tweek("YK", correct)
  when /^VY2/
    tweek("PE", correct)
  else
    original
  end
end

def dumpTranslatedLog(out, db, logID)
  clockAdj = 0
  out << "START-OF-LOG: 3.0\r\nCONTEST: CA-QSO-PARTY\r\nCREATED-BY: CQP Score Program\r\n"
  basecallsign = nil
  db.query("select l.id, l.callsign, c.basecall, l.email, l.opclass, l.clockadj, l.verifiedscore, l.verifiedPHQSOs, l.verifiedCWQSOs, l.verifiedMultipliers, m.abbrev, l.name, l.club from Log as l join Callsign as c on c.id = l.callID left join Multiplier as m on m.id = l.multiplierID where l.id = ? limit 1;",
                 [logID]) { |row|
    out << ("CLAIMED-SCORE: %d\r\nEMAIL: %s\r\nCALLSIGN: %s\r\nCATEGORY-POWER: %s\r\nLOCATION: %s\r\nNAME: %s\r\nCLUB-NAME: %s\r\nX-CQP-CLOCKADJ: %d\r\nX-CQP-BASECALL: %s\r\nX-CQP-ID: %d\r\nX-CQP-SSB-QSOS: %d\r\nX-CQP-CW_QSOS: %d\r\nX-CQP-MULTIPLIERS: %d\r\nX-CQP-SCORE: %d\r\n" %
            [row[6].to_i, row[3].to_s, row[1], row[4], translateLocation(row[10].to_s, row[2], true), row[11].to_s, row[12].to_s, row[5], row[2], row[0].to_i, row[7].to_i, row[8].to_i, row[9].to_i, row[6].to_i])
    basecallsign  = row[2]
    clockAdj = row[5].to_i
  }
  tools = CallsignTools.new
  db.query("select q.frequency, q.fixedMode, q.time, qe.sent_callsign, q.sent_serial, coalesce(m1.abbrev,qe.sent_location) as sentmult,  qe.recvd_callsign, q.recvd_serial, coalesce(m2.abbrev,qe.recvd_location) as recvdmult, q.matchType, qe.comment, q.score from (QSO as q left join Multiplier as m1 on m1.id = q.sent_multiplierID) left join Multiplier as m2 on m2.id = q.recvd_multiplierID, QSOExtra as qe on q.id = qe.id where q.logID = ? order by q.time asc, q.sent_serial asc;",
           [logID]) { |row|
    td = db.toDateTime(row[2]) + clockAdj
    correct = (row[9] != "PartialBye") and (%w{Full Bye Dupe NIL OutsideContest}.include?(row[9]) or ((row[9] == "Partial") and rand() >= 0.6))
    out << ("QSO: %5d %2s %4d-%02d-%02d %02d%02d %-10s %4d %-4s %-10s %4d %-4s\r\n" %
            [row[0], row[1], td.year, td.month, td.mday, td.hour, td.min, row[3], serialNum(row[4]), translateLocation(row[5], basecallsign, true),
             row[6], serialNum(row[7]), translateLocation(row[8],tools.callBase(row[6]),correct)])
  }
  out << "END-OF-LOG:\r\n"
end
