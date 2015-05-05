#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
# Make SSB Sprint report
# By Tom Epperly
# ns6t@arrl.net

require 'set'
require_relative 'ContestDB'

MULTIPLIERS_BY_CALLAREA = {
  "0" => [ "ND", "SD", "NE", "CO", "KS", "MO", "IA", "MN"].to_set,
  "1" => [ "ME", "VT", "NH", "MA", "CT", "RI", "VT" ].to_set,
  "2" => [ "NY", "NJ" ].to_set,
  "3" => [ "PA", "DE", "DC", "MD" ].to_set,
  "4" => [ "KY", "VA", "TN", "NC", "SC", "AL", "GA", "FL" ].to_set,
  "5" => [ "NM", "TX", "OK", "AR", "LA", "MS" ].to_set,
  "6" => [ "CA" ].to_set,
  "7" => [ "AZ", "UT", "NV", "WY", "WA", "OR", "ID", "MT" ].to_set,
  "8" => [ "MI", "OH", "WV" ].to_set,
  "9" => [ "WI", "IL", "IN" ].to_set,
  "KH6" => [ "HI" ].to_set,
  "KL7" => [ "AK" ].to_set,
  "VE1" => [ "NS" ].to_set,     # Nova Scotia
  "VE2" => [ "QC" ].to_set,     # Quebec
  "VE3" => [ "ON" ].to_set,     # Ontario
  "VE4" => [ "MB" ].to_set,     # Manitoba
  "VE5" => [ "SK" ].to_set,     # Saskatchewan
  "VE6" => [ "AB" ].to_set,     # Alberta
  "VE7" => [ "BC" ].to_set,     # British Columbia
  "VE8" => [ "NT" ].to_set,     # Northwest Territories
  "VE9" => [ "NB" ].to_set,     # New Brunswick
  "VO1" => [ "NF" ].to_set,     # Newfoundland
  "VO2" => [ "LB" ].to_set,     # Labrador
  "VY0" => [ "NU" ].to_set,     # Nunavut
  "VY1" => [ "YT" ].to_set,     # Yukon Territory
  "VY2" => [ "PE" ].to_set      # Prince Edward Island
}
MULTIPLIERS_BY_CALLAREA.freeze

total = Set.new
MULTIPLIERS_BY_CALLAREA.each { |key, value|
  if total.intersect?(value)
    print "#{key} has a duplicate entry: #{total & value}\n"
  end
  total.merge(value)
}
print "Total of multipliers: #{total.size}\n"

