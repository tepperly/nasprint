#!/usr/bin/env ruby
# -*- encoding: utf-8; -*-
# 
# Routines for formatting tables with output to plain text, CSV, HTML,
# and eventually PDF.
# 

require_relative 'table'

rc = RowCollection.new
rc << [ "Test", "Column", "Headers" ]
rc << [ "bird", 1, "2" ]
rc << [ "big", MultiColumn.new("black cow", 2) ]
rc << [ MultiColumn.new("moooo..", 2), "cow" ]
rc << [ MultiColumn.new(128, 3) ]
rc << [ 1, 2, 3 ]
print rc.to_s
