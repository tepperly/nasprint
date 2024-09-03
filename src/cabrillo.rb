 #!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
# Parse a NA Sprint pseudo-Cabrillo
# By Tom Epperly
# ns6t@arrl.net
#
require 'csv'
require 'time'

CONTEST_START=Time.utc(2024,03,24,0,0)
CONTEST_END=Time.utc(2024,03,24,4,0)

def mySplit(str, pattern)
  result = [ ]
  start = 0
  while m = pattern.match(str, start)
    if (m.begin(0) - 1) >= start
      result << str[start..(m.begin(0)-1)]
    end
    start = m.end(0)
  end
  if start < str.length
    result << str[start..-1]
  end
  result
end

END_OF_RECORD = /(\r\n?|\n\r?)(?=([a-z]+(-([a-z]+\d*|\d+))*:)|([ \t]*\Z))/i

class Exchange
  def initialize
    @callsign = nil
    @leadingZero = nil
    @name = nil
    @serial = nil
    @qth = nil
    @origqth = nil
  end

  def to_s
    if @leadingZero
      "%-13s %04d %-11s %-11s" % [callsign.to_s, serial.to_i, name.to_s, qth.to_s]
    else
      "%-13s %4d %-11s %-11s" % [callsign.to_s, serial.to_i, name.to_s, qth.to_s]
    end
  end

  attr_reader :callsign, :serial, :qth, :name, :leadingZero, :origqth
  attr_writer :callsign, :qth, :name, :leadingZero, :origqth

  def serial=(value)
    if value.instance_of?(String)
      v = value.strip
      @leadingZero = v.start_with?("0")
    end
    @serial = value.to_i
  end
end


UNPRINTABLE=/[\000\001\002\003\004\005\006\007\010\013\016\017\020\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177]/

class QSO

  def initialize
    @origmode = nil
    @mode = nil
    @freq = nil
    @datetime = nil
    @sentExch = Exchange.new
    @recdExch = Exchange.new
    @transceiver = nil
  end

  attr_reader :mode, :freq, :datetime, :sentExch, :recdExch, :transceiver,
              :origmode

  attr_writer :freq, :datetime, :transceiver
  def mode=(str)
    @origmode = str.strip.upcase
    case str
    when /[uls]sb?|phone|ph/i
      @mode = "PH"
    when /fm/i
      @mode = "FM"
    when /cw|morse/i
      @mode = "CW"
    when /ry|rtty|rt/i
      @mode = "RY"
    else
      raise ArgumentError, "Unknown QSO mode #{str}"
    end
  end

  def to_s
    "QSO: " + @freq.to_s + " " + @mode + " " + @datetime.strftime("%Y-%m-%d %H%M") + " " +
      @sentExch.to_s + " " + @recdExch.to_s + (@transceiver ? @transceiver.to_s : "")
  end
end

class OperatorClass
  def initialize
    @assisted = nil
    @numop = nil                # single, multi, checklog
    @power = nil                # high, low, qrp
    @numtrans = nil             # one or unlimited
    @email = nil
    @phone = nil
    @comment = nil
    @sentQTH = nil
  end

  attr_reader :assisted, :numop, :power, :station, :numtrans,
              :email, :phone,
              :comment, :sentQTH
  attr_writer :email, :phone, :comment, :sentQTH
  
  def assisted=(value)
    @assisted = (value ? true : false)
  end

  ALLOWED_OP_VALUES = { :single => true, :multi => true, :checklog => true }
  def numop=(value)
    if ALLOWED_OP_VALUES[value]
      @numop = value
    else
      raise ArgumentError, "Argument is not one of the allowable values for numop #{value}"
    end
  end

  ALLOWED_POWER_VALUES = { :low => true, :high => true, :qrp => true }
  def power=(value)
    if ALLOWED_POWER_VALUES[value]
      @power = value
    else
      raise ArgumentError, "Argument is not one of the allowable values for power #{value}"
    end
  end

  ALLOWED_STATION_VALUES = { :fixed => true, :mobile => true, :portable => true,
    :rover => true, :expedition => true, :hq => true, :school => true }
  def station=(value)
    if ALLOWED_STATION_VALUES[value]
      @station = value
    else
      raise ArgumentError, "Argument is not one of the allowable values for station #{value}"
    end
  end

  ALLOWED_TRANS_VALUES = { :one => true, :unlimited => true, :swl => true }
  def numtrans=(value)
    if ALLOWED_TRANS_VALUES[value]
      @numtrans = value
    else
      raise ArgumentError, "Argument is not one of the allowable values for numtrans #{value}"
    end
  end
    
