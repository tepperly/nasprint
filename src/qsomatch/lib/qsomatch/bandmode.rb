#!/usr/bin/env ruby
# Code to resolve band/mode mismatches
require 'set'
require 'json'

def jsonFriendly(obj)
  if obj.is_a?(Array)
    result = Array.new
    obj.each { |v|
      result << jsonFriendly(v)
    }
  elsif obj.is_a?(Hash)
    result = Hash.new
    obj.each { |k,v|
      result[k] = jsonFriendly(v)
    }
  elsif obj.respond_to?(:to_h)
    result = Hash.new
    obj.to_h.each { |k,v|
      result[k] = jsonFriendly(v)
    }
  else
    result = obj
  end
  result
end

class QSOMatch
  WARC_BANDS = Set.new(%w{ 12m 17m 30m }).freeze
  ILLEGAL_MODES = Set.new(%w{ RY }).freeze
  MODE_MAP = { 'CW' => 'CW', 'PH' => 'PH', 'FM' => 'PH' }.freeze

  def initialize(id0, id1)
    @ids = [id0, id1]
    @mode = Set.new
    @band = Set.new
    @freq = [ nil, nil ]
    @freqMode = [ "Unknown", "Unknown" ]
    @freqBand = [ "Unknown", "Unknown" ]
  end
  attr_reader :mode, :band

  def id1
    @ids[0]
  end

  def id2
    @ids[1]
  end

  def oneBand
    @band.to_a[0]
  end

  def oneMode
    @mode.to_a[0]
  end

  def bandStr
    a = @band.to_a.sort
    result = a[0]
    @freqBand.each { |b|
      if b == a[0]
        result += "*"
      end
    }
    if a.length > 1
      result += ("|" + a[1])
      if @freqBand.include?(a[1])
        result += "*"
      end
    end
    result
  end

  def modeStr
    a = @mode.to_a.sort
    result = a[0]
    @freqMode.each { |m|
      if m == a[0]
        result += "*"
      end
    }
    if a.length > 1
      result += ("|" + a[1])
      if @freqMode.include?(a[1])
        result += "*"
      end
    end
    result
  end

  def to_s
    sprintf("%-12s %-8s", bandStr, modeStr)
  end
  
  def to_h
    { "type" => "QSOMatch",
      "ids" => @ids, "mode" => @mode.to_a,
      "band" => @band.to_a, 
      "freq" => @freq }
  end

  def setFreq(num, freq)
    @freq[num] = freq
    case freq
    when 1800..2000
      @freqBand[num] = "160m"
      @freqMode[num] = "Unknown"
    when 3500..4000
      @freqBand[num] = "80m"
      if (freq > 3500 and freq < 3600)
        @freqMode[num] = "CW"
      elsif (freq >= 3600 and freq <= 4000)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 7000..7300
      @freqBand[num] = "40m"
      if (freq > 7000 and freq < 7125)
        @freqMode[num] = "CW"
      elsif (freq >= 7125 and freq <= 7300)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 10100..10150
      @freqBand[num] = "30m"
      @freqMode[num] = "CW"
    when 14000..14350
      @freqBand[num] = "20m"
      if (freq > 14000 and freq < 14150)
        @freqMode[num] = "CW"
      elsif (freq >= 14150 and freq <= 14350)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 18068..18168
      @freqBand[num] = "17m"
      if (freq > 18068 and freq < 18110)
        @freqMode[num] = "CW"
      elsif (freq >= 18110 and freq <= 18168)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 21000..21450
      @freqBand[num] = "15m"
      if (freq > 21000 and freq < 21200)
        @freqMode[num] = "CW"
      elsif (freq >= 21200 and freq <= 21450)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 24890..24990
      @freqBand[num] = "12m"
      if (freq > 24890 and freq < 24930)
        @freqMode[num] = "CW"
      elsif (freq >= 24930 and freq <= 24990)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 28000..29700
      @freqBand[num] = "10m"
      if (freq > 28000 and freq < 28300)
        @freqMode[num] = "CW"
      elsif (freq >= 28300 and freq <= 29700)
        @freqMode[num] = "PH"
      else
        @freqMode[num] = "Unknown"
      end
    when 50
      @freqBand[num] = "6m"
      @freqMode[num] = "Unknown"
    when 144
      @freqBand[num] = "2m"
      @freqMode[num] = "Unknown"
    when 222
      @freqBand[num] = '222'
      @freqMode[num] = "Unknown"
    when 432
      @freqBand[num] = '432'
      @freqMode[num] = "Unknown"
    when 902
      @freqBand[num] = '902'
      @freqMode[num] = "Unknown"
    else
      @freqBand[num] = "Unknown"
      @freqMode[num] = "Unknown"
    end
  end

  def mismatch?
    @mode.length != 1 or @band.length != 1
  end

  def modeMismatch?
    @mode.length != 1
  end

  def bandMismatch?
    @band.length != 1
  end

  def bandMode
    # assumes there is only one band and mode
    @band.to_a[0] + "-" + @mode.to_a[0]
  end

  def metric(dominantMode = ['Neither', 'Neither'])
    result = 0
    band = @band.to_a[0]
    mode = @mode.to_a[0]
    @freqMode.each { |fm|
      if fm == mode
        result += 3
      else
        if fm != "Unknown"
          result -= 3
        end
      end
    }
    dominantMode.each { |dm|
      if dm == mode
        result += 3
      else
        if dm != "Neither"
          result -= 3
        end
      end
    }
    if mode == "PH"
      result += 1
    end
    @freqBand.each { |fb|
      if fb == band
        result += 2
      else
        if fb != "Unknown"
          result -= 2
        end
      end
    }
    result
  end
  
  def mode=(val)
    val.each { |v|
      if not ILLEGAL_MODES.include?(v)
        @mode << MODE_MAP[v]
      end
    }
  end

  def band=(val)
    val.each { |v|
      if not WARC_BANDS.include?(v)
        @band << v
      end
    }
  end
