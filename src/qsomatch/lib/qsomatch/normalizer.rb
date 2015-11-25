#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
#
# Normalize a CQP pseudo-Cabrillo
# By Tom Epperly
# ns6t@arrl.net
#
require 'set'

def fixIt(prompt, value, hash)
  if hash.has_key?(value)
    val = hash[value]
    if val.kind_of? String
      return val
    else
      return value
    end
  else
    ans = nil
    while not ["A", "ACCEPT", "R", "REPLACE"].include? ans
      print prompt + ": " + value + " (accept/replace)?"
      ans = STDIN.gets.strip.upcase
    end
    case ans
    when 'A', 'ACCEPT'
      hash[value] = true        # don't ask again
      return value
    when 'R', 'REPLACE'
      hash[value] = STDIN.gets.strip.upcase
      return hash[value]
    end
  end
end

def checkSuspitious(call, linechanged, callChange)
  call = call.upcase
  newcall = fixIt("CALL:", call, callChange)
  return newcall, (linechanged or (newcall != call))
end

def checkSerial(serial, linechanged, serialChange)
  serial = serial.upcase
  newserial = fixIt("SERIAL: ", serial, serialChange)
  return newserial, (linechanged or (newserial != serial))
end

def checkName(name, linechanged, nameChange)
  name = name.upcase
  newname = fixIt("NAME: ", name, nameChange)
  return newname, (linechanged or (newname != name))
end

MDC_MULTS = ["DC", "MD", "MDC"].to_set.freeze

def checkMultiplier(mult, callsign, linechanged, multChange)
  mult = mult.upcase
  if "MAR" == mult or "MR" == mult
    case callsign.upcase
    when "VE1BVD", "VE1DT"
      return "NS", true
    when "VE9AA", "VE9DX", "VE9OA"
      return "NB", true
    when "VO1KVT"
      return "NF", true
    when "VO2NS"
      return "LB", true
    when "VY2LI", "VY2SS"
      return "PE", true
    else
      return "MAR", false
    end
  elsif MDC_MULTS.include?(mult)
    case callsign.upcase
    when "4U1WB", "NN3RP", "W3DQ", "W3GQ", "W3HAC"
      return "DC", ("DC" != mult)
    else
      return mult, false
    end 
  elsif "DX" == mult
    if /^[AKN]H6/.match(callsign.upcase)
      return "HI", ("HI" != mult)
    else
      return mult, false
    end
  else
    newmult = fixIt("MULT: ", mult, multChange)
    return newmult, (linechanged or (newmult != mult))
  end
end


CHECK_MULTS = ["MR", "MD", "DC", "MDC", "DX"].to_set.freeze

def filterLines(filename, lines, callChange, multiplierChange, nameChange, serialChange)
  changed = false
  lines.each_index { |i|
    linechanged = false
    if lines[i].start_with?("QSO:")
      fields = lines[i].split
      if 1 != fields[5].scan(/\d/).size
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[5], linechanged = checkSuspitious(fields[5], linechanged, callChange)
      end
      if 1 != fields[9].scan(/\d/).size
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[9], linechanged = checkSuspitious(fields[9], linechanged, callChange)
      end
      if not /\A\d+\Z/.match(fields[6])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[6], linechanged = checkSerial(fields[6], linechanged, serialChange)
      end
      if not /\A\d+\Z/.match(fields[10])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[10], linechanged = checkSerial(fields[10], linechanged, serialChange)
      end
      if /\d/.match(fields[7])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[7], linechanged = checkName(fields[7], linechanged, namechange)
      end
      if /\d/.match(fields[11])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[11], linechanged = checkName(fields[11], linechanged, namechange)
      end
      if not /\A[A-Z][A-Z]\Z/i.match(fields[8]) or CHECK_MULTS.include?(fields[8])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[8], linechanged = checkMultiplier(fields[8], fields[5], linechanged, multiplierChange)
      end
      if not /\A[A-Z][A-Z]\Z/i.match(fields[12]) or CHECK_MULTS.include?(fields[12])
        print filename + ":" + (i+1).to_s + ":" + lines[i]
        fields[12], linechanged = checkMultiplier(fields[12], fields[9], linechanged, multiplierChange)
      end
      if linechanged
        lines[i] = ("%4s %5s %2s %10s %4s %-10s %4s %-10s %2s  %-10s %4s %-10s %2s " % fields) + fields[13..-1].join(" ") + "\n"
      end
    end
    changed = (changed or linechanged)
  }
  changed
end


callsignRewrites = Hash.new
multiplierRewrites = Hash.new
nameRewrites = Hash.new
serialRewrites = Hash.new
ARGV.each { |arg|
  lines = IO.readlines(arg)
  if filterLines(arg, lines, callsignRewrites, multiplierRewrites, nameRewrites, serialRewrites)
    open(arg, "w:ascii") { |outfile|
      outfile.write(lines.join)
    }
  end
}
