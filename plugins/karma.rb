require "yaml"

Plugin.define :karma do

  name    "Karma"
  author  "Syn"
  version "1.0"

  # The karma regex matches alphanum, spaces, and the period chars.
  assign :karma_re, /^([a-z0-9. ]+?[a-z0-9.])(\+\+|--)\s*?(\d|10)?$/i

  on :start do

    assign :kfile,      config.get("file", "karma.dat")
    assign :points_cap, config.get("points_cap", 10)
    assign :regen,      config.get("regen", 900)
    assign :verbose,    config.get("verbose", false)
    assign :nicks,      {}

    assign :nick_file,  config.get("nick_file", "karma_nicks.dat")
    
    storage_file(nick_file) do |fp|
      data = YAML.load(fp.read())
      nicks.update(data)
    end
  end

  on :stop do
    data = {}

    storage_file(nick_file) do |fp|
      data = YAML.load(fp.read())
    end

    data.update(nicks)

    storage_file(nick_file, "w") do |fp|
      fp.write(YAML.dump(data))
    end
  end

  handle :pubmsg do |event|
    msg = do_pubmsg(event)
    event.reply(msg) unless msg.nil?
  end

  handle :privmsg do |event|
    msg = do_privmsg(event)
    event.reply(msg) unless msg.nil?
  end

  handle :nick do |event|
    oldnick        = event.old_nick
    newnick        = event.new_nick
    nicks[newnick] = nicks.delete(oldnick) if nicks.has_key?(oldnick)
  end

  command :karma do |event|
    msg = do_karma(event)
    event.reply(msg)
  end

  help_for :karma do 
    "{cmd}karma [:command|subject] -- " + 
    "Commands are :points, :top, :bottom, :average, and :stats. " +
    "Points tells you how many karma points you have left to use." +
    "Points will regen over time." + 
    "Top and Bottom will give the top and bottom 3 karmas." +
    "If given a subject, will report the karma for that subject.\n" + 
    "You can give a subject karma by simply giving the subject followed " +
    "immediately by either ++ or -- for good or bad karma. " +
    "Karma can only be given in a public channel. " + 
    "For example: coffee++ or Syn-- or summer glau++"
  end

  helper :do_pubmsg do |event|
    msg   = nil
    found = parse_karma(event.message)
    nick  = event.from

    if found
      update_karma_points(nick)

      subject = found.first
      karma   = found.last
      padjust = nicks[nick][:points] - karma.abs

      if padjust < 0
        msg = "Sorry, #{nick}, but you do not have enough karma " + 
              "points to use. Current karma points: #{points}"
      elsif subject == nick.downcase
        msg = "Change must come from within, but you cannot change your own karma."
      else
        str = "The karma for %s is: %s\n%s"
        save_karma(subject, karma)

        nicks[nick] = {:points => padjust, :last_used => Time.now}
        karma       = get_karmas[subject]
        msg         = str % [subject, karma, points_left(nick)]
      end
    end

    verbose ? msg : nil
  end

  helper :do_privmsg do |event|
    msg = nil

    if parse_karma(event.message())
      msg = "Karma can only be given in a public channel."
    end

    msg
  end

  helper :do_karma do |event|
    subject = event.message.squeeze(" ").strip.downcase()

    if subject.match(/^:/)
      cmd, data = subject.split(/\s+/, 2)

      cmd = cmd.gsub(/:/, "").to_sym()
      msg = karma_command(cmd, data, event)
    elsif not subject.empty?
      karmas = get_karmas()
      if karmas.has_key?(subject)
        msg = "The karma for #{subject} is: #{karmas[subject]}."
      else
        msg = "I could not find a karma for #{subject}. I do apologize."
      end
    else
      msg = "Looking for nothing is zen, but wasteful. " + 
            "Perhaps a subject, please?"
    end

    msg
  end

  helper :parse_karma do |line|
    match = karma_re.match(line)

    if match
      parts = match.captures()

      subject = parts[0].squeeze(" ").strip.downcase()
      karma   = parts[2].to_i.abs()
      karma   = 1 if karma.zero?
      karma   = -(karma) if parts[1] == '--'

      [subject, karma]
    else
      nil
    end
  end

  helper :get_karmas do
    karmas = {}

    storage_file(kfile) do |fp|
      fp.each do |line|
        parts = line.split(/:/).collect {|p| p.strip}

        next if parts.length != 2

        subject = parts.first()
        karma   = parts.last.to_i()

        karmas[subject] = karma
      end
    end

    return karmas
  end

  helper :save_file do |karmas|    
    storage_file(kfile, "w") do |fp|
      karmas.sort.each do |key, value|
        fp.write("%s: %s\n" % [key, value])
      end
    end

    return true
  end

  helper :save_karma do |subject, karma|
    karma  = 1 unless karma.is_a?(Fixnum)
    karma  = 1 if karma.zero?
    karmas = get_karmas

    karmas[subject] = 0 if not karmas.has_key?(subject)
    karmas[subject] += karma
    
    save_file(karmas)
  end

  helper :karma_command do |cmd, args, event|
    cmd = :top unless cmd.is_a?(Symbol)

    karmas = get_karmas()
    msg = ""

    # Convert to an array and sort, highest to
    # lowest.
    karma_array = karmas.to_a.sort {|k1, k2| k2.last <=> k1.last}

    msg = case cmd
    when :points
      nick = event.from
      update_karma_points(nick)
      points_left(nick)
    when :search
      found = karma_array.select { |k|
        k.first.match(/#{args}/)
      }.collect { |k| 
        "%s: %s" % [k.first, k.last]
      }
      found[0..5].join(", ")
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
    when :agg
      agg = karma_array.inject(0) {|t, k| t += k.last}
      "The Aggregate Karma is: %s" % agg
    else
      "I don't know how to handle :#{cmd}"
    end

    return msg
  end

  helper :update_karma_points do |nick|
    cap = points_cap

    if nicks.has_key?(nick)
      # Method: Find how how much time has elapsed since
      # the last update. The divmod is how many points to
      # adjust by and the how much time is left until the
      # next point gain. If the total of points and the
      # adjust is greater than the cap, set the points to
      # the cap, else to the total. Set the last_used 
      # nick value to the time remaining.
      data   = nicks[nick]
      points = data[:points]
      last   = data[:last_used]
      now    = Time.now

      left, adjust = (now - last).divmod(regen)

      left   = now - left
      total  = points + adjust.to_i
      points = (total > cap) ? cap : total

      data = {:points => points, :last_used => left}
    else
      data = {:points => cap, :last_used => Time.now}
    end

    nicks[nick] = data

    return data
  end

  helper :points_left do |nick|
    points = nicks[nick][:points]

    return "You have %s karma points left, %s." % [points, nick]
  end

end
