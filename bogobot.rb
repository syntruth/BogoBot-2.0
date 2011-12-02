#!/usr/bin/env ruby

require "rubygems"

# Ensure our local paths are loaded first.
$LOAD_PATH.insert(0, "./lib")
$LOAD_PATH.insert(0, "./lib/irc")

# Local libs
require 'lib/init'

# Ruby libs
require "daemons"
require "English"
require "getoptlong"
require "logger"
require "pathname"
require "digest/md5"

BOT_VERSION = "2.1.0"
BOT_PATH = Dir.pwd()

# Set our local paths for bot/plugin/storage files.
CONFIG_DIR = File.join(BOT_PATH, "conf")
LOG_DIR    = File.join(BOT_PATH, "logs")
PLUGIN_DIR = File.join(BOT_PATH, "plugins")
EXTEND_DIR = File.join(BOT_PATH, "extensions")
STORE_DIR  = File.join(BOT_PATH, "store")

DEFAULT_COMMAND_OPTIONS = {
  :owner_only => false,
  :is_private => false
}

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
  attr_reader :nick

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
      @config = SimpleConfig::SimpleConfig.new(config_file)
    rescue SimpleConfig::SimpleConfigError => err
      self.error("!!!   Error with config   !!!\n", err)
      raise
    end

    # Initialize the Plugin system
    Plugin.init(self)

    # Holds the bot command map.
    @commands = {}

    # Get our command sigil(s), which defaults to bang. "!"
    # You can have more than one sigil.
    @command_tokens = @config.get("command", "!").gsub(/\s+/, "").split(//)

    # Get our list of plugins to load.
    # Defaults to an empty list.
    @plugins = @config.get("plugin", [])

    # Holds the loaded plugins.
    @plugins_loaded = {}

    # We have to make sure to observe the :plugin_defined
    # event, so we can know when to start 'em.
    observe_event(:plugin_defined) do |event, plugin|
      start_plugin(plugin)
    end

    # Get our owners. There has to be at least ONE owner
    # in the configuration file, or else the bot will exit.
    # Owners are given in the following format:
    #  nick:md5_password
    # ...where nick is the nick the owner will have and the
    # password is a md5'd password. This is weak security, I
    # know, but will address in the future.
    @owners = @config.get("owner", []).inject({}) do |hash, owner|
      nick, pw = owner.split(/\:/, 2)
      if pw.match(/^[A-Fa-f0-9]{32}$/)
        hash[nick.to_sym()] = Owner.new(nick, pw)
      else
        self.error("#{nick} password is not md5. Not added.")
      end
      hash
    end

    # If we have no owners, this is not good, so we panic
    # and exit!
    if @owners.empty?
      self.error "There are no owners in #{config_file} or " + 
        "there is an issue with their password!"
      exit
    end

    # Set our required parameters to get connected...
    @nick     = @config.get("nick", "BogoBot")
    @server   = @config.get("server", "localhost")
    @port     = @config.get("port", "6667")
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
    ['endofmotd', 'nomotd'].each do |motd|
      IRCEvent.add_handler(motd) do |event|
        do_auto_joins()
        true
      end
    end

    # And finally, our generic IRC event handler; this dispatcher
    # will emit events as they come in, if the event has handlers.
    # Since these will most likely be for Plugins, the event is
    # wrapped in a PluginEvent wrapper.
    IRCEvent.add_handler('all') do |event|
      event_type = event.event_type

      if has_event?(event_type)
        event = PluginEvent.new(self, event, false)
        emit_event(event_type, event)
      end
    end

    ######################
    # Built-in Commands. #
    ######################

    # Owner Only Commands
    cmd = add_command(self, "quit", :owner_only => true) do |event|
      do_quit(event)
    end
    cmd.help = "Makes the bot quit."

    cmd = add_command(self, "join", :owner_only => true) do |event|
      do_join(event)
    end
    cmd.help = "{cmd}join <channel> -- Makes the bot join a channel."

    cmd = add_command(self, "part", :owner_only => true) do |event|
      do_part(event)
    end
    cmd.help = "{cmd}part <channel> -- Makes the bot leave a channel."

    cmd = add_command(self, "alias", :owner_only => true) do |event|
      do_command_alias(event)
    end
    cmd.help = "{cmd}alias <command> <old> [<new>] -- " + 
      "Adds or removes a command alias. The command can be " + 
      "either 'add' or 'remove'. Do not put the command token on " + 
      "the old or new command strings."

    cmd = add_command(self, "load", :owner_only => true) do |event|
      do_load_plugin(event)
    end
    cmd.help = "{cmd}load <plugin> -- Loads a plugin."

    cmd = add_command(self, "unload", :owner_only => true) do |event|
      do_unload_plugin(event)
    end
    cmd.help = "{cmd}unload <plugin> -- Unloads a plugin."
    
    cmd = add_command(self, "reload", :owner_only => true) do |event|
      do_reload_plugin(event)
    end
    cmd.help = "{cmd}reload <plugin> -- Reloads a plugin."

    cmd = add_command(self, "plugins", :owner_only => true) do |event|
      do_list_plugins(event)
    end
    cmd.help = "{cmd}list [brief]-- Lists loaded plugins. " + 
      "If 'brief' is true, a brief list is given."

    # Public Commands
    cmd = add_command(self, "list") do |event|
      do_command_list(event)
    end
    cmd.help = "Lists commands."

    cmd = add_command(self, "owner", :is_private => true) do |event|
      do_owner_cmd(event)
    end
    cmd.help = "Owners commands, private message only."
    
    cmd = add_command(self, "owners") do |event|
      do_owner_list(event)
    end
    cmd.help = "Lists owners."

    cmd = add_command(self, "help") do |event|
      do_help(event)
    end
    cmd.help = "{cmd}help <command> -- Shows help for command"
    
    cmd = add_command(self, "version") do |event|
      do_version(event)
    end
    cmd.help = "{cmd}version -- Shows the bot's version."

  # Set the bot for error/debug globals.
  set_bot(self)

  # ...and done!
  end

  # This loads all plugins given in the configuration file and then 
  # opens up the log files, before calling the superclass method to
  # do the actual connection.
  def connect
    # Load our plugins.
    @plugins.each {|p| load_plugin(p)}
    
    log_file = File.join(LOG_DIR, @config.get("log", "bogobot.log"))
    @log = Logger.new(log_file)
    @log.level = @do_debug ? Logger::DEBUG : Logger::WARN

    super()
  end

  # If @log is available, sends the message passed there,
  # else outputs to $strerr.
  def error(msg, error_object=nil)
    if error_object and error_object.is_a?(Exception)
      msg += "\n#{error_object}\n--------\n"
      msg += "  #{error_object.backtrace.join("\n  ")}"
    end

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
  # :cmd_str:    This is the requested string for the command.
  #              Do not prepend a command sigil on the string.
  #              There is _no_ check on if the command string is 
  #              already set for another command. 
  #                (XXX Fix this, actually.)
  # :options:    A hash of options, typically :owner_only and
  #              :is_private boolean values.
  #              If :owner_only is set to true, then only the bot's
  #              owner can call this command.
  #              If :is_private is set to true, then the command can
  #              only be issued from a private message to the bot.
  #
  # You have to pass a block of code for your command to this method.
  # The block will be passed |bot, event| as arguements. The bot is,
  # of course, the instance of the bot, while event is the irc event
  # that triggered the command.
  def add_command(plugin, cmd_str, options={}, &block)
    cmd_str = cmd_str.to_sym() if cmd_str.is_a?(String)
    
    options ||= {}
    options = DEFAULT_COMMAND_OPTIONS.dup.update(options)

    cmd_obj = UserCommand.new(self, options, block)
    @commands[cmd_str] = cmd_obj

    return cmd_obj
  end

  # Removes a command for a given command string. Do not put the
  # command token on the passed string.
  def remove_command(cmd_str)
    @commands.delete(cmd_str) if @commands.has_key?(cmd_str)
  end

  # Returns the list of valid !commands.
  # The returned commands do not have their command sigil on them.
  def valid_commands
    return @commands.keys.sort()
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
    parts = event.message.split(/\s/)

    case parts.length()
    when 1
      cmd = parts.first()
    when 2
      cmd = parts.first()
      args = parts.last.to_sym()
    when 3
      cmd = parts.first()
      args = parts[1..-1].collect {|p| p.to_sym()}
    end

    case cmd
    when "add"
      old = args.first
      new = args.last
      if @commands.has_key?(old)
        @commands[new] = @commands[old].dup()
        @commands[new].alias_for(old)
        msg = "Notice: #{cmdstr}#{old} has been aliased to #{cmdstr}#{new}"
      else
        msg = "No command known as: #{cmdstr}#{old}"
      end

    when "remove"
      old = args
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
    cmd_list = @commands.keys.sort{|k1, k2| k1.to_s <=> k2.to_s}.collect do |key|
      if @commands[key].is_alias?
        "#{key} (alias for: #{@commands[key].alias_for()})"
      else
        key
      end
    end
    reply(event, "Commands: #{cmd_list.join(", ")}")
  end

  def do_help(event)
    topic = event.message.downcase.strip()

    topic = topic.empty? ? :help : topic.to_sym()

    if @commands.has_key?(topic)
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
    channel = event.message.strip()

    return if channel.empty?

    # If not a channel, assume standard public channel.
    channel = "#" + channel if not IRCChannel.is_channel?(channel)

    add_channel(channel)
  end

  def do_list_plugins(event)
    brief = event.message.strip.empty? ? false : true

    joinstr = brief ? ", " : "\n"

    msg = @plugins_loaded.keys.sort.collect { |plugin|
      @plugins_loaded[plugin].to_s(brief)
    }.join(joinstr)

    reply(event, msg)
  end

  def do_load_plugin(event)
    plugin = event.message.strip()

    if not plugin.empty?
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
    plugin = event.message.strip()
    if not plugin.empty?
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
    plugin = event.message.strip()
    if not plugin.empty?
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

    text = event.message

    if not text.empty?
      nick = event.from.to_sym()
      cmd, text = text.split(/\s+/, 2)

      # XXX Um, any other owner commands? Otherwise, this can
      # be simplified.
      case cmd
      when "login"
        pw = Digest::MD5.hexdigest(text)
        if @owners.has_key?(nick)
          if @owners[nick].password == pw
            @owners[nick].login()
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
    owners = @owners.sort{|o1, o2| o1.to_s <=> o2.to_s}.collect do |owner|
      owner[0].to_s()
    end

    if owners.any?
      msg = "Owner: " + owners.join(", ")
    else
      msg = "None logged in."
    end

    reply(event, msg)
  end

  def do_part(event)
    channel = event.message
    channel = "#" + channel if not IRCChannel.is_channel?(channel)
    part(channel)
  end

  def do_quit(event)
    msg = event.message.strip()

    # We need to unload all of our plugins, so that their 
    # stop() methods can be called just in case they need 
    # it to happen to save files, etc.
    self.unload_all_plugins()

    if msg.empty? or msg.nil?
      msg = "A BogoBot Named #{@nick} is Quitting. Version: #{BOT_VERSION}"
    end
    
    if @log
      @log.info("Bogobot Quitting.")
    else
      puts "Bogobot Quitting"
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
      self.error("Error with storage file.", err)
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
  def is_owner?(nick="")
    nick = nick.to_sym() unless nick.is_a?(Symbol)
    return true if @owners.key?(nick) and @owners[nick].is_logged_in?
    return false
  end

  # Handles changing nicks for the owners.
  # XXX Should make sure User objects in Channels are changed
  # as well.
  def on_nick(event)
    old_nick = event.old_nick.to_sym()
    new_nick = event.new_nick.to_sym()
    if @owners.has_key?(old_nick)
      @owners[new_nick] = @owners[old_nick].dup()
      @owners[new_nick].nick = new_nick.to_s()
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
    cmd_str = cmd_str.downcase.to_sym() if cmd_str.is_a?(String)

    if not @commands.has_key?(cmd_str)
      debug "handle_command(): command string #{cmd_str} not found."
      return false 
    end

    begin
      # If the event is a pubmsg and the command is a private-only
      # say so and return.
      if event.event_type == 'pubmsg' and @commands[cmd_str].private?
        self.reply(event, "#{cmd_str} is a private-message only command!")
      else
        # Wrap it up the event for easy use.
        event = PluginEvent.new(self, event, true)
        @commands[cmd_str].call(event)
      end
      return true

    rescue Exception => err
      self.error("Error handling #{cmd_str}!", err)
      self.reply(event, "There was an error running the #{cmd_str} command. Check the logs.")
      return false
    end
  end

  # This will load a plugin in the plugin directory.
  # The plugin is not actually started until its start() method is
  # called. See start_plugin() for more.
  def load_plugin(plugin_name=nil)

    # We refresh the rubygem paths, just in case the plugin needs
    # to load a new library that has been installed since we started
    # running.
    Gem.refresh()

    if plugin_name.is_a?(String) and not plugin_name.empty?
      plugin_name.downcase!

      plugin_file = File.join(PLUGIN_DIR, plugin_name + ".rb")

      if File.exists?(plugin_file)
        begin
          Plugin.load_plugin(plugin_file)
          return true
        rescue Exception => err
          self.error("Error loading #{plugin_file}!", err)
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
      self.error("Error unloading #{plugin_name}!", err)
    end
  end

  def unload_all_plugins
    @plugins_loaded.keys.each do |plugin|
      self.unload_plugin(plugin)
    end
  end

  # Unloads and then reloads a plugin.
  # The plugin is loaded if it wasn't to begin with.
  def reload_plugin(plugin_name=nil)
    return false if plugin_name.nil?
    if @plugins_loaded.has_key?(plugin_name)
      self.unload_plugin(plugin_name)
    end
    self.load_plugin(plugin_name)
  end

  def start_plugin(plugin)
    if not plugin.is_a?(Plugin)
      self.error("#{plugin.class} is not a sub-class of Plugin!")
      return false
    end

    plugin_name = plugin.class.to_s.downcase()

    begin
      conf_name = plugin.config_file()
      plugin_conf = File.join(CONFIG_DIR, conf_name + ".conf")

      conf = SimpleConfig::SimpleConfig.new(plugin_conf, 
        File.exists?(plugin_conf)
      )

      plugin.start(conf)
      @plugins_loaded[plugin_name] = plugin

    rescue Exception => err
      self.error("Error starting plugin: #{plugin_name}!", err)
      return false
    end
  end

  # This will unload a given plugin's commands and handlers, also
  # calling the plugin's stop() method if it exists.
  # This does _not_ remove the plugin from the bot, however, since
  # that is handled by unload_plugin(), which calls this method first.
  def stop_plugin(plugin_name)
    if @plugins_loaded.has_key?(plugin_name)
      @plugins_loaded[plugin_name].stop()
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
    return message
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
    return @is_logged
  end
end

# Encapsulates a !command. This handles _no_ error handling
# on purpose; it should be wrapped in the caller of the 
# command.
class UserCommand
  attr_reader :owner_only
  attr_reader :private

  def initialize(bot, options, block)
    options = {} if not options.is_a?(Hash)

    @bot        = bot
    @owner_only = options[:owner_only]
    @private    = options[:is_private]
    @help       = ""
    @alias_for  = nil
    @block      = block
  end

  def call(event)
    if @owner_only and not @bot.is_owner?(event.from)
      @bot.reply(event, "Sorry, #{event.from}, but you are not my owner.")
      return
    end
    @block.call(event)
  end

  def help=(help_str)
    @help = help_str
  end

  def help(botname="", token="")
    help = @help.dup()
    help.gsub!("{bot}", botname)
    help.gsub!("{cmd}", token)
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
    return false if @alias_for.nil?
    return true
  end

end

############
#   Main   #
############
opts = GetoptLong.new(
  ["--config", "-c", GetoptLong::REQUIRED_ARGUMENT],
  ["--daemon", "-d", GetoptLong::NO_ARGUMENT],
  ["--debug",        GetoptLong::NO_ARGUMENT],
  ["--help",   "-h", GetoptLong::NO_ARGUMENT]
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
