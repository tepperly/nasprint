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
  DIR=File.dirname(__FILE__) + "/fonts/ttf/"
  LOGO_FILE=File.dirname(__FILE__)+"/images/nccc_generic.png"
  LINEFONT="Intel One Mono"
  HEADINGFONT="Trebuchet MS"
  HEADER_HEIGHT=44
  CA_LEGEND = [
    "1E = One-Day County Expedition",
    "C = <i>Checklog</i>",
    "CL = County-Line Expedition",
    "E = County Expedition",
    "L = Low Power",
    "M = Mobile",
    "M/2 = Multi-Two",
    "M/M = Multi-Multi",
    "M/S = Multi-Single",
    "Q = QRP",
    "YL = Female Operator"
  ]
  NONCA_LEGEND = [
    "C = <i>Checklog</i>",
    "L = Low Power",
    "M = Mobile",
    "M/2 = Multi-Two",
    "M/M = Multi-Multi",
    "M/S = Multi-Single",
    "Q = QRP",
    "YL = Female Operator"
  ]
  CA_LEGEND.freeze
  NONCA_LEGEND.freeze

  def initialize(title, legend=CA_LEGEND)
    @title = title
    @legend = legend
    @pdf = Prawn::Document.new(page_style: "LETTER", page_layout: :portrait,
                               top_margin: 95,
                               info: {
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
                                 :bold_italic => "/usr/share/fonts/truetype/msttcorefonts/Verdana_Bold_Italic.ttf"
                               })
    @pdf.font_families.update( "Arial" => {
                                 :normal => "/usr/share/fonts/truetype/msttcorefonts/Arial.ttf",
                                 :black => "/usr/share/fonts/truetype/msttcorefonts/Arial_Black.ttf",
                                 :bold => "/usr/share/fonts/truetype/msttcorefonts/Arial_Bold.ttf",
                                 :italic => "/usr/share/fonts/truetype/msttcorefonts/Arial_Italic.ttf",
                                 :bold_italic => "/usr/share/fonts/truetype/msttcorefonts/Arial_Bold_Italic.ttf"
                               })
    @pdf.font_families.update( "Trebuchet MS" => {
                                 :normal => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS.ttf",
                                 :bold => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Bold.ttf",
                                 :italic => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Italic.ttf",
                                 :bold_italic => "/usr/share/fonts/truetype/msttcorefonts/Trebuchet_MS_Bold_Italic.ttf"
                               })
    @pdf.font_families.update("Intel One Mono" => {
         			:normal => DIR+"IntelOneMono-Regular.ttf",
         			:bold => DIR+"IntelOneMono-Bold.ttf",
         			:italic => DIR+"IntelOneMono-Italic.ttf",
         			:bold_italic => DIR+"IntelOneMono-BoldItalic.ttf"})
    #    @pdf.font "Trebuchet MS"
    @pdf.font LINEFONT
    @pdf.font_size 12
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
    @pdf.image(LOGO_FILE, at: [0, 720], height: HEADER_HEIGHT,
               resize: true)
    @pdf.bounding_box([114,720], width: 350, height: HEADER_HEIGHT) {
      fillBounding("ccffcc")
      @pdf.stroke_bounds
      @pdf.font HEADINGFONT
      @pdf.text(@title, align: :center, valign: :center, kerning: true, size: 16, style: :bold)
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
          if ((oplist.length == 1) and (oplist[0].start_with?("@")))
            return AString.new(" (" + oplist[0] +")")
          else
            return AString.new(" (+ " + oplist.join(", ") + ")")
          end
        end
      else
        if (oplist.length == 1) and (not oplist[0].start_with?("@"))
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
    return AString.new(callsign + " ops = " + oplist.join(", "), style: :italic)
  end

  def extractLocation(list)
    list.each { |str|
      if (str.start_with?("@"))
        return str
      end
    }
    nil
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
        if @pdf.width_of(text.to_s+fstr+opsTxt, inline_format: true) <= opts[:width]
          text = text.to_s+fstr+opsTxt
        else
          stationLocation = extractLocation(text.attributes[:ops])
          textStyles = selectStyles(text)
          if (stationLocation)
            nextLine = longOpsText(text.to_s, text.attributes[:ops] - [ stationLocation ])
            text << shortOpsText(text.to_s, [ stationLocation ]) << fstr
          else
            nextLine = longOpsText(text.to_s, text.attributes[:ops])
            text << fstr
          end
          nextLine.attributes.merge!(textStyles)
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
      if @pdf.cursor <=  @baselineskip*1.25
        @pdf.start_new_page
        if hdrText
          @pdf.font HEADINGFONT
          @pdf.font_size 12
          printLine(hdrText, columnStarts, columnWidths)
          @pdf.font LINEFONT
          @pdf.font_size 12
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
      @pdf.font HEADINGFONT
      @pdf.font_size 12
      printLine(g.header, g.columnStarts, g.columnWidths)
      @pdf.font LINEFONT
      @pdf.font_size 12
      g.rows.each { |r|
        printLine(r, g.columnStarts, g.columnWidths, g.header)
      }
    }
    @pdf.move_down @baselineskip
    @pdf.font HEADINGFONT
    @pdf.font_size 12
    @legend.each { |l|
      if @pdf.cursor <= 0
        @pdf.start_new_page
#        pageHeader
      end
      @pdf.text(l, inline_format: true)
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
        @pdf.text(footnoteStr(i+1) + note, inline_format: true)
      }
      @pdf.fill_color "000000"
    end
  end

  def render(filename)
    @pdf.render_file filename
  end
end
