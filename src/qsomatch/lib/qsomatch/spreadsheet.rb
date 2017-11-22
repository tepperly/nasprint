#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-

require 'axlsx'                 # Ruby Office Open XML format library (gem)
require_relative 'report'
require_relative 'logset'

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
      result[j] = [ (j+1).to_s, OPLABELS[opclass] + " - " + power, nil, nil, nil, nil]
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
      index = s.add_style :alignment => {:horizontal => :center}
      score = s.add_style :b => true, :alignment => {:horizontal => :right}
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
      list.sort! { |x,y| x[2] <=> y[2] }
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

  def saveTo(filename)
    @package.serialize filename
  end

end
