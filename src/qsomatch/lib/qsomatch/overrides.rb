#!/usr/bin/env ruby
# -*- encoding: utf-8 -*-
require 'yaml'

class Overrides
  @@override_files = Hash.new

  def initialize(filename)
    if @@override_files.has_key?(filename)
      @yml = @@override_files[filename]
    else
      if File.exists?(filename)
        @yml = YAML.load_file(filename)
        @yml.freeze
      else
        @yml = { }
        @yml.freeze
      end
      @@override_files[filename] = @yml
    end
  end

  def lookupEntity(callsign)
    if @yml.has_key?("callsigns")
      callOverrides=@yml["callsigns"]
      if callOverrides.has_key?(callsign) and callOverrides[callsign].has_key?("entity")
        return callOverrides[callsign]["entity"].to_i
      end
    end
    nil
  end

  def lookupMultiplier(callsign)
    if @yml.has_key?("callsigns")
      callOverrides=@yml["callsigns"]
      if callOverrides.has_key?(callsign) and callOverrides[callsign].has_key?("multiplier")
        return callOverrides[callsign]["multiplier"]
      end
    end
    nil
  end
end
