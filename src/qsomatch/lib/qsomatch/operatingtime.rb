#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Calculate operating time for a log
#
#
require 'time'

# Return the operating time in minutes
def operatingTime(db, logID)
  optime = 0
  lastQ = nil
  db.query("select time from QSO where logID = ? order by time asc;", [ logID ]) { |row|
    qTime = db.toDateTime(row[0])
    if lastQ
      timeDiffSec = (qTime - lastQ).to_i
      if (timeDiffSec < 15*60  ) # must be more than 15 minutes to count as off time
        optime = optime + (timeDiffSec/60)
      end
    end
    lastQ = qTime
  }
  return optime
end
