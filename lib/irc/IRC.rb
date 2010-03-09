
require 'socket'
require 'IRCConnection'
require 'IRCEvent'
require 'IRCChannel'
require 'IRCUser'
require 'IRCUtil'
require 'IRCTextUtil'
require 'IRCCTCP'


# Class IRC is a master class that handles connection to the irc
# server and parsing of IRC events, through the IRCEvent class. 
class IRC
  @channels = nil

  # Create a new IRC Object instance
  def initialize( nick, server, port, realname='RBot')
    @nick = nick
    @server = server
    @port = port
    @realname = realname
    @channels = Array.new(0)

    # Some good default Event handlers. These can and will be overridden
    # by users. These make changes on the IRCbot object. So they need to 
    # be here.
    
    # Topic events can come on two tags, so we have to handle both of them.
    ['332', 'topic'].each do |topic|    
      IRCEvent.add_handler(topic) do |event|
        self.channels.each do |chan| 
          chan.topic = event.message if chan == event.channel
        end
      end
    end

  end
  
  attr_reader :nick, :server, :port
  
  # Join a channel, adding it to the list of joined channels
  def add_channel(channel)
    join(channel)
    self
  end
  
  # Returns a list of channels joined
  def channels
    @channels
  end
  
  # Alias for IRC.connect
  def start
    self.connect
  end
  
  # Open a connection to the server using the IRC Connect
  # method. Events yielded from the IRCConnection handler are
  # processed and then control is returned to IRCConnection
  def connect
    quithandler = lambda { send_quit("SIG Caught!"); IRCConnection.quit }

    trap("INT", quithandler)
    trap("TERM", quithandler)

    IRCConnection.handle_connection(@server, @port, @nick, @realname) do
      # Log in information moved to IRCConnection

      # Commenting out threads for now. In a bot, race conditions can
      # happen, so for now, prefer a state-machine-esque process.
      # puts event.event_type
      #threads = []

      IRCConnection.main do |event|
        #threads << Thread.new(event) {|localevent|
        #  localevent.process
        #}
        event.process
      end

      #threads.each {|thr| thr.join }
    end
  end
  
  # Joins a channel on a server.
  def join(channel)
    if IRCConnection.send_to_server("JOIN #{channel}")
      @channels.push(IRCChannel.new(channel));
    end
  end
  
  # Leaves a channel on a server
  def part(channel)
    if IRCConnection.send_to_server("PART #{channel}")
      @channels.delete_if {|chan| chan.name == channel }
    end
  end
  
  # Sends a private message, or channel message
  def send_message(to, message)
    message = message.to_s

    message = message.split(/\n/)

    message.each do |line|
      IRCConnection.send_to_server("privmsg #{to} :#{line}");
    end
  end
  
  # Sends a notice
  def send_notice(to, message)
    message = message.to_s()

    message = message.split(/\n/)

    message.each do |line|
      IRCConnection.send_to_server("NOTICE #{to} :#{line}");
    end
  end
  
  # performs an action
  def send_action(to, action)
    send_ctcp(to, 'ACTION', action);
  end

  # send CTCP
  def send_ctcp(to, type, message)
    message = IRCCTCP.quote("#{type} #{message}")
    IRCConnection.send_to_server("privmsg #{to} :#{message}");
  end
  
  # Quits the IRC Server
  def send_quit(message="")
    if message.nil? or message.empty?
      message = "Quit ordered by user" 
    end
    IRCConnection.send_to_server("QUIT :#{message}")
    IRCConnection.quit()
  end
  
  # Ops selected user.
  def op(channel, user)
    IRCConnection.send_to_server("MODE #{channel} +o #{user}")
  end
  
  # Changes the current nickname
  def change_nick(nick)
    IRCConnection.send_to_server("NICK #{nick}")
    @nick = nick
  end
  
  # Removes operator status from a user
  def deop(channel, user)
    IRCConnection.send_to_server("MODE #{channel} -o #{user}")
  end
  
  # Changes target users mode
  def mode(channel, user, mode)
    IRCConnection.send_to_server("MODE #{channel} #{mode} #{user}")
  end
  
  # Retrievs user information from the server
  def get_user_info(user)
    IRCConnection.send_to_server("WHO #{user}")
  end
end
