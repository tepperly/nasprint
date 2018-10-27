#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require_relative 'callsign'
require 'set'

def calcOpClass(cab)
  cab.cqpOpClass
end

def calcPowClass(cab)
  cab.logPower
end

def numFromString(callsign, str)
  if str
    opset = Set.new
    str.split.each { |op|
      if op =~ /\A([a-z0-9]+(\/[a-z0-9]+(\/[a-z0-9])?)?)?\Z/i
        opset << op
      else
        if not op.start_with?("@")
          $stderr.write("Strange operator #{op} in log #{callsign}\n")
        end
      end
    }
    return [1, opset.length].max
  end
  1
end

def calcNumOps(opclass, cab)
  if opclass.start_with?("SINGLE")
    if numFromString(cab.logCall, cab.normalizeOps) != 1
      $stderr.write("Mismatch for #{cab.logCall} between operator class (#{opclass}) and operator line: #{cab.normalizeOps}\n")
    end
    return 1
  else
    return numFromString(cab.logCall, cab.normalizeOps)
  end
end

def checkLocation(db, cab)
  sentQTH = cab.defaultSentQTH
  if sentQTH
    multID, entityID = db.lookupMultiplier(sentQTH)
    return multID, entityID
  end
  return nil, nil
end

def band(freq)
  case freq
  when 1800..2000
    "160m"
  when 3500..4000
    "80m"
  when 7000..7300
    "40m"
  when 10100..10150
    "30m"
  when 14000..14350
    "20m"
  when 18068..18168
    "17m"
  when 21000..21450
    "15m"
  when 24890..24990
    "12m"
  when 28000..29700
    "10m"
  when 50
    "6m"
  when 144
    "2m"
  when 222
    '222'
  when 432
    '432'
  when 902
    '902'
  else
    "unknown"
  end
end

def addQSOs(db, contestID, logID, qsos)
  qsos.each { |qso|
    id = db.insertQSO(contestID, logID, qso.freq, band(qso.freq),
                 qso.origmode, qso.mode, qso.datetime,
                      qso.sentExch, qso.recdExch, qso.transceiver)
    if id and qso.hasGreenInfo?
      db.insertGreenInfo(id, logID, qso.greenattrib)
    end
  }
end

def addOperators(db, logID, ops, basecall)
  numops = 0
  if ops and ops.respond_to?(:each)
    ops.each { |op|
      if not op.start_with?("@")
        numops += 1
      end
    }
    ops.each { |op|
      db.addOperator(logID, op, (op.start_with?("@") ? 0 : 1.0/numops))
    }
  end
  if 0 == numops
    # every log has at least one operator
    db.addOperator(logID, basecall, 1)
  end
end


def addLog(db, cID, cab, ct)
  if cab.logcall
    multID, entID = checkLocation(db, cab)
    if multID
      basecall = ct.callBase(cab.logcall)
      bcID = db.addOrLookupCall(basecall, cID)
      db.markReceived(bcID)
      opclass = calcOpClass(cab)
      logID = db.addLog(cID, cab.logcall, bcID, cab.logEmail,
                        calcPowClass(cab),
                        opclass,
                        multID, entID, cab.name, cab.club, calcNumOps(opclass,cab),
                        cab.hasSpecialCategory?("COUNTY"),
                        cab.hasSpecialCategory?("MOBILE"),
                        cab.hasSpecialCategory?("NEW_CONTESTER"),
                        cab.hasSpecialCategory?("SCHOOL"),
                        cab.hasSpecialCategory?("YL"),
                        cab.hasSpecialCategory?("YOUTH"),
                        )
      addQSOs(db, cID, logID, cab.qsos)
      addOperators(db, logID, cab.opList, basecall)
    else
      print "!!Can't add a log for #{cab.logcall} with no location\n"
    end
  else
    print "!!Can't add a log without a callsign\n"
  end
end
