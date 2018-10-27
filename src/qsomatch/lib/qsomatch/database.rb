#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#

def makeDB(opts = {})
  case opts["type"]
  when "sqlite3"
    require_relative 'database_sqlite'
    return DatabaseSQLite.new(opts)
  when "mysql"
    require_relative 'database_mysql'
    return DatabaseMysql.new(opts)
  end
end
