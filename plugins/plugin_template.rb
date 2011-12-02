Plugin.define "test" do

  name    "Test Plugin"
  author  "Ruby Dude!"
  version "1.0"

  # If you don't want to use the default
  # config file name, you can redefine it:
  # config_file "myconfigfile"

  # You can define two special, optional blocks.
  # The on :start and on :stop blocks are called
  # when the plugin is started and stopped by Bogobot.
  # NOTE: you *should* not use the 'config' command
  # outside of the on :start and on :stop blocks,
  # since the config has not been read until the
  # on :start block is called.
  #
  # In other words, if you plan on using a config,
  # you will need an on :start block to get it.
  #
  # These blocks are the ideal place to set up any 
  # database connections or files that need to be
  # opened and closed.
  #
  # It *is* safe to call your helpers from within
  # these blocks, since they will be defined before
  # these blocks are utilized.

  on :start do
    assign :configvar, config.get("foo", "bar")

    storage_file(configvar) do |fp|
      assign :filedata, fp.read()
    end
  end

  on :stop do
    storage_file(configvar, "w") do |fp|
      fp.write(filedata)
    end
  end

  # You can pre-assign some values to use via the 
  # assign command. Behind the scenes, this creates
  # a getter method that returns the given value. 
  # If you want to assign a new value, just use
  # assign again.
  assign :myvar, "This is a test of myvar!"

  # I suggest that you first define your IRC event
  # handlers.
  # IRC Event handlers are similiar to commands, 'cept 
  # that you specify which IRC event you want to handle
  # instead of giving a command name.
  #
  # Also, the event.message() method will return the full
  # message string, where in a command, the method only
  # returns the string _after_ the command.

  handle :pubmsg do |event|
    message = event.message()
    # ...do some processing here.
    # Most of the time, IRC event handlers are passive and
    # don't nessesarily produce any output, but if they do
    # you use event.reply like in a command.
    event.reply(message)
  end

  # And then define your commands
  # Commands will get an event object, which will
  # have methods for replying, etc. You can call
  # your helper methods in commands and handlers,
  # even if they are defined after the commands and
  # handlers.
  #
  # Normally, you only have to worry about event.message
  # and event.reply. event.message() will return the text
  # of the command, with the command part removed.
  # While event.reply() will take a given message to display
  # and will handle sending it to the correct channel, or
  # if private, the user who issued the command.
  command :echo do |event|
    message = gigo(event.message)
    event.reply(message)
  end

  # To provide a help string for your command, you use
  # help_for, which should provide a string in the block,
  # which will be assigned to the given command.
  #
  # The following can be used for substitution:
  # {cmd} will be replaced with the bot's command sigil, or if
  #   there are more than one, the first command sigil.
  # {bot} will be replaced with the bot's IRC nick.
  help_for :echo do
    "{cmd}echo <text> -- will echo the text as uppercased garbage."
  end

  # Lastly, defined your helper methods that can be called from
  # within your command and handle blocks.
  helper :gigo do |txt|
    txt.upcase.split(//).shuffle.join("")
  end
end
