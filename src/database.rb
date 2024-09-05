#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#

require 'mysql2'
require 'json'

def makeDB
  configuration={"host" => "localhost", "username" => "nasprint", "database" => "NASprint", "password" => "secret" }
  [ Dir.home, Dir.getwd ].each { |directory|
    filename = File.join(directory, ".nasprint.json")
    if File.file?(filename)
      begin
        o = JSON.parse(File.read(filename))
        configuration.keys.each{ |key|
          if o.has_key?(key)
            configuration[key] = o[key]
          end
        }
        break
      rescue
        print "Unable to read in file " + filename +  "\n"
      end
    end
  }
  return Mysql2::Client.new(:host => configuration["host"],
                            :username => configuration["username"], :password => configuration["password"],
                            :database => configuration["database"])
end
