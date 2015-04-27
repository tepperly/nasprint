#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Describe errors in comments.
#
require_relative 'homophone'

def lookupMult(db, id)
  res = db.query("select abbrev from Multiplier where id = #{id} limit 1;")
  res.each(:as => :array) { |row|
    return row[0]
  }
  nil
end

def fillInComment(db, contestID)
  ncmp = NameCompare.new(db)
  res = db.query("select q1.id, q1.band, q1.fixedMode, q1.time, l1.clockadj, c1.callsign, e1.serial, e1.name, e1.location, e1.multiplierID, q2.band, q2.fixedMode, q2.time, l2.clockadj, c2.callsign, e2.serial, e2.name, e2.location, e2.multiplierID from QSO as q1, QSO as q2, Exchange as e1, Exchange as e2, Call as c1, Call as c2 Log as l1, Log as l2 where q1.logID = l1.id  and q2.logID = l2.id and and l1.contestID = #{contestID} and l2.contestID = #{contestID} and q1.matchType = 'Partial' and q1.matchID is not null and q2.id = q1.matchID and q1.id = q2.matchID and q1.comment is null and e1.id = q1.recvdID and e2.id = q2.sentID and c1.id = e1.callID and c2.id = e2.callID;")
  res.each(:as => :array) { |row|
    comments = Array.new
    if row[5] != row[14]
      comments << "busted call #{row[14]}"
    end
    if row[1] != row[10]
      comments << "band mismatch #{row[10]}"
    end
    if row[2] != row[11]
      comments << "mode mismatch #{row[11]}"
    end
    if ((row[3] + row[4]) - (row[12] + row[13])).abs > 15*60*60
      comments << "time mismatch #{(row[12]+row[13]).to_s}"
    end
    if (row[6] - row[15]).abs > 1
      comments << "serial # #{row[15]}"
    end
    if not ncmp.namesEqual?(row[7],row[16]) # compare accounting for homophones
      comments << "name mismatch #{row[16]}"
    end
    if not row[9] or (row[9] != row[18])
      comments << "location mismatch #{lookupMult(db,row[18])}"
    end
    if comments.empty?
      print "Looks like a full match was missed #{row[0]}\n"
    else
      db.query("update QSO set comment='#{comments.join(", ")}' where id = #{row[0]} limit 1;")
    end
  }
end
  
