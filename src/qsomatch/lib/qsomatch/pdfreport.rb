#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
require 'prawn'
require 'set'
require_relative 'callsign'

class AString < String
  def initialize(str, options={})
    super(str)
    @attributes = Hash.new()
    self.addAttributes(options)
  end

  def addAttributes(options = { })
    @attributes.merge!(options)
  end

  attr_reader :attributes
end

class Group
  def initialize(header, columnStarts, widths)
    @header = header
    @rows = Array.new
    @columnStarts = columnStarts
    @columnWidths = widths
  end

  attr_reader :header, :rows, :columnStarts, :columnWidths
  attr_writer :rows
end

class ReportPDF
  LOGO_FILE=File.dirname(__FILE__)+"/images/nccc_generic.png"
  HEADER_HEIGHT=44
  LEGEND = [
    "C = <i>Checklog</i>",
    "E = Country Expedition",
    "L = Low Power",
    "M = Mobile",
    "M/M = Multi-Multi",
    "M/S = Multi-Single",
    "Q = QRP",
    "YL = Female Operator"
  ]
  LEGEND.freeze

  def initialize(title, legend=LEGEND)
    @title = title
    @legend = legend
    @pdf = Prawn::Document.new(:page_style => "LETTER", :page_layout => :portrait,
                               :top_margin => 95,
                               :info => {
                                 :Title => title.gsub("\n"," : "),
                                 :Author => "Northern California Contest Club",
                                 :Subject => "Contest results published by the NCCC",
                                 :Keywords => "NCCC, ham radio, contest, radiosport",
                                 :CreationDate => Time.now,
                                 :ModDate => Time.now
                               })
    @pdf.font_families.update( "Verdana" => {
                                 :normal => "/usr/share/fonts/truetype/msttcorefonts/Verdana.ttf",
                                 :bold => "/usr/share/fonts/truetype/msttcorefonts/Verdana_Bold.ttf",
                                 :italic => "/usr/share/fonts/truetype/msttcorefonts/Verdana_Italic.ttf",
                                 :fold_italic => "/usr/share/fonts/truetype/msttcorefonts/Verdana_Bold_Italic.ttf"
                               })
    @pdf.font_families.update( "Arial" => {
                                 :normal => "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf",
                                 :black => "/usr/share/fonts/truetype/msttcorefonts/Arial_Black.ttf",
                                 :bold => "/usr/share/fonts/truetype/msttcorefonts/Arial_Bold.ttf",
                                 :italic => "/usr/share/fonts/truetype/msttcorefonts/Arial_Italic.ttf",
                                 :fold_italic => "/usr/share/fonts/truetype/msttcorefonts/Arial_Bold_Italic.ttf"
                               })
    @pdf.font_families.update( "Trebuchet MS" => {
                                 :normal => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS.ttf",
                                 :bold => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Bold.ttf",
                                 :italic => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Italic.ttf",
                                 :fold_italic => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Bold_Italic.ttf"
                               })
    @pdf.font "Trebuchet MS"
    @pdf.default_leading = (0.25 * @pdf.font_size).to_i
    @baselineskip = @pdf.default_leading + @pdf.font_size
    @footnotes = [ ]
    @pdf.repeat(:all) {
      pageHeader
    }
  end

  def fillBounding(color)
    @pdf.save_graphics_state {
      bounds = @pdf.bounds
      @pdf.fill_color(color)
      @pdf.rectangle([0, bounds.top], bounds.width, bounds.height)
      @pdf.fill
    }
  end

  def pageHeader
    y = @pdf.cursor
    @pdf.image(LOGO_FILE, :at => [0, 720], :height => HEADER_HEIGHT,
               :resize => true)
    @pdf.bounding_box([114,720], :width => 350, :height => HEADER_HEIGHT) {
      fillBounding("ccffcc")
      @pdf.stroke_bounds
      @pdf.text(@title, :align =>:center, :valign => :center, :kerning => true, :size => 16, :style => :bold)
    }
    @pdf.move_cursor_to( y)
  end

  STYLE_ATTRIBUTES = [
    :kerning, :style, :size, :align, :color
  ].to_set
  STYLE_ATTRIBUTES.freeze

  def selectStyles(text)
    result = { :inline_format => true }
    if text.respond_to?(:attributes)
      text.attributes.each { |k,v|
        if STYLE_ATTRIBUTES.include?(k)
          result[k] = v
        end
      }
    end
    result
  end

  def shortOpsText(call, oplist)
    ct = CallsignTools.new
    basecall = ct.callBase(call)
    station = "@" + basecall.to_s
    if oplist and (not oplist.empty?) and (oplist != [ basecall.to_s ]) and (oplist != [ basecall.to_s, station]) and (oplist != [ station, basecall.to_s ]) and (oplist != [ station ] )
      if oplist.include?(call) || oplist.include?(basecall)
        oplist = oplist.clone
        oplist.delete(call)
        oplist.delete(basecall)
        if not oplist.empty?
          return AString.new(" (+ " + oplist.join(",") + ")")
        end
      else
        if oplist.length == 1
          return AString.new(" (" + oplist[0] + " op)")
        else
          return AString.new(" (" + oplist.join(", ") + ")")
        end
      end
    end
    ""
  end

  def footnoteStr(num)
    "<sup><color rgb=\"ff0000\">" + num.to_s + "</color></sup>"
  end

  def longOpsText(callsign, oplist)
    return AString.new(callsign + " ops = " + oplist.join(", "), :style => :italic)
  end

  def processAttributes(text, opts)
    nextLine = nil
    fstr = ""
    if text.respond_to?(:attributes)
      if text.attributes.has_key?(:footnote)
        @footnotes << text.attributes[:footnote]
        fstr = footnoteStr(@footnotes.length)
      end
      if text.attributes.has_key?(:ops)
        opsTxt = shortOpsText(text.to_s, text.attributes[:ops])
        if @pdf.width_of(text.to_s+fstr+opsTxt, :inline_format => true) <= opts[:width]
          text = text.to_s+fstr+opsTxt
        else
          nextLine = longOpsText(text.to_s, text.attributes[:ops])
          text << fstr
          nextLine.attributes.merge!(selectStyles(text))
        end
      else
        text = text.to_s + fstr
      end
    end
    return text, nextLine
  end

  def printLine(text, columnStarts, columnWidths, hdrText=nil)
    nextLine = [ text ]
    while not nextLine.empty?
      text = nextLine.pop
      if @pdf.cursor <=  @baselineskip
        @pdf.start_new_page
        if hdrText
          printLine(hdrText, columnStarts, columnWidths)
        end
      end
      y = @pdf.cursor
      if text.length == columnStarts.length
        text.each_index { |i|
          opts = {:at => [columnStarts[i], y], :width => columnWidths[i]}
          opts.merge!(selectStyles(text[i]))
          textstr, nl = processAttributes(text[i], opts)
          if nl
            nextLine << nl
          end
          oldfill = @pdf.fill_color
          if opts.has_key?(:color)
            @pdf.fill_color(opts[:color])
          end
          @pdf.text_box(textstr, opts)
          if opts.has_key?(:color)
            @pdf.fill_color(oldfill)
          end
        }
        @pdf.move_down (@baselineskip)
      else
        if text.instance_of? Array
          text = text[0]
        end
        @pdf.text(text, selectStyles(text))
      end
    end
  end

  def printGroups(groups)
    @footnotes = [ ]
    first = true
    groups.each { |g|
      if first
        first = false
      else
        @pdf.move_down @baselineskip
      end
      printLine(g.header, g.columnStarts, g.columnWidths)
      g.rows.each { |r|
        printLine(r, g.columnStarts, g.columnWidths, g.header)
      }
    }
    @pdf.move_down @baselineskip
    @legend.each { |l|
      if @pdf.cursor <= 0
        @pdf.start_new_page
#        pageHeader
      end
      @pdf.text(l, :inline_format => true)
    }
    if @footnotes.length > 0
      @pdf.move_down @baselineskip
      @pdf.fill_color "ff0000"
      @footnotes.each_index { |i|
        if @pdf.cursor <= 0
          @pdf.start_new_page
#          pageHeader
        end
        note = @footnotes[i]
        @pdf.text(footnoteStr(i+1) + note, :inline_format => true)
      }
      @pdf.fill_color "000000"
    end
  end

  def render(filename)
    @pdf.render_file filename
  end
end
