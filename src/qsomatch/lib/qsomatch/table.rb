#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
# 
# Routines for formatting tables with output to plain text, CSV, HTML,
# and eventually PDF.
# 

require 'cgi'

THOUSANDS_SEPARATOR=','

module StandardData
  def columnText(options = {})
    to_s
  end
end

class Integer
  def columnText(options = {})
    case options.fetch(:as, :plain)
    when :plain, :HTML
      to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1" + THOUSANDS_SEPARATOR)
    else
      to_s
    end
  end
end

class String
  def columnText(options = {})
    case options.fetch(:as, :plain)
    when :CSV
      '"' + to_s.gsub('"','\"') + '"'
    when :html
      CGI.escapeHTML(to_s)
    else
      to_s
    end
  end
end

class MultiColumn
  def initialize(content, numColumns=1)
    @content = content
    @numColumns = numColumns
  end

  attr_reader :numColumns

  def columnText(options = {} )
    @content.columnText(options)
  end
end

class RowCollection
  DEFAULTS = { 
    :column_margin => 1,
    :left_margin => 0,
    :right_margin => 0,
    :vertical_line => "|",
    :horizontal_line => "-",
    :down_right => "+",
    :down_left => "+",
    :up_right => "+",
    :up_left => "+",
    :tee_down => "+",
    :tee_up => "+",
    :tee_right => "+",
    :tee_left => "+",
    :cross => "+"
  }
  UTF_DEFAULTS = { 
    :column_margin => 1,
    :left_margin => 0,
    :right_margin => 0,
    :vertical_line => "\u2502",
    :horizontal_line => "\u2500",
    :down_right => "\u250c",
    :down_left => "\u2510",
    :up_right => "\u2514",
    :up_left => "\u2518",
    :tee_down => "\u252c",
    :tee_up => "\u2534",
    :tee_right => "\u251c",
    :tee_left => "\u2524",
    :cross => "\u253c"
  }
  def initialize
    @lines = []
    @numColumns = nil
    @widths = Array.new
  end

  def <<(line)
    @lines << line
  end

  def numColumn(element)
    element.respond_to?(:numColumns) ? element.numColumns : 1
  end

  def columnsInRow(row)
    result = 0
    row.each { |col|
      result += numColumn(col)
    }
    result
  end
 
  def calcNumColumns
    @lines.map { |line| columnsInRow(line) }.max
  end

  def format(options = { })
    opts = UTF_DEFAULTS.merge(options)
    @numColumns = calcNumColumns
    @widths = Array.new(@numColumns, 0)
    extraConstraints = Array.new
    @lines.each { |row|
      col = 0
      row.each { |element|
        str = element.columnText(options)
        num = numColumn(element) 
        if num > 1
          extraConstraints << { :range => (col..(col+num-1)), :width => str.length }
        else
          if str.length > @widths[col]
            @widths[col] = str.length
          end
        end
        col += num
      }
    }
    extraConstraints.each { |ec|
      currentWidth = @widths[ec[:range]].reduce(:+) + (ec[:range].size-1)*opts[:column_margin]
      if currentWidth < ec[:width]
        neededSpace = ec[:width] - currentWidth
        perColumn = neededSpace / ec[:range].size
        extra = neededSpace % ec[:range].size
        ec[:range].each { |i|
          @widths[i] += perColumn
          if extra > 0
            @widths[i] += 1
            extra -= 1
          end
        }
      end
    }
  end

  def addHorizontal(col, prevLine, result, lastCol, opts)
    if prevLine[col]
      if 0 == col
        result << opts[:up_right]
      elsif (lastCol - 1) == col
        result << opts[:up_left]
      else
        result << opts[:tee_up]
      end
    else
      result << opts[:horizontal_line]
    end
    prevLine[col] = false
    col + 1
  end
  
  def addVertical(col, prevLine, result, lastCol, opts)
    if prevLine[col]
      if 0 == col
        result << opts[:tee_right]
      elsif (lastCol - 1) == col
        result << opts[:tee_left]
      else
        result << opts[:cross]
      end
    else
      if 0 == col
        result << opts[:down_right]
      elsif (lastCol - 1) == col
        result << opts[:down_left]
      else
        result << opts[:tee_down]
      end
    end
    prevLine[col] = true
    col + 1
  end

  def horizontalLine(linewidths, prevLine, totalwidth, options = {})
    result = ""
    col = 0
    if linewidths.is_a?(Numeric)
      linewidths.times { 
        col = addHorizontal(col, prevLine, result, linewidths, options)
      }
    else
      linewidths.each { |width|
        col = addVertical(col, prevLine, result, totalwidth, options)
        width.times {
          col = addHorizontal(col, prevLine, result, totalwidth, options)
        }
      }
      col = addVertical(col, prevLine, result, totalwidth, options)
    end
    result << "\n"
  end

  def simpleLine?(line)
    line.each { |element|
      if numColumn(element) != 1
        return false
      end
    }
    true
  end

  def widthsForLine(widths, line, opts)
    if (widths.size == line.size) and simpleLine?(line)
      return widths
    else
      result = Array.new
      wcol = 0
      line.each { |element|
        if wcol > widths.size
          return result
        end
        num = numColumn(element)
        result << (widths[wcol, num].reduce(:+) + (num-1)*opts[:column_margin])
        wcol += num
      }
      if wcol < widths.size
        remaining = widths[wcol..-1]
        result << (remaining.reduce(:+) + (remaining.size-1)*opts[:column_margin])
      end
      return result
    end  
  end

  def to_s(options = { })
    result = ""
    if not @lines.empty?
      opts = UTF_DEFAULTS.merge(options)
      format(opts)
      totalwidth = @widths.reduce(:+) + @widths.length*opts[:column_margin] + 1
      linewidths = nil
      prevLine = Array.new(totalwidth, false) # no vertical bars in previous line
      @lines.each { |line|
        linewidths = widthsForLine(@widths, line, opts)
        result << horizontalLine(linewidths, prevLine, totalwidth, opts)
        linewidths.each_index { |ind|
          element = line[ind] ? line[ind] : ""
          result << opts[:vertical_line]
          str = element.columnText(opts)
          if element.is_a?(Numeric)
            result << " " * (linewidths[ind]-str.length) + str
          else
            result << str + " " * (linewidths[ind]-str.length)
          end
        }
        result << (opts[:vertical_line] + "\n")
      }
      result << horizontalLine(totalwidth, prevLine, totalwidth, opts)
    end
    result
  end
end
  
