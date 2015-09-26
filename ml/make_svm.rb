#!/usr/bin/env ruby

require 'csv'

LABELS = { "Yes" => 1, "No" => 0 }.freeze

def writeTraining(data, filename)
  open(filename, "w:ascii") { |out|
    data.each { |row|
      out.write(LABELS[row[13]])
      row[2,11].each_with_index { |value, index|
        out.write(" " + (index+1).to_s + ":" + value.to_s)
      }
      out.write("\n")
    }
  }
end

all_data = Array.new
yes_data = Array.new
no_data = Array.new
ARGV.each { |arg|
  CSV.foreach(arg) { |row|
    all_data << row
    if row[-1] == "Yes"
      yes_data << row
    else
      no_data << row
    end
  }
}

print "#{yes_data.length} matches\n#{no_data.length} unmatched\n"

writeTraining(all_data, "test_svm.in")
