# Simple Config class module.
#
# Released into the Public Domain.
#
# This module defines a simple, but very powerful config file 
# reader/writer. Though not quite as poweful as YAML, this uses
# simpler config files that are human readable and editable.
# Config files consist of 'key = value' pairs, with the special 
# exception of keys that start with an '*' symbol; keys of this 
# sort have their values added to an array under that key name. 
#
# The Config class is a sub-class of the Hash class, so 
# inherits all of it's methods.
#
# Example config:
# server = my.server.com
# port = 8080
# *plugin = plugin1
# *plugin = plugin2
#
# Comments in the config file start with a # and go to the end 
# of the line.
#
# Values of "true", "yes", and "on" are converted to boolean 
# true. Values of "false", "no", and "off" are converted to
# boolean false values. Values of "nil", "null", "none" are
# converted to nil values. The reverse of these values will be
# saved as "true", "false", and "null" respectively.
#
# The Config class, when given the config file, will read and 
# parse the file and presents several static and dynamic
# methods for getting and setting data values.
#
# To instantiate a Config instance:
#
#   require "config"
#   conf = Config::Config.new(config_file_path)
#
# The new() method takes a second, optional argument, which if
# it is false, will -not- read the file upon object creation. A
# later called to the read() method will then read the file; the 
# default is for the file to be read and parsed when the object
# is created.
#
# Values can be read using the following ways:
#
# get(key[, value]) -- which takes the key name, and a second, 
# optional default value if the key name is not set.
#   conf.get("key_name")
#   conf.get("key_name", "default value")
#
# [key] -- simply takes the key name; if there is no value for the
# key, then nil is returned.
#   conf["key_name"]
#
# <key_name>() -- the key name can be used as a method name to
# obtain the value, and if given an argument, it becomes the
# default value if there is no value for the given key. If no
# argument is given, and the key does not exist, nil is returned.
#  conf.key_name()
#  conf.key_name("default value")
#
# Values can be written using the following ways:
#
# set(key, value) -- sets the key to value.
#
# [key] = value  -- ...does likewise.
#
# set_<key_name>(value) -- Sets the key to value.
#
# Examples:
#
#  conf.get("server", "localhost")
#  conf["server"]
#  conf.server()
#  conf.server("localhost")
#  conf.set("server", "new.server.com")
#  conf["server"] = "new.server.com")
#  conf.set_server("new.server.com")
#
# You can use save() to write the current config object back to
# the given file.
#
# Calling dump() dumps the config to stdout in a nice, but config
# file incompatible, way.
#
# You can set a new file to save to using new_file(filename), and
# if given a second, optional argument of true, will save the file
# right away, otherwise, you will have to invoke the save() method
# manually. Default is to -not- save the file when called. This 
# method returns the old config filename.

module Config

  class ConfigError < Exception
  end

  class Config

    def initialize(conf_file=nil, do_open_now=true)
      @file = conf_file
      @config = {}
      @has_read = false

      @on_disk = (@file and File.exists?(@file)) ? true : false

      self.open() if do_open_now
    end

    def on_disk?
      return @on_disk
    end

    def has_read?
      return @has_read
    end

    def new_file(new_file, do_save=false)
      old_file = @file
      @file = new_file
      self.save() if do_save
      return old_file
    end

    def open!
      if not @on_disk
        raise ConfigError, "#{@file} does not exist!"
      end
      self.open()
    end

    def open
      return if not @on_disk

      File.open(@file, "r") do |f|
        f.each_line do |line|
          is_string = false
          line.strip!

          # Skip blank lines and comments.
          next if line == "" or line[0].chr == "#"

          key, value = line.split("=", 2)
          key.strip!
          value.strip!

          # Detect if we have a string, and if so, then strip 
          # leading and ending single and double quotes.
          match_obj = value.match(/^(["'])(.*?)(\1)$/)
          if match_obj
            is_string = true
            value = match_obj.captures[1]
          end

          # If not a string, convert boolean values
          if not is_string
            case value.downcase
            when "true", "yes", "on"
              value = true
            when "false", "no", "off"
              value = false
            when "nil", "null", "none"
              value = nil
            end
          end

          # Handle list config options
          if key[0].chr == "*"
            key = key[1..-1]
            @config[key] = [] if not @config.key?(key)
            @config[key].push(value)
          else
            @config[key] = value
          end
          
        end
      end

      @has_read = true

      return self
    end

    def reload
      @config = {}
      self.open()
      return self
    end

    def save

      lines_wrote = 0

      begin
        File.open(@file, "w") do |f|
          @config.keys.sort.each do |k|
            if @config[k].class == Array
              @config[k].each do |value|
                f.write("*#{k} = #{convert_value(value)}\n")
              end
            else
              f.write("#{k} = #{convert_value(@config[k])}\n")
            end
            lines_wrote += 1
          end
        end
      rescue Exception => errmsg
        raise ConfigError, "Error saving config (#{@file}): #{Exception.to_s} -> #{errmsg}"
      end

      @on_disk = true

      return lines_wrote
    end

    def get(key, default=nil)
      if key.class == Symbol
        key = key.to_s
      end
      return @config[key] if @config.key?(key)
      return default
    end

    def set(key, value=nil)
      if key.class == Symbol
        key = key.to_s
      end
      @config[key] = value
    end

    def dump
      @config.keys.sort.each do |key|
        if @config[key].class == Array
          puts "#{key} = \n  #{@config[key].collect{|v| convert_value(v) }.join("\n  ")}"
        else
          puts "#{key} = #{convert_value(@config[key])}"
        end
      end
    end

    private

    def convert_value(value)
      case value
      when true
        return "true"
      when false
        return "false"
      when nil
        return "null"
      else
        return value
      end
    end

    def method_missing(method_id, *args)
      name = method_id.id2name
      return set(name[4..-1], *args) if name[0..3] == "set_"
      return get(name, *args)
    end

  # End Class
  end

# End Module
end
