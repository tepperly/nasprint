#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# 

# require 'database'
require 'nokogiri'
require_relative 'fetch'

XML_NAMESPACE = {'qrz' => 'http://xmldata.qrz.com'}
DELIM = /\s*,\s*/

def addToDb(db, xml, filename)
  found = false
  xml.xpath("//qrz:Callsign/qrz:call", XML_NAMESPACE).each { |match|
    db[match.text.strip.upcase] = filename
    found = true
  }
  xml.xpath("//qrz:Callsign/qrz:aliases", XML_NAMESPACE).each { |match|
    match.text.strip.upcase.split(DELIM) { |call|
      found = true
      db[call] = filename
    }
  }
  return found
end

def readXMLDb(db = Hash.new)
  specialEntries = /^\.\.?$/
  Dir.foreach("xml_db") { |filename|
    if not specialEntries.match(filename)
      wholefile = "xml_db/" + filename
      open(wholefile, "r:iso8859-1:utf-8") { |io|
        xml = Nokogiri::XML(io)
        addToDb(db, xml, wholefile)
      }
    end
  }
  db
end


def lookupCall(qrz, db, call)
  if qrz
    str, xml = qrz.lookupCall(call)
    if str and xml
      open("xml_db/#{call}.xml", "w:iso-8859-1") { |out|
        str.encode!(Encoding::ISO_8859_1, :undef => :replace)
        out.write(str)
      }
      return addToDb(db, xml, "xml_db/#{call}.xml")
    else
      print "Lookup failed: #{call}\n"
      return false
    end
  end
  false
end
