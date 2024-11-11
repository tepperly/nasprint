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
      timeDiffSec = (qTime - (lastQ ? lastQ : firstQ)).to_i
      if (timeDiffSec < REST_THRESHOLD)
        lastQ = qTime
      else
        timeDiffSec = lastQ ? (lastQ-firstQ).to_i : 0
        optime += ([timeDiffSec, MINIMUM_TIME_WINDOW].max/60).to_i
        firstQ = qTime
        lastQ = nil
      end
    else
      firstQ = qTime
    end
  }
  if firstQ
    timeDiffSec = lastQ ? (lastQ-firstQ).to_i : 0
    optime += ([timeDiffSec, MINIMUM_TIME_WINDOW].max/60).to_i
  end
  return optime
end
