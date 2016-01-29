#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Calculate time adjustments between logs
#

require 'crossmatch'
require 'set'

class CalcTimeAdj
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
    @numvars = 0
    @idtovar = Hash.new
    @vartoid = Hash.new
    @trusted = Set.new # set of variable numbers
    @badclocks = Set.new
  end

  def buildVariables
    @numvars = 0
    @idtovar.clear
    @vartoid.clear
    @trusted.clear
    @badclocks.clear
    @db.query("select distinct l.id, l.trustedclock from Log as l, QSO as q where q.logID = l.id and q.matchID is not null and l.contestID= ? order by l.id asc;", [@contestID]) { |row|
      @idtovar[row[0].to_i] = @numvars
      @vartoid[@numvars] = row[0].to_i
      if @db.toBool(row[1])
        @trusted << @numvars
      end
      @numvars = @numvars + 1
    }      
  end

  TRUSTED_CLOCK = 100           # discourage non-zero clock adjustment
  AVERAGE_CLOCK = 1             # add a penalty for adjusting this clock
  BAD_CLOCK = 0.001             # encourage moving this clock a lot

  def numRows(logs)
    numrows = nil
    @db.query("select count(*) from QSO as q where #{logs.membertest("q.logID")} and q.matchID is not null and q.id < q.matchID;") { |row|
      numrows = row[0]
    }
    numrows
  end

  GRACE_PERIOD=CrossMatch::PERFECT_TIME_MATCH  # in minutes

  def calcMaxTimeDiff(logs)
    maxdiff = 24*60*3           # 3 days is default
    @db.query("select max(abs(cast(#{@db.timediff('MINUTE', 'q1.time', 'q2.time')} as integer))) from QSO as q1 join QSO as q2 on q1.id = q2.matchID and q2.id = q1.matchID where #{logs.membertest("q1.logID")} and #{logs.membertest("q2.logID")} and q1.matchID is not null and q2.matchID is not null limit 1;") { |row|
      maxdiff = 1 + row[0].to_i
    }
    return maxdiff - GRACE_PERIOD
  end

  def maxTimeByLog(logs)
    timediff = Hash.new
    @db.query("select l.id, max(abs(cast(#{@db.timediff('MINUTE', 'q1.time', 'q2.time')} as integer))) from Log as l join (QSO as q1 join QSO as q2 on q1.id = q2.matchID and q2.id = q1.matchID) on l.id = q1.logID where #{logs.membertest("q1.logID")} and #{logs.membertest("q2.logID")} and q1.matchID is not null and q2.matchID is not null group by l.id order by l.id asc;") { |row|
      timediff[row[0].to_i] = 1+row[1].to_i-GRACE_PERIOD
    }
    timediff
  end
  
  def buildMILP
    logs = LogSet.new(@idtovar.keys)
    big_M = calcMaxTimeDiff(logs)
    timediff = maxTimeByLog(logs)
    varsPerLog = Hash.new
    totalClockErrs = 0
    violationsPerLog = Hash.new(0)
    intvars = Array.new
    @db.query("select q1.logID, q2.logID, cast(#{@db.timediff('MINUTE','q1.time', 'q2.time')} as integer) as tdiff, count(*) from QSO as q1, QSO as q2 where #{logs.membertest("q1.logID")} and #{logs.membertest("q2.logID")} and q1.matchID is not null and q1.matchID = q2.id and q1.id < q2.id group by q1.logID, q2.logID, tdiff order by q1.logID asc, q2.logID asc;") { |row|
      row[0,2].each { |i|
        if not varsPerLog.has_key?(i.to_i)
          varsPerLog[i.to_i] = Array.new
        end
        varsPerLog[i] << "#{row[3].to_i} * QSO#{intvars.length}"
        if row[2].to_i.abs > GRACE_PERIOD
          violationsPerLog[i] += row[3].to_i
        end
      }
      if row[2].to_i.abs > GRACE_PERIOD
        totalClockErrs += row[3].to_i
      end
      intvars << [ row[0].to_i, row[1].to_i, row[2].to_i, row[3].to_i]
    }
    print "#{totalClockErrs} initial QSO clock mismatches\n"
    continuousvars = @numvars
    if not intvars.empty?
      milp_PENALTY = 0.9/@numvars/(big_M+2*GRACE_PERIOD)
      open("/tmp/calcadj.lp", "w") { |out|
        out.write("max: ")
        intvars.each_with_index { |v,i|
          out.write(((v[3] != 1) ? (v[3].to_s + " ")  : "")  +
                    "QSO" + i.to_s + " + ")
        }
        out.write(@idtovar.keys.map { |x| 
                    (-milp_PENALTY).to_s + " * LP" + x.to_s + " + " +
                    (-milp_PENALTY).to_s + " * LN" + x.to_s }.join(" + ") +
                  " - 0.01*MaxPerLog;\n")
        intvars.each_with_index { |v,i|
          out.write("LP#{v[0]} - LN#{v[0]} - LP#{v[1]} + LN#{v[1]} + #{big_M} * QSO#{i} <= #{big_M + GRACE_PERIOD - v[2]};\n")
          out.write("LP#{v[0]} - LN#{v[0]} - LP#{v[1]} + LN#{v[1]} - #{big_M} * QSO#{i} >= #{-GRACE_PERIOD - big_M - v[2]};\n")
        }
        varsPerLog.each { |k,v|
#          out.write(v.join(" + ") + " <= #{violationsPerLog[k]};\n")
#          if violationsPerLog[k] > 0
            out.write(v.join(" + ") + " <= MaxPerLog;\n")
#          end
        }
        @idtovar.keys.each { |id|
          out.write("0 <= LP#{id} <= #{big_M};\n")
          out.write("0 <= LN#{id} <= #{big_M};\n")
        }

        out.write("\nbinary ")
        intvars.each_index { |i|
          if i > 0
            out.write(", ")
          end
          out.write("QSO" + i.to_s)
        }
        out.write(";\n")
      }
    end
  end

  def buildMatrix
    logs = LogSet.new(@idtovar.keys)
    numrows = numRows(logs)
    if numrows and numrows > 0
      open("/tmp/calcadj.py","w") { |out|
        numrows = numrows + @numvars
        out.write("#!/usr/bin/env python\nimport numpy\nimport numpy.linalg\nA = numpy.zeros((#{numrows}, #{@numvars}))\nb = numpy.zeros((#{numrows},))\n")
        rowcount = 0
        @db.query("select q1.logID, q1.time, q2.logID, q2.time from QSO as q1, QSO as q2 where #{logs.membertest("q1.logID")} and #{logs.membertest("q2.logID")} and q1.matchID is not null and q1.matchID = q2.id and q1.id < q2.id;") { |row|
          out.write("A[#{rowcount},#{@idtovar[row[0]]}] = 1\nA[#{rowcount},#{@idtovar[row[2]]}] = -1\n")
          out.write("b[#{rowcount}] = #{@db.toDateTime(row[3]).to_i-@db.toDateTime(row[1]).to_i}\n")
          rowcount = rowcount + 1
        }
        @numvars.times { |i|
          if @trusted.include?(i)
            out.write("A[#{rowcount},#{i}] = #{TRUSTED_CLOCK}\n")
          elsif @badclocks.include?(i)
            out.write("A[#{rowcount},#{i}] = #{BAD_CLOCK}\n")
          else
            out.write("A[#{rowcount},#{i}] = #{AVERAGE_CLOCK}\n")
          end
          out.write("b[#{rowcount}] = 0\n")
          rowcount = rowcount + 1
        }
        out.write("adj, residuals, rank, s = numpy.linalg.lstsq(A,b)\n")
        out.write("for i in xrange(#{@numvars}):\n")
        out.write("  print adj[i]\n")
        out.write("pass\n# done\n")
      }
      IO.popen("python /tmp/calcadj.py") { |res|
        rowcount = 0
        begin
          @db.begin_transaction
          res.each { |line|
            clock_adjustment = line.to_f
            @db.query("update Log set clockadj = ? where id = ? limit 1;", 
                      [clock_adjustment, @vartoid[rowcount]]) { }
            if clock_adjustment >= 3600
              @badclocks << rowcount
            end
            rowcount = rowcount + 1
          }
        ensure
          @db.end_transaction
        end
      }
    end
  end

  def reportByLog
    prevCall = nil
    outfile = nil
    @db.query("select l1.callsign, l1.clockadj, q1.time, l2.clockadj, q2.time from (Log as l1 join QSO as q1 on l1.id = q1.logID) join (Log as l2 join QSO as q2 on l2.id = q2.logID) on (q1.matchID = q2.id and q1.id = q2.matchID) where l1.contestID = ? and l2.contestID = ? order by l1.id asc, q1.time asc, q1.recvd_serial asc;", [ @contestID, @contestID ] ) { |row|
      if row[0] != prevCall
        if outfile
          outfile.close
        end
        outfile = open("output/" + row[0].gsub(/[^a-z0-9]/i,"_") +
                       "_clock.txt", "w:ascii")
      end
      outfile.write("\"" + @db.toDateTime(row[2]).to_s + "\",\"" +
                    @db.toDateTime(row[4]).to_s + "\"," +
                    row[1].to_s + "," +
                    row[3].to_s + ",\"" +
                    (@db.toDateTime(row[2]) + row[1]).to_s + "\",\"" +
                    (@db.toDateTime(row[4]) + row[3]).to_s + "\"\n")
      prevCall=row[0]
    }
    if outfile
      outfile.close
    end
  end

  def report(out)
    diff = @db.timediff('SECOND','q1.time','q2.time')
    diff2 = "(" + diff + " + l1.clockadj - l2.clockadj)"
    @db.query("select l1.id, l1.callsign, l1.clockadj, count(*), sum(#{diff}*#{diff}), sum(abs(#{diff}) > #{GRACE_PERIOD}*60), sum(#{diff2}*#{diff2}), sum(abs(#{diff2}) > #{GRACE_PERIOD}*60) from (Log as l1 join QSO as q1 on l1.id = q1.logID) join (Log as l2 join QSO as q2 on l2.id = q2.logID) on q1.matchID = q2.id and q2.matchID = q1.id where l1.contestID = ? and l2.contestID = ? group by l1.id order by l1.id asc;", [@contestID, @contestID] ) {  |row|
      out.write(row[0].to_s + ",\"" + row[1] + "\"," +
                row[2..-1].join(",") + "\n")
    }
  end


  def markOutOfContest
    count = 0
    ids = [ ]
    res = @db.query("select distinct q.id from QSO as q, Log as l, Contest as c where l.contestID = #{@contestID} and q.logID=l.id and (" +
                    @db.dateAdd("q.time", "l.clockadj", "second") +
                    " < " +
                    @db.dateSub("c.start", 4, "minute") +
                    " or " +
                    @db.dateAdd("q.time", "l.clockadj", "second") +
                    " > " +
                    @db.dateAdd("c.end", 5, "minute") +
                    ") and matchType != 'OutsideContest';") { |row|
      ids << row[0].to_i
    }
    @db.query("update QSO set matchType = 'OutsideContest' where id in (#{ids.join(",")}) limit 1;") { }
    count = count + @db.affected_rows
    count
  end
end
