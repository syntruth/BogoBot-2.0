class TestPlugin < Plugin::PluginBase

  # Set up and pre-running configuration
  # happens here
  def initialize
  
    name "My Test Plugin"
    author "Ruby Dude"
    version "0.1"
  end

  # This is where the plugin actually starts
  # to run. Bogobot will pass itself as the first
  # argument and a Config::Config object as the second
  # argument. Note, that _even_ if the plugin does not
  # have a physical configuration file in Bogobot's 
  # configuration directory (conf/) that an object is still
  # passed; it just represents an empty config, but with the
  # 'correct' config file name assigned, so you could add things
  # to the config and then call it's save() method. Later 
  # loadings of the plugin will then use that file.
  # Typically, you won't need to save the config to an instance
  # variable, but you could if there was a need.
  # I do not recommend saving the bot's instance; there is no need,
  # since any command are passed an instance of the bot anyways.
  # Handlers need to use the bot instance passed to initialize, 
  # however, but this may be fixed in a future version.
  # (Future versions may allow the bot to be spawned
  # as several bots, so...don't save a bot's ref!)
  def start(bot, config)
    @config = config

    # Adding commands is very simple. You call the bot's
    # add_command() method, which has the following positional
    # arguments and requires a block:
    #
    # :plugin:  You _must_ pass in the plugin's instance, so this
    #           will always be self. (It's used to track plugins for
    #           loading and unloading.)
    # :command: This is what the actual command string will be. Do not
    #           prepend a command-token on the front. Valid command
    #           strings must be at least 2 characters long.
    # :owner:   Boolean value; is this an owner-only command?
    # :private: Boolean value; does this command require it to be issued
    #           in a private message to the bot?
    #
    # The block given to add_command() will receive two arguments:
    #
    # :bot:     The instance of the bot calling this command.
    # :event:   The public or private message event that fired this command.
    #
    # Although not required, typically you would pass control over to an 
    # instance method.
    bot.add_command(self, "test", false, false) do |bot, event|
      self.do_test_command(bot, event)
    end

    # Adding an event handler is very similar. You call the bot's
    # add_handler() method with some positional parameters and a 
    # block.
    # Parameters are:
    #
    # :plugin: Again, this is the plugin's instance for tracking.
    # :event:  This can be either a string, a symbol (preferred) or
    #          an array of strings/symbols of event types the plugin
    #          wants to handle.
    #
    # The passed in block will receive the the event object, and again
    # typically you'd hand off control to a class method, though this
    # is not required.
    bot.add_handler(self, :pubmsg) do |event|
      self.do_pubmsg(bot, event)
    end
  end

  def do_test_command(bot, event)
    # Typically, you are interested in the message of the event,
    # so you can parse it as needed.  However, it's sent with the
    # command part still attached, so you can use the bot's
    # parse_message() method to get the message. This will return
    # the message string, which could be empty.
    message = bot.parse_message(event).strip()

    # ...process message here...

    # Once you are ready to reply, if you even have to, you call
    # the bot's reply() method, which takes the event object back
    # and whatever message you want to post. It will automatically
    # handle sending a public or private message based on how the
    # event was recieved.
    bot.reply(event, "We got a 'test' command!")
  end

  def do_pubmsg(bot, event)
    # Process the event here.
    # You should return either true or false, for future
    # versions of the bot will use the return value to determine
    # if it should call any handlers _after_ this one.
    return true
  end

# End class
end

# Before the plugin can be used, you need to register
# it.  This is handled with a Kernel method, that passes
# the plugin's class to the bot to be started.
register_plugin(TestPlugin)
