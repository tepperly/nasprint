#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring

require 'sqlite3'

class DatabaseSQLite
  AUTOINCREMENT="autoincrement"

  def initialize(opts)
    @db = SQLite3::Database.new(opts["filename"])
  end

  def true
    1
  end

  def has_enum?
    false
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
