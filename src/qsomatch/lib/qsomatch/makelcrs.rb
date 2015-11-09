#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#

require 'getoptlong'
require_relative 'database'
require_relative 'contestdb'

$name = nil
$year = nil
opts = GetoptLong.new(
                      [ '--help', '-h', GetoptLong::NO_ARGUMENT],
                      [ '--year', '-y', GetoptLong::REQUIRED_ARGUMENT],
                      [ '--name', '-n', GetoptLong::REQUIRED_ARGUMENT],
                      )
opts.each { |opt, arg| 
  case opt
  when '--help'
    print "Help\n"
  when '--name'
    $name = arg
  when '--year'
    $year = arg.to_i
  end
}

class LCR
  RIGHT_MARGIN = 64

  def initialize(logID, contestDB, filename, out, name, year)
    @logID = logID
    @cdb = contestDB
    @contestName = name
    @contestYear = year
    @callsign, @name, @location, @dxprefix, @team, @verifiedQSOs, @verifiedMultipliers, @verifiedScore, @powclass, @opclass, @numStates = @cdb.logInfo(logID)
    @filename = filename
    @out = out
  end

  def logLocation
    if "DX" == @location
      return "DX (" + @cdb.logEntity(@logID) + ")"
    end
    @location
  end

  def lcrIntro
    line = @contestName.to_s + " " + @contestYear.to_s + " LOG REPORT FOR " + @callsign
    numSpace = [0, (RIGHT_MARGIN - line.length) / 2].max
    @out << " " * numSpace + line + "\r\n" + " " * numSpace + "=" * line.length + "\r\n\r\n"
    @out << "CATEGORY-POWER: %s\r\n      LOCATION: %s\r\n          TEAM: %s\r\n" % [ @opclass, logLocation, @team.to_s ]
    
  end

  def timeSummary
    @out << "\r\nTIME ANALYSIS\r\n-------------\r\n\r\n"
    logClockAdj = @cdb.logClockAdj(@logID)
    @out << "CLOCK-ADJUSTMENT: #{logClockAdj} seconds\r\n"

    logs = @cdb.qsosOutOfContest(@logID)
    if not logs.empty?
      @out << "\r\n"
      logs.each { |log|
        @out << ("QSO #" + log['number'].to_s + " at " +
                 log['time'].strftime("%Y-%m-%d %H:%M") +
                 " (" + (log['time']+logClockAdj).strftime("%H:%M") +
                 " adjusted) is outside the contest time.\r\n")
      }
    end

    @out << "\r
The clock adjustment is based on a based on a comparison between\r
the QSO times in your log and the QSO times in the logs of stations\r
you worked. The value here is based on a least-squares algorithm to\r
minimize discrepancies between logs.\r
"
  end

  def scoreSummary
    rawQSOs, dupeQSOs, bustedQSOs, penaltyQSOs, outside = @cdb.scoreSummary(@logID)
    @out << "\r\nSCORE SUMMARY\r\n-------------\r\n\r\n"
    @out << ("    Raw QSOs = %d\r\n       Dupes = %d\r\n Busted QSOs = %d\r\nPenalty QSOs = %d\r\nOutside time = %d\r\n  Final QSOs = %d\r\n#Multipliers = %d\r\n------------------------------\r\n Final Score = %d\r\n  Error rate = %.1f%%\r\n" %
            [ rawQSOs, dupeQSOs, bustedQSOs, penaltyQSOs, outside, @verifiedQSOs, @verifiedMultipliers, @verifiedScore,
              (((rawQSOs - dupeQSOs) > 0) ? (100*bustedQSOs.to_f/(rawQSOs - dupeQSOs).to_f) : 0.0) ] )
  end

  def multiplierSummary
    multipliers = @cdb.logMultipliers(@logID)
    @out << "\r\nMULTIPLIER CALCUATION\r\n---------------------\r\n\r\n"
    str = "List of " + @verifiedMultipliers.to_s + " mults = "
    first = true
    column = str.size
    @out << str
    multipliers.to_a.sort.each { |mult|
      if column + mult.size + 2 >= RIGHT_MARGIN
        @out << ",\r\n"
        column = 0
      end
      if column > 0 and not first
        @out << ", "
        column += 2
      end
      first = false
      @out << mult
      column += mult.size
    }
    if column > 0
      @out << "\r\n"
    end
    @out << "Number of US states worked: " + @numStates.to_s + "\r\n"
  end

  def dupeSummary
    dupes = @cdb.dupeQSOs(@logID)
    if not dupes.empty?
      @out << "\r\nDUPE CHECK RESULTS\r\n------------------\r\n\r\n"
      dupes.each { |row|
        @out << "QSO #" + row['num'].to_s + " " + row['callsign'].upcase + " is a dupe.\r\n"
      }
      @out << "\r\nThere were #{dupes.length} dupes found. All dupes provide no QSO credit and give\r\nno penalties.\r\n"
    end
  end

  def write
    lcrIntro
    timeSummary
    dupeSummary
    multiplierSummary
    scoreSummary
  end
end

if $name and $year
  begin
    db = makeDB
    cdb = ContestDatabase.new(db)
    contestID = cdb.addOrLookupContest($name, $year, nil)
    if not contestID
      print "Unknown contest #{$name} #{$year}\n"
      exit 2
    end
    logs = cdb.logsForContest(contestID)
    if not logs.empty?
      logs.each { |log|
        call = cdb.logCallsign(log).upcase.strip
        filename = call + "_lcr.txt"
        open("output/" + filename, "w:ascii") { |outfile|
          lcr = LCR.new(log, cdb, filename, outfile, $name, $year)
          lcr.write
        }
      }
    end
  ensure
    db.close
  end
end
