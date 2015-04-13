#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# 

# require 'database'
require 'nokogiri'
require_relative 'fetch'

XML_NAMESPACE = {'qrz' => 'http://xmldata.qrz.com'}
DELIM = /\s*,\s*/

def addToDb(db, xml, filename)
  xml.xpath("//qrz:Callsign/qrz:call", XML_NAMESPACE).each { |match|
    db[match.text.strip.upcase] = filename
  }
  xml.xpath("//qrz:Callsign/qrz:aliases", XML_NAMESPACE).each { |match|
    match.text.strip.upcase.split(DELIM) { |call|
      db[call] = filename
    }
  }
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
  str, xml = qrz.lookupCall(call)
  if str and xml
    open("xml_db/#{call}.xml", "w:iso-8859-1") { |out|
      out.write(str)
    }
    addToDb(db, xml, "xml_db/#{call}.xml")
    true
  else
    print "Lookup failed: #{call}\n"
    false
  end
end
