module Kernel

  @@bot = nil

  def set_bot(bot)
    @@bot = bot
  end

  def get_bot
    @@bot
  end

  def error(message)
    # handle message
    @@bot.error(message)
  end

  # Plugin Register method
  # Merely a wrapper for the bot's init plugin.
  def register_plugin(plugin)
    @@bot.start_plugin(plugin)
  end

  # XXX: Implement someday!
  # Register a Bot extension
  #def register_extension(mod_name)
  #  begin
  #    @@bot.extend(instance_eval(mod_name))
  #    return true
  #  rescue Exception
  #    error("Unable to extend with module: #{mod_name}!")
  #    return false
  #  end
  #end

end
