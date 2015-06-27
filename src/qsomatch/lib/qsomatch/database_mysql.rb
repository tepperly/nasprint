#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
require 'mysql2'
require 'mysql2-cs-bind'

class DatabaseMysql
  AUTOINCREMENT="auto_increment"
  def initialize(opts)
    @db = Mysql2::Client.new(opts)
  end

  def toDateTime(obj)
    obj                         # MySQL already has it as a date
  end

  def dateAdd(starttime, adjustment, units)
    return "date_add(" + starttime + ", INTERVAL " +
      adjustment.to_s + " " + units + ")"
  end

  def dateSub(starttime, adjustment, units)
    return "date_sub(" + starttime + ", INTERVAL " +
      adjustment.to_s + " " + units + ")"
  end


  def timediff(units, time1, time2)
    "timestampdiff(" + units + ", " + time1 + ", " + time2 + ")"

  def autoincrement
    return AUTOINCREMENT
  end

  def has_enum?
    true
  end

  def true
    "TRUE"
  end

  def close
    @db.close
  end

  def last_id
    @db.last_id
  end

  def affected_rows
    @db.affected_rows
  end
  
  def tables
    results = Array.new
    res = @db.query("show tables;")
    res.each(:as => :array) { |row|
      results << row[0]
    }
    results
  end

  def formattime(time)
    time.strftime("%Y-%m-%d %H:%M:%S")
  end

  def query(queryStr, values = [ ])
    @db.xquery(queryStr, values, :as => :array)
  end
end
