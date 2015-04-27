#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
#
# Validate and cross match QSOs
#
require 'set'

class NameCompare
  def initialize(db)
    res = db.query("select name1, name2 from Homophone;")
    @homophones = Hash.new(Set.new)
    res.each(:as => :array) { |row|
      r0 = row[0].upcase
      r1 = row[1].upcase
      if r0 != r1
        addEntry(r0, r1)
        addEntry(r1, r0)
      end
    }
  end

  def addEntry(r0, r1)
    if not @homophones.has_key?(r0)
      @homophones[r0] = Set.new
    end
    @homophones[r0].add(r1)
  end

  def namesEqual?(name1, name2)
    name1 = name1.upcase
    name2 = name2.upcase
    return ((name1 == name2) or @homophones[name1].include?(name2) or
            @homophones[name2].include?(name2))
  end
end
