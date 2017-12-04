#!/usr/bin/env ruby
require 'prawn'
require 'set'

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
end

class ReportPDF
  LOGO_FILE=File.dirname(__FILE__)+"/images/nccc_generic.png"
  HEADER_HEIGHT=44

  def initialize(title)
    @title = title
    @pdf = Prawn::Document.new(:page_style => "LETTER", :page_layout => :portrait)
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
    @pdf.image(LOGO_FILE, :at => [0, 720], :height => HEADER_HEIGHT,
               :resize => true)
    @pdf.bounding_box([114,720], :width => 350, :height => HEADER_HEIGHT) {
      fillBounding("ccffcc")
      @pdf.stroke_bounds
      @pdf.text(@title, :align =>:center, :valign => :center, :kerning => true, :size => 16, :style => :bold)
    }
    @pdf.move_down 8
  end

  STYLE_ATTRIBUTES = [
    :kerning, :style, :size, :align, :color
  ].to_set
  STYLE_ATTRIBUTES.freeze
  
  def selectStyles(text)
    result = Hash.new
    if text.respond_to?(:attributes)
      text.attributes.each { |k,v|
        if STYLE_ATTRIBUTES.include?(k)
          result[k] = v
        end
      }
    end
    result
  end

  def shortOpsText(str, oplist)
    if oplist and (not oplist.empty?) and (oplist != [ str ])
      if oplist.include?(str)
        oplist = oplist.clone
        oplist.delete(str)
        return " (" + oplist.join(",") + ")"
      else
        if oplist.length == 1
          return " (" + oplist[0] + " op)"
        else
          return " (" + oplist.join(", ") + ")"
        end
      end
    end
    ""
  end

  def longOpsText(callsign, oplist)
    return AString.new(callsign + " ops = " + oplist.join(", "), :style => :italic)
  end

  def processAttributes(text, opts)
    nextLine = nil
    if text.respond_to?(:attributes)
      if text.attributes.has_key?(:ops)
        opsTxt = shortOpsText(text.to_str, text.attributes[:ops])
        if @pdf.width_of(text.to_str+opsTxt) <= opts[:width]
          text = text.to_str+opsTxt
        else
          nextLine = longOpsText(text.to_str, text.attributes[:ops])
        end
      end
    end
    return text, nextLine
  end

  def printLine(text, columnStarts, columnWidths)
    nextLine = [ text ]
    while not nextLine.empty?
      text = nextLine.pop
      if @pdf.cursor <= 0
        @pdf.start_new_page
        pageHeader
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
          @pdf.text_box(textstr, opts)
        }
        @pdf.move_down 16
      else
        if text.instance_of? Array
          text = text[0]
        end
        @pdf.text(text, selectStyles(text))
      end
    end
  end

  def printGroups(groups)
    first = true
    groups.each { |g|
      if first
        first = false
      else
        @pdf.move_down 16
      end
      printLine(g.header, g.columnStarts, g.columnWidths)
      g.rows.each { |r|
        printLine(r, g.columnStarts, g.columnWidths)
      }
    }
  end

  def render(filename)
    @pdf.render_file filename
  end
end
