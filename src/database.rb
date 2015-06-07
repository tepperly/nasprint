#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#

require 'mysql2'

def makeDB
  return Mysql2::Client.new(:host => "localhost",
                            :username => "nasprint", :password => "NASpRiNtpwd",
                            :database => "CQPQSOs")
end
