#!/usr/bin/env ruby

require 'xz'
require 'csv'

class Entity
  def initialize(canonPrefix, name,
                 entityID, continent, 
                 cqZone, ituZone,
                 latitude, longitude, timeadj)
    @canonPrefix = canonPrefix
    @canonPrefix.freeze
    @name = name
    @name.freeze
    @entityID = entityID
    @entityID.freeze
    @continent = continent
    @continent.freeze
    @cqZone = cqZone
    @cqZone.freeze
    @ituZone = ituZone
    @ituZone.freeze
    @latitude = latitude
    @latitude.freeze
    @longitude = longitude
    @longitude.freeze
    @timeadj = timeadj
    @timeadj.freeze
  end

  def createRelated(options = { })
    if options.empty?
      return self
    else
      Entity.new(canonPrefix, name, entityID, 
                 (options.include?(:continent) ? options[:continent] : continent),
                 (options.include?(:cqZone) ? options[:cqZone] : cqZone),
                 (options.include?(:ituZone) ? options[:ituZone] : ituZone),
                 (options.include?(:latitude) ? options[:latitude] : latitude),
                 (options.include?(:longitude) ? options[:longitude] : longitude),
                 (options.include?(:timeadj) ? options[:timeadj] : timeadj))
    end
  end

  attr_reader :canonPrefix, :name, :entityID, :continent, :cqZone,
      :ituZone, :latitude, :longitude, :timeadj
end

class CallPrefix
  def initialize(prefix, entity)
    @prefix = prefix
    @prefix.freeze
    @entity = entity
    @entity.freeze
  end

  def match?(callsign)
    callsign.start_with?(@prefix)
  end

  attr_reader :prefix, :entity

  def <=>(cp)
    cp.prefix.length <=> @prefix.length
  end
end
                 

class CallsignLocator

  def initialize
    if not defined? @@callprefixes
      readRules
      sortRules
    end
  end

  def readRules
    @@exceptions = Hash.new
    @@callprefixes = Hash.new
    XZ::StreamReader.open(File.dirname(__FILE__) + "/cty.csv.xz") { |infile|
      CSV.parse(infile.read(),:col_sep => ',') { |record|
        ent = Entity.new(record[0], record[1], record[2].to_i,
                         record[3].strip.upcase,
                         record[4].to_i, record[5].to_i,
                         record[6].to_f, -record[7].to_f,
                         record[8])
        ent.freeze
        addEntity(ent, record[9])
      }
    }
  end

  def sortRules
    @@callprefixes.each { |key,value|
      value.sort! { |x,y| x <=> y }
    }
  end

  CQZONEOVERRIDE=/\((\d+)\)/
  ITUZONEOVERRIDE=/\[(\d+)\]/
  TIMEOFFSETOVERRIDE=/~([^~]*)~/
  LATLONGOVERRIDE=/<([^\/]*\/([^>]*)>)>/

  def readOverrides(str)
    result = Hash.new
    if CQZONEOVERRIDE =~ str
      result[:cqZone] = $1.to_i
      str.gsub!(CQZONEOVERRIDE,"")
    end
    if ITUZONEOVERRIDE  =~ str
      result[:ituZone] = $1.to_i
      str.gsub!(ITUZONEOVERRIDE, "")
    end
    if TIMEOFFSETOVERRIDE =~ str
      result[:timeadj] = $1.to_f
      str.gsub!(TIMEOFFSETOVERRIDE, "")
    end
    if LATLONGOVERRIDE =~ str
      result[:latitude] = $1.to_f
      result[:longitude] = $2.to_f
      str.gsub!(LATLONGOVERRIDE, "")
    end
    result
  end

  def addEntity(entity, prefixRules)
    prefixRules.split(/[ \t\r\n\f;]+/).each { |item|
      overrides = readOverrides(item)
      ent = entity.createRelated(overrides)
      ent.freeze
      if item.start_with?("=")
        @@exceptions[item[1..-1]] = ent
      else
        key = item[0,1]
        if not @@callprefixes.include?(key)
          @@callprefixes[key] = Array.new
        end
        @@callprefixes[key] << CallPrefix.new(item, ent)
      end
    }
  end

  def lookup(callsign)
    if not callsign.empty?
      if @@exceptions.include?(callsign)
        return @@exceptions[callsign]
      else
        key = callsign[0,1] # first letter
        if @@callprefixes.include?(key)
          @@callprefixes[key].each { |cp|
            if cp.match?(callsign)
              return cp.entity
            end
          }
        end
      end
    end
    nil
  end
end
