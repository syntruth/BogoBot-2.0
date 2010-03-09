#!/usr/bin/env ruby

require "rubygems"

# Ensure our local paths are loaded first.
$LOAD_PATH.insert(0, "./lib")

# Ruby libs
require "daemons"
require "English"
require "getoptlong"
require "logger"
require "pathname"
require "md5"

# Local libs
require 'lib/init'

BOT_VERSION = "2.0.1"

pwd = Dir.pwd()

# Set our local paths for bot/plugin/storage files.
CONFIG_DIR = File.join(pwd, "conf")
LOG_DIR    = File.join(pwd, "logs")
PLUGIN_DIR = File.join(pwd, "plugins")
STORE_DIR  = File.join(pwd, "store")

# Usage text.
USAGE = <<EOF

%s <options>

-c, --config=
  Specifies the config file to use for the bot. Defaults to 'default.conf'. 
  You do not need to put the '.conf' on the end.
  Config must be in #{CONFIG_DIR}. 

-d, --daemon
  Puts the Bot into the background. The default is to not daemonize the bot.

-h, --help
  Prints the help text.  You are reading this now. ;)

EOF

# The main Bot class. 
class BogoBot < IRC

  # Include IRC Text formatting methods.
  include IRCTextUtil

  attr_reader :log

  # This configures most of the bot but does _not_ connect
  # the bot to the server specified. (See connect() for that.)
  # Two optional parameters:
  # :config_file:  The bot's configuration file, defaults to
  #                conf/default.conf -- see that file for 
  #                details of settings.
  # :do_debug:     This turns on debug output for the bot and 
  #                any plugins that call the debug() method.
  #                If the bot is daemonized, the debug messages
  #                are saved to the bot's log file specified
  #                in the config, which is log/bogobot.log by
  #                default.
  def initialize(config_file="default.conf", do_debug=false)
    @do_debug = do_debug

    config_file += ".conf" if not config_file.end_with?(".conf")
    config_file = File.join(CONFIG_DIR, config_file)
    
    begin
      @config = Config::Config.new(config_file)
    rescue Config::ConfigError => err
      self.error("!!!   Error with config   !!!\n")
      raise
    end

    # Holds the bot command map.
    @commands = {}

    # Get our command sigil(s), which defaults to bang. "!"
    # You can have more than one sigil.
    @command_tokens = @config.get("command", "!").gsub(/\s+/, "").split(//)

    # Get our list of plugins to load.
    # Defaults to an empty list.
    @plugins = @config.get("plugin", [])

    # Holds information on the loaded plugins.
    @plugins_loaded = {}

    # Get our owners. There has to be at least ONE owner
    # in the configuration file, or else the bot will exit.
    # Owners are given in the following format:
    #  nick:md5_password
    # ...where nick is the nick the owner will have and the
    # password is a md5'd password. This is weak security, I
    # know, but will address in the future.
    @owners = {}
    all_owners = @config.get("owner", [])

    # Split each owners entry into a nick and password, and 
    # if the password is not 32-characters long, do not 
    # include that owner.
    all_owners.each do |owner|
      nick, pw = owner.split(/\:/, 2)
      if pw.length != 32
        self.error "#{nick} password is not md5. Not added."
        next
      end
      @owners[nick] = Owner.new(nick, pw)
    end

    # If we have no owners, this is not good, so we panic
    # and exit!
    if @owners.empty?
      self.error "There are no owners in #{config_file} or " + 
        "there is an issue with their password!"
    end

    # Set our required parameters to get connected...
    @nick = @config.get("nick", "BogoBot")
    @server = @config.get("server")
    @port = @config.get("port", "6667")
    @realname = @nick

    # ...and then call our superclass constructor.
    super(@nick, @server, @port, @realname)

    # Our own IRC event handlers.

    # Chat mesages.
    ['pubmsg', 'privmsg'].each do |type|
      IRCEvent.add_handler(type) do |event|
        on_message(event)
        true
      end
    end

    # Nick change events.
    IRCEvent.add_handler('nick') do |event|
      on_nick(event)
      true
    end

    # These two are odd; it's sort of a hack to know when it's
    # safe to join channels.
    # TODO: see if there is a more common way of knowing when it's
    # okay to join channels.
    IRCEvent.add_handler('endofmotd') do |event|
      do_auto_joins()
      true
    end

    IRCEvent.add_handler('nomotd') do |event|
      do_auto_joins()
      true
    end

    ######################
    # Built-in Commands. #
    ######################

    # Owner Only Commands
    add_command(self, "quit", true, false,
      "Makes the bot quit.") do |bot, event|
      do_quit(event)
    end

    add_command(self, "join", true, false,
      "{cmd}join <channel> -- Makes the bot join a channel.") do |bot, event|
      do_join(event)
    end

    add_command(self, "part", true, false,
      "{cmd}part <channel> -- Makes the bot leave a channel.") do |bot, event|
      do_part(event)
    end

    add_command(self, "alias", true, false,
      "{cmd}alias <command> <old> [<new>] -- " + 
      "Adds or removes a command alias. The command can be " + 
      "either 'add' or 'remove'. Do not put the command token on " + 
      "the old or new command strings.") do |bot, event|
      do_command_alias(event)
    end

    add_command(self, "load", true, false,
      "{cmd}load <plugin> -- Loads a plugin.") do |bot, event|
      do_load_plugin(event)
    end

    add_command(self, "unload", true, false,
      "{cmd}unload <plugin> -- Unloads a plugin.") do |bot, event|
      do_unload_plugin(event)
    end

    add_command(self, "reload", true, false,
      "{cmd}reload <plugin> -- Reloads a plugin.") do |bot, event|
      do_reload_plugin(event)
    end

    add_command(self, "plugins", true, false,
      "{cmd}list [brief]-- Lists loaded plugins. " + 
      "If 'brief' is true, a brief list is given.") do |bot, event|
      do_list_plugins(event)
    end

    # Public Commands
    add_command(self, "list", false, false, "Lists commands.") do |bot, event|
      do_command_list(event)
    end

    add_command(self, "owner", false, true,
      "Owners commands, private message only.") do |bot, event|
      do_owner_cmd(event)
    end

    add_command(self, "owners", false, false, "Lists owners.") do |bot, event|
      do_owner_list(event)
    end

    add_command(self, "help", false, false,
      "{cmd}help <command> -- Shows help for command") do |bot, event|
      do_help(event)
    end
    
    add_command(self, "version", false, false,
      "{cmd}version -- Shows the bot's version.") do |bot, event|
      do_version(event)
    end

    # Okay, we're configured and ready to go. Add ourselves 
    # to the kernel so that the register_* methods will work.
    set_bot(self)

  end

  # This loads all plugins given in the configuration file and then 
  # opens up the log files, before calling the superclass method to
  # do the actual connection.
  def connect
    # Load our plugins.
    @plugins.each do |p|
      load_plugin(p)
    end

    log_file = File.join(LOG_DIR, @config.get("log", "bogobot.log"))
    @log = Logger.new(log_file)
    @log.level = @do_debug ? Logger::DEBUG : Logger::WARN
    super()
  end

  # If @log is available, sends the message passed there,
  # else outputs to $strerr.
  def error(msg)
    if @log.nil?
      $stderr.write(msg + "\n")
    else
      @log.error(msg)
    end
  end

  # If @log is available, sends the message passed there,
  # else outputs to $stdout. ONLY if set to debug mode!
  def debug(msg="")
    return if not @do_debug
    if @log.nil?
      $stdout.write(msg + "\n")
    else
      @log.debug(msg)
    end
  end

  # This handles adding !commands to the bot. Plugins _must_
  # pass themselves as the first argument; this is used to keep
  # track of plugin's commands. The bot passes itself, but has
  # no affect.
  # Parameters:
  # :cmd_str:    This is the requested string for the command,
  #              which has to be at least 2 characters long. Do not
  #              prepent a command sigil on the string. There is 
  #              _no_ check on if the command string is already
  #              set for another command. (XXX Fix this, actually.)
  # :owner_only: A boolean value; if true, then only bot owners can
  #              call this command.
  # :help:       A string that will be used when the help command is
  #              called for this command.
  # You have to pass a block of code for your command to this method.
  # The block will be passed |bot, event| as arguements. The bot is,
  # of course, the instance of the bot, while event is the irc event
  # that triggered the command.
  def add_command(plugin, cmd_str, owner_only, is_priv, help, &block)
    plugin_name = plugin.class.to_s.downcase()
    
    # Handle plugin commands so they can be removed later.
    if plugin != self
      if @plugins_loaded.has_key?(plugin_name)
        @plugins_loaded[plugin_name][:commands].push(cmd_str)
      else
        self.error("add_command given an unknown plugin: #{plugin_name}")
        return
      end
    end

    if cmd_str.length >= 2
      @commands[cmd_str] = UserCommand.new(owner_only, help, is_priv, block)
    else
      self.error("Command #{cmd_str} is less than 2 characters long.")
    end
  end

  # This method is used to add an IRC event handler. Plugins _must_
  # pass themselves as the first argument; this is used to keep
  # track of the plugin's handlers. the bot passes itself, but has
  # no affect.
  # Parameters:
  # :event_type:  This is either a string or symbol for the irc event
  #               that is being requrested to be handled, such as 
  #               :privmsg or :nick. See lib/irc/eventmap.yml for all
  #               known events. This argument may also be an array of
  #               irc events that will be handled by the same code.
  #               :privmsg events that are sent to a channel are set to
  #               :pubmsg for event_type, and CTCP events are set to
  #               their CTCP type, such as :action.
  # You must pass a block to this method, which will be passed 
  # |bot, event| as arguments. The event will be the one being handled.
  def add_handler(plugin, event_type, &handler)
    plugin_name = plugin.class.to_s.downcase()

    if event_type.is_a?(Array)
      events = event_type.collect { |event| event.to_s.downcase() }
    else
      events = event_type.to_s.downcase.to_a()
    end

    if @plugins_loaded.has_key?(plugin_name)
      events.each do |event|

        if not @plugins_loaded[plugin_name][:handlers].has_key?(event)
          @plugins_loaded[plugin_name][:handlers][event] = []
        end

        @plugins_loaded[plugin_name][:handlers][event].push(handler)

        IRCEvent.add_handler(event) do |e|
          handler.call(e)
        end
      end
    else
      bot.error "add_handler given an unknown plugin: #{plugin_name}"
    end
  end

  # Removes a command for a given command string. Do not put the
  # command token on the passed string.
  def remove_command(cmd_str)
    @commands.delete(cmd_str) if @commands.has_key?(cmd_str)
  end

  # Removes all of a given plugin's commands. Used for unloading
  # a plugin.
  # Parameters:
  # :plugin:  The plugin instance who's commands are to be removed.
  def remove_plugin_commands(plugin)
    plugin_name = plugin.class.to_s.downcase()
    if @plugins_loaded.has_key?(plugin_name)
      @plugins_loaded[plugin_name][:commands].each do |cmd_str|
        self.remove_command(cmd_str)
      end
      @plugins_loaded[plugin_name][:commands].clear()
    end
  end

  # Remove a handler for a given event.
  # Parameters:
  # :event_type: The string/symbol irc event.
  # :handler:    This is the block object that was passed to 
  #              add_handler() -- so if you anticipate removing a
  #              handler, make sure you make a reference to it, since
  #              this will use the id's to compare.
  #              XXX: Um, how is a plugin to do this? Must revisit this.
  def remove_handler(event_type, handler)
    IRCEvent.remove_handler(event_type, handler)
  end

  # Removes all of a plugin's event handlers for a given plugin.
  # User for unloading a plugin.
  # Parameters:
  # :plugin: The plugin's instance.
  def remove_plugin_handlers(plugin)
    plugin_name = plugin.class.to_s.downcase()

    if @plugins_loaded.has_key?(plugin_name)
      @plugins_loaded[plugin_name][:handlers].each do |event_type, handlers|
        handlers.each do |handler|
          self.remove_handler(event_type, handler)
        end
      end
      @plugins_loaded[plugin_name][:handlers].clear()
    end
  end

  # Joins all channels specified in the bot's config file.
  def do_auto_joins()
    self.debug("Auto Joining Channels.")
    channels = @config.get("channel", [])
    if channels and channels.is_a?(Array)
      channels.each do |chan|
        self.debug("    Joining: #{chan}")
        add_channel(chan)
      end
    end
    return
  end

  # Handles aliasing a command from within IRC.
  def do_command_alias(event)
    cmd = nil
    cmdstr = @command_tokens.first()
    parts = parse_message(event).split(/\s/)

    case parts.length()
    when 1
      cmd = parts.first()
    when 2
      cmd = parts.first()
      args = parts.last()
    when 3
      cmd = parts.first()
      args = parts[1..-1]
    end

    case cmd
    when "add"
      old = args.first()
      new = args.last()
      if @commands.has_key?(old)
        @commands[new] = @commands[old].dup()
        @commands[new].alias_for(old)
        msg = "Notice: #{cmdstr}#{old} has been aliased to #{cmdstr}#{new}"
      else
        msg = "No command known as: #{cmdstr}#{old}"
      end

    when "remove"
      old = args.first()
      if @commands.has_key?(old)
        if @commands[old].is_alias?
          @commands.delete(old)
          msg = "Notice: #{cmdstr}#{old} has been removed."
        else
          msg = "Notice: #{cmdstr}#{old} is not an alias."
        end
      end

    else
      msg = "Unknown alias command. For help, use #{cmdstr}help alias"
    end

    reply(event, msg)
  end

  def do_command_list(event)
    cmd_list = @commands.keys.sort.collect do |key|
      if @commands[key].is_alias?
        "#{key} (alias for: #{@commands[key].alias_for()})"
      else
        key
      end
    end
    reply(event, "Commands:  #{cmd_list.join(", ")}")
  end

  def do_help(event)
    topic = parse_message(event).strip()

    topic = "help" if topic.empty?

    if @commands.key?(topic)
      msg = @commands[topic].help(@nick, @command_tokens.first())

      if @commands[topic].is_alias?
        msg += " (Alias for #{@commands[topic].alias_for()})"
      end

      if @commands[topic].owner_only
        msg += " (Owner Command Only)"
      end
    else
      msg = "No help found for: #{topic}."
    end

    reply(event, msg)
  end

  def do_join(event)
    channel = parse_message(event).strip()
    channel = "#" + channel if "#&+!".index(channel[0].chr()).nil?
    add_channel(channel)
  end

  def do_list_plugins(event)
    brief = parse_message(event).strip.any?

    joinstr = brief ? ", " : "\n"

    msg = @plugins_loaded.keys.sort.collect { |plugin|
      @plugins_loaded[plugin][:object].to_s(brief)
    }.join(joinstr)

    reply(event, msg)
  end

  def do_load_plugin(event)
    plugin = parse_message(event).strip()
    if plugin.any?
      if load_plugin(plugin)
        msg = "Plugin #{plugin} loaded."
      else
        msg = "Unable to load #{plugin} plugin! Check logs."
      end
    else
      msg = "I need a plugin name to load!"
    end
    reply(event, msg)
  end

  def do_unload_plugin(event)
    plugin = parse_message(event).strip()
    if plugin.any?
      if unload_plugin(plugin)
        msg = "Plugin #{plugin} unloaded."
      else
        msg = "Unable to unload #{plugin} plugin. Check logs."
      end
    else
      msg = "I need a plugin name to unload!"
    end
    reply(event, msg)
  end

  def do_reload_plugin(event)
    plugin = parse_message(event).strip()
    if plugin.any?
      if reload_plugin(plugin)
        msg = "Plugin #{plugin} reloaded."
      else
        msg = "Unable to reload #{plugin} plugin. Check logs."
      end
    else
      msg = "I need a plugin name to reload!"
    end
  end

  def do_owner_cmd(event)
    if event.event_type == "pubmsg"
      msg = "Owner commands can only be used in a private message."
      reply(event, msg)
      return
    end

    text = parse_message(event).strip()

    if text.any?
      cmd, text = text.split(/\s+/, 2)

      # XXX Um, any other owner commands? Otherwise, this can
      # be simplified.
      case cmd
      when "login"
        pw = MD5.new(text).to_s()
        if @owners.has_key?(event.from)
          if @owners[event.from].password == pw
            @owners[event.from].login()
            msg = "#{event.from} logged in as owner."
          else
            msg = "Password does not match."
          end
        else
          msg = "No owner known as #{event.from}"
        end
      else
        msg = "Unknown owner command: #{cmd}"
      end
    else
      msg = "I need a command for owner."
    end

    send(:target => event.from, :message => msg)
    return
  end

  def do_owner_list(event)
    owners = @owners.keys.sort.inject([]) do |own, owner|
      @owners[owner].is_logged_in? ? own.push(@owners[owner].nick) : own
    end

    if owners.any?
      msg = owners.join(", ")
    else
      msg = "None logged in."
    end

    reply(event, msg)
  end

  def do_part(event)
    channel = parse_message(event).strip()
    channel = "#" + channel if "#&+!".index(channel[0].chr).nil?
    part(channel)
  end

  def do_quit(event)
    msg = parse_message(event).strip()

    # We need to unload all of our plugins, so that their 
    # stop() methods can be called just in case they need 
    # it to happen to save files, etc.
    self.unload_all_plugins()

    if msg.empty?
      msg = "A BogoBot Named #{@nick} is Quitting. Version: #{BOT_VERSION}"
    end

    send_quit(msg)
  end

  def do_version(event)
    nick = @nick.end_with?("s") ? @nick + "'" : @nick + "'s"
    reply(event, "#{nick} version is #{BOT_VERSION}")
  end

  # Opens a given storage file and yields the file object. If there
  # is an issue opening the file, then nil is yielded instead, so
  # any code calling this method should check the passed value before
  # using it. The file is closed after the block returns.
  def get_storage_file(fname, mode="r", &block)
    fname = get_storage_path(fname)

    begin
      fp = File.open(fname, mode)
      block.call(fp)
      fp.close()
    rescue Exception => err
      self.error "Error with storage file: #{err}"
      block.call(nil)
    end
  end

  # Returns the storage path for a given filename.
  def get_storage_path(fname="")
    return File.join(STORE_DIR, fname)
  end

  # Gets a format string, a wrapper for
  # IRCTextUtil.get_format_string()
  def get_format_string(options={})
    return IRCTextUtil.get_format_string(options)
  end

  # If the given nick is a owner and is logged in, returns true.
  def is_owner?(nick=nil)
    return true if @owners.key?(nick) and @owners[nick].is_logged_in?
  end

  # XXX There is a bug here for nicks that contains {}'s and []'s.
  # It will change -to- nicks containing those, but won't change
  # back later.
  def on_nick(event)
    old_nick = event.old_nick
    new_nick = event.new_nick
    if @owners.has_key?(old_nick)
      @owners[new_nick] = @owners[old_nick].dup()
      @owners[new_nick].nick = new_nick
      @owners.delete(old_nick)
    end
    return true
  end

  # This handles both pubmsg and privmsg events.
  def on_message(event)
    msg = event.message.strip()
    if @command_tokens.include?(msg[0].chr())
      cmd, args = msg[1..-1].split(" ", 2)
      handle_command(cmd, event)
    end
    return true
  end

  # Handles a command for a given command string and event.
  def handle_command(cmd_str, event)
    cmd_str.downcase!
    return false if not @commands.has_key?(cmd_str)
    begin
      # If the event is a pubmsg and the command is a private-only
      # say so and return.
      if event.event_type == 'pubmsg' and @commands[cmd_str].private?
        self.reply(event, "#{cmd_str} is a private-message only command!")
      else
        @commands[cmd_str].call(self, event) if @commands.has_key?(cmd_str)
      end
      return true
    rescue Exception => err
      self.error "Error handling #{cmd_str}!: #{err}\n    #{err.backtrace.join("\n    ")}"
      self.reply(event, "There was an error running the #{cmd_str} command. Check the logs.")
      return false
    end
  end

  # This will load a plugin in the plugin directory. The plugin, however
  # is responsible for calling Kernel.register_plugin() to initiate the
  # actual plugin class. See start_plugin().
  def load_plugin(plugin_name=nil)

    if plugin_name.is_a?(String) and plugin_name.any?
      plugin_name.downcase!

      plugin_file = File.join(PLUGIN_DIR, plugin_name + ".rb")

      if File.exists?(plugin_file)
        begin
          load plugin_file
          return true
        rescue Exception => err
          self.error "Error loading #{plugin_file}: #{err}    " + err.backtrace.join("\n    ")
        end
      else
        self.error "Can not find #{plugin_file} to load."
      end
    else
      self.error "Got non-string or empty string value for plugin_name!"
    end

    return false
  end

  # This unloads a given plugin and removes it from the bot.
  # The plugin's name is passed as the argument.
  def unload_plugin(plugin_name=nil)
    return false if plugin_name.nil?
    begin
      self.stop_plugin(plugin_name)
      @plugins_loaded.delete(plugin_name)
      return true
    rescue Exception => err
      self.error "Error unloading #{plugin_file}: #{err}    " + err.backtrace.join("\n    ")
    end
  end

  def unload_all_plugins
    @plugins_loaded.keys.each do |plugin|
      self.unload_plugin(plugin)
    end
  end

  # Unloads and then reloads a plugin.
  # If the plugin is loaded if it wasn't to begin with.
  def reload_plugin(plugin_name=nil)
    return false if plugin_name.nil?
    if @plugins_loaded.has_key?(plugin_name)
      self.unload_plugin(plugin_name)
    end
    return self.load_plugin(plugin_name)
  end

  # This method starts a plugin, after it has called Kernel.register_plugin().
  # It must be passed the plugin's Class, which has to be a subclass
  # of Plugin::PluginBase.  This will instatiate the plugin, then will call
  # the plugin's start() method, passing in the bot and any config file for
  # the plugin.
  def start_plugin(plugin)
    if not plugin.is_a?(Class)
      self.error("start_plugin passed a non-class!")
      return false
    end

    if not plugin.ancestors.include?(Plugin::PluginBase)
      self.error("#{plugin.to_s} is not a sub-class of PluginBase!")
      return false
    end

    plugin_name = plugin.to_s.downcase()

    begin
      p = plugin.new()

      @plugins_loaded[plugin_name] = {
        :object => p,
        :commands => [],
        :handlers => {}
      }

      conf_name = p.config_file()
      plugin_conf = File.join(CONFIG_DIR, conf_name + ".conf")
      conf = Config::Config.new(plugin_conf, File.exists?(plugin_conf))

      p.start(self, conf)
      return true

    rescue Exception => err
      @plugins_loaded.delete(plugin_name)
      self.error("Error starting plugin: #{plugin_name} => #{err}    \n" + err.backtrace.join("\n    "))
      return false
    end
  end

  # This will unload a given plugin's commands and handlers, also
  # calling the plugin's stop() method if it exists.
  # This does _not_ remove the plugin from the bot, however, since
  # that is handled by unload_plugin(), which calls this method first.
  def stop_plugin(plugin_name)
    if @plugins_loaded.has_key?(plugin_name)
      plugin = @plugins_loaded[plugin_name][:object]
      self.remove_plugin_commands(plugin)
      self.remove_plugin_handlers(plugin)
      plugin.stop() if plugin.respond_to?(:stop)
    end
  end

  # Sends a message back to the irc server, in response to the given
  # event. Basically a wrapper for send() that automatically handles
  # if the event was fired from a private or public message.
  # Note, that _only_ events with the custom irc event type of 'pubmsg'
  # is sent publicly, everything else is sent to the user who generated
  # the event.
  # For more custom server replies, you will have to call send() directly,
  # though this will handle the vast majority of your needs and is simpler
  # to use.
  def reply(event, message="")
    if event.event_type == "pubmsg"
      send(:target => event.channel, :message => message)
    else
      send(:target => event.from, :message => message)
    end
  end

  # This is just like reply(), 'cept for actions.
  def action(event, message)
    if event.event_type == "pubmsg"
      send_action(event.channel, message)
    else
      send_action(event.from, message)
    end
  end

  # Convience wrapper around send_ctcp() method.
  def ctcp(target, type, message)
    send_ctcp(target, type, message)
  end

  # Sends a message to the server, with options specified in the args
  # hash.  The valid keys are:
  # :target:  The target of this message, either a nick for a private
  #           messages or a channel for public messages.
  # :message: The message to be sent to the server.
  # :type:    The type of message event to send, which defaults to a
  #           :notice event. Valid values are: :notice, :pubmsg, :privmsg
  #           NOTE: Proper irc bot protocol states that bots should only
  #           reply with :notice events, since such events should be 
  #           ignored and NEVER be replied to themselves. This is to prevent
  #           bot's entering infinite message passing loops.
  def send(args={})
    target = args[:target]
    message = args[:message]

    return if target.nil? or message.nil?

    type = args.has_key?(:type) ? args[:type] : :notice

    case type
    when :notice
      send_notice(target, message)
    when :pubmsg, :privmsg
      send_message(target, message)
    else
      self.error "Unknown send type: #{type}"
    end

  end

  # Parses an event's message, removing any command and
  # returning the message part, or an empty string otherwise.
  # Intended to be used by !command handlers, _not_ event handlers.
  def parse_message(event)
    cmd, message = event.message.to_s.split(/\s/, 2)
    return message.to_s()
  end

end

# Encapsulates a bot owner.
class Owner
  attr_reader :nick
  attr_reader :password
  attr_reader :is_logged

  def initialize(nick, pw)
    @nick = nick
    @password = pw
    @is_logged = false
  end

  def nick=(new_nick)
    @nick = new_nick
  end

  def login
    @is_logged = true
  end

  def is_logged_in?
    return true if @is_logged
  end
end

# Encapsulates a !command. This handles _no_ error handling
# on purpose; it should be wrapped in the caller of the 
# command.
class UserCommand
  attr_reader :owner_only
  attr_accessor :private

  def initialize(owner_only, help, is_priv, block)
    @owner_only = owner_only
    @help = help.to_s
    @private = is_priv
    @alias_for = ""
    @block = block
  end

  def call(bot, event)
    if @owner_only and not bot.is_owner?(event.from)
      msg = "Sorry, #{event.from}, but you are not my owner."
      bot.reply(event, msg)
      return
    end
    @block.call(bot, event)
  end

  def help(botname="", token="")
    help = @help.dup()
    help.gsub!("{bot}", botname) if botname.any?
    help.gsub!("{cmd}", token) if token.any?
    return help
  end

  def private?
    return @private
  end

  def alias_for(cmd=nil)
    return @alias_for if cmd.nil?
    @alias_for = cmd
    return self
  end

  def is_alias?
    return @alias_for.any?
  end

end

############
#   Main   #
############
opts = GetoptLong.new(
  ["--config", "-c", GetoptLong::REQUIRED_ARGUMENT],
  ["--daemon", "-d", GetoptLong::NO_ARGUMENT],
  ["--debug", GetoptLong::NO_ARGUMENT],
  ["--help", "-h", GetoptLong::NO_ARGUMENT]
)

config = "default"
do_daemon = false
debug = false
  
opts.each do |opt, arg|
  case opt
  when "-c", "--config"
    config = arg
  when "-d", "--daemon"
    do_daemon = true
  when "--debug"
    debug = true
  when "-h", "--help"
    puts USAGE % File.basename($PROGRAM_NAME)
    exit
  end
end

bot = BogoBot.new(config, debug)

if do_daemon
  bot.debug "Daemonizing BogoBot..."
  Daemons.daemonize()
end

bot.connect()
