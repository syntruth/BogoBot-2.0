module IRCCTCP

  LOW_LEVEL_QUOTE = "\020"
  CTCP_LEVEL_QUOTE = "\134"
  CTCP_DELIMITER = "\001"

  LOW_LEVEL_MAPPING = {
    "0" => "\000",
    "n" => "\n",
    "r" => "\r",
    LOW_LEVEL_QUOTE => LOW_LEVEL_QUOTE
  }

  LOW_LEVEL_RE = /#{LOW_LEVEL_QUOTE}(.)/

  def IRCCTCP.is_ctcp?(message)
    return message.include?(CTCP_DELIMITER)
  end

  def IRCCTCP.quote(message)
    LOW_LEVEL_MAPPING.each do |key, value|
      message.gsub!(/#{value}/, key)
    end
    return CTCP_DELIMITER + message + CTCP_DELIMITER
  end

  def IRCCTCP.dequote(message)
    if message.include?(LOW_LEVEL_QUOTE)
      message.gsub!(LOW_LEVEL_RE) do |match|
        if LOW_LEVEL_MAPPING.has_key?($1)
          LOW_LEVEL_MAPPING[$1]
        else
          match
        end
      end
    end

    if message.include?(CTCP_DELIMITER)

      parts = message.split(CTCP_DELIMITER).reject { |part| part.empty? }

      all = parts.inject([]) do |arr, part|
        part.any? ? arr.push(part.split(/\s/, 2)) : arr
      end

      if parts.length() % 2 == 0
        all.push(CTCP_DELIMITER + parts.last())
      end

      return all
    else
      return message
    end
  end

end
