module IRCTextUtil

  # Text Formats
  FORMATS = {
    :bold      => "\x02",
    :fixed     => "\x11",
    :italic    => "\x1d",
    :reverse   => "\x16",
    :underline => "\x1f",
  }

  # Text Colors
  COLORS = {
    :white         => "00",
    :black         => "01",
    :dark_blue     => "02",
    :dark_green    => "03",
    :light_red     => "04",
    :dark_red      => "05",
    :magenta       => "06",
    :orange        => "07",
    :yellow        => "08",
    :light_green   => "09",
    :cyan          => "10",
    :light_cyan    => "11",
    :light_blue    => "12",
    :light_magenta => "13",
    :grey          => "14",
    :light_grey    => "15"
  }

  def IRCTextUtil.get_format_string(options={})
    fs = "%s"

    return fs if not options.is_a?(Hash)

    formats = []
    fg_color = nil
    bg_color = nil

    # Run through our options, finding any formats and
    # the foreground and background colors.
    options.each do |key, value|
      value = value.to_sym() if value.is_a?(String)
      case key
      when :color, :foreground, :fg
        fg_color = value
      when :background, :bg
        bg_color = value
      else
        if FORMATS.has_key?(key) and value
          formats.push(key)
        end
      end
    end

    # First we do the colors.
    fs = wrap_in_color(fs, fg_color, bg_color)

    # And then we do the formats.
    formats.each do |format|
      fs = wrap_in_format(fs, format)
    end

    return fs
  end

  def IRCTextUtil.wrap_text(text, options={})
    return get_format_string(options) % text
  end

  def IRCTextUtil.wrap_in_color(text, fg=nil, bg=nil)

    if COLORS.has_key?(fg)
      color = COLORS[fg]

      if COLORS.has_key?(bg)
        color += "," + COLORS[bg]
      end

      return "\x03#{color}#{text}\x03"
    else
      return text
    end
  end

  def IRCTextUtil.wrap_in_format(text, format)
    return text unless FORMATS.has_key?(format)
    format = FORMATS[format]
    return "#{format}#{text}#{format}"
  end

  def IRCTextUtil.wrap_in_bold(text)
    return wrap_in_format(text, :bold)
  end

  def IRCTextUtil.wrap_in_underline(text)
    return wrap_in_format(text, :underline)
  end

  def IRCTextUtil.wrap_in_italics(text)
    return wrap_in_format(text, :italic)
  end

  def IRCTextUtil.wrap_in_reverse(text)
    return wrap_in_format(text, :reverse)
  end

end
