#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require_relative 'callsign'

def calcOpClass(cab)
  if (cab.logOperator != "SINGLE-OP") # or (cab.logAssisted == "ASSISTED")
    return "CHECKLOG"
  else
    return cab.logPower
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
    db.insertQSO(contestID, logID, qso.freq, band(qso.freq),
                 qso.origmode, qso.mode, qso.datetime,
                 qso.sentExch, qso.recdExch, qso.transceiver)
  }
end

def addLog(db, cID, cab)
  if cab.logcall
    multID, entID = checkLocation(db, cab)
    if multID
      basecall = callBase(cab.logcall)
      bcID = db.addOrLookupCall(basecall, cID)
      db.markReceived(bcID)
      logID = db.addLog(cID, cab.logcall, bcID, cab.logEmail,
                        calcOpClass(cab),
                        multID, entID, cab.name, cab.club)
      addQSOs(db, cID, logID, cab.qsos)
    else
      print "!!Can't add a log with no location\n"
    end
  else
    print "!!Can't add a log without a callsign\n"
  end
end
