#!/usr/bin/env
require 'set'
require_relative 'callsign'
require_relative 'pdfreport'

class ReportLaTeX
  EOL="\r\n"

  def initialize(title, subtitle, filename, legend=ReportPDF::CA_LEGEND)
    @title = title
    @ct = CallsignTools.new
    @subtitle = subtitle
    @filename = filename
    @legend = legend
    @output = createHeader(title, filename)
  end

  def createHeader(title, filename)
    out = open(filename, "w")
    out.write(LATEX_HEADER)
    return out
  end

  def finishFile
    @output.write(LATEX_FOOTER)
  end

  def startGroup(g)
    @output.write("\\CQPGroup{#{g.header[0]}}#{EOL}")
  end

  COLOR_MAPPING = {
    "000000" => "black",
    "ff0000" => "red"
  }.freeze

  def gleanMetadata(row)
    operator=""
    footnote=""
    color="black"
    row.each { |field|
      if field.respond_to?(:attributes)
        if field.attributes.has_key?(:ops)
          operator = field.attributes[:ops]
        end
        if field.attributes.has_key?(:color)
          color = COLOR_MAPPING[field.attributes[:color]]
        end
        if field.attributes.has_key?(:footnote)
          footnote=field.attributes[:footnote]
        end
      end
    }
    return operator, footnote, color
  end

  def shortOpsText(call, oplist)
    basecall = @ct.callBase(call)
    station = "@" + basecall.to_s
    if oplist and (not oplist.empty?) and (oplist != [ basecall.to_s ]) and (oplist != [ basecall.to_s, station]) and (oplist != [ station, basecall.to_s ]) and (oplist != [ station ] )
      if oplist.include?(call) || oplist.include?(basecall)
        oplist = oplist.clone
        oplist.delete(call)
        oplist.delete(basecall)
        if not oplist.empty?
          if ((oplist.length == 1) and (oplist[0].start_with?("@")))
            return "(" + oplist[0] +")"
          else
            return "(+ " + oplist.join(", ") + ")"
          end
        end
      else
        if (oplist.length == 1) and (not oplist[0].start_with?("@"))
          return "(" + oplist[0] + " op)"
        else
          return "(" + oplist.join(", ") + ")"
        end
      end
    end
    ""
  end

  def longOpsText(call, oplist)
    oplist.join(", ")
  end

  def printEntrant(row)
    operator, footnote, color = gleanMetadata(row)
    opArray = operator.kind_of?(Array)
    basicInfo = (row.map { |str| "{" + str + "}"}).join("")
    longOpText = "{"  + (opArray ? longOpsText(row[0], operator) : operator) + "}"
    footText = "{" + footnote + "}"
    @output.write("\\LineScore" + basicInfo + longOpText + footText + EOL)
  end

  def printGroups(groups)
    groups.each { |g|
      startGroup(g)
      g.rows.each { |row|
        printEntrant(row)
      }
    }
  end

  LATEX_HEADER = "\\documentclass{minimal}#{EOL}\
\\usepackage{cqpformat}#{EOL}\
\\begin{document}#{EOL}\
\\begin{CQPLineScores}#{EOL}\
"

  LATEX_FOOTER = "\\end{CQPLineScores}#{EOL}\
\\end{document}#{EOL}"

end
