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

  def getSingletons
    if @yml.has_key?("singletons")
      return @yml["singletons"]
    else
      return Array.new
    end
  end

  def lookupScoreOverrides
    if @yml.has_key?("score_overrides")
      return @yml["score_overrides"]
    else
      return Hash.new
    end
  end

  def lookupChecklogs
    results = [ ]
    if @yml.has_key?("callsigns")
      callOverrides=@yml["callsigns"]
      callOverrides.each_pair { |callsign, properties|
        if properties.has_key?("checklog") and properties["checklog"]
          results << callsign
        end
      }
    end
    return results
  end
end
