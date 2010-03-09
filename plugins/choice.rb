class Choice < Plugin::PluginBase

  def initialize()
    author "Syn"
    name "Choice"
    version "1.0"

    @sayings = []
    @yes_no = ["Yes", "No"]
    @words = ["are", "does", "is", "should", "will"]
  end

  def start(bot, config)
    @sayings = config.get("saying", @yes_no)

    choice_help = "{cmd}[#{@words.join("|")}] <subject> <question>? " +
      "-- Ask a question. Multiple choice questions are separated by commas " + 
      "or \" or \".\n" +
      "Example: {cmd}should I eat cake or go jogging? ...or... " + 
      "{cmd}will I get lucky?"

    @words.each do |word|
      bot.add_command(self, word, false, choice_help) do |bot, event|
        self.do_choice(bot, event)
      end
    end

  end

  def stop
    # nop
  end

  def do_choice(bot, event)
    text = bot.parse_message(event).strip()

    if text.any?
      options = self.parse_options(text)
      case options.length
      when 1
        msg = @sayings[rand(@sayings.length())]
      else
        msg = options[rand(options.length())]
      end
    else
      msg = "Maybe you should ask a question?"
    end

    bot.reply(event, msg)
  end

  def parse_options(txt="")
    options = []
    sre = /\,?\s+or\s+|\,\s+/

    # Get rid of the question mark if there is one 
    # and the subject.
    txt.strip!
    txt.sub!(/\?$/, "")
    txt.sub!(/^\w+\s+/, "")

    options = txt.split(sre)
    options.collect! {|s| s.strip }
    return options
  end

# End Class
end

register_plugin(Choice)
