#!/usr/bin/env
# -*- encoding: utf-8; -*-
#
# Code to dump a log from the database in pseudo-Cabrillo format.
#

def dumpLogs(db, contestID)
  res = db.query("select id, callsign from Log where contestID = ? order by callsign asc;",
                 [contestID])
  res.each { |row|
    open("output/" + row[1].to_s.upcase + "_cab.txt", "w:ascii") { |out|
      dumpLog(out, db, row[0])
    }
  }
end

def dumpLog(out, db, logID)
  out << "START-OF-LOG: 3.0\r\nCONTEST: NA-SPRINT-SSB\r\nCREATED-BY: NA Sprint Score Program\r\nCATEGORY-MODE: SSB\r\n"
  out << "\
SOAPBOX: This file is not your original log. It is created by the\r\n\
SOAPBOX: NA Sprint Scoring program after log normalization and\r\n\
SOAPBOX: analysis. It shows how each QSO in your log was judged.\r\n\
SOAPBOX: The text of your log may have been changed to an\r\n\
SOAPBOX: equivalent form to make it easier to score.\r\n"
  res = db.query("select l.id, l.callsign, c.basecall, l.email, l.opclass, l.clockadj, l.verifiedscore, l.verifiedQSOs, l.verifiedMultipliers, m.abbrev, l.name, l.club from Log as l join Callsign as c on c.id = l.callID left join Multiplier as m on m.id = l.multiplierID where l.id = ? limit 1;",
                 [logID])
  res.each { |row|
    out << ("CLAIMED-SCORE: %d\r\nEMAIL: %s\r\nCALLSIGN: %s\r\nCATEGORY-POWER: %s\r\nLOCATION: %s\r\nNAME: %s\r\nCLUB-NAME: %s\r\nX-SSBSPRINT-CLOCKADJ: %d\r\nX-SSBSPRINT-BASECALL: %s\r\nX-SSBSPRINT-ID: %d\r\nX-SSB-QSOS: %d\r\nX-SSBSPRINT-MULTIPLIERS: %d\r\nX-SSBSPRINT-SCORE: %d\r\n" %
            [row[6].to_i, row[3].to_s, row[1], row[4], row[9].to_s, row[10].to_s, row[11].to_s, row[5], row[2], row[0].to_i, row[7].to_i, row[8].to_i, row[6].to_i])
  }
  res = db.query("select q.frequency, q.fixedMode, q.time, qe.sent_callsign, q.sent_serial, if(q.sent_multiplierID is null,qe.sent_location,m1.abbrev) as sentmult, qe.recvd_callsign, q.recvd_serial, if (q.recvd_multiplierID is null,qe.recvd_location,m2.abbrev) as recvdmult, q.matchType, q.comment from (QSO as q left join Multiplier as m1 on m1.id = q.sent_multiplierID) left join Multiplier as m2 on m2.id = q.recvd_multiplierID where q.logID = ? order by q.time asc, s.serial asc;",
                 [logID])
  res.each { |row|
    out << ("QSO: %5d %2s %4d-%02d-%02d %02d%02d %-10s %4d %-3s %-10s %4d %-3s %%{%s: %s}%%\r\n" %
            [row[0], row[1], row[2].year, row[2].month, row[2].mday, row[2].hour, row[2].min, row[3], row[4], row[5],
             row[6], row[7], row[8], row[9], row[10].to_s])
  }
  out << "END-OF-LOG:\r\n"
end
