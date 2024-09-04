#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#

require 'mysql2'
require 'json'

def makeDB
  host = "localhost"
  username = "nasprint"
  database = "NASprint"
  password = "secret"
  [ Dir.home, Dir.getwd ].each { |directory|
    filename = File.join(directory, ".nasprint.json")
    if File.file?(filename)
      begin
        o = JSON.parse(File.read(filename))
        if o.has_key?("username")
          username = o["username"]
        end
        if o.has_key?("database")
          database = o["database"]
        end
        if o.has_key?("password")
          password = o["password"]
        end
        if o.has_key?("host")
          host = o["host"]
        end
        break
      rescue
        print "Unable to read in file " + filename +  "\n"
      end
    end
  }
  return Mysql2::Client.new(:host => host,
                            :username => username, :password => password,
                            :database => database)
end
