class Karma < Plugin::PluginBase

  KARMA_RE = /^([A-Za-z0-9]+?)([+]{2}|--)\s*/

  def initialize
    name "Karma"
    author "Syn"
    version "0.1"

    @file = nil
  end

  def start(bot, config)
    @file = bot.get_storage_path(config.get("file", "karma.dat"))
    @verbose = config.get("verbose", false)

    # Ensure our storage file exists.
    if not File.exists?(@file)
      self.save_file({})
    end

    bot.add_handler(self, 'pubmsg') do |event|
      self.do_pubmsg(bot, event)
    end

    bot.add_handler(self, 'privmsg') do |event|
      self.do_privmsg(bot, event)
    end

    karma_help = "{cmd}karma <subject> -- returns the karma for subject. " +
      "You can give a subject karma by simply giving the subject followed " +
      "but either ++ for good karma, or -- for bad karma. Subjects must not " +
      "have spaces. For example: coffee++ or Syn--"

    bot.add_command(self, "karma", false, false, karma_help) do |bot, event|
      self.do_karma(bot, event)
    end

  end

  def do_pubmsg(bot, event)
    found = self.parse_karma(event.message())

    if found

      bot.debug("Karma -- I found: #{found.join(" : ")}")

      subject = found.first()
      karma = found.last()

      if subject == event.from.downcase()
        msg = "Change must come from within, but you cannot change your karma."
      else
        self.save_karma(subject, karma)
        karmas = self.get_karmas()
        msg = "The karma for #{subject} is: #{karmas[subject]}."
      end

      bot.reply(event, msg) if @verbose

    end

    return true
  end

  def do_privmsg(bot, event)
    if self.parse_karma(event.message())
      bot.reply(event, "Karma can only be given in a public channel.")
    end
    return true
  end

  def do_karma(bot, event)
    subject = bot.parse_message(event).strip.downcase()
    
    if subject.any?
      karmas = self.get_karmas()
      if karmas.has_key?(subject)
        msg = "The karma for #{subject} is: #{karmas[subject]}."
      else
        msg = "I could not find a karma for #{subject}. I do apologize."
      end
    else
      msg = "Looking for nothing is zen, but wasteful. " + 
        "Perhaps a subject, please?"
    end

    bot.reply(event, msg)
  end

  def parse_karma(line="")
    match = KARMA_RE.match(line)
    if match

      subject, up_down = match.captures()

      subject = subject.downcase()
      karma = (up_down == "++") ? 1 : -1

      return [subject, karma]
    end
    return nil
  end

  def get_karmas
    karmas = {}

    return karmas if @file.nil?

    File.open(@file) do |fp|
      fp.each do |line|
        parts = line.split(/:/).collect {|p| p.strip}

        next if parts.length != 2

        subject = parts.first()
        karma = parts.last.to_i()

        karmas[subject] = karma
      end
    end

    return karmas
  end

  def save_file(karmas)
    return false if @file.nil?
    
    File.open(@file, "w") do |fp|
      karmas.sort.each do |key, value|
        fp.write("%s: %s\n" % [key, value])
      end
    end

    return true
  end

  def save_karma(subject, karma=1)
    karmas = self.get_karmas()
    karmas[subject] = 0 if not karmas.has_key?(subject)
    karmas[subject] += karma
    self.save_file(karmas)
  end

end

register_plugin(Karma)