end

class MatchLog
  DOMINANT_THRESHOLD  = 5
  def initialize(id)
    @id = id
    @numCW = 0
    @numPH = 0
  end

  def dominantMode
    if @numCW >= DOMINANT_THRESHOLD and @numPH == 0
      return "CW"
    elsif @numPH >= DOMINANT_THRESHOLD and @numCW == 0
      return "PH"
    end
    "Neither"
  end

  def to_h
    { "type" => "MatchLog",
      "id" => @id,
      "numCW" => @numCW.to_i,
      "numPH" => @numPH.to_i }
  end

  attr_reader :id, :numCW, :numPH
  attr_writer :numCW, :numPH
end

class MismatchedLogs
  def initialize(log1, log2)
    @logs = [ log1, log2 ]
    @qsos = Array.new
  end

  def to_h
    { "type" => "MismatchedLogs",
      "logs" => @logs,
      "qsos" => @qsos
    }
  end

  def dominantMode
    @logs.map { |l| l.dominantMode }
  end

  def metric
    dominant = dominantMode
    bandMode = Set.new
    result = 0
    @qsos.each { |q|
      bandMode << q.bandMode
      result += q.metric(dominant)
    }
    return result + 100*bandMode.length
  end

  def allAmbiguous
    result = Array.new
    @qsos.each { |q|
      if q.mode.length > 1
        result << q.mode
      end
      if q.band.length > 1
        result << q.band
      end
    }
    result
  end

  def numUnresolved
    result = 0
    @qsos.each { |qso|
      if qso.modeMismatch?
        result += 1
      end
      if qso.bandMismatch?
        result += 1
      end
    }
    result
  end

  def <<(qso)
    @qsos << qso
  end

  attr_reader :qsos
end

  

