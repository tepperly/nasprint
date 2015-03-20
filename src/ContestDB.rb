#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#
require 'csv'


class ContestDatabase
  CHARS_PER_CALL = 16

  def initialize(db)
    @db = db
    createDB
  end

  def createDB
    createContestTable
    createEntityTable
    createMultiplierTable
    createLogTable
    createQSOTable
  end

  def createContestTable
    @db.query("create table if not exists Contest (id integer primary key auto_increment, year smallint not null);")
  end

  def createEntityTable
    @db.query("create table if not exists Entity (id integer primary key, name varchar(64) not null, continent enum ('AS', 'EU', 'AF', 'OC', 'NA', 'SA', 'AN') not null);")
    open(File.dirname(__FILE__) + "/entitylist.txt", "r:ascii") { |inf|
      inf.each { |line|
        if (line =~ /^\s+\S+\s+(.*)\s+([a-z][a-z](,[a-z][a-z])?)\s+\S+\s+\S+\s+(\d+)\s*$/i)
          begin
            @db.query("insert into Entity (id, name, continent) values (#{$4.to_i}, \"#{@db.escape($1.strip)}\", \"#{@db.escape($2[0,2])}\");")
          rescue Mysql2::Error => e
            if e.error_number != 1062 # ignore duplicate entry
              raise e
            end
          end
        else
          "Entity line doesn't match: #{line}"
        end
      }
    }

  end

  def createMultiplierTable
    @db.query("create table if not exists Multiplier (id integer primary key auto_increment, abbrev char(2) not null unique, entityID integer, ismultiplier bool);")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
      begin
        if row[0] == row[1]
          entity = row[2].to_i
          if entity > 0
            @db.query("insert into Multiplier (abbrev, entityID, ismultiplier) values (\"#{@db.escape(row[1].strip.upcase)}\", #{entity}, TRUE);")
          else
            # DX gets a null for entityID and ismultiplier
            @db.query("insert into Multiplier (abbrev) values (\"#{@db.escape(row[1].strip.upcase)}\");")
          end
        end
      rescue Mysql2::Error => e
        if e.error_number != 1062 # ignore duplicate entry
          raise e
        end
      end
    }
    @db.query("create table if not exists MultiplierAlias (id integer primary key auto_increment, abbrev varchar(32) not null unique, multiplierID integer not null, entityID integer not null);")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
      if row[0] != row[1]
        begin
          res = @db.query("select id, entityID from Multiplier where abbrev = '#{@db.escape(row[1].strip.upcase)}' limit 1")
          if row[3]
            entityID = row[3].to_i
          else
            entityID = nil
          end
          res.each(:as => :array) { |mult|
            if entityID and (entityID <= 0)
              entityID = mult[2].to_i
            end
            @db.query("insert into MultiplierAlias (abbrev, multiplierID, entityID) values ('#{@db.escape(mult[0])}', #{mult[1].to_i}, #{entityID});")
          }
        rescue Mysql2::Error => e
          if e.error_number != 1062 # ignore duplicate
            raise e
          end
      end
    }
  end

  def createLogTable
    # table of callsigns converted to base format
    @db.query("create table if not exists Callsign (id integer primary key auto_increment, contestID integer not null, basecall varchar(#{CHARS_PER_CALL}) not null, logrecvd bool, validcall bool, index bcind (contestID, basecall));")
    @db.query("create table if not exists Log (id integer primary key auto_increment, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, callID integer not null, email varchar(128), opclass enum('CHECKLOG', 'QRP', 'LOW', 'HIGH'), verifiedscore integer, verifiedQSOs integer, verifiedMultipliers integer, index callind (callsign), index contestind (contestID));")
  end

  def createQSOTable
    @db.query("create table if not exists Exchange (id integer primary key auto_increment, callsign varchar(#{CHARS_PER_CALL}), callID integer, serial integer, name varchar(24), location varchar(8), multiplierID integer, entityID integer, index calltxtind (callsign), index callidind (callID), index serialind (serial), index locind (location), index multind (multiplierID), index nameind (name));")
    @db.query("create table if not exists QSO (id integer primary key auto_increment, logID integer not null, frequency integer, band enum('20m', '40m', '80m', 'unknown'), mode char(6), fixedMode enum('PH', 'CW', 'FM', 'RY'), time datetime, sentID integer not null, recvdID integer not null, transmitterNum integer, matchID integer, matchType enum('None','Full','Bye', 'Unique', 'Partial', 'NIL') not null default 'None');")
  end
end
