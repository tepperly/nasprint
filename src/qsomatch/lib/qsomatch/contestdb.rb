#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#
require 'csv'
require 'set'
require_relative 'callsign'


class ContestDatabase
  CHARS_PER_CALL = 16
  CHARS_PER_NAME = 24

  def initialize(db)
    @db = db
    @contestID = nil
    @callCache = Hash.new
    createDB
  end

  attr_writer :contestID
  attr_reader :contestID

  def readTables
    @db.tables.sort
  end

  def createDB
    tables = readTables
    if not tables.include?("Contest")
      createContestTable
    end
    if not tables.include?("Entity")
      createEntityTable
    end
    if not tables.include?("Multiplier")
      createMultiplierTable
    end
    createMultiplierAlias
    if not (tables.include?("Callsign") and tables.include?("Log"))
      createLogTable
    end
    if not (tables.include?("QSOExtra") and tables.include?("QSO"))
      createQSOTable
    end
    if not tables.include?("Overrides")
      createOverrides
    end
    if not tables.include?("Pairs")
      createPairs
    end
    if not tables.include?("Team")
      createTeamTable
    end
    if not tables.include?("TeamMember")
      createTeamMemberTable
    end
  end

  def createContestTable
    @db.query("create table if not exists Contest (id integer primary key #{@db.autoincrement}, name varchar(64) not null, year smallint not null, start datetime not null, end datetime not null);")
    @db.query("create unique index if not exists contind on Contest (name, year);")
  end

  def createTeamTable
    @db.query("create table if not exists Team (id integer primary key #{@db.autoincrement}, name varchar(64) not null, managercall varchar(#{CHARS_PER_CALL}) not null, manageremail varchar(128), registertime datetime, contestID integer not null);")
    @db.query("create unique index if not exists teamind on Team (name, contestID);")
  end

  def createTeamMemberTable
    @db.query("create table if not exists TeamMember (teamID integer not null, logID integer not null, contestID integer not null, primary key (teamID, logID));")
    @db.query("create unique index if not exists logind on TeamMember (logID, contestID);")
  end

  def extractPrefix(prefix)
    
  end

  def createEntityTable
    if @db.has_enum?
      @db.query("create table if not exists Entity (id integer primary key, name varchar(64) not null, prefix varchar(8), continent enum ('AS', 'EU', 'AF', 'OC', 'NA', 'SA', 'AN') not null);")
    else
      @db.query("create table if not exists Entity (id integer primary key, name varchar(64) not null, prefix varchar(8), continent char(2) not null);")
    end
    open(File.dirname(__FILE__) + "/entitylist.txt", "r:ascii") { |inf|
      inf.each { |line|
        if (line =~ /^\s+(\S+)\s+(.*)\s+([a-z][a-z](,[a-z][a-z])?)\s+\S+\s+\S+\s+(\d+)\s*$/i)
          begin
            @db.query("insert into Entity (id, name, continent) values (?, ?, ?);",
                      [ $5.to_i, $2.strip, $3[0,2] ])
          rescue Mysql2::Error => e
            if e.error_number != 1062 # ignore duplicate entry
              raise e
            end
          rescue SQLite3::ConstraintException => e
            
          end
        else
          "Entity line doesn't match: #{line}"
        end
      }
    }
    CSV.foreach(File.dirname(__FILE__) + "/prefixlist.txt", "r:ascii") { |row|
      begin
        @db.query("update Entity set prefix = ? where id = ? limit 1;",
                  [row[1].to_s, row[0].to_i])
      rescue Mysql2::Error => e
        if e.error_number != 1062 # ignore duplicate entry
          raise e
        end
      rescue SQLite3::ConstraintException => e
            
      end
    }
  end

  def createMultiplierTable
    @db.query("create table if not exists Multiplier (id integer primary key #{@db.autoincrement}, abbrev char(4) not null unique, wasstate char(2), entityID integer, ismultiplier bool);")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
      begin
        if row[0] == row[1]
          entity = row[2].to_i
          if entity > 0
            @db.query("insert into Multiplier (abbrev, entityID, wasstate, ismultiplier) values (?, ?, ?, #{@db.true});",
                      [row[1].strip.upcase, entity, row[3]])
          else
            # DX gets a null for entityID and ismultiplier
            @db.query("insert into Multiplier (abbrev) values (?);",
                      [row[1].strip.upcase ])
          end
        end
      rescue Mysql2::Error => e
        if e.error_number != 1062 # ignore duplicate entry
          raise e
        end
      rescue SQLite3::ConstraintException => e
            
      end
    }
  end
  
  def createMultiplierAlias
    @db.query("create table if not exists MultiplierAlias (id integer primary key #{@db.autoincrement}, abbrev varchar(32) not null unique, multiplierID integer not null, entityID integer not null);")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii") { |row|
      if row[0] != row[1]
        begin
          res = @db.query("select id, entityID from Multiplier where abbrev = ? limit 1;", [row[1].strip.upcase ])
          if row[2]
            entityID = row[2].to_i
          else
            entityID = nil
          end
          res.each { |mult|
            if (not entityID) or (entityID <= 0)
              entityID = mult[1].to_i
            end
            @db.query("insert into MultiplierAlias (abbrev, multiplierID, entityID) values (?, ?, ?);", [row[0], mult[0].to_i, entityID] )
          }
        rescue Mysql2::Error => e
          if e.error_number != 1062 # ignore duplicate
            raise e
          end
        rescue SQLite3::ConstraintException => e
            
        end
      end
    }
  end
  
  def createLogTable
    # table of callsigns converted to base format
    @db.query("create table if not exists Callsign (id integer primary key #{@db.autoincrement}, contestID integer not null, basecall varchar(#{CHARS_PER_CALL}) not null, logrecvd bool, validcall bool);")
    @db.query("create index if not exists bcind on Callsign (contestID, basecall);")
    if @db.has_enum?
      @db.query("create table if not exists Log (id integer primary key #{@db.autoincrement}, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, callID integer not null, email varchar(128), multiplierID integer not null, entityID integer default null, opclass enum('CHECKLOG', 'QRP', 'LOW', 'HIGH'), verifiedscore integer, verifiedQSOs integer, verifiedMultipliers integer, clockadj integer not null default 0, name varchar(128), club varchar(128));")
    else
      @db.query("create table if not exists Log (id integer primary key #{@db.autoincrement}, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, callID integer not null, email varchar(128), multiplierID integer not null, entityID integer default null, opclass char(7), verifiedscore integer, verifiedQSOs integer, verifiedMultipliers integer, clockadj integer not null default 0, name varchar(128), club varchar(128));")
    end
      @db.query("create index if not exists callind on Log (callsign);")
    @db.query("create index if not exists contestind on Log (contestID);")
             
  end

  def lookupMultiplierByID(mID)
    res = @db.query("select abbrev from Multiplier where id = ? limit 1;", [mID])
    res.each { |row|
      return row[0]
    }
    nil
  end

  EXCHANGE_FIELD_TYPES = { "_callID" => "integer not null" ,
    "_entityID" => "integer",
    "_multiplierID" => "integer",
    "_serial" => "integer"
  }
  EXCHANGE_EXTRA_FIELD_TYPES = {
    "_callsign" => "varchar(#{CHARS_PER_CALL})",
    "_location" => "varchar(24)"
  }

  def exchangeFields(m, prefix)
    m.keys.sort.map { |field|
      prefix + field + " " + m[field]
    }.join(", ")
  end


  def createQSOTable
    if @db.has_enum?
      @db.query("create table if not exists QSO (id integer primary key #{@db.autoincrement}, logID integer not null, frequency integer, band enum('241G','142G','119G','75G','47G','24G','10G','5.7G','3.4G','2.3G','1.2G','902','432','222','2m','6m','10m','15m','20m', '40m', '80m','160m', 'unknown') default 'unknown', fixedMode enum('PH', 'CW', 'FM', 'RY'), time datetime, " +
                exchangeFields(EXCHANGE_FIELD_TYPES, "sent") + ", " +
                exchangeFields(EXCHANGE_FIELD_TYPES, "recvd") +
                ", matchID integer, matchType enum('None','Full','Bye', 'Unique', 'Partial', 'Dupe', 'NIL', 'OutsideContest', 'Removed','TimeShiftFull', 'TimeShiftPartial') not null default 'None');")
    else
      @db.query("create table if not exists QSO (id integer primary key #{@db.autoincrement}, logID integer not null, frequency integer, band char(7) default 'unknown', fixedMode char(2), time datetime, " +
                exchangeFields(EXCHANGE_FIELD_TYPES, "sent") + ", " +
                exchangeFields(EXCHANGE_FIELD_TYPES, "recvd") +
                ", matchID integer, matchType char(17) not null default 'None');")
    end
    @db.query("create index if not exists matchind on QSO (matchType);")
    @db.query("create index if not exists bandind on QSO (band);")
    @db.query("create index if not exists logind on QSO (logID);")
    @db.query("create index if not exists timeind on QSO (time);")
    @db.query("create index if not exists modeind on QSO (fixedMode);")
    @db.query("create index if not exists sent_multind on QSO (sent_multiplierID);")
    @db.query("create index if not exists recvd_multind on QSO (recvd_multiplierID);")
    @db.query("create index if not exists sent_callind on QSO (sent_callID);")
    @db.query("create index if not exists recvd_callind on QSO (recvd_callID);")
    @db.query("create table if not exists QSOExtra (id integer primary key #{@db.autoincrement}, logID integer not null, mode char(6), transmitterNum integer, comment varchar(256), " +
              exchangeFields(EXCHANGE_EXTRA_FIELD_TYPES, "sent") + ", " +
              exchangeFields(EXCHANGE_EXTRA_FIELD_TYPES, "recvd") +
              ");")
    @db.query("create index if not exists logind on QSOExtra (logID);")
  end

  def addOrLookupCall(callsign, contestIDVar=nil)
    callsign = callsign.upcase
    if not contestIDVar
      contestIDVar = @contestID
    end
    if contestIDVar
      if contestIDVar == @contestID and @callCache.has_key?(callsign)
        return @callCache[callsign]
      end

      result = @db.query("select id from Callsign where basecall = ? and contestID = ? limit 1;", [callsign, contestIDVar.to_i])
      result.each { |row|
        if contestIDVar == @contestID
          @callCache[callsign] = row[0].to_i
        end
        return row[0].to_i
      }
      @db.query("insert into Callsign (contestID, basecall) values (?, ?);", [contestIDVar.to_i, callsign])
      return @db.last_id
    end
    nil
  end

  def findLog(callsign)
    res =  @db.query("select l.id from Log as l join Callsign as c on c.id = l.callID where l.callsign= ? or c.basecall= ? limit 1;", [callsign, callsign])
    res.each { |row| return row[0] }
    nil
  end

  def contestTime(year)
    start = Time.gm(year,10,1,16,0)
    while not start.saturday?
      start += (24 * 60 * 60) # one day in seconds
    end
    stop = start + (30 * 60 * 60) # thirty hours in seconds
    return start, stop
  end

  def addOrLookupContest(name, year, create=false)
    if name and year
      result = @db.query("select id from Contest where name=? and year = ? limit 1;", [name, year.to_i])
      result.each { |row|
        return row[0].to_i
      }
      if create
        start_time, stop_time = contestTime(year.to_i)
        @db.query("insert into Contest (name, year, start, end) values (?, ?, ?, ?);",
                  [name, year.to_i, @db.formattime(start_time),
                    @db.formattime(stop_time)])
        return @db.last_id
      end
    end
    nil
  end

  def capOrNull(str)
    str ? str.upcase : nil
  end

  def numOrNull(num)
    num ? num.to_i : nil
  end

  def markReceived(callID)
    @db.query("update Callsign set logrecvd = 1 where id = ? limit 1;", [callID.to_i])
  end

  def addLog(contID, callsign, callID, email, opclass, multID, entID, name, club)
    @db.query("insert into Log (contestID, callsign, callID, email, opclass, multiplierID, entityID, name, club) values (?, ?, ?, ?, ?, ?, ?, ?, ?);",
              [contID.to_i, capOrNull(callsign), callID.to_i, email, opclass, multID.to_i,
numOrNull(entID), name, club])

    return @db.last_id
  end

  def lookupMultiplier(str)
    res = @db.query("select id, entityID from Multiplier where abbrev = ? limit 1;", [ capOrNull(str)] )
    res.each { |row|
      return row[0].to_i, (row[1].nil? ? nil : row[1].to_i)
    }
    return nil, nil
  end

  def createOverrides
    @db.query("create table if not exists Overrides (id integer primary key #{@db.autoincrement}, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, multiplierID integer not null, entityID integer not null);")
    @db.query("create index if not exists callindex on Overrides (callsign);")
  end

  def removeOverrides(contestID)
    @db.query("delete from Overrides where contestID = ?;", [ contestID ])
  end
  
  def createPairs
    @db.query("create table if not exists Pairs (id integer primary key #{@db.autoincrement}, contestID integer not null, line1 varchar(128) not null, line2 varchar(128) not null, ismatch bool);")
    @db.query("create index if not exists contind on Pairs (contestID);")
    @db.query("create index if not exists lineind on Pairs (line1, line2);")
  end

  def removePairs(contestID)
    @db.query("delete from Pairs where contestID = ?;", [ contestID ])
  end

  def dateOrNull(date)
    if date
      return @db.formattime(date)
    else
      nil
    end
  end

  def translateExchange(exch, contestID)
    basecall = callBase(exch.callsign)
    bcID = addOrLookupCall(basecall, contestID)
    multID, entityID = lookupMultiplier(exch.qth)
    return bcID, multID, entityID
  end

  def insertQSO(contestID, logID, frequency, band, roughMode, mode, datetime,
                sentExchange, recvdExchange, transNum)
    recvdCallID, recvdMultID, recvdEntityID = translateExchange(recvdExchange, contestID)
    sentCallID, sentMultID, sentEntityID = translateExchange(sentExchange, contestID)
    @db.query("insert into QSO (logID, frequency, band, fixedMode, time, " +
              (EXCHANGE_FIELD_TYPES.keys.sort.map { |f| "sent" + f }.join(", ")) + ", " +
              (EXCHANGE_FIELD_TYPES.keys.sort.map { |f| "recvd" + f}.join(", ")) +
              ") values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
              [ numOrNull(logID), band, mode, dateOrNull(datetime),
                numOrNull(sentCallID), numOrNull(sentEntityID), numOrNull(sentMultID),
                numOrNull(sentExchange.serial),
                numOrNull(recvdCallID), numOrNull(recvdEntityID), numOrNull(recvdMultID),
                numOrNull(recvdExchange.serial) ])
    qsoID = @db.last_id
    @db.query("insert into QSOExtra (id, logID, mode, " +
              (EXCHANGE_EXTRA_FIELD_TYPES.keys.sort.map { |f| "sent" + f }.join(", ")) + ", " +
              (EXCHANGE_EXTRA_FIELD_TYPES.keys.sort.map { |f| "recvd" + f}.join(", ")) +
              ", transmitterNum) values (?, ?, ?, ?, ?, ?, ?, ?);",
              [ numOrNull(qsoID), numOrNull(logID), capOrNull(roughMode),
                sentExchange.callsign, sentExchange.origqth,
                recvdExchange.callsign, recvdExchange.origqth,
                numOrNull(transNum) ])
  end

  def removeContestQSOs(contestID)
    logs = logsForContest(contestID)
    if not logs.empty?
      @db.query("delete from QSO where logID in (?);", [logs])
      @db.query("delete from QSOExtra where logID in (?));", [logs])
    end
    clearTeams(contestID)
    @db.query("delete from Callsign where contestID = ?;" [ contestID ])
    @db.query("delete from Log where contestID = ?;", [ contestID ])
  end

  def removeWholeContest(contestID)
    removeContestQSOs(contestID)
    removeOverrides(contestID)
    removePairs(contestID)
    @db.query("delete from Contest where contestID = ? limit 1;", [contestID])
  end

  def logsForContest(contestID)
    logs = Array.new
    res = @db.query("select id from Log where contestID = ? order by id asc;", [contestID])
    res.each { |row|
      logs << row[0].to_i
    }
    logs
  end

  def logsByMultipliers(contestID, multipliers)
    logs = Array.new
    if (not multipliers.is_a?(String)) and multipliers.empty?
      return logs
    end
    res = @db.query("select l.id from Log as l join Multiplier as m on l.multiplierID = m.id where l.contestID = #{contestID} and m.abbrev in (?) order by l.verifiedscore desc, l.verifiedMultipliers desc, l.callsign asc;", [multipliers])
    res.each { |row|
      logs << row[0].to_i
    }
    return logs
  end

  def logsByContinent(contestID, continent)
    result = Array.new
    res = @db.query("select id from Multiplier where abbrev='DX' limit 1;")
    multID = nil
    res.each { |row|
      multID = row[0].to_i
    }
    if multID
      res = @db.query("select l.id from Log as l join Entity as e on e.id = l.entityID where l.contestID = ? and l.multiplierID = ? and e.continent = ? order by l.verifiedscore desc, l.verifiedMultipliers desc, l.callsign asc;", [contestID, multID, continent])
      res.each {  |row|
        result << row[0].to_i
      }
    end
    result
  end

  def numBandChanges(logID)
    count = 0
    prev = nil
    res = @db.query("select q.band from QSO as q where q.logID = #{logID.to_i} order by q.time asc, q.sent_serial asc, q.id asc;", [logID.to_i])
    res.each { |row|
      if row[0].to_s != prev
        count = count + 1
        prev = row[0].to_s
      end
    }
    return (count > 0) ? (count - 1) : 0
  end

  def qsosByBand(logID)
    res = @db.query("select band, matchType, count(*) from QSO where logID = ? and matchType in ('Full', 'Bye', 'NIL') group by band, matchType order by band asc, matchType asc;", [logID])
    results = Hash.new(0)
    res.each { |row|
      case row[1]
      when 'Full', 'Bye'
        results[row[0]] = results[row[0]] + row[2].to_i
      when 'NIL'
        results[row[0]] = results[row[0]] - row[2].to_i
      end
    }
    return results
  end

  def qsosByHour(logID)
    results = Array.new
    cres = @db.query("select c.start, c.end from Contest as c join Log as l on l.contestID = c.id and l.id = ? limit 1;", [logID])
    cres.each { |crow|
      tstart = crow[0]
      tend = crow[1]
      prev = tstart - 24*60*60
      numHours = (tend - tstart).to_i/3600
      results = Array.new(numHours, 0)
      numHours.times {  |i|
        queryStr = "select matchType, count(*) from QSO where logID = ? and matchType in ('Full', 'Bye', 'NIL') and time between ? and ? order by matchType asc;"
        res = @db.query(queryStr, [logID, @db.formattime(prev),
                          @db.formattime(tstart+3600*(i+1)-1)])
        res.each { |row|
          case row[0]
          when 'Full', 'Bye'
            results[i] = results[i] + row[1].to_i
          when 'NIL'
            results[i] = results[i] - row[1].to_i
          end
        }
        prev = tstart + 3600*(i+1)
      }
    }
    return results
  end
  
  def firstName(str)
    if str
      match = /^(\S+)\b/.match(str)
      if match
        return match[1].upcase
      end
      return str.upcase
    end
    return ""
  end

  def logMultipliers(logID)
    multipliers = Set.new
    res = @db.query("select distinct m.abbrev from QSO as q join Multiplier as m on m.id = q.recvd_multiplierID where q.logID = ? and q.matchType in ('Full', 'Bye') and m.abbrev != 'DX';",
                    [logID])
    res.each { |row|
      multipliers.add(row[0])
    }
    res = @db.query("select distinct en.name from (QSO as q join Multiplier as m on m.id = q.recvd_multiplierID and m.abbrev='DX') join Entity as en on en.id = q.recvd_entityID where q.logID = ? and q.matchType in ('Full', 'Bye') and en.continent = 'NA';", [logID])
    res.each { |row|
      multipliers.add(row[0])
    }
    multipliers
  end

  def lookupTeam(contestID, logID)
    @db.query("select t.name from TeamMember as m join Team as t on t.id = m.teamID where m.contestID = #{contestID} and m.logID = ? limit 1;", [logID]).each { |row|
      return row[0]
    }

    nil
  end

  def numStates(logID)
    res = @db.query("select count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = ? and matchType in ('Full', 'Bye') join Multiplier as m on m.id = q.recvd_multiplierID where l.id = ? group by l.id order by numstates desc, l.callsign asc limit 1;", [logID, logID])
    res.each { |row|
      return row[0]
    }
    0
  end

  def baseCall(callID)
    res = @db.query("select basecall from Callsign where id = ? limit 1;", [callID])
    res.each { |row|
      return row[0]
    }
    nil
  end

  def logCallsign(logID)
    res = @db.query("select callsign from Log where id = ? limit 1;", [logID])
    res.each { |row|
      return row[0]
    }
    nil
  end
  
  def logInfo(logID)
    res = @db.query("select l.callsign, l.name, m.abbrev, e.prefix, l.verifiedqsos, l.verifiedMultipliers, l.verifiedscore, l.opclass, l.contestID from Log as l left join Multiplier as m on m.id = l.multiplierID left join Entity as e on e.id = l.entityID where l.id = ? limit 1;",
                    [ logID ])
    res.each {|row|
      name = firstName(row[1])
      return row[0], name, row[2], row[3], lookupTeam(row[8], logID), row[4], row[5], row[6], row[7], numStates(logID)
    }
    return nil
  end

  def lostQSOs(logID)
    res = @db.query("select sum(matchType in ('None','Unique','Partial','Dupe','OutsideContest','Removed')) as numremoved, sum(matchType = 'NIL') as numnil from QSO where logID = ? group by logID;",
                    [logID ] )
    res.each { |row|
      return row[0] + 2*row[1]
    }
  end

  def topNumStates(contestID, num)
    logs = Array.new
    res = @db.query("select l.id, l.callsign, count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = l.id and l.contestID = ? and matchType in ('Full', 'Bye') join Multiplier as m on m.id = q.recvd_multiplierID group by l.id order by numstates desc, l.callsign asc limit ?, 1;", [ contestID, num-1 ])
    limit = nil
    res.each { |row|
      limit = row[2]
    }
    res = @db.query("select l.id, l.callsign, count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = l.id and l.contestID = ? and matchType in ('Full', 'Bye') join Multiplier as m on m.id = q.recvd_multiplierID group by l.id  having numstates >= ? order by numstates desc, l.callsign asc;", [contestID, limit])
    res.each { |row|
      logs << [ row[1], row[2] ]
    }
    logs
  end

  # In the case of ties, this can return more than num
  def topLogs(contestID, num, opclass=nil, criteria="l.verifiedscore")
    logs = Array.new
    if opclass
      res =@db.query("select l.id, l.callsign, #{criteria} as reportcriteria from Log as l where l.contestID = ? and l.opclass = ? order by reportcriteria desc, l.callsign asc limit ?, 1;",
                [contestID, opclass, (num -1)])
    else
      res =@db.query("select l.id, l.callsign, #{criteria} as reportcriteria from Log as l where l.contestID = ? order by reportcriteria desc, l.callsign asc limit ?, 1;",
                [contestID, (num -1)])
    end
    # get score of last item on list
    limit = nil
    res.each { |row|
      limit = row[2]
    }
    if limit
      res = @db.query("select l.id, l.callsign, #{criteria} as reportcriteria from Log as l where l.contestID = ? and #{criteria} >= ? " +
      (opclass ? "and l.opclass = \"#{opclass}\" " : "") +
      "order by reportcriteria desc, l.callsign asc;", [ contestID, limit ])
    else
      res = @db.query("select l.id, l.callsign, l.#{criteria} from Log as l where l.contestID = ? " +
      (opclass ? "and l.opclass = \"#{opclass}\" " : "") +
                      "order by l.#{criteria} desc, l.callsign asc limit ?;",
                      [contestID, num ])
    end
    res.each { |row|
      logs << [ row[1], row[2], numBandChanges(row[0]), lostQSOs(row[0]), qsosByHour(row[0])]
    }
    logs
  end

  def clearTeams(cid)
    @db.query("delete from TeamMember where contestID = ?;", [cid])
    @db.query("delete from Team where contestID = ?;", [cid])
  end

  def addTeam(name, managercall, manageremail, registertime, contestID)
    @db.query("insert into Team (name, managercall, manageremail, registertime, contestID) values (?, ?, ?, ?, ?);",
              [name, managercall, manageremail, dateOrNull(registertime), contestID.to_i])
    return @db.last_id
  end

  def addTeamMember(cid, teamID, logID)
    @db.query("insert into TeamMember (teamID, logID, contestID) values (?, ?, ?);",
              [teamID.to_i, logID.to_i cid.to_i])
  end

  def reportTeams(cid)
    teams = Array.new
    res = @db.query("select t.id, t.name, sum(l.verifiedscore) as score, count(l.id) as nummembers from (Team as t join Log as l) join TeamMember as tm on tm.teamID = t.id and tm.logID = l.id where l.contestID = ? and t.contestID = ? and tm.contestID = ? group by t.id order by score desc;", [cid, cid, cid])
    res.each { |row|
      memlist = Array.new
      members = @db.query("select l.callsign, l.verifiedscore from Log as l join TeamMember as tm on l.id = tm.logID and tm.teamID = ? order by l.verifiedscore desc, l.callsign desc;",
                          [row[0].to_i])
      members.each { |mrow|
        memlist << { "callsign" => mrow[0], "score" => mrow[1] }
      }
      teams << { "name" => row[1], "score" => row[2], "nummembers" => row[3], "members" => memlist  }
    }
    teams
  end
  
  def dupeQSOs(logID)
    dupes = Array.new
    res = @db.query("select q.sent_serial, qe.recvd_callsign from QSO as q join QSOExtra as qe on q.id = qe.id where q.logID = ? and q.matchType = 'Dupe' order by q.sent_serial asc;",
                    [logID])
    res.each { |row|
      dupes << { 'num' => row[0].to_i, 'callsign' => row[1].to_s }
    }
    dupes
  end

  def goldenLogs(contestID)
    golden = Array.new
    res = @db.query("select l.id, l.callsign, l.verifiedQSOs, sum(q.matchType in ('Unique','Partial','NIL','OutsideContest','Removed')) as nongolden from Log as l join QSO as q on l.id = q.logID where l.contestID = ? group by l.id having nongolden = 0 order by l.verifiedQSOs desc, l.callsign asc;", [contestID])
    res.each { |row|
      golden << { "callsign" => row[1], "numQSOs" => row[2] }
    }
    golden
  end

  def scoreSummary(logID)
    res = @db.query("select count(*) as rawQSOs, sum(matchType='Dupe') as dupeQSOs, sum(matchType in ('Unique','Partial','Removed')) as bustedQSOs, sum(matchType = 'NIL') as penaltyQSOs, sum(matchType = 'OutsideContest') as outside from QSO where logID = ? group by logID;", [logID])
    res.each { |row|
      return row[0], row[1], row[2], row[3], row[4]
    }
    nil
  end

  def logEntity(logID)
    res = @db.query("select e.name from Entity as e join Log as l on e.id = l.entityID where l.id = ? limit 1;", [logID])
    res.each {  |row|
      return row[0]
    }
    nil
  end

  def logClockAdj(logID)
    res = @db.query("select clockadj from Log where id = ? limit 1;", [logID])
    res.each {  |row|
      return row[0]
    }
    0
  end
  
  def qsosOutOfContest(logID)
    logs = Array.new
    res = @db.query("select q.time, q.sent_serial from QSO as q join where q.logID = ? and matchType = 'OutsideContest' order by q.sent_serial asc;", [logID])
    res.each { |row|
      logs << { 'time' => row[0], 'number' => row[1] }
    }
    logs
  end
end
