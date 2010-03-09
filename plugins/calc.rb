class Calc < Plugin::PluginBase

  ALLOWED = "0123456789+-/*().%<>&|".split(//)

  def initialize
    author "Randy"
    version "1.0b"
    name "Calc"
  end

  def start(bot, config)
    calc_help = "{cmd}calc <string> -- Calulates string. " +
      "Allowed characters: #{ALLOWED.join("")}"
    bot.add_command(self, "calc", false, false, calc_help) do |bot, event|
      self.do_calc(bot, event)
    end
  end

  def stop
    #nop
  end

  def do_calc(bot, event)
    msg = bot.parse_message(event).strip.gsub(/\s+/, "")

    parts = msg.split(//)
    bad = parts - (parts & ALLOWED)

    if bad.any?
      msg = "#{event.from}: There are unallowed characters. " + 
        "Bad characters: #{bad.join("")}"
    else
      msg = "#{event.from}, the answer is: " + eval(msg).to_s()
    end

    bot.reply(event, msg)
  end

end

register_plugin(Calc)
