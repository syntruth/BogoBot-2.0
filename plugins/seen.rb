# Keeps track of the last thing people say or the last action
# they did.

require "yaml"

class SeenUser
  attr_accessor :nick
  attr_accessor :channel
  attr_accessor :timestamp
  attr_accessor :text
  attr_accessor :action

  def initialize(nick, channel, timestamp, text, action)
    @nick = nick
    @channel = channel
    @timestamp = timestamp
    @text = text
    @action = action
  end

  def action?
    return @action
  end

  def time
    return @timestamp.strftime("%I:%M%P")
  end

  def date
    return @timestamp.strftime("%h, %d %Y")
  end

  def to_s
    s = "%s - %s - %s - %s - %s"
    return s % [@nick, @channel, @timestamp, @text, @action]
  end
end

class Seen < Plugin::PluginBase

  def initialize()
    author "Randy"
    version "0.2"
    name "Seen"
  end

  def start(bot, config)
    file = config.get("file", "seendata.dat")
    @seen_file = bot.get_storage_path(file)

    @seen_users = {}

    @action = "%s last seen in %s on %s at %s doing: %s %s"
    @chat =   "%s last seen in %s on %s at %s saying: %s"

    @ignore_channels = config.get("ignore", []).collect { |ch|
      ch[1..-1] if "#&".include?(ch[0].chr)
    }.reject { |ch| ch.nil? }

    self.load_seen()

    if @seen_users.any?
      bot.debug "Number of nicks seen: #{@seen_users.keys.length}"
    else
      bot.debug "No seen data!"
    end

    bot.add_handler(self, ['pubmsg', 'action']) do |event|
      self.handler(bot, event)
    end
    
    seen_help = "{cmd}seen <nick> -- Displays the last time 'nick' was seen in watched channels."

    bot.add_command(self, "seen", false, seen_help) do |bot, event|
      self.do_seen(bot, event)
    end
  end

  def stop
    self.save_seen()
  end

  def handler(bot, event)
    action = event.event_type == 'action'

    nick = event.from
    channel = event.channel
    channel = channel[1..-1] if "#&".index(channel[0].chr)
    timestamp = Time.now()
    text = event.message

    return true if @ignore_channels.include?(channel)

    if not @seen_users.has_key?(nick)
      @seen_users[nick] = SeenUser.new(nick, channel, timestamp, text, action)
    else
      @seen_users[nick].timestamp = Time.now()
      @seen_users[nick].channel = channel
      @seen_users[nick].text = text
      @seen_users[nick].action = action
    end

    self.save_seen()

    # return true so we don't stop event handler.
    return true
  end

  def do_seen(bot, event)
    nick = bot.parse_message(event).strip()

    if nick.any?
      bot.debug("Looking for #{nick}")
      if @seen_users.key?(nick)
        bot.debug("Found them: #{@seen_users[nick]}")
        msg = self.format(@seen_users[nick])
      else
        msg = "Unknown user: #{nick}"
      end

    else
      msg = "I need to a name to look up."
    end
    bot.reply(event, msg)
  end


  def format(user)
    if user.action?
      return @action % [user.nick, 
        user.channel, 
        user.date,
        user.time,
        user.nick, 
        user.text
      ]
    else
      return @chat % [user.nick, 
        user.channel, 
        user.date, 
        user.time,
        user.text
      ]
    end
  end

  def save_seen
    if @seen_file
      File.open(@seen_file, "w") do |fp|
        fp.write(YAML.dump(@seen_users))
      end
    end
  end

  def load_seen
    if @seen_file and File.exists?(@seen_file)
      File.open(@seen_file) do |fp|
        users = YAML.load(fp.read())
        @seen_users.update(users) if users
      end
    end
  end

end

register_plugin(Seen)
