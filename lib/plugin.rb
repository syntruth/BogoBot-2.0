# Holds the Plugin logic. 
#
# Any plugin _should_ subclass the PluginBase class and 
# override the initialize() and start() methods; not doing so
# will raise a PluginError exception.
module Plugin

  # Handles a plugin's errors.
  class PluginError < Exception
  end

  class PluginBase

    attr :config_file
    attr :name
    attr :author
    attr :version

    # Override this!
    # The plugin's initialize method should do any _non connected_ setup
    # work.
    def initialize()
      raise PluginError, "You must override Plugin::PluginBase#initialize()!"
    end

    # Override this!
    # The plugin's start method will be passed the bot instance and a
    # Config::Config instance. The config object might not actually be a
    # opened and read file if the config file did not exist, but will be
    # assigned a filepath none the less.
    # This method is where you call the add_command and add_handler bot
    # methods.
    def start(*args)
      raise PluginError, "You must override Plugin::PluginBase#start()!"
    end

    # This method does not need to exist, but if it does, it will
    # be called when the plugin is unloaded.
    def stop
      # nop
    end

    # The following methods SHOULD NOT be overridden!

    # Used to specify a different config file if the default config
    # file is undesired. The default is the plugin's lowerclassed
    # name with a ".conf" extension. If called without arguments,
    # it returns the config file name.
    def config_file(cf=nil)
      if cf.nil?
        if @config_file.nil?
          return self.class.to_s.downcase()
        else
          return @config_file
        end
      end
      @config_file = cf
      return self
    end

    def author(a=nil)
      return @author if a.nil?
      @author = a
    end

    def name(n=nil)
      return @name if n.nil?
      @name = n
    end

    def version(v=nil)
      return @version if v.nil?
      @version = v
    end

    # Returns the plugin's information; if short is true, then only
    # returns the plugin's name.
    def to_s(short=true)
      return @name if short
      return "%s -- Author: %s Version: %s" % [@name, @author, @version]
    end


  end

end

