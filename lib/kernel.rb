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
    @@bot ? @@bot.error(message) : $stderr.write(message + "\n")
  end

  def debug(message)
    @@bot ? @@bot.debug(message) : $stdout.write(message + "\n")
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
