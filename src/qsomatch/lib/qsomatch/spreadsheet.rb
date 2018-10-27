#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'axlsx'                 # Ruby Office Open XML format library (gem)
require_relative 'report'
require_relative 'logset'
require_relative 'callsign'
require_relative 'dxmap'

class Spreadsheet
  def initialize(db, contestID)
    @db = db
    @contestID = contestID
    @package = Axlsx::Package.new
    @workbook = @package.workbook
  end

  LIMIT = 750
  REGIONS = [ [ "California", 'isCA' ],  [ "Non-California", 'not isCA' ] ]
  REGIONS.freeze
  POWERS = %w{ HIGH LOW QRP }
  POWERS.freeze
  OPCLASSES = %w{ SINGLE SINGLE_ASSISTED MULTI_SINGLE MULTI_MULTI }
  OPCLASSES.freeze
  OPLABELS = { "SINGLE" => "SO", "SINGLE_ASSISTED" => "SO - A", "MULTI_SINGLE" => "M-S",
    "MULTI_MULTI" => "M-M" }
  OPLABELS.freeze

  def newSpreadsheet
    @package = Axlsx::Package.new
  end

  def topPerCat(num, region, power, opclass)
    result = Array.new(num)
    i = 0
    @db.query("select c.basecall, m.abbrev, s.verified_score from Scores as s,Log as l, Multiplier as m, Callsign as c where s.logID = l.id and l.contestID = ? and s.multID = m.id and l.callID = c.id and l.powclass = ? and l.opclass = ? and #{region} order by s.verified_score desc limit ?;",
              [@contestID, power, opclass, num]) { |row|
      result[i] = [ (i+1).to_s, OPLABELS[opclass] + " - " + power, row[0]+"/"+row[1], row[2].to_i,
        ((i > 0) ? result[i-1][3] - row[2].to_i : nil), nil]
      i += 1
    }
    i.upto(num-1) { |j|
      result[j] = [ (j+1).to_s, OPLABELS[opclass] + " - " + power] + [nil] * 4
    }
    result
  end

  def addCategories(num = 3)
    @workbook.styles { |s|
      blue_header = s.add_style :bg_color => "00FFFF", :fg_color => "00", :alignment => {:horizontal => :center }, :b => true
      plain_header = s.add_style :alignment => {:horizontal => :center }
      centered = s.add_style :alignment => {:horizontal => :center }
      right = s.add_style :alignment => {:horiginal => :right }
      right_warn =s.add_style :alignment => {:horiginal => :right }, :fg_color => "00", :bg_color => "ff0000"
      callsign = s.add_style :b => true
      cat_header = { "HIGH" => s.add_style(:bg_color => "00FF00", :fg_color => "00"),
        "LOW" => s.add_style(:bg_color => "c9daf8", :fg_color => "00"),
        "QRP" => s.add_style(:bg_color => "fff2cc", :fg_color => "00")}
      @workbook.add_worksheet(:name => "Top #{num} by Category") { |sheet|
        REGIONS.each { |region, constraint|
          sheet.add_row([nil, region, "CALL", "SCORE", " Difference ", " "]*OPCLASSES.length,
                        :style => [ plain_header, blue_header, blue_header,
                          blue_header,blue_header,plain_header ]*OPCLASSES.length)
          POWERS.each { |power|
            rows = Array.new
            styles = [ centered, cat_header[power], callsign, right, right, nil]*OPCLASSES.length
            num.times { rows << Array.new }
            OPCLASSES.each { |opclass|
              lines = topPerCat(num, constraint, power, opclass)
              rows.each_index { |i|
                rows[i] += lines[i]
              }
            }
            rows.each { |l|
              mstyles = styles.clone
              OPCLASSES.length.times { |i|
                if l[4+i*6] and l[4+i*6] <= LIMIT # small differences get highlighted with red
                  mstyles[4+i*6] = right_warn
                end
              }
              sheet.add_row(l, :style => mstyles)
            }
            sheet.add_row
          }
        }
      }
    }
  end

  def topWine(num, region)
    result = Array.new(num)
    i = 0
    @db.query("select c.basecall, m.abbrev, s.verified_score from Scores as s,Log as l, Multiplier as m, Callsign as c where s.logID = l.id and l.contestID = ? and s.multID = m.id and l.callID = c.id and l.opclass in ('SINGLE', 'SINGLE_ASSISTED') and #{region} order by s.verified_score desc limit ?;",
              [@contestID, num]) { |row|
      result[i] = [ row[0]+"/"+row[1], row[2].to_i]
      i += 1
    }
    result
  end

  def addWineWinners(num = 24)
    @workbook.styles { |s|
      regstyle = { "California" => s.add_style(:b => true, :bg_color => "ffff00", :alignment => { :horizontal => :center}),
        "Non-California" => s.add_style(:b => true, :bg_color => "ead1dc", :alignment => { :horizontal => :center})
      }
      callsign = s.add_style :b => true
      index = s.add_style :alignment => {:horizontal => :center}, :edges => [:top, :bottom, :left, :right ]
      score = s.add_style :b => true, :alignment => {:horizontal => :right}, :edges => [:top, :bottom, :left, :right ]
      diff_warn = s.add_style :b => true, :alignment => {:horizontal => :right}, :bg_color => "ff0000"
      @workbook.add_worksheet(:name => "Top #{num} Wine Contenders") { |sheet|
        sheet.add_row
        sheet.add_row([ nil, REGIONS[0][0], "Score", " Difference ", nil,
                        nil, REGIONS[1][0], "Score", " Difference "],
                      :style => [nil, regstyle[REGIONS[0][0]], regstyle[REGIONS[0][0]], regstyle[REGIONS[0][0]], nil,
                        nil, regstyle[REGIONS[1][0]], regstyle[REGIONS[1][0]], regstyle[REGIONS[1][0]]])
        lines = Array.new(num)
        num.times { |i| lines[i] = Array.new }
        REGIONS.each { |region, constraint|
          tops = topWine(num, constraint)
          lines.each_index { |i|
            scoreInd = lines[i].length+2
            lines[i] << (i+1)
            if tops.length > i
              lines[i] << tops[i][0]
              lines[i] << tops[i][1]
              lines[i] << ((i > 0) ? (lines[i-1][scoreInd] - tops[i][1]) : nil)
            else
              lines[i] << nil
              lines[i] << nil
              lines[i] << nil
            end
            lines[i] << " "
          }
        }
        lines.each { |line|
          sheet.add_row(line,
                        :style => [ index, callsign, score,
                          ((line[3] and line[3] <= LIMIT) ? diff_warn : score), nil,
                          index, callsign, score,
                          ((line[8] and line[8] <= LIMIT) ? diff_warn : score), nil])
        }
      }
    }
  end

  def specialAward(num, sheet, regcon, title, constraint)
    @workbook.styles { |s|
      header = s.add_style :b => true, :alignment => {:horizontal => :center}
      index = s.add_style :alignment => {:horizontal => :center}
      right = s.add_style :alignment => {:horizontal => :right}
      callsign = s.add_style :alignment => {:horizontal => :left}, :b => true
      missing = s.add_style :alignment => {:horizontal => :left}, :i => true
      right_warn = s.add_style :alignment => {:horizontal => :right}, :bg_color => "ff0000"
      sheet.add_row([nil, title, "Score", "Difference"], :style => [nil, header, header, header])
      i = 1
      prev = nil
      @db.query("select c.basecall, m.abbrev, s.verified_score from Scores as s,Log as l, Multiplier as m, Callsign as c where s.logID = l.id and l.contestID = ? and s.multID = m.id and l.callID = c.id and #{regcon} and #{constraint} order by s.verified_score desc limit ?;",
                [@contestID, num]) { |row|
        if prev
          diff = prev - row[2].to_i
          sheet.add_row([i, row[0]+"/"+row[1], row[2].to_i, diff],
                        :style=>[index, callsign, right,
                          ((diff <= LIMIT) ? right_warn : right)])
        else
          sheet.add_row([i, row[0]+"/"+row[1], row[2].to_i],
                        :style => [ index, callsign, right])
        end
        prev = row[2].to_i
        i += 1
      }
      if i == 1
        sheet.add_row([nil, "(none)"],
                      :style => [nil, missing])
      end
      sheet.add_row
    }
  end

  def qsoAward(num, sheet, regcon, title, column, coldesc)
    @workbook.styles { |s|
      header = s.add_style :b => true, :alignment => {:horizontal => :center}
      index = s.add_style :alignment => {:horizontal => :center}
      right = s.add_style :alignment => {:horizontal => :right}
      callsign = s.add_style :alignment => {:horizontal => :left}, :b => true
      missing = s.add_style :alignment => {:horizontal => :left}, :i => true
      right_warn = s.add_style :alignment => {:horizontal => :right}, :bg_color => "ff0000"
      sheet.add_row([nil, title, coldesc + " QSOs", "Difference"],
                    :style=>[nil, header, header, header])
      prev = nil
      i = 1
      @db.query("select c.basecall, m.abbrev, s.#{column} from Scores as s,Log as l, Multiplier as m, Callsign as c where s.logID = l.id and l.contestID = ? and s.multID = m.id and l.callID = c.id and #{regcon} and l.opclass in ('SINGLE', 'SINGLE_ASSISTED') order by s.#{column} desc limit ?;",
                [@contestID, num]) { |row|
        if prev
          diff = prev - row[2].to_i
          sheet.add_row([i, row[0]+"/"+row[1], row[2].to_i, diff],
                        :style=>[index, callsign, right,
                          ((diff <= 10) ? right_warn : right)])
        else
          sheet.add_row([i, row[0]+"/"+row[1], row[2].to_i],
                        :style=>[index, callsign, right])
        end
        prev = row[2].to_i
        i += 1
      }
      if i == 1
        sheet.add_row([nil, "(none)"],
                      :style => [nil, missing])
      end
      sheet.add_row
    }
  end

  def firstToAllMults(num, sheet, title, regcon)
    @workbook.styles { |s|
      header = s.add_style :b => true, :alignment => {:horizontal => :center}
      index = s.add_style :alignment => {:horizontal => :center}
      left = s.add_style :alignment => {:horizontal => :left}
      callsign = s.add_style :alignment => {:horizontal => :left}, :b => true
      missing = s.add_style :alignment => {:horizontal => :left}, :i => true
      sheet.add_row([nil, "Callsign", "Time All Mults Worked"],
                    :style=>[nil, header, header])
      r = Report.new(@db, @contestID)
      list = r.firstTo58List(@contestID, regcon)
      if not list.empty?
        i = 1
        list = list[0,num]  # cap number to report
        list.each { |row|
          sheet.add_row([i, row[0] +"/" + row[1], row[2].to_s],
                        :style => [ index, callsign, left])
          i += 1
        }
      else
        sheet.add_row([nil, "(none)"],
                      :style => [nil, missing])
      end
      sheet.add_row
    }
  end

  def regionSpecialAwards(num, region, constraint)
    @workbook.add_worksheet(:name => (region + " Special Awards")) { |sheet|
      specialAward(num, sheet, constraint, region + " Single-OP YL", "opclass in ('SINGLE', 'SINGLE_ASSISTED') and isYL")
      specialAward(num, sheet, constraint, region + " Single-OP Youth", "opclass in ('SINGLE', 'SINGLE_ASSISTED') and isYOUTH")
      specialAward(num, sheet, constraint, region + " Top School", "isSCHOOL")
      if (region == "California")
        specialAward(num, sheet, constraint, region + " New Contester", "opclass in ('SINGLE', 'SINGLE_ASSISTED') and isNEW")
        specialAward(num, sheet, constraint, "Single-Op County Expedition", "opclass in ('SINGLE', 'SINGLE_ASSISTED') and isCCE")
        specialAward(num, sheet, constraint, "Multi-Single County Expedition", "opclass = 'MULTI_SINGLE' and isCCE")
        specialAward(num, sheet, constraint, "Multi-Multi County Expedition", "opclass = 'MULTI_MULTI' and isCCE")
      end
      firstToAllMults(3, sheet, region + " First to 58", " and " + constraint)
      qsoAward(2, sheet, constraint, "Most Phone QSOs", "verified_ph", "PH")
      qsoAward(2, sheet, constraint, "Most CW QSOs", "verified_cw", "CW")
    }
  end

  def addSpecialAwards
    REGIONS.each { |region, constraint|
      regionSpecialAwards(2, region, constraint)
    }
  end

  def callWithOp(basecall, logID)
    result = basecall
    count = 0
    @db.query("select callsign from Operator where logID = ? and substr(callsign,1,1) != '@' and callsign != ?;",
              [ logID, basecall ]) { |row|
      result = basecall + " ("+row[0]+" op)"
      count += 1
      if count > 1
        return basecall
      end
    }
    result
  end

  def wineWinners(region)
    result = Array.new
    @db.query("select l.id, c.basecall, m.abbrev, s.verified_score from Scores as s,Log as l, Multiplier as m, Callsign as c where s.logID = l.id and l.contestID = ? and s.multID = m.id and l.callID = c.id and l.opclass in ('SINGLE', 'SINGLE_ASSISTED') and #{region} order by s.verified_score desc limit 20;",
              [@contestID ]) { |row|
      result << [ callWithOp(row[1], row[0].to_i), row[2], row[3] ]
    }
    result
  end
  
  def wineFinalReport
    @workbook.styles { |s|
      font = {:font_name => "Verdana"}
      border = {:border => { :style => :thin, :color => "000000"}}
      leftborder = s.add_style(:border => { :style => :thin, :color => "000000", :edges => [:left]} )
      lrborder = s.add_style(:border => { :style => :thin, :color => "000000", :edges => [:left, :right]})
      align = {:alignment => { :horizontal => :center, :vertical => :center }}
      ralign = {:alignment => { :horizontal => :right, :vertical => :center }}
      lalign = {:alignment => { :horizontal => :left, :vertical => :center }}
      titlestyle = s.add_style({:b => true, :bg_color => "ffff00"}.merge(align).merge(border).merge(font ))
      subtitlestyle = s.add_style({:b => true, :bg_color => "ccffcc"}.merge(border).merge( align).merge(font))
      regstyle = { "California" => s.add_style({:b => true, :bg_color => "fde9d9"}.merge( border).merge( align).merge(font)),
        "Non-California" => s.add_style({:b => true, :bg_color => "fde9d9"}.merge(border).merge(align).merge(font)) }
      num = s.add_style align.merge(font).merge(border)
      callsign = s.add_style({:b => true}.merge(border).merge(lalign).merge(font))
      qth = s.add_style( align.merge( border).merge(font))
      score = s.add_style( ralign.merge( border).merge(font).merge({:format_code => "#,##0"}))
      @workbook.add_worksheet(:name => "CQP #{$year} Wine Results",
                              :page_margins => {
                                :left => 0.5, :right => 0.5, :top => 0.5, :bottom => 0.5,
                                :header => 0, :footer => 0}
                              ) { |sheet|
        sheet.add_row ["#{$year} California QSO Party Awards", nil,nil,nil,nil,nil,nil,nil,nil]
        sheet.merge_cells("A1:I1")
        sheet["A1:I1"].each { |c| c.style = titlestyle }
        sheet.add_row ["Wine Winners", nil,nil,nil,nil,nil,nil,nil,nil ]
        sheet.merge_cells("A2:I2")
        sheet["A2:I2"].each { |c| c.style = subtitlestyle }
        sheet.add_row ["CALIFORNIA",nil,nil,nil,nil,"NON-CALIFORNIA",nil,nil,nil]
        sheet.merge_cells("A3:D3")
        sheet.merge_cells("F3:I3")
        sheet["A3:D3"].each { |c| c.style = regstyle["California"] }
        sheet["F3:I3"].each { |c| c.style = regstyle["Non-California"] }
        caWinners = wineWinners("isCA")
        nonCAWinners = wineWinners("not isCA")
        20.times { |i|
          row = Array.new(9)
          row[0] = (i+1).to_s
          if caWinners[i]
            3.times { |j| row[j+1] = caWinners[i][j] }
          end
          row[5] = (i+1).to_s
          if nonCAWinners[i]
            3.times { |j| row[j+6] = nonCAWinners[i][j] }
          end
          sheet.add_row(row, :style =>
                        [num, callsign, qth, score, nil,
                          num, callsign, qth, score ])
        }
        sheet.column_widths 5, 21.3, 6.5, 10.5, 1.8, 5, 21.3, 6.5, 10.5
      }
    }
  end

  def topPlaqCat(region, power, opclass, num=1, withNum = false, extracon="", criteria="s.verified_score")
    i = 1
    result = Array.new
    @db.query("select l.id, c.basecall, m.fullname, s.verified_ph, s.verified_cw, s.verified_mult, s.verified_score from Log as l, Callsign as c on c.id = l.callID, Multiplier as m on m.id = s.multID, Scores as s on s.logID = l.id where l.contestID = ? and l.powclass in ( #{power.map{|x| '"'+x+'"'}.join(', ')} ) and l.opclass in (#{opclass.map{|x| '"'+x+'"'}.join(', ')}) and #{region}  #{extracon} order by #{criteria} desc limit ?;",
              [@contestID, num.to_i]) { |row|
      result << [ (withNum ? (i.to_s + ". ") : "") + callWithOp(row[1], row[0].to_i),
        row[2], row[5], row[4], row[3], row[6], row[0].to_i ]
      i += 1
    }
    result
  end

  def opsList(logID)
    basecall = nil
    if logID
      @db.query("select callsign from Log where id = ? limit 1;", [logID]) { |row|
        basecall = row[0]
      }
    end
    count = 0
    ops = [ ]
    if basecall and logID
      @db.query("select callsign from Operator where logID = ?;", [logID]) { |row|
        ops << row[0]
        if not row[0].start_with?("@") and basecall != row[0]
          count += 1
        end
      }
    end
    return (count > 1) ? ("Ops = " + ops.join(", ")) : nil
  end

  def addTwoRegions(sheet, name, namestyle, headstyle, powclass, opclass, num,
                    callsign, qth, numstyle, score, opsstyle, numbered=false, extracon="",
                    criteria="s.verified_score")
    sheet.add_row [name,nil,"Mults", "CW", "PH", "Score", nil,
                   name,nil,"Mults", "CW", "PH", "Score"]
    sheet.merge_cells(sheet.rows.last.cells[(0..1)])
    sheet.rows.last.cells[0].style = namestyle
    sheet.rows.last.cells[7].style = namestyle
    sheet.rows.last.cells[(2..5)].each { |c| c.style = headstyle }
    sheet.rows.last.cells[(9..12)].each { |c| c.style = headstyle }
    sheet.merge_cells(sheet.rows.last.cells[(7..8)])
    ca = topPlaqCat("m.isCA", powclass, opclass, num, numbered, extracon)
    nonca = topPlaqCat("not m.isCA", powclass, opclass, num, numbered, extracon)
    [ca.length, nonca.length].max.times { |i|
      sheet.add_row((ca[i] ? ca[i][0..5] : [ "None"] + [nil]*5) +
                    [ nil ] +
                    (nonca[i] ? nonca[i][0..5] : [ "None"] + [nil]*5) ,
                    :style => [ callsign, qth, numstyle, numstyle, numstyle, score, nil,
                      callsign, qth, numstyle, numstyle, numstyle, score ] )
      caOps = ca[i] ? opsList(ca[i][6]) : nil
      noncaOps = nonca[i] ? opsList(nonca[i][6]) : nil
      if caOps or noncaOps
        sheet.add_row([caOps] + [nil]*6 + 
                        [ noncaOps ] + [ nil ] * 5,
                      :style => [ opsstyle ] *6 + [ nil ] + [opsstyle]*6)
        sheet.merge_cells(sheet.rows.last.cells[0..5])
        sheet.merge_cells(sheet.rows.last.cells[7..12])
      end
    }
  end

  ALLPOWERS = %w{ LOW HIGH QRP }
  ALLPOWERS.freeze

  def addMostQSOs(sheet, name, namestyle, headstyle, callsign, qth, num,
                  criteria, column)
    sheet.add_row [name,nil,"Num QSOs", nil, nil, nil, nil,
                   name,nil,"Num QSOs", nil, nil, nil]
    sheet.merge_cells(sheet.rows.last.cells[(0..1)])
    sheet.rows.last.cells[(2..5)].each { |c| c.style = headstyle }
    sheet.merge_cells(sheet.rows.last.cells[(2..3)])
    sheet.merge_cells(sheet.rows.last.cells[(4..5)])
    sheet.rows.last.cells[0].style = namestyle
    sheet.rows.last.cells[7].style = namestyle
    sheet.rows.last.cells[(9..12)].each { |c| c.style = headstyle }
    sheet.merge_cells(sheet.rows.last.cells[(7..8)])
    sheet.merge_cells(sheet.rows.last.cells[(9..10)])
    sheet.merge_cells(sheet.rows.last.cells[(11..12)])
    ca = topPlaqCat("m.isCA", ALLPOWERS, %w{SINGLE SINGLE_ASSISTED}, 1, false, "",
                    criteria)
    nonca = topPlaqCat("not m.isCA", ALLPOWERS, %w{SINGLE SINGLE_ASSISTED}, 1, false, "",
                       criteria)
    [ca.length, nonca.length].max.times { |i|
      sheet.add_row((ca[i] ? [ca[i][0], ca[i][1], ca[i][column].to_s + " QSOs",
                        nil, nil, nil]
                      : [ "None", nil, nil, nil, nil. nil]) +
                    [ nil ] +
                    (nonca[i] ? [nonca[i][0], nonca[i][1], nonca[i][column].to_s + " QSOs",
                        nil, nil, nil]
                      : [ "None", nil, nil, nil, nil, nil]) ,
                    :style => [ callsign, qth, num, nil, nil, nil, nil,
                      callsign, qth, num, nil, nil, nil ] )
      sheet.merge_cells(sheet.rows.last.cells[(2..3)])
      sheet.merge_cells(sheet.rows.last.cells[(4..5)])
      sheet.merge_cells(sheet.rows.last.cells[(9..10)])
      sheet.rows.last.cells[(4..5)].each { |c| c.style = num }
      sheet.merge_cells(sheet.rows.last.cells[(11..12)])
      sheet.rows.last.cells[(11..12)].each { |c| c.style = num }

    }
  end

  ALLOPS = %w{ SINGLE SINGLE_ASSISTED MULTI_SINGLE MULTI_MULTI }
  ALLOPS.freeze

  def clubRow(list, size)
    if list.empty?
      return [ "None", nil, size, nil, nil, nil ]
    else
      top = list[0]
      return [ top[0], nil, size, top[1], top[2], nil ]
    end
  end

  def addClubAwards(sheet, namestyle, headstyle, clubstyle, logsstyle, scorestyle)
    sheet.add_row(["Top CA Club Awards", nil, "Size","Logs", "Score", nil, nil,
                    "Top Non-CA Club Awards", nil, "Size", "Logs", "Score", nil],
                  :style => [namestyle, namestyle, headstyle, headstyle,
                    headstyle, headstyle, nil, namestyle, namestyle, headstyle, headstyle,
                    headstyle, headstyle])
    sheet.merge_cells(sheet.rows.last.cells[0..1])
    sheet.merge_cells(sheet.rows.last.cells[4..5])
    sheet.merge_cells(sheet.rows.last.cells[7..8])
    sheet.merge_cells(sheet.rows.last.cells[11..12])
    %w{ Large Medium Small }.each { |size|
      caclubs = clubList(@db, @contestID, size, "California")
      noncaclubs = clubList(@db, @contestID, size, "Non-California")
      carow = clubRow(caclubs, size)
      noncarow = clubRow(noncaclubs, size)
      sheet.add_row(carow + [ nil ] + noncarow,
                    :style => [clubstyle, clubstyle,
                      logsstyle, logsstyle, scorestyle, scorestyle, nil,
                      clubstyle, clubstyle,
                      logsstyle, logsstyle, scorestyle, scorestyle])
      sheet.merge_cells(sheet.rows.last.cells[0..1])
      sheet.merge_cells(sheet.rows.last.cells[4..5])
      sheet.merge_cells(sheet.rows.last.cells[7..8])
      sheet.merge_cells(sheet.rows.last.cells[11..12])
    }
  end

  def timeDuration(cdb, time)
    start, stop = cdb.contestTime($year)
    duration = time - start
    hours = (duration/3600).to_i
    minutes = ((duration - hours*3600)/60).to_i
    return time.strftime("%H:%M (") +  hours.to_s + " hr " + minutes.to_s + " min)"
  end

  def addFirst58(sheet, namestyle, headstyle, callstyle, qthstyle, numstyle)
    cdb = ContestDatabase.new(@db, CallsignTools.new)
    r = Report.new(@db, @contestID)
    results = Hash.new
    REGIONS.each { |k,v|
      results[k] = r.firstTo58List(@contestID, " and " + v)
    }
    sheet.add_row(["First To 58 Multipliers", nil, "Time (duration)", nil, nil, nil,
                    nil,
                    "First To 58 Multipliers", nil, "Time (duration)", nil, nil, nil],
                  :style => [namestyle,  namestyle,
                    headstyle, headstyle, headstyle, headstyle, nil, namestyle,  namestyle,
                    headstyle, headstyle, headstyle, headstyle])
    sheet.merge_cells(sheet.rows.last.cells[0..1])
    sheet.merge_cells(sheet.rows.last.cells[2..5])
    sheet.merge_cells(sheet.rows.last.cells[7..8])
    sheet.merge_cells(sheet.rows.last.cells[9..12])
    row = Array.new
    if results['California'].empty?
      row = row + ["None", nil, nil, nil, nil, nil]
    else
      top = results['California'][0]
      row = row + [top[0],cdb.getFullname(top[1]),
        timeDuration(cdb, top[2]), nil, nil, nil]
    end
    row += [ nil ]
    if results['Non-California'].empty?
      row = row + ["None", nil, nil, nil, nil, nil]
    else
      top = results['Non-California'][0]
      row = row + [top[0],cdb.getFullname(top[1]),
        timeDuration(cdb, top[2]), nil, nil, nil]
    end
    sheet.add_row(row, :style => [callstyle, qthstyle, numstyle, numstyle, numstyle, numstyle,
                    nil, callstyle, qthstyle, numstyle, numstyle, numstyle, numstyle])
    sheet.merge_cells(sheet.rows.last.cells[2..5])
    sheet.merge_cells(sheet.rows.last.cells[9..12])
  end

  def numCounties(id)
    @db.query("select count(*) from Log as l join Scores as s on s.logID = l.id where l.id = ? limit 1;",
              [ id ] ) { |row|
      return row[0].to_i
    }
    0
  end

  def bestMobile
    result = Array.new
    @db.query("select l.id, l.callsign, sum(s.verified_ph+s.verified_cw) as numqsos from Log as l, Scores as s on s.logID = l.id where l.contestID = ? and l.isMOBILE group by l.id order by numqsos desc limit 1;", [@contestID ]) { |row|
      result << ([callWithOp(row[1], row[0].to_i), numCounties(row[0]).to_s + " counties",
          row[2].to_s + " QSOs"] + [nil]*3)
      ops = opsList(row[0])
      if ops
        result << ([ops] + [nil]*5)
      end
    }
    if result.empty?
      result << ([ 'None' ] + [nil]*5)
    end
    result
  end
 
  def mobileQSOs(sheet, namestyle, callstyle, qthstyle, headstyle,opsstyle)
    sheet.add_row(["Most Mobile QSOs", nil, "Number of QSOs", nil, nil, nil, nil,
                    nil,nil,nil,nil,nil,nil],
                  :style => [namestyle, namestyle, headstyle, headstyle,
                    headstyle, headstyle] + [ nil ] * 7)
    sheet.merge_cells(sheet.rows.last.cells[0..1])
    sheet.merge_cells(sheet.rows.last.cells[2..5])
    mobile = bestMobile
    sheet.add_row(mobile[0] + [ nil ] *7,
                  :style => [callstyle] + [ qthstyle ] * 5 +[ nil ] *7)
    sheet.merge_cells(sheet.rows.last.cells[2..5])
    if (mobile.length > 1)
      sheet.add_row(mobile[1] + [ nil ] * 7,
                    :style => [opsstyle]*6 + [nil ] *7)
      sheet.merge_cells(sheet.rows.last.cells[0..5])
    end
  end

  def leftColumnAward(sheet, namestyle, headstyle, callstyle, qth, numstyle, score,
                      opsstyle, name, num, powclass, opclass,extracon)
    results = topPlaqCat("m.isCA", powclass, opclass, num, num > 1, extracon)
    sheet.add_row([name, nil, "Mults", "CW", "PH", "Score"] + [nil]*7,
                  :style => [namestyle]*2 + [headstyle]*4 + [nil]*7)
    sheet.merge_cells(sheet.rows.last.cells[(0..1)])
    results.each { |row|
      sheet.add_row((row ? row[0..5] : [ "None"] + [nil]*5) +
                    [ nil ]*7,
                    :style => [ callstyle, qth, numstyle, numstyle, numstyle, score] +
                    [nil]*7)
      ops = row ? opsList(row[6]) : nil
      if ops
        sheet.add_row([ops] + [nil]*12,
                      :style => [ opsstyle ] *6 + [ nil ]*7)
        sheet.merge_cells(sheet.rows.last.cells[0..5])
      end
    }
  end

  def rightColumnAward(sheet, row, titlestyle, namestyle, header,
                       callstyle, qth, num, score)
    sheet.rows[row].cells[7].value = "Top DX (Non-USA, Non-Canadian)" 
    sheet.rows[row].cells[7..12].each { |c| c.style = titlestyle }
    sheet.merge_cells(sheet.rows[row].cells[7..12])
    row += 1
    sheet.rows[row].cells[7].value = "Top DX"
    sheet.rows[row].cells[9].value = "Mults"
    sheet.rows[row].cells[10].value = "CW"
    sheet.rows[row].cells[11].value = "PH"
    sheet.rows[row].cells[12].value = "Score"
    sheet.rows[row].cells[7..8].each { |c| c.style = namestyle }
    sheet.merge_cells(sheet.rows[row].cells[7..8])
    sheet.rows[row].cells[9..12].each { |c| c.style = header }
    row += 1
    styles = [ callstyle, qth, num, num, num, score ]
    dx = topPlaqCat("m.abbrev='DX'", ALLPOWERS, ALLOPS, 1, false)
    if dx.empty?
      sheet.rows[row].cells[7].value = "None"
      styles.each_index { |i|
        sheet.rows[row].cells[7+i].style = styles[i]
      }
    else
      cl = CallsignLocator.new
      dx.each { |dxrow|
        6.times { |i|
          sheet.rows[row].cells[7+i].value = dxrow[i]
          sheet.rows[row].cells[7+i].style = styles[i]
        }
        ent = cl.lookup(dxrow[0])
        if ent
          sheet.rows[row].cells[8].value = ent.name
        end
        row += 1
        ops = opsList(row[6])
        if ops
          sheet.rows[row].cells[7].value = ops
          6.times { |i| sheet.rows[row].cells[7+i].style = opsstyle }
          sheet.merge_cells(sheet.rows[row].cells[7..12])
          row += 1
        end
      }
    end
    row
  end

  def plaqueAwards(recdb)
    @workbook.styles { |s|
      font = {:font_name => "Verdana", :sz => 8}
      border = {:border => { :style => :thin, :color => "000000"}}
      leftborder = s.add_style(:border => { :style => :thin, :color => "000000", :edges => [:left]} )
      lrborder = s.add_style(:border => { :style => :thin, :color => "000000", :edges => [:left, :right]})
      align = {:alignment => { :horizontal => :center, :vertical => :center }}
      ralign = {:alignment => { :horizontal => :right, :vertical => :center }}
      lalign = {:alignment => { :horizontal => :left, :vertical => :center }}
      awardname = s.add_style({:b => true, :bg_color => "fde9d9", :fg_color => "0000ff"}.merge(font).merge(border).merge(lalign))
      header = s.add_style({:b => true, :bg_color => "fde9d9", :fg_color => "000000"}.merge(font).merge(border).merge(align))
      titlestyle = s.add_style({:b => true, :bg_color => "ffff00"}.merge(align).merge(border).merge(font ))
      subtitlestyle = s.add_style({:b => true, :bg_color => "ccffcc"}.merge(border).merge( align).merge(font))
      regstyle = { "California" => s.add_style({:b => true, :bg_color => "ffffff", :fg_color => "ff0000"}.merge( border).merge( align).merge(font)),
        "Non-California" => s.add_style({:b => true, :bg_color => "ffffff", :fg_color => "ff0000"}.merge(border).merge(align).merge(font)) }
      num = s.add_style align.merge(font).merge(border)
      callsign = s.add_style({:b => true}.merge(border).merge(lalign).merge(font))
      qth = s.add_style( align.merge( border).merge(font))
      score = s.add_style( ralign.merge( border).merge(font).merge({:format_code => "#,##0"}))
      opsstyle = s.add_style( lalign.merge( border).merge(font))
      @workbook.add_worksheet(:name => "CQP #{$year} Plaque Awards",
                              :page_margins => {
                                :left => 0.25, :right => 0.25,
                                :top => 0.25, :bottom => 0.25,
                                :header => 0, :footer => 0}) { |sheet|
        sheet.add_row ["#{$year} CALIFORNIA QSO PARTY AWARDS",
                       nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil]
        sheet.merge_cells("A1:M1")
        sheet["A1:M1"].each { |c| c.style = titlestyle } 
        sheet.add_row ["PLAQUE AWARDS", nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil]
        sheet.merge_cells("A2:M2")
        sheet["A2:M2"].each { |c| c.style = subtitlestyle }
        sheet.add_row [ "CALIFORNIA", nil,nil,nil,nil,nil,nil,
                       "NON-CALIFORNIA = USA, VE, DX",
                       nil,nil,nil,nil,nil]
        sheet.merge_cells("A3:F3")
        sheet["A3:F3"].each { |c| c.style = regstyle["California"] }
        sheet.merge_cells("H3:M3")
        sheet["H3:M3"].each { |c| c.style = regstyle["Non-California"] }
        addTwoRegions(sheet, "Single-Op HP", awardname, header,
                      %w{HIGH}, %w{SINGLE}, 2,
                      callsign, qth, num, score, opsstyle, true)
        addTwoRegions(sheet, "Single-Op LP", awardname, header,
                      %w{LOW}, %w{SINGLE}, 2,
                      callsign, qth, num, score, opsstyle, true)
        addTwoRegions(sheet, "Single-Op QRP", awardname, header,
                      %w{QRP}, %w{SINGLE}, 1, callsign, qth, num, score, opsstyle)
        addTwoRegions(sheet, "Single-Op HP, Assisted", awardname, header,
                      %w{HIGH}, %w{SINGLE_ASSISTED}, 2,
                      callsign, qth, num, score, opsstyle, true)
        addTwoRegions(sheet, "Single-Op LP, Assisted",  awardname, header,
                      %w{LOW}, %w{SINGLE_ASSISTED}, 2,
                      callsign, qth, num, score, opsstyle, true)
        addTwoRegions(sheet, "Single-Op QRP, Assisted", awardname, header,
                      %w{QRP}, %w{SINGLE_ASSISTED}, 1, callsign, qth, num, score, opsstyle)
        addTwoRegions(sheet, "Single-Op YL", awardname, header,
                      ALLPOWERS, %w{SINGLE SINGLE_ASSISTED}, 1, callsign, qth, num, score, opsstyle,
                      false, " and l.isYL")
        addTwoRegions(sheet, "Single-Op Youth", awardname, header,
                      ALLPOWERS, [ "SINGLE", "SINGLE_ASSISTED"], 1, callsign, qth, num, score, opsstyle,
                      false, " and l.isYOUTH")
        addTwoRegions(sheet, "Top School", awardname, header,
                      ALLPOWERS, ALLOPS, 1, callsign, qth, num, score, opsstyle,
                      false, " and l.isSCHOOL")
        addTwoRegions(sheet, "Top Multi-Single", awardname, header,
                      ALLPOWERS, %w{MULTI_SINGLE}, 1, callsign, qth, num, score, opsstyle,
                      false)
        addMostQSOs(sheet, "Most CW QSOs", awardname, header, callsign, qth, num,
                    "s.verified_cw", 3)
        addMostQSOs(sheet, "Most PH QSOs", awardname, header, callsign, qth, num,
                    "s.verified_ph", 4)
        addClubAwards(sheet, awardname, header, callsign, num, score)
        addFirst58(sheet, awardname, header, callsign, qth, num)
        rightColumnRow = sheet.rows.length+1
        mobileQSOs(sheet, awardname, callsign, qth, header,opsstyle)
        leftColumnAward(sheet, awardname, header, callsign, qth, num, score,
                        opsstyle, "Single-Op New Contester", 1, ALLPOWERS,
                        %w{ SINGLE SINGLE_ASSISTED }, "and l.isNEW")
        leftColumnAward(sheet, awardname, header, callsign, qth, num, score,
                        opsstyle, "Single-Op Expeditions", 2, ALLPOWERS,
                        %w{ SINGLE SINGLE_ASSISTED }, "and l.isCCE")
        leftColumnAward(sheet, awardname, header, callsign, qth, num, score,
                        opsstyle, "Multi-Single Expeditions", 1, ALLPOWERS,
                        %w{ MULTI_SINGLE }, "and l.isCCE")
        leftColumnAward(sheet, awardname, header, callsign, qth, num, score,
                        opsstyle, "Top Multi-Multi", 1, ALLPOWERS,
                        %w{ MULTI_MULTI }, "")
        leftColumnAward(sheet, awardname, header, callsign, qth, num, score,
                        opsstyle, "Top Multi-Multi Expedition", 1, ALLPOWERS,
                        %w{ MULTI_MULTI }, "and l.isCCE")
        rightColumnRow = rightColumnAward(sheet, rightColumnRow, titlestyle,
                                          awardname, header, callsign, qth, num,
                                          score)
        sheet.column_widths 12, 12, 5, 5, 5, 7, 1, 12, 12, 5, 5, 5, 7
      }
    }
  end

  def saveTo(filename)
    @package.serialize filename
  end

end
