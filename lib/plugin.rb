# This Plugin Library requires the Events lib, since that
# is how it announces that a new plugin has been defined.

# Create our plugin events.
create_event :plugin_defined
create_event :plugin_loaded
create_event :plugin_unloaded

class Plugin
 
  def Plugin.init(bot)
    @@bot = bot
  end
 
  def Plugin.load_plugin(plugin_file)
    load plugin_file
    emit_event(:plugin_loaded, plugin_file)
  end

  # All the meta-magic happens here.
  def Plugin.define(name, &block)
    # Set up the name.
    name = name.to_s.capitalize!

    # If it exists already, remove it.
    Object.send(:remove_const, name) rescue nil

    # Create the class with Plugin as the superclass.
    plugin = Object.const_set(name, Class.new(self)).new()

    # Set up the __define__ method with the supplied block,
    # which will be evaluated with instance_eval, which is
    # where the real magic happens.
    plugin.class.send(:define_method, :__define__, &block)

    # Now call the __define__ method to allow all the 
    # defining of the plugin to happen.
    plugin.__define__()

    # Remove the __define__ method to prevent any sort of abuse.
    plugin.class.send(:undef_method, :__define__)

    # Now let the bot know the plugin has been defined so it
    # can do it's part of the deal.
    emit_event(:plugin_defined, plugin)

    # And return the plugin
    return plugin
  end

  def initialize
    @commands    = {}
    @handlers    = {}
    @config_file = self.class.to_s.downcase()
  end

  def config_file(f=nil)
    if f.nil?
      return @config_file
    end
    @config_file = f
    return f
  end

  def irc_format_string(opts={})
    return @@bot.get_format_string(opts)
  end

  def storage_path(file)
    return @@bot.get_storage_path(file)
  end

  def storage_file(file, mode="r", &block)
    @@bot.get_storage_file(file, mode) do |fp|
      block.call(fp) if not fp.nil?
    end
  end

  def ensure_file(file)
    path = @@bot.get_storage_path(file)
    unless File.exists?(path)
      File.open(path, "w") do |fp|
        fp.write("")
      end
    end
    return path
  end

  def name(str="")
    @name ||= str
  end

  def author(str="")
    @author ||= str
  end

  def version(str="")
    @version ||= str
  end

  def config
    # Prevent this from being called outside of the 
    # on_start and on_stop methods.
    meth = direct_caller()
    if meth == "on_start" or meth == "on_stop"
      return @config
    else
      raise PluginError, "config() called outside of the on :start or on :stop blocks!"
    end
  end

  def start(conf)
    @config = conf
    self.on_start()
  end

  def stop
    self.on_stop()
    self.remove_all_handlers()
    self.remove_all_commands()
  end

  # You can override this using: on :start do ... end
  # when defining the plugin.
  # This is only needed if you need to do some more
  # set up when the plugin is started.
  def on_start
    false
  end

  # You can override this using: on :stop do ... end
  # when defining the plugin.
  # Like with on_start, this is only needed if you 
  # have work to do when the plugin is stopped.
  def on_stop
    false
  end

  def on(event, &block)
    name = "on_%s" % Plugin.make_name(event, false)
    self.class.send(:define_method, name, &block)
  end

  def handle(name, &block)
    @handlers[name] = observe_event(name, true) do |evt, event|
      block.call(event)
    end
  end

  def command(name, options = {}, &block)
    name = name.to_sym if name.is_a?(String)
    @commands[name] = @@bot.add_command(self, name, options, &block)
  end

  def remove_handle(name)
    if @handlers.has_key?(name)
      unobserve_event(name, @handlers[name])
      @handlers.delete(name) 
      return true
    end
    return false
  end

  def remove_all_handlers
    @handlers.keys.each {|event| self.remove_handle(event)}
  end

  def remove_command(name)
    @@bot.remove_command(name)
    @commands.delete(name)
  end

  def remove_all_commands
    @commands.keys.each {|cmd| self.remove_command(cmd)}
  end

  def help_for(name)
    name = name.to_sym() if name.is_a?(String)
    if @commands.has_key?(name)
      @commands[name].help = yield
    end
  end

  def helper(name, &block)
    name = Plugin.make_name(name)
    self.class.send(:define_method, name, &block)
  end

  def assign(name, value)
    name = Plugin.make_name(name)
    self.class.send(:define_method, name) { value }
  end

  def to_s(short=true)
    return @name if short
    return "%s -- Author: %s Version: %s" % [@name, @author, @version]
  end

  private

  def Plugin.make_name(name, to_symbol=true)
    name = name.to_s.downcase.gsub(/\s+/, "_")
    return to_symbol ? name.to_sym() : name
  end

end

# This class encapsulates an IRC event to be provided
# to both IRC event handlers and !command handlers.
class PluginEvent
  def initialize(bot, event, is_command=true)
    @bot = bot
    @event = event
    @is_command = is_command
  end

  def reply(msg)
    @bot.reply(@event, msg)
  end

  def action(msg)
    @bot.action(@event, msg)
  end

  def ctcp(msg)
    @bot.ctcp(@event, msg)
  end

  def message
    if @is_command 
      cmd, message = @event.message.split(" ", 2)
      message = "" if message.nil?
      return message
    else
      return @event.message
    end
  end

  def method_missing(name, *args)
    name = name.id2name()
    if @event.respond_to?(name)
      @event.send(name, *args)
    else
      raise NoMethodError, "undefined method `#{name}' for #{self.class}"
    end
  end
end

# Plugin Error Exception
class PluginError < Exception
end
