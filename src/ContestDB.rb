#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Build a SQL database to do log crossing checking & scoring
#
require 'csv'
require 'set'
require_relative 'cabrillo'


class ContestDatabase
  CHARS_PER_CALL = 16
  ALLOWED_BANDS = %w{ 10m 15m 20m 40m }.to_set.freeze

  def initialize(db)
    @db = db
    @contestID = nil
    createDB
  end

  attr_writer :contestID
  attr_reader :contestID

  def readTables
    result = Set.new
    @db.execute("select name from sqlite_master where type='table';") { |row|
      if not row[0].start_with?("sqlite_")
        result << row[0]
      end
    }
    result
  end

  def createDB
    tables = readTables
    if not tables.include?("Contest")
      createContestTable
    end
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
    if not tables.include?("Team")
      createTeamTable
    end
    if not tables.include?("TeamMember")
      createTeamMemberTable
    end
  end

  def createContestTable
    @db.execute("create table if not exists Contest (id integer primary key autoincrement, name varchar(64) not null, year smallint not null, start datetime not null, end datetime not null);") { }
    @db.execute("create unique index if not exists contind on Contest (name, year);") {}
  end

  def createTeamTable
    @db.execute("create table if not exists Team (id integer primary key autoincrement, name varchar(64) not null, managercall varchar(#{CHARS_PER_CALL}) not null, manageremail varchar(128), registertime datetime, contestID integer not null);") { }
    @db.execute("create unique index if not exists teamind on Team (name, contestID);") { }
  end

  def createTeamMemberTable
    @db.execute("create table if not exists TeamMember (teamID integer not null, logID integer not null, contestID integer not null, primary key (teamID, logID));") { }
    @db.execute("create unique index if not exists logind on TeamMember (logID, contestID);") { }
  end

  def extractPrefix(prefix)
    
  end

  def toxicStatistics(contestID)
    results = Array.new
    res = @db.execute("select l.callsign, l.callID, count(*) from Log as l, QSO as q where q.logID = l.id and contestID = #{contestID.to_i} group by l.id order by l.callsign asc;")  { |row|
      item = Array.new(8)
      item[0] = row[0]
      item[1] = row[1].to_i
      item[2] = row[2].to_i
      results << item
    }
    results.each { |item|
      @db.execute("select count(*), sum(q.matchType in ('Full')), sum(q.matchType = 'Partial'), sum(q.matchType = 'NIL'), sum(q.matchType = 'Removed') from QSO as q join Exchange as e on q.recvdID = e.id where e.callID = #{item[1]} group by e.callID limit 1;") { |row|
        row.each_index { |i|
          item[3+i] = row[i].to_i
        }
      }
    }
    results
  end

  def createMultiplierTable
    @db.execute("create table if not exists Multiplier (id integer primary key autoincrement, flid integer default null, abbrev char(5) not null unique, fullname char(32) not null, entityID integer, floridamultiplier bool not null, othermultiplier bool not null, multtype char(2) check (multtype in ('FL','CA','US','DX')) not null, continent char(2) check(continent in ('AF','AN','AS','EU', 'MM', 'NA','OC', 'SA')) );")
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii", :skip_lines => /^#/) { |row|
      f = row.map { |x| x.strip.upcase }
      begin
        @db.execute("insert into Multiplier (abbrev, fullname, entityID, floridamultiplier, othermultiplier, multtype, continent) values (?,?,?,?,?,?,?);",
                    [ f[0], f[1], f[3].to_i, (f[4]=="TRUE") ? 1 : 0, (f[5]=="TRUE") ? 1 : 0, f[6], f[7] ]) { }
        if (f[0] == f[2])
          id = @db.last_insert_row_id
          @db.execute("update Multiplier set flid = ? where id = ? and flid is null limit 1;", [id, id]) { }
        end
      # rescue Mysql2::Error => e
      #   if e.error_number != 1062 # ignore duplicate entry
      #     raise e
      #   end
      end
    }
    CSV.foreach(File.dirname(__FILE__) + "/multipliers.csv", "r:ascii", :skip_lines => /^#/) { |row|
      f = row.map { |x| x.strip.upcase }
      if (f[0] != f[2]) 
        multiID=nil
        equivID=nil
        @db.execute("select id from Multiplier where abbrev=? limit 1;", [f[0]]) { |drow|
          multiID = drow[0].to_i
        }
        @db.execute("select id from Multiplier where abbrev=? limit 1;", [f[2]]) { |drow|
          equivID = drow[0].to_i
        }
        if multiID and equivID
          @db.execute("update Multiplier set flid = ? where id = ? and flid is null limit 1;", [ equivID, multiID] ) { }
        end
      end
    }
  end
  
  def createMultiplierAlias
    @db.execute("create table if not exists MultiplierAlias (id integer primary key autoincrement, abbrev varchar(32) not null unique, multiplierID integer not null);") {}
    CSV.foreach(File.dirname(__FILE__) + "/multiplier_aliases.csv", "r:ascii", headers: :first_row) { |row|
      alreadyDefined = false
      @db.execute("select id from MultiplierAlias where abbrev=? limit 1;", [row[0]]) { |dbrow|
        alreadyDefined = true
      }
      if not alreadyDefined
        @db.execute("select id from Multiplier where abbrev=? limit 1;", [ row[1].upcase ]) { |dbrow|
          @db.execute("insert into MultiplierAlias (abbrev, multiplierID) values (?, ?);", [ row[0], dbrow[0].to_i] ) { }
        }
      end
    }
  end
  
  def createLogTable
    # table of callsigns converted to base format
    @db.execute("create table if not exists Callsign (id integer primary key autoincrement, contestID integer not null, basecall varchar(#{CHARS_PER_CALL}) not null, logrecvd bool, validcall bool);") {}
    @db.execute("create index if not exists bcind on Callsign (contestID, basecall);") { }
    @db.execute("create table if not exists Log (id integer primary key autoincrement, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, callID integer not null, email varchar(128), multiplierID integer not null, entityID integer default null, powclass char(4) check(powclass in ('QRP', 'LOW', 'HIGH')) not null default 'HIGH', opclass char(3) check(opclass in ('CHK', 'SO', 'SOA', 'MS', 'MM')), mobile bool not null default 0, expedition bool not null default 0, school bool not null default 0, modclass char(5) check(modclass in ('PH','CW','MIXED')), verifiedscore integer, verifiedPHQSOs integer, verifiedCWQSOs integer, verifiedMultipliers integer, clockadj integer not null default 0, name varchar(128), club varchar(128));") { }
    @db.execute("create index if not exists callind on Log (callsign);") { }
    @db.execute("create index if not exists contestind on Log (contestID); ") { }
    @db.execute("create index if not exists clubind on Log (club); ") { }
  end

  def createQSOTable
    @db.execute("create table if not exists Exchange (id integer primary key autoincrement, callsign varchar(#{CHARS_PER_CALL}), callID integer, signalreport integer, location varchar(8), multiplierID integer);") { }
    @db.execute("create index if not exists calltxtind on Exchange (callsign);" ) { }
    @db.execute("create index if not exists callidind on Exchange (callID);" ) { }
    @db.execute("create index if not exists locind on Exchange (location);" ) { }
    @db.execute("create index if not exists multind on Exchange (multiplierID);") { }
    @db.execute("create table if not exists QSO (id integer primary key autoincrement, logID integer not null, frequency integer, band char(7) check(band in ('10m', '15m', '20m', '40m', 'unknown')) not null default 'unknown', mode char(6), fixedMode char(2) check(fixedMode in ('PH', 'CW')), time datetime, sentID integer not null, recvdID integer not null, transmitterNum integer, matchID integer, matchType char(16) check(matchType in ('None','Full','Bye', 'Unique', 'Partial', 'Dupe', 'NIL', 'OutsideContest', 'Removed','TimeShiftFull', 'TimeShiftPartial')) not null default 'None', comment varchar(256));")
    @db.execute("create index if not exists matchind on QSO (matchType);") {  }
    @db.execute("create index if not exists bandind on QSO (band);") { }
    @db.execute("create index if not exists logind on QSO (logID);") { }
    @db.execute("create index if not exists timeind on QSO (time);") { }
  end

  def addOrLookupCall(callsign, contestIDVar=nil)
    callsign = callsign.upcase.strip
    if not contestIDVar
      contestIDVar = @contestID
    end
    if contestIDVar
      result = @db.execute("select id from Callsign where basecall=? and contestID = ? limit 1;",
                           [callsign, contestIDVar.to_i]) { |row|
        return row[0].to_i
      }
      @db.execute("insert into Callsign (contestID, basecall) values (?, ?);", [contestIDVar.to_i, callsign]) { }
      return @db.last_insert_row_id
    end
    nil
  end

  def findLog(callsign)
    res = nil
    if @contestID
       @db.execute("select l.id from Log as l join Callsign as c on c.id = l.callID where ((l.callsign=? or c.basecall=?) and l.contestID = ? limit 1;", [callsign, callsign, @contestID ]) { |row| return row[0].to_i }
    else
      print "No contest ID\n"
      @db.execute("select l.id from Log as l join Callsign as c on c.id = l.callID where (l.callsign=? or c.basecall=?  limit 1;",
                  [callsign, callsign]){ |row| return row[0].to_i }
    end
    nil
  end

  def addOrLookupContest(name, year, create=false)
    if name and year
      @db.execute("select id from Contest where name = ? and year = ? limit 1;", [name, year]) { |row|
        @contestID = row[0].to_i
        return @contestID
      }
      if create
        @db.execute("insert into Contest (name, year, start, end) values (?,?,?,?);",
                    [name, year.to_i, CONTEST_START.iso8601, CONTEST_END.iso8601]) { }
        @contestID = @db.last_insert_row_id
        return @contestID
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
    @db.execute("update Callsign set logrecvd = 1 where id = ? limit 1;", [callID.to_i]) { }
  end

  #  def addLog(contID, callsign, callID, email, opclass, multID, entID, name, club)
  def addLog(contID, callsign, callID, email, multiplierID, entityID, powclass, opclass, mobile, expedition, school, modclass, name, club)
    @db.execute("insert into Log (contestID , callsign,  callID, email, multiplierID, entityID, powclass, opclass, mobile, expedition, school, modclass, name, club) values (?,?,?,?,?,?,?,?,?,?,?,?,?,?);",
                [contID, callsign, callID, email, multiplierID, entityID, powclass, opclass, mobile, expedition, school, modclass, name, club]) { }
    return @db.last_insert_row_id
  end

  def lookupMultiplier(str)
    @db.execute("select id, entityID from Multiplier where abbrev = ? limit 1;", [ str] ) { |row|
      return row[0].to_i, (row[1].nil? ? nil : row[1].to_i)
    }
    return nil, nil
  end

  def createOverrides
    @db.execute("create table if not exists Overrides (id integer primary key autoincrement, contestID integer not null, callsign varchar(#{CHARS_PER_CALL}) not null, multiplierID integer not null, entityID integer not null);") { }
    @db.execute("create index if not exists callindex on Overrides (callsign);") { }
  end

  def removeOverrides(contestID)
    @db.execute("delete from Overrides where contestID = ?;", [contestID]) { }
  end

  def addOverride(contestID,
                  callsign,
                  multiplierID,
                  entityID)
    if contestID and callsign and multiplierID and entityID then
      @db.execute("insert into Overrides (contestID, callsign, multiplierID, entityID) values (?,?,?,?);",
                  [ contestID, callsign.upcase, multiplierID.to_i, entityID.to_i]) { }
    end 
  end
  
  def createPairs
    @db.execute("create table if not exists Pairs (id integer primary key autoincrement, contestID integer not null, line1 varchar(128) not null, line2 varchar(128) not null, ismatch bool);")
    @db.execute("create index if not exists contind on Pairs (contestID);" ) { }
    @db.execute("create index if not exists lineind on Pairs (line1, line2);") { }
  end

  def removePairs(contestID)
    @db.execute("delete from Pairs where contestID = ?};", [contestID])
  end

  def removeExchange(id)
    if id.respond_to?('join')
      @db.execute("delete from Exchange where id in (#{id.join(", ")}) limit #{id.size};") { }
    else
      @db.execute("delete from Exchange where id = ? limit 1;", [id.to_i]) { }
    end
  end

  def addExchange(callsign, callID, signalreport, location, multiplierID)
    @db.exchange("insert into Exchange (callsign, callID, signalreport, location, multiplierID) values (?, ?, ?, ?, ?);",
                 [callsign, callID.to_i, signalreport.to_i, location, multiplierID]) { }
    return @db.last_insert_row_id
  end

  def dateOrNull(date)
    if date
      return date.iso8601
    else
      nil
    end
  end

  def insertQSO(logID, frequency, band, roughMode, mode, datetime,
                sentID, recvdID, transNum)
    if not ALLOWED_BANDS.include?(band)
      band = "unknown"
    end
    @db.execute("insert into QSO (logID, frequency, band, mode, fixedMode, time, sentID, recvdID, transmitterNum) values (?,?,?,?,?,?,?,?,?);",
                [logID.to_i, frequency, band, roughMode, mode, dateOrNull(datetime), sentID.to_i, recvdID.to_i, transNum] ){ }
  end

  def removeContestQSOs(contestID)
    logs = logsForContest(contestID)
    if not logs.empty?
      @db.execute("select recvdID, sentID from QSO where logID in (#{logs.join(", ")});") { |row|
        removeExchange([row[0], row[1]])
      }
      @db.execute("delete from QSO where logID in (#{logs.join(", ")});") { }
    end
    clearTeams(contestID)
    @db.execute("delete from Callsign where contestID = ?;", [ contestID] ) { }
    @db.execute("delete from Log where contestID = ?;", [ contestID] ) { }
  end

  def removeWholeContest(contestID)
    removeContestQSOs(contestID)
    removeOverrides(contestID)
    removePairs(contestID)
    @db.execute("delete from Contest where contestID = ? limit 1;", [ contestID] )
  end

  def logsForContest(contestID)
    logs = Array.new
    @db.execute("select id from Log where contestID = ? order by id asc;", [contestID]) { |row|
      logs << row[0].to_i
    }
    logs
  end

  def logsByMultipliers(contestID, multipliers)
    logs = Array.new
    if multipliers.is_a?(String)
      multiplierConstraints = " = \"#{SQLite3::Database::quote(multipliers)}\""
    else
      if multipliers.empty?
        return logs
      else
        multiplierConstraints = " in (#{multipliers.map { |x| "\"" + SQLite3::Database::quote(x.to_s) + "\"" }.join(", ")})"
      end
    end
    @db.execute("select l.id from Log as l join Multiplier as m on l.multiplierID = m.id where l.contestID = #{contestID} and m.abbrev #{multiplierConstraints} order by l.verifiedscore desc, l.verifiedMultipliers desc, l.callsign asc;") { |row|
     logs << row[0].to_i
    }
    return logs
  end
 
  def logsByContinent(contestID, continent)
    logs = Array.new
    @db.execute("select l.id from Log as l join Multiplier as m on l.multiplierID = m.id where l.contestID = ? and m.continent = ? order by l.verifiedscore desc, l.verifiedMultipliers desc, l.callsign asc;") { |row|
      logs << row[0].to_i
    }
    logs
  end

  def numBandChanges(logID)
    count = 0
    prev = nil
    @db.execute("select q.band from QSO as q where q.logID = ? order by q.time asc, q.id asc;",
                [ logID.to_i ]){ |row|
      if row[0].to_s != prev
        count = count + 1
        prev = row[0].to_s
      end
    }
    return (count > 0) ? (count - 1) : 0
  end

  def qsosByBand(logID)
    res = @db.query("select band, matchType, count(*) from QSO where logID = #{logID} and matchType in ('Full', 'Bye','Unique', 'NIL') group by band, matchType order by band asc, matchType asc;")
    results = Hash.new(0)
    res.each(:as => :array) { |row|
      case row[1]
      when 'Full', 'Bye', 'Unique'
        results[row[0]] = results[row[0]] + row[2].to_i
      when 'NIL'
        results[row[0]] = results[row[0]] - row[2].to_i
      end
    }
    return results
  end

  def qsosByHour(logID)
    results = Array.new
    cres = @db.query("select c.start, c.end from Contest as c join Log as l on l.contestID = c.id and l.id = #{logID} limit 1;")
    cres.each(:as => :array) { |crow|
      tstart = crow[0]
      tend = crow[1]
      prev = tstart - 24*60*60
      numHours = (tend - tstart).to_i/3600
      results = Array.new(numHours, 0)
      numHours.times {  |i|
        queryStr = "select matchType, count(*) from QSO where logID = #{logID} and matchType in ('Full', 'Bye', 'NIL', 'Unique') and time between #{dateOrNull(prev)} and #{dateOrNull(tstart + 3600*(i+1) - 1)} group by matchType order by matchType asc;"
        res = @db.query(queryStr)
        res.each(:as => :array) { |row|
          case row[0]
          when 'Full', 'Bye', 'Unique'
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
    res = @db.query("select distinct m.abbrev from QSO as q join Exchange as e on e.id = q.recvdID join Multiplier as m on m.id = e.multiplierID where q.logID = #{logID} and q.matchType in ('Full', 'Bye', 'Unique') and m.abbrev != 'DX';")
    res.each(:as => :array) { |row|
      multipliers.add(row[0])
    }
    res = @db.query("select distinct en.name from (QSO as q join Exchange as e on e.id = q.recvdID join Multiplier as m on m.id = e.multiplierID and m.abbrev='DX') join Entity as en on en.id = e.entityID where q.logID = #{logID} and q.matchType in ('Full', 'Bye', 'Unique') and en.continent = 'NA';")
    res.each(:as => :array) { |row|
      multipliers.add(row[0])
    }
    multipliers
  end

  def lookupTeam(contestID, logID)
    @db.query("select t.name from TeamMember as m join Team as t on t.id = m.teamID where m.contestID = #{contestID} and m.logID = #{logID} limit 1;").each(:as => :array) { |row|
      return row[0]
    }

    nil
  end

  def sentName(logID)
    namequery = @db.query("select e.name from Exchange as e join QSO as q on q.sentID = e.id where q.logID = #{logID} order by q.id asc limit 1;")
    namequery.each(:as => :array) { |nrow|
      if nrow[0] and nrow[0].length > 0
        return nrow[0].strip.upcase
      end
    }
    nil
  end
  
  def numStates(logID)
    res = @db.query("select count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = #{logID} and matchType in ('Full', 'Bye', 'Unique') join Exchange as e on q.recvdID = e.id join Multiplier as m on m.id = e.multiplierID where l.id = #{logID} group by l.id order by numstates desc, l.callsign asc limit 1;")
    res.each(:as => :array) { |row|
      return row[0]
    }
    0
  end

  def logCallsign(logID)
    res = @db.query("select callsign from Log where id = #{logID} limit 1;")
    res.each(:as => :array) { |row|
      return row[0]
    }
    nil
  end
  
  def logInfo(logID)
    res = @db.query("select l.callsign, l.name, m.abbrev, e.prefix, l.verifiedqsos, l.verifiedMultipliers, l.verifiedscore, l.opclass, l.contestID from Log as l left join Multiplier as m on m.id = l.multiplierID left join Entity as e on e.id = l.entityID where l.id = #{logID} limit 1;")
    res.each(:as => :array) {|row|
      name = firstName(row[1])
      sentname = sentName(logID)
      if sentname
        name = sentname
      end
      return row[0], name, row[2], row[3], lookupTeam(row[8], logID), row[4], row[5], row[6], row[7], numStates(logID)
    }
    return nil
  end

  def lostQSOs(logID)
    res = @db.query("select sum(matchType in ('None','Partial','Dupe','OutsideContest','Removed')) as numremoved, sum(matchType = 'NIL') as numnil from QSO where logID = #{logID} group by logID;")
    res.each(:as => :array) { |row|
      return row[0] + 2*row[1]
    }
  end

  def topNumStates(contestID, num)
    logs = Array.new
    res = @db.query("select l.id, l.callsign, count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = l.id and l.contestID = #{contestID} and matchType in ('Full', 'Bye', 'Unique') join Exchange as e on q.recvdID = e.id join Multiplier as m on m.id = e.multiplierID group by l.id order by numstates desc, l.callsign asc limit #{num-1}, 1;")
    limit = nil
    res.each(:as => :array) { |row|
      limit = row[2]
    }
    res = @db.query("select l.id, l.callsign, count(distinct m.wasstate) as numstates from Log as l join QSO as q on q.logID = l.id and l.contestID = #{contestID} and matchType in ('Full', 'Bye', 'Unique') join Exchange as e on q.recvdID = e.id join Multiplier as m on m.id = e.multiplierID group by l.id  having numstates >= #{limit} order by numstates desc, l.callsign asc;")
    res.each(:as => :array) { |row|
      logs << [ row[1], row[2] ]
    }
    logs
  end

  # In the case of ties, this can return more than num
  def topLogs(contestID, num, opclass=nil, criteria="l.verifiedscore")
    logs = Array.new
    basicQuery = "select l.id, l.callsign, #{criteria} as reportcriteria from Log as l where l.contestID = #{contestID} " +
      (opclass ? "and l.opclass = \"#{opclass}\" " : "") +
      "order by reportcriteria desc, l.callsign asc limit #{num-1}, 1;"
    # get score of last item on list
    res = @db.query(basicQuery)
    limit = nil
    res.each(:as => :array) { |row|
      limit = row[2]
    }
    if limit
      res = @db.query("select l.id, l.callsign, #{criteria} as reportcriteria from Log as l where l.contestID = #{contestID} and #{criteria} >= #{limit} " +
      (opclass ? "and l.opclass = \"#{opclass}\" " : "") +
      "order by reportcriteria desc, l.callsign asc;")
    else
      res = @db.query("select l.id, l.callsign, l.#{criteria} from Log as l where l.contestID = #{contestID} " +
      (opclass ? "and l.opclass = \"#{opclass}\" " : "") +
                      "order by l.#{criteria} desc, l.callsign asc limit #{num};")
    end
    res.each(:as => :array) { |row|
      logs << [ row[1], row[2], numBandChanges(row[0]), lostQSOs(row[0]), qsosByHour(row[0])]
    }
    logs
  end

  def clearTeams(cid)
    @db.query("delete from TeamMember where contestID = #{cid};")
    @db.query("delete from Team where contestID = #{cid};")
  end

  def addTeam(name, managercall, manageremail, registertime, contestID)
    @db.query("insert into Team (name, managercall, manageremail, registertime, contestID) values (\"#{@db.escape(name)}\", \"#{@db.escape(managercall)}\", #{strOrNull(manageremail)}, #{dateOrNull(registertime)}, #{contestID.to_i});")
    return @db.last_insert_row_id
  end

  def addTeamMember(cid, teamID, logID)
    @db.query("insert into TeamMember (teamID, logID, contestID) values (#{teamID.to_i}, #{logID.to_i}, #{cid.to_i});")
  end

  def reportTeams(cid)
    teams = Array.new
    res = @db.query("select t.id, t.name, sum(l.verifiedscore) as score, count(l.id) as nummembers from (Team as t join Log as l) join TeamMember as tm on tm.teamID = t.id and tm.logID = l.id where l.contestID = #{cid} and t.contestID = #{cid} and tm.contestID = #{cid} and l.contestID = #{cid} group by t.id order by score desc;")
    res.each(:as => :array) { |row|
      memlist = Array.new
      members = @db.query("select l.callsign, l.verifiedscore from Log as l join TeamMember as tm on l.id = tm.logID and tm.teamID = #{row[0]} and l.contestID=#{cid} order by l.verifiedscore desc, l.callsign desc;")
      members.each(:as => :array) { |mrow|
        memlist << { "callsign" => mrow[0], "score" => mrow[1] }
      }
      teams << { "name" => row[1], "score" => row[2], "nummembers" => row[3], "members" => memlist  }
    }
    teams
  end
  
  def dupeQSOs(logID)
    dupes = Array.new
    res = @db.query("select s.serial, r.callsign from (QSO as q join Exchange as s on s.id = q.sentID) join Exchange as r on r.id = q.recvdID where q.logID = #{logID} and matchType = 'Dupe' order by s.serial asc;")
    res.each(:as => :array) { |row|
      dupes << { 'num' => row[0].to_i, 'callsign' => row[1].to_s }
    }
    dupes
  end

  def goldenLogs(contestID)
    golden = Array.new
    res = @db.query("select l.id, l.callsign, l.verifiedQSOs, sum(q.matchType in ('Partial','NIL','OutsideContest','Removed')) as nongolden from Log as l join QSO as q on l.id = q.logID where l.contestID = #{contestID} group by l.id having nongolden = 0 order by l.verifiedQSOs desc, l.callsign asc;")
    res.each(:as => :array) { |row|
      golden << { "callsign" => row[1], "numQSOs" => row[2] }
    }
    golden
  end

  def scoreSummary(logID)
    res = @db.query("select count(*) as rawQSOs, sum(matchType='Dupe') as dupeQSOs, sum(matchType in ('Partial','Removed')) as bustedQSOs, sum(matchType = 'NIL') as penaltyQSOs, sum(matchType = 'OutsideContest') as outside from QSO where logID = #{logID} group by logID;")
    res.each(:as => :array) { |row|
      return row[0], row[1], row[2], row[3], row[4]
    }
    nil
  end

  def logEntity(logID)
    res = @db.query("select e.name from Entity as e join Log as l on e.id = l.entityID where l.id = #{logID} limit 1;")
    res.each(:as => :array) {  |row|
      return row[0]
    }
    nil
  end

  def logClockAdj(logID)
    res = @db.query("select clockadj from Log where id = #{logID} limit 1;")
    res.each(:as => :array) {  |row|
      return row[0]
    }
    0
  end
  
  def qsosOutOfContest(logID)
    logs = Array.new
    res = @db.query("select q.time, s.serial from QSO as q join Exchange as s on s.id = q.sentID where q.logID = #{logID} and matchType = 'OutsideContest' order by s.serial asc;")
    res.each(:as => :array) { |row|
      logs << { 'time' => row[0], 'number' => row[1] }
    }
    logs
  end

  def randomDoorPrize(contestID)
    res = @db.query("select count(*) from Log where contestID = #{contestID} and verifiedscore >= 1500 limit 1;")
    count = nil
    res.each(:as => :array) { |row| count = row[0] }
    if count
      res = @db.query("select name, year from Contest where id = #{contestID} limit 1;")
      res.each(:as => :array) { |row|
        print row[0].to_s + " " + row[1].to_s + " (#{count} logs having >= 1500 points)\n"
      }
      i = 1
      res = @db.query("select c.name, c.year, l.callsign from Contest as c, Log as l where c.id = #{contestID} and l.contestID = #{contestID} and l.verifiedscore >= 1500 order by rand() limit 31;")
      res.each(:as => :array) { |row|
        print "%2d. %s %4d %s\n" % [i, row[0], row[1], row[2] ]
        i = i + 1
      }
    end
  end
end
