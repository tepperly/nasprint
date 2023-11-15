#!/usr/bin/env ruby

require 'sqlite3'
require 'set'

class FCC
  def initialize(filename)
    @db = SQLite3::Database.new(filename)
    @db.busy_timeout(500)
    res = @db.execute("select name from sqlite_master where type='table' and name='Active'")
    @activeTable = "select AM.operator_class from AM, HD where AM.callsign=? and AM.unique_system_identifier=HD.unique_system_identifier and AM.callsign = HD.callsign and HD.license_status = \"A\" limit 1;"
    res.each { |row|
      @activeTable = "select id from Active where callsign=? limit 1;"
    }
  end

  def validHFLicense?(callsign)
    res = @db.execute(@activeTable, [callsign])
    res.each { |row|
      return true
    }
    return false
  end
end
