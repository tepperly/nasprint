#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Calculate time adjustments between logs
#

class CalcTimeAdj
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
    @numvars = 0
    @idtovar = Hash.new
    @vartoid = Hash.new
  end

  def buildVariables
    @numvars = 0
    @idtovar = Hash.new
    @vartoid = Hash.new
    res = @db.query("select distinct l.id from Log as l, QSO as q where q.logID = l.id and q.matchID is not null and l.contestID= ? order by l.id asc;", [@contestID])
    res.each { |row|
      @idtovar[row[0].to_i] = @numvars
      @vartoid[@numvars] = row[0].to_i
      @numvars = @numvars + 1
    }      
  end

  PENALTY_TERM = 0.001

  def buildMatrix
    numrows = nil
    res = @db.query("select count(*) from QSO as q where q.logID in (?) and q.matchID is not null and q.id < q.matchID;", [ @idtovar.keys])
    res.each { |row|
      numrows = row[0]
    }
    if numrows and numrows > 0
      open("/tmp/calcadj.py","w") { |out|
        numrows = numrows + @numvars
        out.write("#!/usr/bin/env python\nimport numpy\nimport numpy.linalg\nA = numpy.zeros((#{numrows}, #{@numvars}))\nb = numpy.zeros((#{numrows},))\n")
        res = @db.query("select q1.logID, q1.time, q2.logID, q2.time from QSO as q1, QSO as q2 where q1.logID in (?) and q2.logID in (?) and q1.matchID is not null and q1.matchID = q2.id and q1.id < q2.id;", [@idtovar.keys, @idtovar.keys])
        rowcount = 0
        res.each { |row|
          out.write("A[#{rowcount},#{@idtovar[row[0]]}] = 1\nA[#{rowcount},#{@idtovar[row[2]]}] = -1\n")
          out.write("b[#{rowcount}] = #{@db.toTimeDate(row[3]).to_i-@db.toTimeDate(row[1]).to_i}\n")
          rowcount = rowcount + 1
        }
        @numvars.times { |i|
          out.write("A[#{rowcount},#{i}] = #{PENALTY_TERM}\n")
          out.write("b[#{rowcount}] = 0\n")
          rowcount = rowcount + 1
        }
        out.write("adj, residuals, rank, s = numpy.linalg.lstsq(A,b)\n")
        out.write("for i in xrange(#{@numvars}):\n")
        out.write("  print adj[i]")
        out.write("# done")
      }
      IO.popen("python /tmp/calcadj.py") { |res|
        rowcount = 0
        res.each { |line|
          @db.query("update Log set clockadj = ? where id = ? limit 1;", [line.to_f, @vartoid[rowcount]])
          rowcount = rowcount + 1
        }
      }
    end
  end

  def markOutOfContest
    count = 0
    res = @db.query("select distinct q.id from QSO as q, Log as l, Contest as c where l.contestID = #{@contestID} and q.logID=l.id and (" +
                    @db.dateAdd("q.time", "l.clockadj", "second") +
                    " < " +
                    @db.dateSub("c.start", 4, "minute") +
                    " or " +
                    @db.dateAdd("q.time", "l.clockadj", "second") +
                    " > " +
                    @db.dateAdd("c.end", 5, "minute") +
                    ") and matchType != 'OutsideContest';")
    res.each { |row|
      @db.query("update QSO set matchType = 'OutsideContest' where id = ? limit 1;", [row[0].to_i])
      count = count + @db.affected_rows
    }
    count
  end
end
