
# Handles connection to IRC Server
class IRCConnection

  # Controls the connection loop.
  @@quit = false

  # Holds our socket objects.
  @@readsockets = Array.new(0)

  # Holds the event handlers.
  @@events = Hash.new()

  # Creates a socket connection and then yields.
  def IRCConnection.handle_connection(server, port, nick='ChangeMe', realname='MeToo' )
    @server = server
    @port = port
    @nick = nick
    @realname = realname

    socket = create_tcp_socket(server, port)

    add_IO_socket(socket) do |sock| 
      begin
        IRCEvent.new(sock.readline.chomp) 
      rescue Errno::ECONNRESET
        # Catches connection reset by peer, attempts to reconnect
        # after sleeping for 10 second.
        remove_IO_socket(sock)
        sleep 5
        handle_connection(@server, @port, @nick, @realname)
      end
    end

    send_to_server "NICK #{nick}"
    send_to_server "USER #{nick} 8 * :#{realname}"

    if block_given?
      yield
      @@socket.close
    end
  end
  
  def IRCConnection.create_tcp_socket(server, port)
    @@socket = TCPSocket.open(server, port)
    if block_given?
      yield
      @@socket.close
      return
    end
    return @@socket
  end
  
  # Sends a line of text to the server
  def IRCConnection.send_to_server(line)
    @@socket.write(line + "\n")
  end
  
  # This loop monitors all IO_Sockets IRCConnection controls
  # (including the IRC socket) and yields events to the IO_Sockets
  # event handler. 
  def IRCConnection.main
    while not @@quit
      do_one_loop do |event|
        yield event
      end
    end
  end

  # Makes one single loop pass, checking all sockets for data to read,
  # and yields the data to the sockets event handler.
  def IRCConnection.do_one_loop
    read_sockets = select(@@readsockets, nil, nil, nil);

    read_sockets[0].each do |sock|
      if sock.eof? && sock == @@socket
        puts "Detected Socket Close"
        remove_IO_socket(sock)
        sleep 5
        handle_connection(@server, @port, @nick, @realname)
      else
        yield @@events[sock.to_i].call(sock)
      end
    end
  end

  # Ends connection to the irc server
  def IRCConnection.quit
    @@quit = true
  end 

  # Retrieves user info from the server
  def IRCConnection.get_user_info(user)
    IRCConnection.send_to_server("WHOIS #{user}")
  end

  # Adds a new socket to the list of sockets to monitor for new data.
  def IRCConnection.add_IO_socket(socket, &event_generator)
    @@readsockets.push(socket)
    @@events[socket.to_i] = event_generator
  end

  def IRCConnection.remove_IO_socket(sock)
    sock.close
    @@readsockets.delete_if {|item| item == sock }
    @@quit = false
  end
end


