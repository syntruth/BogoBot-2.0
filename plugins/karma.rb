class Karma < Plugin::PluginBase

  KARMA_RE = /^([a-z0-9 ]+?[a-z0-9])(\+\+|--)\s*?(\d|10)?$/i

  def initialize
    name "Karma"
    author "Syn"
    version "0.6"

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

    karma_help = "{cmd}karma [:command|subject] -- " + 
      "Commands are :top, :bottom, :average, and :stats. " +
      "Top and Bottom will give the top and bottom 3 karmas." +
      "If given a subject, will report the karma for that subject.\n" + 
      "You can give a subject karma by simply giving the subject followed " +
      "immediately by either ++ or -- for good or bad karma. " +
      "Karma can only be given in a public channel. " + 
      "For example: coffee++ or Syn-- or summer glau++"

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
    subject = bot.parse_message(event).squeeze(" ").strip.downcase()

    if subject.match(/^:/)
      cmd = subject.sub(/^:/, "").to_sym()
      msg = karma_stats(cmd)
    elsif subject.any?
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
      parts = match.captures()

      subject = parts[0].squeeze(" ").strip.downcase()
      karma = parts[2].to_i.abs()
      karma = 1 if karma.zero?
      karma = -(karma) if parts[1] == '--'

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

  def karma_stats(cmd=:top)
    karmas = self.get_karmas()
    msg = ""

    # Converty to an array and sort, highest to
    # lowest.
    karma_array = karmas.to_a.sort do |k1, k2|
      k2.last <=> k1.last
    end

    msg = case cmd
    when :top
      top = karma_array[0..2].collect do |k| 
        "%s: %s" % [k.first, k.last]
      end
      "Top Karma Holders: " + top.join(", ")
    when :bottom
      bottom = karma_array.reverse[0..2].collect do |k| 
        "%s: %s" % [k.first, k.last]
      end
      "Bottom Karma Holders: " + bottom.join(", ")
    when :average
      sum = karma_array.inject(0) {|t, k| t += k.last}
      avg = sum / karma_array.length()
      "The Average Karma is: %s" % avg
    when :stats
      "There are #{karma_array.length()} Karma entries."
    end

    return msg
  end

end

register_plugin(Karma)
