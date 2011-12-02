#
# This is a Kernel extension to add event/callbacks, in a generic
# way, to Ruby. This is not nearly as cool as Qt's signal/slot 
# system, but should work for simple projects.
#
# Three events are pre-defined:
#
#  :event_created  -- when a new event is created.
#  :event_emitted  -- when a event is emitted, but only if it
#                     is _NOT_ :event_emitted.
#  :event_removed  -- when a event is removed.
# 
# Event handler callbacks are by default not threaded; they are
# called in sequential order they were observed in, with the next
# one being called after the prior one finishes. If you wish to 
# use threading, call:
# 
#   set_threaded_events(true)
# 
# Afterwards, all handler callbacks will be wrapped in Thread
# objects and joined immediately.
# 
# To find out if events are being threaded, you can call:
# 
#   are_events_threaded?
# 
# ...which will return true if threads are being used.
# 
#
# Author:: Randy Carnahan
# Copyright:: Copyright (c) 2009 Randy Carnahan
# License:: Distributed under the same terms as the Ruby language.
#
module Kernel

  # Our events hash. Each key will reference an array of +Proc+
  # objects that are the event callbacks.
  @@kernel_events = {
    :event_created => [],
    :event_emitted => [],
    :event_removed => []
  }

  # If this is true, then event callbacks will be ran
  # in threads.
  @@threaded_events = false

  # Holds our silenced events. Events in this array are not emitted
  # if they have been silencted.
  @@silenced_events = []

  # If this is set to true, and an event handler has an error,
  # it is quietly ignored and the next handler is called.
  @@supress_exceptions = false

  # EventError Exception to handle all event related errors.
  class EventError < StandardError
  end

  # Adds the event to the events hash.
  # +event+ must be a Symbol or a String, or else an EventError
  # is raised.
  # The :event_created event is emitted after creation.
  def create_event(event)
    event = symbolize_event(event)

    if not @@kernel_events.has_key?(event)
      @@kernel_events[event] = []
      emit_event(:event_created, event)
      return true
    end
    return false
  end

  # Removes +event+ from the events hash.
  # The :event_removed event is emitted if the removal was
  # successful.
  def remove_event(event)
    event = symbolize_event(event)

    if @@kernel_events.has_key?(event)
      @@kernel_events.delete(event)
      emit_event(:event_removed, event)
    end

    return event
  end

  # Checks for a specific event, and returns true if it exists as
  # a key in the events hash.
  def has_event?(event)
    event = symbolize_event(event)
    return @@kernel_events.has_key?(event) ? true : false
  end

  # This will return true if event callbacks are handled
  # via threads, otherwise false.
  def are_events_threaded?
    return @@threaded_events
  end

  # Call this method to watch for an event to happen.
  # +event+:: The event to watch.
  # +create_event_if_needed+:: If the event doesn't exist yet,
  #  create it.
  # +block+:: The anonymous block to be called when the event happens.
  #
  # The ID of the block is returned, which needs to be used to remove
  # an observer.
  def observe_event(event, create_if_needed=nil, &block)
    event = symbolize_event(event)

    if not has_event?(event)
      if create_if_needed
        create_event(event)
      else
        raise EventError, "No event known by: #{event}:#{event.class}"
      end
    end

    @@kernel_events[event].push(block) 
    return block.object_id
  end

  # This will remove an event handler from an observed event.
  # +event+:: The event to remove the handler from.
  # +handler_id+:: This is the handler id of the block that was
  #   returned from observe_event() -- if you didn't save the value
  #   you won't be able to remove the observer!
  def unobserve_event(event, handler_id)
    event = symbolize_event(event)

    if @@kernel_events.has_key?(event)
      @@kernel_events.delete_if do |evt, handler| 
        handler.object_id == handler_id
      end
    end

    return event
  end

  # Call this method when you are ready to announce that an event has happened.
  # +event+:: The event that is happening.
  # The values in the args parameter will be passed to the callback.
  # The :event_emitted event is emitted _after_ all callbacks for a given
  # event have been called and _only_ if a callback was called.
  # The :event_emitted event is _not_ emitted if :event_emitted was the
  # event being emitted.
  def emit_event(event, *args)
    event = symbolize_event(event)

    return false if @@silenced_events.include?(event)

    has_done_callback = false

    if has_event?(event)
      @@kernel_events[event].each do |callback|
        begin
          if @@threaded_events
            Thread.new { callback.call(event, *args) }.join()
          else
            callback.call(event, *args)
          end
        rescue Exception => err
          if @@suppress_exceptions
            next
          else
            raise
          end
        end
        has_done_callback = true
      end
    else
      raise EventError, "No event known by: #{event}:#{event.class}"
    end

    if has_done_callback and event != :event_emitted
      emit_event(:event_emitted, event)
    end
    return has_done_callback
  end

  # Calling this with a true value will cause all event callbacks
  # to be wrapped in their own threads.
  def set_threaded_events(bool=true)
    @@threaded_events = (bool ? true : false)
  end

  # This will cause an event's callbacks to _not_ be called when the 
  # event is emitted.
  # If called with a block, then the event will be silenced until
  # the block is finished.
  def silence_event(event)
    event = symbolize_event(event)
    @@silenced_events.push(event) unless @@silenced_events.include?(event)

    if block_given?
      yield
      unsilence_event(event)
    end

    return event
  end

  # Unsilenced an event if it has previously been silenced.
  def unsilence_event(event)
    event = symbolize_event(event)
    return @@silenced_events.delete(event)
  end

  # This sets to suppression of exceptions for event handlers. If
  # bool is set is true, then exceptions from handlers are quietly
  # ignored and any following handlers are called, otherwise the 
  # exception is raised.
  def suppress_exceptions(bool=true)
    @@suppress_exceptions = (bool ? true : false)
  end

  # Will symbolize the event name, if it is a string, or raise
  # an EventError if the event is not a string or already a 
  # symbol. All events will be downcased and any spaces replaced with
  # underscores.
  def symbolize_event(event)
    case event
    when Symbol
      return event
    when String
      return event.downcase.gsub(/\s+/, "_").to_sym()
    else
      raise EventError, "Given Event is not a string or symbol!"
    end
  end

end

