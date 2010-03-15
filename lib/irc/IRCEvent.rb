require 'yaml'

# This is a lookup class for IRC event name mapping
class EventLookup
  @@lookup = YAML.load_file("#{File.dirname(__FILE__)}/eventmap.yml")
  
  # returns the event name, given a number
  def EventLookup::find_by_number(num)
    return @@lookup[num.to_i]
  end
end


# Handles an IRC generated event.
# Handlers are called in the order they were given to 
# add_handler(). In all events, the "all" event is called
# first. If any handler returns a nil value, no other
# handlers following it are called.
class IRCEvent
  @@handlers = { 
    'all' => [],
    'ping' => [Proc.new {|event| IRCConnection.send_to_server("PONG #{event.message}")}] 
  }
  attr_reader :hostmask, :message, :event_type, :from, :channel, :target, :mode, :stats

  def initialize (line)

    line.sub!(/^:/, '')
    mess_parts = line.split(':', 2);

    # mess_parts[0] is server info
    # mess_parts[1] is the message that was sent
    @message = mess_parts[1]
    @stats = mess_parts[0].scan(/[-\w.\#\@\+]+/)
 
    if @stats[0].match(/^PING/)
      @event_type = 'ping'
    elsif @stats[1] && @stats[1].match(/^\d+/)
      @event_type = EventLookup::find_by_number(@stats[1]);
      @channel = @stats[3]
    else
      @event_type = @stats[2].downcase if @stats[2]
    end
    
    if @event_type != 'ping'
      @from = @stats[0] 
      @user = IRCUser.create_user(@from)
    end

    @hostmask = @stats[1] if %W(privmsg join).include? @event_type
    @channel = @stats[3] if @stats[3] and !@channel
    @target  = @stats[5] if @stats[5]
    @mode    = @stats[4] if @stats[4]


    #####################################################
    # Unfortunatly, not all messages are created equal. # 
    # This is our special exceptions section            #
    #####################################################

    @channel = @message if @event_type == 'join'

    # This is to differtiate public messages.  We'll change the
    # event_type. Further, if the message is a ctcp message, we
    # dequote it and set the event_type to the ctcp tag.
    # For example, this would be an ctcp action payload:
    #
    #  '\001ACTION some action here...\001'
    #
    # which would get returned as an array of:
    #
    #  ['ACTION', 'some action here...']
    #
    # This, the event_type would be 'ctcp_action' and message will
    # be set to the ctcp types data. UNLESS the message is untagged
    # then it's just set as a pubmsg.
    if @event_type == 'privmsg' and "#&+!".index(@channel[0].chr)
      if IRCCTCP.is_ctcp?(@message)
        ctcp_message = IRCCTCP.dequote(@message)
        case ctcp_message
        when String
          @message = ctcp_message
        when Array
          # Just grab the first one for now. I have not ever
          # seen multiple CTCP messages in one line before.
          ctcp_event = ctcp_message.first()
          @event_type = ctcp_event.first.downcase()
          @message = ctcp_event.last()
        end
      else
        @event_type = 'pubmsg'
      end
    end

    # For 'nick' events, we create two methods
    if @event_type == 'nick'
      def self.old_nick
        return @from
      end
      def self.new_nick
        return @message
      end
    end
    
  end
  
  # Adds a handler to the handler function hash.
  # XXX Add a priority argument here.
  def IRCEvent.add_handler(event_type, &block)
    begin
      event_type = event_type.to_s.downcase()
      @@handlers[event_type] = [] if not @@handlers.has_key?(event_type)
      @@handlers[event_type].push(block)
      return block.object_id
    rescue Exception
      return false
    end
  end

  def IRCEvent.remove_handler(event_type, block_obj_id)
    event_type = event_type.to_s.downcase() if event_type.is_a?(Symbol)
    @@handlers[event_type].reject! { |block| block.object_id == block_obj_id }
  end

  # Process this event, preforming which ever handler and callback is specified
  # for this event.
  def process

    # Our default return value
    handled = false

    # The 'all' handlers always get called.
    handlers = @@handlers["all"]

    # Now add the other handlers for this event if they exist.
    if @@handlers.has_key?(@event_type)
      handlers += @@handlers[@event_type]
    end

    # Call handlers in order.
    handlers.each do |handler|
      begin
        handler.call(self)
        handled = true # At least one handler was called.
      rescue => err
        $stderr.write("Error handling event #{@event_type}: #{err}\n    #{err.backtrace.join("\n    ")}\n\n")
      end
    end

    return handled
  end
end

