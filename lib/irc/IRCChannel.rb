require "IRCUser"

# Represents an IRC Channel
class IRCChannel

  ChannelSigils = ["#", "&", "+", "!"]
  ChannelSigilRE = /^[#{ChannelSigils.join('')}]/

  def IRCChannel.is_channel?(channel="")
    return true if ChannelSigils.include?(channel[0].chr)
  end

  # Returns the channel with out the channel sigil.
  def IRCChannel.strip(channel)
    return channel.gsub(ChannelSigilRE, '')
  end

  attr_reader :name

  def initialize(name)
    @name = name
    @users = Array.new(0)
    @topic = nil
  end
  
  # set the topic on this channel
  def topic=(topic)
    @topic = topic
  end

  # get the topic on this channel
  def topic 
    return @topic if @topic
    return "No Topic set"
  end
  
  # add a user to this channel's userlist
  def add_user(username)
    @users.push(IRCUser.create_user(username))
  end

  # returns the current user list for this channel
  def users
    @users
  end
end
