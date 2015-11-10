#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Calculate time adjustments between logs
#

require 'crossmatch'
require 'gsl'

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
    @db.query("select distinct l.id from Log as l, QSO as q where q.logID = l.id and q.matchID is not null and l.contestID= ? order by l.id asc;", [@contestID]) { |row|
      @idtovar[row[0].to_i] = @numvars
      @vartoid[@numvars] = row[0].to_i
      @numvars = @numvars + 1
    }      
  end

  PENALTY_TERM = 10.0 # 0.001

  def numRows(logs)
    @db.query("select count(*) from QSO as q where #{logs.membertest("q.logID")} and q.matchID is not null and q.id < q.matchID;") { |row|
      return row[0]
    }
    nil
  end

  def buildMatrix
    logs = LogSet.new(@idtovar.keys)
    numrows = numRows(logs)
    if numrows and numrows > 0
      numrows = numrows + @numvars
      print "Building matrix #{Time.now.to_s}\n"
      mA = GSL::Matrix.zeros(numrows, @numvars)
      b = GSL::Vector.alloc(numrows)
      rowcount = 0
      @db.query("select q1.logID, q1.time, q2.logID, q2.time from QSO as q1, QSO as q2 where #{logs.membertest("q1.logID")} and #{logs.membertest("q2.logID")} and q1.matchID is not null and q1.matchID = q2.id and q1.id < q2.id;") { |row|
        mA[rowcount, @idtovar[row[0]]] = 1
        mA[rowcount, @idtovar[row[2]]] = -1
        b[rowcount] = @db.toDateTime(row[3]).to_i-@db.toDateTime(row[1]).to_i
        rowcount += 1
      }
      @numvars.times { |i|
        mA[rowcount, i] = PENALTY_TERM
        b[rowcount] = 0
        rowcount += 1
      }
      x = GSL::Vector.alloc(@numvars)
      r = GSL::Vector.alloc(numrows)
      print "Done #{Time.now.to_s}\n"
      print "Starting QR factorization #{Time.now.to_s}\n"
      qr, tau = mA.QRPT_decomp
      print "Done #{Time.now.to_s}\n"
      print "Starting QR least-squares solve #{Time.now.to_s}\n"
      qr.QR_lssolve(tau, b, x, r)
      print "Done #{Time.now.to_s}\n"
      begin
        @db.begin_transaction
        rowcount = 0
        @numvars.times { |i|
          @db.query("update Log set clockadj = ? where id = ? limit 1;",
                    [ x[i], @vartoid[rowcount] ])
          rowcount += 1
        }
      ensure
        @db.end_transaction
      end
    end
  end

  def report(out)
    diff = @db.timediff('SECOND','q1.time','q2.time')
    diff2 = "(" + diff + " + l1.clockadj - l2.clockadj)"
    @db.query("select l1.id, l1.callsign, l1.clockadj, count(*), sum(#{diff}*#{diff}), sum(abs(#{diff}) > 15*60), sum(#{diff2}*#{diff2}), sum(abs(#{diff2}) > 15*60) from (Log as l1 join QSO as q1 on l1.id = q1.logID) join (Log as l2 join QSO as q2 on l2.id = q2.logID) on q1.matchID = q2.id and q2.matchID = q1.id where l1.contestID = ? and l2.contestID = ? group by l1.id order by l1.id asc;", [@contestID, @contestID] ) {  |row|
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
