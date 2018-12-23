#!/usr/bin/env ruby

CLUB_CONSTRAINT = { "California" => "c.isCA", "Non-California" => "not c.isCA" }
CLUB_CONSTRAINT.freeze
CLUB_REGIONS = CLUB_CONSTRAINT.keys.sort
CLUB_REGIONS.freeze
CLUB_LOG_CAP = { "Large" => 10000000, "Medium" => 35, "Small" => 10 }
CLUB_LOG_CAP.freeze

def clubScore(db, contestID, clubID, limit=1000000)
  result = 0
  numlog = 0
  db.query("select round(s.verified_score*sum(o.clubAlloc)) as contrib from Log as l join Operator as o on (o.logID = l.id and o.clubID = c.id) join Scores as s on s.logID = l.id join Clubs as c on o.clubID = c.id where l.contestID = ? and c.id = ? and l.opclass != 'CHECKLOG' group by l.id, s.multID, c.id order by contrib desc;", [contestID, clubID]) { |row|
    if numlog < limit
      result += row[0].to_i
    end
    numlog += 1
  }
  return result, numlog
end

def clubList(db, contestID, size, region)
  clubs = [ ]
  db.query("select distinct c.id, c.fullname from Clubs as c join Operator as o on o.clubID = c.id join Log as l on o.logID = l.id where l.contestID = ? and l.opclass != 'CHECKLOG' and c.type = ? and #{CLUB_CONSTRAINT[region]};",
           [contestID, size.upcase]) { |row|
    score, numlogs = clubScore(db, contestID, row[0].to_i, CLUB_LOG_CAP[size])
    clubs << [row[1].to_s, numlogs, score]
  }
  clubs.sort! { |x,y| y[2] <=> x[2] }
  clubs
end
