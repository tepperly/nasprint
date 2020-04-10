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
    @in_transaction = false
    @db = SQLite3::Database.new(opts["filename"])
    @db.busy_timeout(500)
    if $verbose
      @db.trace { |sql|
        print "SQLite3 Statement #{Time.now.to_s} (#{@in_transaction ? 1 : 0}): #{sql}\n"
        $stdout.flush
      }
    end
  end

  def true
    1
  end

  def false
    0
  end

  def boolToDB(val)
    return val ? 1 : 0
  end

  def toBool(val)
    (val and (val.to_i != 0)) ? true : false
  end

  def formattime(time)
    time.strftime("%Y-%m-%dT%H:%M:%SZ")
  end

  def has_enum?
    false
  end

  def begin_transaction
    @db.execute("begin transaction;")
    @in_transaction = true
  end

  def end_transaction
    if @in_transaction
      @db.execute("commit transaction;")
      @in_transaction = false
    end
  end

  def rollback
    @in_transaction = false
    @db.execute("rollback transaction;")
  end

  def affected_rows
    @db.changes
  end

  DIFF_DIVISOR = {
    "MINUTE" => "60.0",
    "SECOND" => "1",
    "HOUR" => "(60.0*60.0)"
  }

  def adjtimediff(units, t1, adj1, t2, adj2)
    "(((strftime('%s'," + t1 + ") + " + adj1.to_s +
      ") - (strftime('%s'," + t2 + ") + " + adj2.to_s + "))/" +
      DIFF_DIVISOR[units] + ")"
  end

  def timediff(units, time1, time2)
    "((strftime('%s'," + time1 + ") - strftime('%s'," + time2 + "))/" +
      DIFF_DIVISOR[units] + ")"
  end

  def toDateTime(obj)
    obj.kind_of?(String) ? Time.iso8601(obj) : obj
  end

  def toSecs(value, units)
    case units
    when 'second','seconds'
      return value
    when 'minute', 'minutes'
      return "(60*(" + value + "))"
    when 'hour', 'hours'
      return "(3600*(" + value + "))"
    when 'day', 'days'
      return "(86400*(" + value + "))"
    end
  end

  def dateAdd(starttime, adjustment, units)
    if adjustment.kind_of?(Numeric)
      return "datetime(" + starttime + ", \"" +
        ((adjustment > 0) ? "+" : "-") +
        adjustment.abs.to_s + " " + units + "\")"
    else
      return "datetime(strftime('%s'," + starttime + ") + " +
        toSecs(adjustment, units) + ", 'unixepoch')"
    end
  end

  def dateSub(starttime, adjustment, units)
    if adjustment.kind_of?(Numeric)
      return "datetime(" + starttime + ", \"" +
        ((adjustment > 0) ? "-" : "+") +
        adjustment.abs.to_s + " " + units + "\")"
    else
      return "datetime(strftime('%s'," + starttime + ") - " +
        toSecs(adjustment, units) + ", 'unixepoch')"
    end
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
    if block_given?
      @db.execute(queryStr, values) { |row|
        yield row
      }
      nil
    else
      return @db.execute(queryStr, values)
    end
  end

  def close
    @db.execute("PRAGMA optimize;") unless @db.closed?
    @db.close
  end
end
