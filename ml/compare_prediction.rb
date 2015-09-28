#!/usr/bin/env ruby

require 'csv'
require 'database'
require 'crossmatch'
require 'qsomatch'

def readfile(file)
  open(file, "r") { |i|
    return i.readlines()
  }
end


def getTimeAdj(db, qsoID)
  db.query("select l.clockadj from Log as l, QSO as q where l.id = q.logID and q.id = ? limit 1;", [ qsoID ]) { |row|
    return row[0]
  }
  0
end

if ARGV.length == 4
  csvfile = CSV.read(ARGV[0])
  file1 = readfile(ARGV[1])
  file2 = readfile(ARGV[2])
  numlines = [ csvfile.length, file1.length, file2.length ].min
  if numlines > 0
    if file1[0].split.length == 1
      # swap file1 and file2
      tmp = file1
      file1 = file2
      file2 = tmp
    end
    truepositives = 0
    truenegatives = 0
    falsenegatives = Array.new
    falsepositives = Array.new
    numlines.times { |i|
      label1 = file1[i].split[0]
      label2 = file2[i].split[0]
      if label1 == "1" and label2 == "1"
        truepositives += 1
      elsif label1 == "0" and label2 == "0"
        truenegatives += 1
      elsif label1 == "1" and label2 == "0"
        falsenegatives << [ csvfile[i][0].to_i, csvfile[i][1].to_i ]
      elsif label1 == "0" and label2 == "1"
        falsepositives << [ csvfile[i][0].to_i, csvfile[i][1].to_i]
      end
    }

    print "Number of records: " + numlines.to_s + "\n"
    print "Number of true positives: " + truepositives.to_s + "\n"
    print "Number of true negatives: " + truenegatives.to_s + "\n"
    print "Number of false positives: " + falsepositives.length.to_s + "\n"
    print "Number of false negatives: " + falsenegatives.length.to_s + "\n"

    db = makeDB({'type' => 'sqlite3', 'filename' => ARGV[3]})
    print "FALSE POSITIVES\n===============\n"
    falsepositives.each { |fp|
      q1 = lookupQSO(db, fp[0])
      q2 = lookupQSO(db, fp[1])
      metric, cp = q1.probablyMatch(q2)
      m = Match.new(q1, q2, metric, cp)
      print m.to_s + "\n"
    }
    print "FALSE NEGATIVES\n===============\n"
    falsenegatives.each { |fn|
      q1 = lookupQSO(db, fn[0])
      q2 = lookupQSO(db, fn[1])
      metric, cp = q1.probablyMatch(q2)
      m = Match.new(q1, q2, metric, cp)
      print m.to_s + "\n"
    }
  end
end