class BandModeMismatch
  def initialize(db, contestID, cdb)
    @db = db
    @contestID = contestID
    @cdb = cdb
    @logs = LogSet.new(cdb.logsForContest(contestID))
  end

  def resolve
    resolveSimple
    # everything left is now a band mode mismatch
    resolveMismatched
  end

  MODEMAP = { 'PH' => 'PH', 'CW' => 'CW', 'FM' => 'CW' }.freeze
  def resolveSimple
    # for any unmatched QSO the band and mode are taken as authoritative
    @db.query("update QSO set judged_band = band, judged_mode = fixedMode where #{@logs.membertest("logID")} and judged_band is null and judged_mode is null and matchID is null and fixedMode in ('PH', 'CW');")
    @db.query("update QSO set judged_band = band, judged_mode = 'PH' where #{@logs.membertest("logID")} and judged_band is null and judged_mode is null and matchID is null and fixedMode = 'FM';")
    # for matched QSOs where bands agree, the judged_band is the match
    @db.query("select q1.id, q2.id, q1.band from QSO as q1 join QSO as q2 on (q1.id = q2.matchID and q2.id = q1.matchID) where #{@logs.membertest("q1.logID")} and q1.id < q2.id and q1.band = q2.band and (q1.judged_band is null or q2.judged_band is null);") { |row|
      @db.query("update QSO set judged_band = ? where id in (?, ?) and judged_band is null;", [ row[2], row[0], row[1] ]) { }
    }
    # for matched QSOs where modes agree, the judged_mode is the match
    @db.query("select q1.id, q2.id, q1.fixedMode from QSO as q1 join QSO as q2 on (q1.id = q2.matchID and q2.id = q1.matchID) where #{@logs.membertest("q1.logID")} and q1.id < q2.id and q1.fixedMode = q2.fixedMode and (q1.judged_mode is null or q2.judged_mode is null);") { |row|
      @db.query("update QSO set judged_mode = ? where id in (?, ?) and judged_mode is null;", [ MODEMAP[row[2]], row[0], row[1] ]) { }
    }
  end

  def qsoCounts(id)
    @db.query("select sum(fixedMode = 'CW'), sum(fixedMode in ('PH','FM')) from QSO where logID = ? group by logID limit 1;", [ id ]) { |countrow|
      return countrow[0], countrow[1]
    }
    return 0, 0
  end

 
  def getBit(val, bit)
    (val >> bit) & 1
  end
  
  def assignChoice(x, choices, perm)
    x.each_with_index { |set, ind|
      set.clear
      set << choices[ind][getBit(perm, ind)]
    }
  end
  
  def resolveMismatched
    logsWithMismatches = Array.new
    @db.query("select distinct q1.logID, q2.logID from QSO as q1 join QSO as q2 on (q1.id = q2.matchID and q2.id = q1.matchID) where #{@logs.membertest("q1.logID")} and q1.logID < q2.logID and (q1.judged_mode is null or q1.judged_band is null or q2.judged_mode is null or q2.judged_band is null);") { |row|
      log1 = MatchLog.new(row[0])
      cw, phone = qsoCounts(log1.id)
      log1.numCW = cw
      log1.numPH = phone
      log2 = MatchLog.new(row[1])
      cw, phone = qsoCounts(log2.id)
      log2.numCW = cw
      log2.numPH = phone
      mm = MismatchedLogs.new(log1, log2)
      @db.query("select q1.id, q1.frequency, coalesce(q1.judged_mode, q1.fixedMode), coalesce(q1.judged_band, q1.band), q2.id, q2.frequency, coalesce(q2.judged_mode, q2.fixedMode), coalesce(q2.judged_band, q2.band) from QSO as q1 join QSO as q2 on (q1.id = q2.matchID and q2.id = q1.matchID) where q1.logID = ? and q2.logID = ?;", [row[0], row[1] ]) { |qrow|
        qm = QSOMatch.new(qrow[0], qrow[4])
        qm.setFreq(0, qrow[1])
        qm.setFreq(1, qrow[5])
        qm.band = [ qrow[3], qrow[7] ]
        qm.mode = [ qrow[2], qrow[6] ]
        mm << qm
      }
      logsWithMismatches << mm
    }
#    File.write("bandmode.json", JSON.pretty_generate(jsonFriendly(logsWithMismatches)))

    logsWithMismatches.each { |un|
      amb = un.allAmbiguous
      choiceVector = amb.map { |s| s.to_a }
      numPerm = (2 ** choiceVector.length)
      if numPerm > 0
        assignChoice(amb, choiceVector, 0)
        best = 0
        bestMetric = un.metric
        1.upto(numPerm-1) { |p|
          assignChoice(amb, choiceVector, p)
          nextMetric = un.metric
          if nextMetric > bestMetric
            bestMetric = nextMetric
            best = p
          end
        }
        assignChoice(amb, choiceVector, best)
      end
    }
    qsosByBand = Hash.new
    %w{ 2m 6m 222 432 902 10m 15m 20m 40m 80m 160m }.each { |band|
      qsosByBand[band] = Array.new
    }
    qsosByMode = Hash.new
    %w{ CW PH }.each { |mode|
      qsosByMode[mode] = Array.new
    }
    logsWithMismatches.each { |un|
      un.qsos.each { |q|
        print "QSO #{q.id1} #{q.id2}\n"
        qsosByBand[q.oneBand].insert(-1, q.id1, q.id2)
        qsosByMode[q.oneMode].insert(-1, q.id1, q.id2)
      }
    }
    numChanged = 0
    qsosByBand.each { |band, ids|
      if not ids.empty?
        @db.query("update QSO set judged_band = ? where id in (#{ids.join(", ")}) and judged_band is null;", [ band ])
        numChanged += @db.affected_rows
      end
    }
    print "#{numChanged} band mismatches fixed\n"
    numChanged = 0
    qsosByMode.each { |mode, ids|
      if not ids.empty?
        print "#{mode} #{ids.join(", ")}\n"
        @db.query("update QSO set judged_mode = ? where id in (#{ids.join(", ")}) and judged_mode is null;", [ MODEMAP[mode] ])
        numChanged += @db.affected_rows
      end
    }
    print "#{numChanged} mode mismatches fixed\n"
  end
end
