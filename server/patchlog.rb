#!/usr/local/bin/ruby
# -*- encoding: utf-8 -*-
# CQP upload script
# Tom Epperly NS6T
# ns6t@arrl.net
#
#
require 'set'

def makePatch(attributes)
  result = "".encode("US-ASCII")
  attributes.each { |key, value|
    keystr = key.upcase.strip.encode("US-ASCII") + ": " 
    if value =~ /(\r?\n)/       # multi-line value string
      value.split(/(\r?\n)/).each { |line|
        result = result + keystr + line.strip.encode("US-ASCII", :invalid => :replace,
                                                           :undef => :replace) + "\n"
      }
    else
      result = result + keystr + value.to_s.strip.encode("US-ASCII", :invalid => :replace,
                                                           :undef => :replace) + "\n"
    end
  }
  result
end

def findConvenientLocation(content)
  # first choice is right before the first QSO
  loc = content.index(/^\s*QSO\s*:/i)
  if not loc
    # second choice is before any legitimate Cabrillo header item
    loc = content.index(/^\s*(LOCATION|CALLSIGN|CATEGORY-OPERATOR|CATEGORY-ASSISTED|CATEGORY-POWER|CATEGORY-TRANSMITTER|CLAIMED-SCORE|CLUB|CONTEST|CREATED-BY|NAME|ADDRESS|ADDRESS-CITY|ADDRESS-STATE-PROVINCE|ADDRESS-POSTALCODE|ADDRESS-COUNTRY|OPERATORS|SOAPBOX|EMAIL|OFFTIME|CATEGORY)\s*:/i)
  end
  loc
end

def patchLog(content, attributes)
  content.gsub!(/\r\n/, "\n".encode("US-ASCII"))   # standardize on Linux EOL standard
  patch = makePatch(attributes)
  firstQ = findConvenientLocation(content)
  if firstQ                     # insert patch right before first QSO
    content = content.insert(firstQ, patch)
  end
  content
end

BADCLUBNAME = %w{OTHER NONE }.to_set
BADCLUBNAME.freeze

def makeAttributes(id, callsign, email, email_confirm, sentqth, phone, 
                   comments, multiclub,
                   expedition, youth, mobile, female, school, newcontester,
                   clubname, clubother, clubcategory,
                   opclass, powclass)
  result = { }
  result['X-CQP-CALLSIGN'] = callsign
  result['X-CQP-SENTQTH'] = sentqth
  result['X-CQP-EMAIL'] = email
  result['X-CQP-CONFIRM1'] = email_confirm
  result['X-CQP-PHONE'] = phone
  result['X-CQP-COMMENTS'] = comments
  result['X-CQP-POWER'] = (powclass ? powclass.upcase : "")
  result['X-CQP-OPCLASS'] = (opclass ? opclass.upcase : "")
  case multiclub
  when 0
    result['X-CQP-MULTICLUB'] = "false"
  when 1
    result['X-CQP-MULTICLUB'] = "true"
  else
    result['X-CQP-MULTICLUB'] = "unknown"
  end
  categories = [ ]
  if expedition == 1
    categories.push("COUNTY")
  end
  if youth == 1
    categories.push("YOUTH")
  end
  if mobile == 1
    categories.push("MOBILE")
  end
  if female == 1
    categories.push("YL")
  end
  if school == 1
    categories.push("SCHOOL")
  end
  if newcontester == 1
    categories.push("NEW_CONTESTER")
  end
  if clubname and (not clubname.strip.empty?) and (not BADCLUBNAME.include?( clubname))
    result['X-CQP-CLUBNAME'] = clubname.strip.upcase
  else
    if clubother and (not clubother.strip.empty?) and (not BADCLUBNAME.include?(clubother))
      result['X-CQP-CLUBNAME'] = clubother.strip.upcase
    else
      result['X-CQP-CLUBNAME'] = "NONE"
    end
  end
  if clubcategory and (not clubcategory.strip.empty?)
    result['X-CQP-CLUBCATEGORY'] = clubcategory.strip.upcase
  else
    result['X-CQP-CLUBCATEGORY'] = "UNSPECIFIED"
  end
  result['X-CQP-CATEGORIES'] = categories.join(" ")
  result['X-CQP-ID'] = id.to_s
  result['X-CQP-TIMESTAMP'] = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S.%L +0000")
  power = power.to_s.strip.upcase
  if %w( LOW HIGH QRP ).include?(power)
    result['X-CQP-POWER'] = power
  end
  opclass = opclass.to_s.upcase
  if %w( SINGLE SINGLE-ASSISTED MULTI-SINGLE MULTI-MULTI CHECKLOG ).include?(opclass)
    result['X-CQP-OPCLASS'] = opclass
  end
  result
end
