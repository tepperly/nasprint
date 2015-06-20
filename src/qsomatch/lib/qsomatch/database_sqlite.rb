#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring

require 'sqlite3'
require 'time'

module Mysql2
  class Error
    def error_number
      1062
    end
  end
end

class DatabaseSQLite
  AUTOINCREMENT="autoincrement"

  def initialize(opts)
    @db = SQLite3::Database.new(opts["filename"])
  end

  def true
    1
  end

  def formattime(time)
    time.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def has_enum?
    false
  end

  def affected_rows
    @db.changes
  end

  DIFF_DIVISOR = {
    "MINUTE" => "60.0",
    "SECOND" => "1",
    "HOUR" => "(60.0*60.0)"
  }

  def timediff(units, time1, time2)
    "((" + time1 + " - " + time2 + ")/" +
      DIFF_DIVISOR[units] + ")"
  end

  def toDateTime(obj)
    obj.kind_of?(String) ? Time.iso8601(obj) : obj
  end


  def autoincrement
    return AUTOINCREMENT
  end

  def tables
    results = Array.new
    res = @db.execute("select name from main.sqlite_master where type='table' order by name asc;")
    res.each { |row|
      results << row[0]
    }
    results
  end

  def last_id
    @db.last_insert_row_id
  end

  def query(queryStr, values = [ ])
    @db.execute(queryStr, values)
  end

  def close
    @db.close
  end
end
