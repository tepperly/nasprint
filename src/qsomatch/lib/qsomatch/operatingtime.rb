#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Calculate operating time for a log
#
#
require 'time'

REST_THRESHOLD=15*60  # fifteen minutes of idle starts as off time
MINIMUM_TIME_WINDOW = 60 # seconds

# Return the operating time in minutes
def operatingTime(db, logID, multID)
  optime = 0
  firstQ = nil
  lastQ = nil
  db.query("select time from QSO where logID = ? and sent_multiplierID = ? order by time asc;", [ logID, multID ]) { |row|
    qTime = db.toDateTime(row[0])
    if firstQ
      timeDiffSec = (qTime - lastQ).to_i
      if (timeDiffSec < REST_THRESHOLD)
        lastQ = qTime+60 # assume that station worked through the whole minute
      else
        timeDiffSec = (lastQ - firstQ).to_i
        optime += ([timeDiffSec, MINIMUM_TIME_WINDOW].max/60).to_i
        firstQ = qTime
        lastQ = firstQ + 60 # assume that the station worked through the whole minute
      end
    else
      firstQ = qTime
      lastQ = firstQ + 60 # assume that the station worked through the whole minute
    end
  }
  if firstQ
    timeDiffSec = (lastQ - firstQ).to_i
    optime += ([timeDiffSec, MINIMUM_TIME_WINDOW].max/60).to_i
  end
  return optime
end
