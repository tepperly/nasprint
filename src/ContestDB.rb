#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#
require 'csv'


class ContestDatabase
  CHARS_PER_CALL = 16
  CHARS_PER_NAME = 24

  def initialize(db)
    @db = db
    @contestID = nil
    createDB
  end

  attr_writer :contestID
  attr_reader :contestID

  def readTables
    result = Array.new
    res = @db.query("show tables;")
    res.each(:as => :array) { |row|
      result << row[0]
    }
    result.sort
  end

  def createDB
    tables = readTables
    if not tables.include?("Contest")
      createContestTable
    end
    if not tables.include?("Entity")
      createEntityTable
    end
    createHomophoneTable
    if not tables.include?("Multiplier")
      createMultiplierTable
    end
    createMultiplierAlias
    if not (tables.include?("Callsign") and tables.include?("Log"))
      createLogTable
    end
    if not (tables.include?("Exchange") and tables.include?("QSO"))
      createQSOTable
    end
    if not tables.include?("Overrides")
      createOverrides
    end
    if not tables.include?("Pairs")
      createPairs
    end
  end

  def createContestTable
    @db.query("create table if not exists Contest (id integer primary key auto_increment, name varchar(64) not null, year smallint not null, unique index contind (name, year), start datetime not null, end datetime not null);")
  end

  def createHomophoneTable
    @db.query("create table if not exists Homophone (id integer primary key auto_increment, name1 varchar(#{CHARS_PER_NAME}), name2 varchar(#{CHARS_PER_NAME}), index n1ind (name1), index n2ind (name2));")
    CSV.foreach(File.dirname(__FILE__) + "/homophones.csv", "r:ascii") { |row|
      row.each { |i|
        row.each { |j|
          begin
            @db.query("insert into Homophone (name1, name2) values (\"#{@db.escape(i)}\", \"#{@db.escape(j)}\");")
          rescue Mysql2::Error => e
            if e.error_number != 1062 # ignore duplicate entry
              raise e
            end
          end
        }
      }
    }
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
  end
  
  def createMultiplierAlias
    @db.query("create table if not exists MultiplierAlias (id integer primary key auto_increment, abbrev varchar(32) not null unique, multiplierID integer not null, entityID integer not null);")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
      if row[0] != row[1]
        begin
          res = @db.query("select id, entityID from Multiplier where abbrev = \"#{@db.escape(row[1].strip.upcase)}\" limit 1")
          if row[2]
            entityID = row[2].to_i
          else
            entityID = nil
          end
          res.each(:as => :array) { |mult|
            if (not entityID) or (entityID <= 0)
              entityID = mult[1].to_i
            end
            @db.query("insert into MultiplierAlias (abbrev, multiplierID, entityID) values (\"#{@db.escape(row[0])}\", #{mult[0].to_i}, #{entityID});")
          }
        rescue Mysql2::Error => e
          if e.error_number != 1062 # ignore duplicate
            raise e
          end
        end
      end
    }
  end
  
  def createLogTable
    # table of callsigns converted to base format
    @db.query("create table if not exists Callsign (id integer primary key auto_increment, contestID integer not null, basecall varchar(#{CHARS_PER_CALL}) not null, logrecvd bool, validcall bool, index bcind (contestID, basecall));")
    @db.query("create table if not exists Log (id integer primary key auto_increment, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, callID integer not null, email varchar(128), multiplierID integer not null, entityID integer default null, opclass enum('CHECKLOG', 'QRP', 'LOW', 'HIGH'), verifiedscore integer, verifiedQSOs integer, verifiedMultipliers integer, clockadj integer not null default 0, index callind (callsign), index contestind (contestID));")
  end

  def createQSOTable
    @db.query("create table if not exists Exchange (id integer primary key auto_increment, callsign varchar(#{CHARS_PER_CALL}), callID integer, serial integer, name varchar(#{CHARS_PER_NAME}), location varchar(8), multiplierID integer, entityID integer, index calltxtind (callsign), index callidind (callID), index serialind (serial), index locind (location), index multind (multiplierID), index nameind (name));")
    @db.query("create table if not exists QSO (id integer primary key auto_increment, logID integer not null, frequency integer, band enum('20m', '40m', '80m', 'unknown') default 'unknown', mode char(6), fixedMode enum('PH', 'CW', 'FM', 'RY'), time datetime, sentID integer not null, recvdID integer not null, transmitterNum integer, matchID integer, matchType enum('None','Full','Bye', 'Unique', 'Partial', 'Dupe', 'NIL', 'OutsideContest', 'Removed','TimeShiftFull', 'TimeShiftPartial') not null default 'None', comment varchar(256), index matchind (matchType), index bandind (band), index logind (logID), index timeind (time));")
  end

  def addOrLookupCall(callsign, contestIDVar=nil)
    callsign = callsign.upcase
    if not contestIDVar
      contestIDVar = @contestID
    end
    if contestIDVar
      result = @db.query("select id from Callsign where basecall=\"#{@db.escape(callsign)}\" and contestID = #{contestIDVar.to_i} limit 1;")
      result.each(:as => :array) { |row|
        return row[0].to_i
      }
      @db.query("insert into Callsign (contestID, basecall) values (#{contestIDVar.to_i}, \"#{@db.escape(callsign)}\");")
      return @db.last_id
    end
    nil
  end

  def addOrLookupContest(name, year, create=false)
    if name and year
      result = @db.query("select id from Contest where name=\"#{@db.escape(name)}\" and year = #{year.to_i} limit 1;")
      result.each(:as => :array) { |row|
        return row[0].to_i
      }
      if create
        @db.query("insert into Contest (name, year) values (\"#{@db.escape(name)}\", \"#{year.to_i}\");")
        return @db.last_id
      end
    end
    nil
  end

  def strOrNull(str)
    if str
      return "\"" + @db.escape(str) + "\""
    else
      return "NULL"
    end
  end

  def capOrNull(str)
    if str
      return "\"" + @db.escape(str.upcase) + "\""
    else
      return "NULL"
    end
  end

  def numOrNull(num)
    if num
      return num.to_i.to_s
    else
      return "NULL"
    end
  end

  def markReceived(callID)
    @db.query("update Callsign set logrecvd = 1 where id = #{callID.to_i} limit 1;")
  end

  def addLog(contID, callsign, callID, email, opclass, multID, entID)
    @db.query("insert into Log (contestID, callsign, callID, email, opclass, multiplierID, entityID) values (#{contID.to_i}, #{capOrNull(callsign)}, #{callID.to_i}, #{strOrNull(email)}, #{strOrNull(opclass)}, #{multID.to_i}, #{numOrNull(entID)});")
    return @db.last_id
  end

  def lookupMultiplier(str)
    res = @db.query("select id, entityID from Multiplier where abbrev = #{capOrNull(str)} limit 1;")
    res.each(:as => :array) { |row|
      return row[0].to_i, (row[1].nil? ? nil : row[1].to_i)
    }
    return nil, nil
  end

  def createOverrides
    @db.query("create table if not exists Overrides (id integer primary key auto_increment, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, multiplierID integer not null, entityID integer not null, index callindex (callsign));")
  end

  def removeOverrides(contestID)
    @db.query("delete from Overrides where contestID = #{contestID};")
  end
  
  def createPairs
    @db.query("create table if not exists Pairs (id integer primary key auto_increment, contestID integer not null, line1 varchar(128) not null, line2 varchar(128) not null, ismatch bool, index contind (contestID), index lineind (line1, line2));")
  end

  def removePairs(contestID)
    @db.query("delete from Pairs where contestID = #{contestID};")
  end

  def removeExchange(id)
    if id.respond_to?('join')
      @db.query("delete from Exchange where id in (#{id.join(", ")}) limit #{id.size};")
    else
      @db.query("delete from Exchange where id = #{id.to_i} limit 1;")
    end
  end

  def addExchange(callsign, callID, serial, name, location, multID,
                  entityID)
    @db.query("insert into Exchange (callsign, callID, serial, name, location, multiplierID, entityID) values (#{capOrNull(callsign)}, #{callID.to_i}, #{numOrNull(serial)}, #{capOrNull(name)}, #{capOrNull(location)}, #{numOrNull(multID)}, #{numOrNull(entityID)});")
    return @db.last_id
  end

  def dateOrNull(date)
    if date
      return date.strftime("\"%Y-%m-%d %H:%M:%S\"")
    else
      "NULL"
    end
  end

  def insertQSO(logID, frequency, band, roughMode, mode, datetime,
                sentID, recvdID, transNum)
    @db.query("insert into QSO (logID, frequency, band, mode, fixedMode, time, sentID, recvdID, transmitterNum) values (#{numOrNull(logID)}, #{numOrNull(frequency)}, #{strOrNull(band)}, #{capOrNull(roughMode)}, #{strOrNull(mode)}, #{dateOrNull(datetime)}, #{numOrNull(sentID)}, #{numOrNull(recvdID)}, #{numOrNull(transNum)});")
  end

  def removeContestQSOs(contestID)
    logs = Array.new
    exchanges = Array.new
    res = @db.query("select id from Log where contestID = #{contestID};")
    res.each(:as => :array) { |row| logs << row[0] }
    res = @db.query("select recvdID, sentID from QSO where logID in (#{logs.join(", ")});")
    res.each(:as => :array) { |row| 
      removeExchange([row[0], row[1]])
    }
    @db.query("delete from QSO where logID in (#{logs.join(", ")});")
    @db.query("delete from Callsign where contestID = #{contestID};")
    @db.query("delete from Log where contestID = #{contestID};")
  end

  def removeWholeContest(contestID)
    removeContestQSOs(contestID)
    removeOverrides(contestID)
    removePairs(contestID)
    @db.query("delete from Contest where contestID = #{contestID} limit 1;")
  end
end
