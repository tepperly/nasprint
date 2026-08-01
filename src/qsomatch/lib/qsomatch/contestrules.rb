#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Contest rules that are a function of the year of the contest should
# go here.


class ContestRules

  def points_per_phone
    if not defined? $year or $year.nil? or $year < 2013 or $year > Time.now.year
      fail "This ruby module cannot be loaded until the global $year is defined with a reasonable value"
    end
    ($year >= 2026) ? 3 : 2
  end

  def points_per_cw
    3
  end
end
