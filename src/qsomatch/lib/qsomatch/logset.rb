#!/usr/bin/env ruby

class LogSet
  def initialize(list)
    @logs = list.map { |i| i.to_i }
    @isContiguous, @min, @max = testContiguous
  end

  def testContiguous
    sum = 0
    max = nil
    min = nil
    @logs.each { |i|
      if max.nil? or i > max
        max = i
      end
      if min.nil? or i < min
        min = i
      end
      sum += i
    }
    return ((not (min.nil? or max.nil?)) and
            (sum == (max*(max+1)/2 - min*(min-1)/2))), min, max
    
  end

  def membertest(id)
    if @isContiguous
      return "(" + id + " between " + @min.to_s + " and " + @max.to_s + ")"
    else
      if not (@min.nil? or @max.nil?)
        return "(" + id + " in (" + @logs.join(", ") + "))"
      else
        # no logs
        return "(" + id + " < -10000)"
      end
    end
  end

  attr_reader :logs

end