end

def readMultipliers(file)
  multAlias = Hash.new
  CSV.foreach(file, "r:ascii") { |row|
    multAlias[row[0].strip.upcase] = row[1].strip.upcase
  }
  multAlias.freeze
  return multAlias
end

class Cabrillo
  MULTIPLIER_ALIASES = readMultipliers(File.dirname(__FILE__) + "/multipliers.csv")

  def initialize(filename)
    @logID = nil
    @cleanparse = true
    @filename = filename
    @cabversion = nil
    @certificate = nil
    @name = nil
    @claimed = nil
    @gridsquare = nil
    @section = nil
    @location = nil
    @club = nil
    @iota = nil
    @creator = nil
    @logcall = nil
    @dblogcall = nil
    @dbphone = nil
    @dbsentqth = nil
    @timeperiod = nil
    @parsestate = 0
    @logCat = OperatorClass.new
    @dbCat = OperatorClass.new
    @dbcomments = nil
    @stationType = nil
    @band = nil
    @address = [ ]
    @x_lines = [ ]
    @offtimes =  [ ]
    @soapbox = [ ]
    @city = nil
    @state = nil
    @postcode= nil
    @country = nil
    @operators = nil
    @qsos = [ ]
    parse
  end

  attr_reader :cleanparse, :logcall, :qsos, :club, :name, :gridsquare

  def trans(oldstate, newstate)
    if @parsestate <= oldstate
      @parsestate = newstate
    else
      $stderr.write("Unexpected state transition #{@parsestate} #{oldstate} #{newstate} in #{@filename}.\n")
      @parsestate = newstate
    end
  end

  def normalizeMult(str)
    tmp = normalizeString(str)
    if MULTIPLIER_ALIASES[tmp]
      return  MULTIPLIER_ALIASES[tmp]
    else
      $stderr.write("Unknown multiplier: '" + str + "'\n")
      return tmp
    end
  end

  def fixTime(time)
    hour = time / 100
    min = time % 100
    if min >= 60
      min = 59
    end
    if hour >= 24
      hour = 23
    end
    hour * 100 + min
  end

  def parseTime(date, time)
    date = date.gsub("/","-")
    if (date =~ /\d{1,2}-\d{1,2}-\d{4}/) # mon-day-year
      date = $3 + "-" + $1 + "-" + $2
    end
    time = time.to_i
    begin
      result = Time.strptime(date + " " + ("%04d" % time) + " UTC", "%Y-%m-%d %H%M %Z")
    rescue => e
      time = fixTime(time)
      if date =~ /\A\d{2}-\d{1,2}-\d{1,2}\Z/ # two digit year
        result = Time.strptime(date + " " + ("%04d" % time) + " UTC", "%y-%m-%d %H%M %Z")
      else
        result = Time.strptime(date + " " + ("%04d" % time) + " UTC", "%Y-%m-%d %H%M %Z")
      end
    end
    result
  end

  def startQSO(freq, mode, date, time, sentcall)
    trans(2,2)
    qso = QSO.new
    qso.freq = freq.to_i
    qso.mode = mode.to_s
    qso.datetime = parseTime(date, time)
    qso.sentExch.callsign = sentcall.upcase
    if @logcall.nil?
      @logcall = sentcall.upcase
    end
    qso
  end

  def processLine(line)
    case line
    when /\Astart-of-log:\s*([23].0)?\s*/i
      if $1
        @cabversion = $1
      end
      trans(0,1)
    when /\Aend-of-log:\s*/i
      trans(2, 3)
    when /\Acallsign:\s*([a-z0-9]+(\/[a-z0-9]+(\/[a-z0-9])?)?)?\s*/i
      trans(1, 1)
      if $1
        @logcall = $1.upcase
      end
    when /\Acategory-assisted:\s*((non-|un)?assis?ted)?\s*\Z/i
      if $1
        @logCat.assisted = ($1.upcase == "ASSISTED")
      end
      trans(1, 1)
    when /\Acategory-assisted:\s*no(\s+assisted)?\s*/i
      trans(1, 1)
      @logCat.assisted = false
    when /\Acategory-band:\s*(\S*)?\s*/i
      trans(1, 1)
      @band = $1
    when /\Acategory-dxpedition:\s*(\S*)\s/i
      @dxpedition = $1
      trans(1, 1)
    when /\Acategory-mode:\s*(ssb|cw|rtty|mixed)\s*/i
      @mode = $1
      trans(1, 1)
    when /\Agrid-locator:\s*([a-z0-9]+)\s*/i
      @gridsquare = $1
      trans(1,1)
    when /\Acategory-mode:\s*ph\s*/i
      trans(1, 1)
      @mode = "SSB"
    when /\Acategory-operator:\s*(single-op|single\s+operator|single)\s*\Z/i
      trans(1, 1)
      @logCat.numop = :single
    when /\Acategory-operator:\s*checklog\s*/i
      trans(1, 1)
      @logCat.numop = :checklog
    when /\Acategory-operator:\s*multi-op|multiple\s*/i
      trans(1,1)
      @logCat.numop = :multi
    when /\Acategory-operator:\s*multi-single\s*/i
      trans(1, 1)
      @logCat.numop = :multi
      @logCat.numtrans = :one
    when /\Acategory-operator:\s*multi-multi\s*/i
      trans(1, 1)
      @logCat.numop = :multi
      @logCat.numtrans = :unlimited
    when /\Acategory-power:\s*(low|qrp|high)\s*/i
      trans(1, 1)
      @logCat.power = $1.downcase.to_sym
    when /\Acategory-power:\s*(\d+)(\s*w)?\s*/i
      trans(1, 1)
      pow = $1.to_i
      if (pow <= 5)
        @logCat.power = :qrp
      elsif (pow <= 200)
        @logCat.power = :low
      else
        @logCat.power = :high
      end
    when /\Acategory-power:\s*(lo(cal)?)\s*\Z/i
      trans(1, 1)
      @logCat.power = :low
    when /\Acategory-station:\s*(fixed|portable|hq)\s*\Z/i
      trans(1, 1)
      @stationType = $1.upcase
    when /\Acategory-station:\s*(mobile|rover|hq)\s*\Z/i
      trans(1, 1)
    when /\Acategory-station:\s*(school)\s*\Z/i
      trans(1, 1)
    when /\Acategory-station:\s*(home)\s*\Z/i
      trans(1, 1)
      @station = "fixed"
    when /\Acategory-station:\s*\Z/i
      # ignore
    when /\Acategory-time:\s*((\d+)[- ]hours?)?\s*/i
      trans(1, 1)
      if $1
        hours = $2.to_i
        if hours <= 6
          hours = 6
        elsif hours <= 12
          hours = 12
        else
          hours = 24
        end
        @timeperiod = "#{hours}-HOURS"
      end
    when /\Acategory-time:\s*(\d+)\s*\Z/i
      trans(1, 1)
      if $1
        hours = $1.to_i
        if hours <= 6
          hours = 6
        elsif hours <= 12
          hours = 12
        else
          hours = 24
        end
        @timeperiod = "#{hours}-HOURS"
      end
    when /\Acategory:\s*(.*)\Z/i
      trans(1, 1)
      processCategories($1.upcase)
    when /\Acategory-transmitter:\s*(one|two|limited|unlimited|swl)?\s*/i
      trans(1, 1)
      if $1
        if $1.upcase == "ONE"
          @logCat.numtrans = :one
        elsif $1.upcase == "SWL"
          @logCat.numtrans = :swl
        else
          @logCat.numtrans = :unlimited
        end
      end
    when /\Acategory-overlay:\s*((\S+)(\s+\S+)*)?\s*\Z/i
      trans(1, 1)
      if $1
        processOverlay($1.upcase)
      end
    when /\Acertificate:\s*(yes|no)\s*/i
      trans(1, 1)
      @certificate = ($1.upcase == "YES")
    when /\Aclaimed-score:\s*(\S*)\s*/i
      trans(1, 1)
      if $1 and $1.length > 0
        @claimed = $1
      end
    when /\Aarrl-section:\s*(\S+)?\s*/i
      trans(1, 1)
      if $1
        @section = normalizeString($1)
        if MULTIPLIER_ALIASES[@section]
          @logCat.sentQTH = MULTIPLIER_ALIASES[@section]
        end
      end
    when /\A(team|club(-name)?):\s*(.*)/i
      trans(1, 1)
      @club = $3.strip.gsub(/\s+/, " ")
    when /\Aiota-island-name:\s*(.*)/i
      trans(1, 1)
      @iota = $1.strip.gsub(/s+/, " ")
    when /\Acontest:\s*(.*)/i
      trans(1, 1)
      # ignore
    when /\Acreated-by:\s*(.*)/i
      trans(1, 1)
      @creator = $1.strip
    when /\A(e-?mail|address-email):\s*(.*)/i
      trans(1, 1)
      @logCat.email = $2.strip
    when /\Alocation:\s*(.*)/i
      trans(1, 1)
      @location = normalizeString($1)
      if MULTIPLIER_ALIASES[@location]
        @logCat.sentQTH = MULTIPLIER_ALIASES[@location]
      end
    when /\A(category-)?name:\s*(.*)/i
      trans(1, 1)
      @name = $2.strip.gsub(/\s+/, " ")
    when /\Aaddress:\s*(.*)/i
      trans(1, 1)
      @address << $1.strip
    when /\Aaddress-city:\s*(.*)/i
      trans(1, 1)
      @city = $1.strip
    when /\A(address-)?state-province:\s*(.*)/i
      trans(1, 1)
      @state = $2.strip
    when /\Aaddress-postalcode:\s*(.*)/i
      trans(1, 1)
      @postcode = $1.strip
    when /\Aaddress-country:\s*(.*)/i
      trans(1, 1)
      @country = $1.strip
    when /\Aoperators:\s*(.*)/i
      trans(1, 1)
      @operators = $1.strip
    when /x-ssbsprint-email:\s*(.*)/i
      @dbCat.email = $1.strip
      @x_lines << line          # save
    when /\Aofftime:\s*(.*)/i
      trans(1, 1)
      @offtimes << $1.strip
    # when /\Ax-cqp-comments:\s*(.*)\Z/i
    #   trans(1, 1)
    #   if $1 and $1.length > 0
    #     if @dbcomments
    #       @dbcomments = @dbcomments + $1.strip + "\n"
    #     else
    #       @dbcomments = $1.strip + "\n"
    #     end
    #   end
    when /\Ax(-[a-z]+)+:.*/i
      @x_lines << line          # ignore and save
    when /hq-date-received:\s*(.*)/i
      @x_lines << line          # ignore and save
    when /hq-confirmation:\s*(.*)/i
      @x_lines << line          # ignore and save
    when /grid-locator:\s*(.*)/i
      @x_lines << line          # ignore and save
    when /\Asoapbox:\s*(.*)/i
      trans(1, 1)
      @soapbox << $1.strip
    when /\Aqso: +(\d+) +([a-z]{2,3}) +(\d{4}[-\/]\d{1,2}[-\/]\d{1,2}) +(\d{4}) +([a-z0-9]+(\/[a-z0-9]+(\/[a-z0-9])?)?) +(\d+) +([a-z]+) +([a-z0-9]+) +([a-z0-9]+(\/[a-z0-9]+(\/[a-z0-9])?)?) +(\d+) +([a-z]+) +([a-z0-9]+)( +(\d+) *| *)(\{.*\})?$/i
      qso = startQSO($1, $2, $3, $4, $5)
      qso.sentExch.serial = $8
      qso.sentExch.name = $9
      qso.sentExch.origqth = $10.upcase.strip
      qso.sentExch.qth = normalizeMult($10)
      if qso.sentExch.qth and not @logCat.sentQTH
        @logCat.sentQTH = qso.sentExch.qth
      end
      qso.recdExch.callsign = $11.upcase
      qso.recdExch.serial = $14
      qso.recdExch.name = $15
      qso.recdExch.origqth = $16.upcase.strip
      qso.recdExch.qth = normalizeMult($16)
      if ($18)
        qso.transceiver = $18.strip.to_i
      end
      @qsos << qso
    else
      return "Unknown line: '" + line + "'\n"
    end
    false
  end

  def pretreat(content)
    if content.scan(UNPRINTABLE).length >= (content.length / 15)
      raise ArgumentError, "File #{@filename} appears to be binary"
    end
    content.gsub!("\000", " ")  # replace null character with space
    if content.scan(/<eo[rh]>/i).length >= 5
      raise ArgumentError, "File #{@filename} appears to be a ADIF"
    end
    if content.scan(/^start-of-log:/i).length == 1
      content.gsub!(/.*^start-of-log:/im,"START-OF-LOG:")
    end
    return content
  end

  def sigReportCount(sym, value)
    count = 0
    @qsos.each { |qso|
      ser = qso.method(sym).call.serial
      if (59 == ser) or (599 == ser)
        count = count + 1
      end
      if ser.nil?
        qso.method(sym).call.serial = value
      end
    }
    count
  end

  def each
    @qsos.each { |qso|
      yield qso
    }
  end

  def sigReportSet(sym, value)
    @qsos.each { |qso|
      ser = qso.method(sym).call.serial 
      if (59 == ser) or (599 == ser) or ser.nil?
        qso.method(sym).call.serial = value
      end
    }
  end

  def normalizeString(str)
    str.strip.upcase.gsub(/\s{2,}/, " ")
  end
    

  def defaultSentQTH
    if @dbCat.sentQTH
      tmp = normalizeString(@dbCat.sentQTH)
      if MULTIPLIER_ALIASES[tmp]
        return MULTIPLIER_ALIASES[tmp]
      end
    end
    if @logCat.sentQTH and MULTIPLIER_ALIASES[@logCat.sentQTH]
      return MULTIPLIER_ALIASES[@logCat.sentQTH]
    end
    nil
  end

  def reviewQTH(sym, default="XXXX")
    @qsos.each { |qso|
      if qso.method(sym).call.qth.nil?
        qso.method(sym).call.qth = default
      end
    }
  end

  def reviewQSOs
    if sigReportCount(:sentExch,9999) >= ((3*@qsos.length)/4)
      sigReportSet(:sentExch, 9999)
    end
    if sigReportCount(:recdExch, 9999) >= ((3*@qsos.length)/4)
      sigReportSet(:recdExch, 9999)
    end
    reviewQTH(:sentExch, defaultSentQTH)
    reviewQTH(:recdExch)
  end

  def checkTime(qso)
    if qso.datetime < CONTEST_START
      print "QSO date #{qso.datetime} before contest start\n"
    end
    if qso.datetime > CONTEST_END
      print "QSO date #{qso.datetime} after contest end\n"
    end
  end

  def parse
    @parsestate = 0
    content = pretreat(File.read(@filename, {:encoding => "US-ASCII"}))
    lines = mySplit(content, END_OF_RECORD)
    lines.each { |line|
      msg = processLine(line) 
      if msg
        if line =~ /\AQSO:/
          line.gsub!(/[^-a-zA-Z\/0-9 :]/," ")
          if processLine(line)       # try again
            @cleanparse = false
            $stderr.write(msg)
          end
        else
          @cleanparse = false
          $stderr.write(msg)
        end
      end
    }
    reviewQSOs
    @qsos.each { |qso| checkTime(qso) }
    print "cleanparse is #{@cleanparse.to_s}\n"
  end

  def logCall
    if @dblogcall and ((@dblogcall =~ /\A[A-Z0-9\/]+\Z/) or not @logcall)
      @dblogcall
    else
      @logcall
    end
  end

  def logPower
    if @dbCat.power
      @dbCat.power.to_s.upcase
    else
      @logCat.power.to_s.upcase
    end
  end

  def logNumTrans
    if @dbCat.numtrans
      @dbCat.numtrans.to_s.upcase
    else
      @logCat.numtrans.to_s.upcase
    end
  end

  def logAssisted
    if not @dbCat.assisted.nil?
      @dbCat.assisted ? "ASSISTED" : "NON-ASSISTED"
    else
      @logCat.assisted ? "ASSISTED" : "NON-ASSISTED"
    end
  end

  def calcClaimed
    tmp = @claimed.strip.gsub(/\s+|[,.]/,"")
    tmp.to_i.to_s
  end

  def logEmail
    if @dbCat.email and @dbCat.email.length > 1 
      @dbCat.email
    else
      @logCat.email
    end
  end

  def normalizeOps
    @operators.split(/\s*,\s*|\s+/).join(" ")
  end

  def logOperator
    if @dbCat.numop
      case @dbCat.numop
      when :single
        return "SINGLE-OP"
      when :multi
        return "MULTI-OP"
      when :checklog
        return "CHECKLOG"
      end
    end
    if @logCat.numop
      case @logCat.numop
      when :single
        return "SINGLE-OP"
      when :multi
        return "MULTI-OP"
      when :checklog
        return "CHECKLOG"
      end
    end
    "CHECKLOG"
  end


  def write(out)
   out.write("START-OF-LOG: 3.0
CALLSIGN: #{logCall}
CATEGORY-ASSISTED: #{logAssisted}
CATEGORY-OPERATOR: #{logOperator}
CATEGORY-POWER: #{logPower}
CATEGORY-TRANSMITTER: #{logNumTrans}
CONTEST: NA-SPRINT-SSB
NAME: #{@name}
")
    if @band
      out.write("CATEGORY-BAND: " + normalizeString(@band) + "\n")
    end
    if @mode
      out.write("CATEGORY-MODE: " + normalizeString(@mode) + "\n")
    end
    if @stationType
      out.write("CATEGORY-STATION: " + normalizeString(@stationType) + "\n")
    end
    if @timeperiod
      out.write("CATEGORY-TIME: " + @timeperiod + "\n")
    end
    if not @certificate.nil?
      out.write("CERTIFICATE: " + (@certificate ?  "YES\n" : "NO\n" ))
    end
    if @claimed and @claimed.strip.length > 0
      out.write("CLAIMED-SCORE: " + calcClaimed + "\n")
    end
    if @club and @club.strip.length > 0
      out.write("CLUB: " + @club.strip.gsub(/\s{2,}/, " ") + "\n")
    end
    if @creator and @creator.strip.length > 0
      out.write("CREATED-BY: " + @creator.strip + "\n")
    end
    email = logEmail
    if email and email.length > 0
      out.write("EMAIL: " + email + "\n");
    end
    if @location and @location.strip.length > 0
      out.write("LOCATION: " + @location.strip + "\n")
    else
      if @section and @section.strip.length > 0
        out.write("LOCATION: " + @section.strip + "\n")
      else
        if @iota and @iota.strip.length > 0
          out.write("LOCATION: " + @iota.strip + "\n")
        end
      end
    end
    @address.each { |line|
      line = line.strip
      if line.length > 0
        out.write("ADDRESS: " + line + "\n")
      end
    }
    if @city and @city.strip.length > 0
      out.write("ADDRESS-CITY: " + @city.strip + "\n")
    end
    if @state and @state.strip.length > 0
      out.write("ADDRESS-STATE-PROVINCE: " + @state.strip + "\n")
    end
    if @postcode and @postcode.strip.length > 0
      out.write("ADDRESS-POSTALCODE: " + @postcode.strip + "\n")
    end
    if @country and @country.strip.length > 0
      out.write("ADDRESS-COUNTRY: " + @country.strip + "\n")
    end
    if @operators and @operators.strip.length > 0
      out.write("OPERATORS: " + normalizeOps + "\n")
    end
    @offtimes.each { |line|
      out.write("OFFTIME: " + line.strip + "\n")
    }
    @soapbox.each { |line|
      out.write("SOAPBOX: " + line.strip + "\n")
    }
    @x_lines.each { |line|
      out.write(line.strip + "\n")
    }
    @qsos.each { |qso|
      writeQSO(out, qso)
    }
    out.write("END-OF-LOG:\n")
  end
  
  def writeQSO(out, qso)
    out.write("QSO: %5d %2s %4d-%02d-%02d %04d " %
              [ qso.freq, qso.mode, 
                qso.datetime.year,
                qso.datetime.month,
                qso.datetime.day,
                qso.datetime.hour*100 + qso.datetime.min ])
    out.write(qso.sentExch.to_s + " " + qso.recdExch.to_s)
    if qso.transceiver
      out.write(" " + qso.transceiver.to_s)
    end
    out.write("\n")
  end


  def processOverlay(str)
    str.split.each { |tok|
      case tok
      when 'CLASSIC','EXPERT','OVER-50', 'ROOKIE','TB-WIRES', 'GENERAL', 'FIXED', 'STATION', 'YOUTH'
      when 'SINGLE-OP'
        @logCat.numop = :single
      end
    }
  end

  def processCategories(str)
    if (str =~ /MULTI-MULTI|M-M/)
      @logCat.numop = :multi
      @logCat.numtrans = :unlimited
      str.gsub!(/MULTI-MULTI|M-M/, " ")
    end
    if (str =~ /NON-ASSIS?TED/)
      @logCat.assisted = false
      str.gsub!(/NON-ASSIS?TED/,"")
    end
    str.gsub!(/POWER/," ")
    str.split(/[-! \t\m]+/).each { |tok|
      case tok
      when "SINGLE"
        @logCat.numop = :single
      when "MULTI"
        @logCat.numop = :multi
      when "ONE"
        @logCat.numtrans = :one
      when 'TWO'
        @logCat.numtrans = :unlimited
      when "HIGH", "LOW", "QRP"
        @logCat.power = tok.downcase.to_sym
      when "ASSISTED"
        @logCat.assisted = true
      when "UNASSISTED"
        @logCat.assisted = false
      when "CHECKLOG"
        @logCat.numop = :checklog
      when "LO", "LP", "LOWW"
        @logCat.power = :low
      when 'SO'
        @logCat.numop = :single
      when 'ALL'
        @band = "ALL"
      when "15"
        @band = "15m"
      when 'MIXED', "SSB", "CW"
        @mode = tok
      when 'MM'
        @logCat.numop = :multi
        @logCat.numtrans = :unlimited
      when "MS"
        @logCat.numop = :multi
        @logCat.numtrans = :one
      when "MEDIUM", "HP"
        @logCat.power = :high
      when /OP|CLUB|50|OVER/
      when /10M|15M|20M|40M|80M/
        @band = tok
      when /PHONE/
        @mode = "SSB"
      else
        $stderr.write("Missing: '#{tok}'\n")
      end
    }
  end

  def dbcomments=(value)
    if value and value.strip.length > 0
      @dbcomments = value.strip
    end
  end

  def dblogcall=(value)
    if value and value.length > 0
      @dblogcall = value.upcase.strip
    end
  end

  def dbsentqth=(qth)
    @dbCat.sentQTH = qth
  end
  
  def dblogID=(id)
    @logID = id
  end

  def dboptype=(value)
    case value
    when "single", "single-op"
      @dbCat.assisted = false
      @dbCat.numop = :single
      @dbCat.numtrans = :one
    when "multi-single"
      @dbCat.assisted = true    # not really sure
      @dbCat.numop = :multi
      @dbCat.numtrans = :one
    when "multi-multi"
      @dbCat.assisted = true    # not really sure
      @dbCat.numop = :multi
      @dbCat.numtrans = :unlimited
    when "checklog"
      @dbCat.assisted = true
      @dbCat.numop = :checklog
      @dbCat.numtrans = :unlimited
    else
      raise ArgumentError, "Unknown dboptype #{value}"
    end
  end

  def dbpower=(value)
    case value
    when "Low"
      @dbCat.power = :low
    when "High"
      @dbCat.power = :high
    when "QRP"
      @dbCat.power = :qrp
    else
      raise ArgumentError, "Unknown dbpower #{value}"
    end
  end
  
  def dbemail=(value)
    @dbCat.email = value
  end

  attr_accessor :dbphone

end
