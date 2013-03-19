# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# IRCBot

require 'socket'

require_relative '../../Timer'
require_relative '../../IRCPlugin'
require_relative '../UserPool/IRCUser'

require_relative 'IRCMessage'
require_relative 'IRCLoginListener'
require_relative 'IRCFirstListener'

class IRCBot < IRCPlugin

  Description = "Provides IRC connectivity."

  Dependencies = [ :UserPool, :ChannelPool, :Router ]

  attr_reader :last_sent, :last_received, :start_time, :user

  def afterLoad
    load_helper_class(:IRCMessage)
    load_helper_class(:IRCLoginListener)
    load_helper_class(:IRCFirstListener)

    @config = {
      :server => 'localhost',
      :port => 6667,
      :serverpass => nil,
      :username => 'bot',
      :nickname => 'bot',
      :realname => 'Bot',
      :userpass => nil,
      :channels => nil,
      :plugins  => nil,
    }.merge!(@config)

    @config.freeze  # Don't want anything modifying this

    @user = IRCUser.new(@config[:username], nil, @config[:realname], @config[:nickname])

    @login_listener = IRCLoginListener.new(self) # Set login listener

    @first_listener = IRCFirstListener.new # Set first listener

    @user_pool = @plugin_manager.plugins[:UserPool] # Get user pool
    @channel_pool = @plugin_manager.plugins[:ChannelPool] # Get channel pool
    @router = @plugin_manager.plugins[:Router] # Get router

    @watchdog = nil
  end

  def beforeUnload
    return "Can't unload before connection is killed" if @sock

    @router = nil
    @channel_pool = nil
    @user_pool = nil

    @first_listener = nil
    @login_listener = nil
    @user = nil

    unload_helper_class(:IRCFirstListener)
    unload_helper_class(:IRCLoginListener)
    unload_helper_class(:IRCMessage)

    nil
  end

  #truncates truncates a string, so that it contains no more than byte_limit bytes
  #returns hash with key :truncated, containing resulting string.
  #hash is used to avoid double truncation and for future truncation customization.
  def truncate_for_irc(raw, byte_limit)
    return raw if (raw.instance_of? Hash) #already truncated
    raw = encode raw.dup

    #char-per-char correspondence replace, to make the returned count meaningful
    raw.gsub!(/[\r\n]/, ' ')
    raw.strip!

    #raw = raw[0, 512] # Trim to max 512 characters
    #the above is wrong. characters can be of different size in bytes.

    truncated = raw.byteslice(0, byte_limit)

    #the above might have resulted in a malformed string
    #try to guess the necessary resulting length in chars, and
    #make a clean cut on a character boundary
    i = truncated.length
    loop do
      truncated = raw[0, i]
      break if truncated.bytesize <= byte_limit
      i-=1
    end

    {:truncated => truncated}
  end

  #truncates truncates a string, so that it contains no more than 510 bytes
  #we trim to 510 bytes, b/c the limit is 512, and we need to accommodate for cr/lf
  def truncate_for_irc_server(raw)
    truncate_for_irc(raw, 510)
  end

  #this is like truncate_for_irc_server(),
  #but it also tries to compensate for truncation, that
  #will occur, if this command is broadcast to other clients.
  def truncate_for_irc_client(raw)
    truncate_for_irc(raw, 510-@user.host_mask.bytesize-2)
  end

  def send(raw)
    send_raw(truncate_for_irc_client(raw))
  end

  #returns number of characters written from given string
  def send_raw(raw)
    raw = truncate_for_irc_server(raw)

    @last_sent = raw
    raw = raw[:truncated]
    log_sent_message(raw)

    @sock.write "#{raw}\r\n"

    raw.length
  end

  def log_sent_message(raw)
    str = raw.dup
    str.gsub!(@config[:serverpass], '*SRP*') if @config[:serverpass]
    str.gsub!(@config[:userpass], '*USP*') if @config[:userpass]
    puts "#{timestamp} \e[#34m#{str}\e[0m"
  end

  def receive(raw)
    @watch_time = Time.now

    raw = encode raw
    @last_received = raw
    puts "#{timestamp} #{raw}"

    @router.dispatch_message(IRCMessage.new(self, raw.chomp), [@login_listener, @first_listener])
  end

  def timestamp
    "\e[#37m#{Time.now}\e[0m"
  end

  def start
    @start_time = Time.now
    begin
      start_watchdog()

      server = @config[:server]
      if server.instance_of? Array
        server = server[rand(1..server.length)-1]
      end

      @sock = TCPSocket.open server, @config[:port]
      @login_listener.login
      until @sock.eof? do # Throws Errno::ECONNRESET
        receive @sock.gets
        # improve latency a bit, by flushing output stream,
        # which was probably written into during the process
        # of handling received data
        @sock.flush
      end
    rescue SocketError, Errno::ECONNRESET, Errno::EHOSTUNREACH => e
      puts "Cannot connect: #{e}"
    rescue IOError => e
      puts "IOError: #{e}"
    rescue SignalException => e
      raise e # Don't ignore signals
    rescue Exception => e
      puts "Unexpected exception: #{e}"
    ensure
      stop_watchdog()
      @sock = nil
    end
  end

  def stop
    if @sock
      puts "Forcibly closing socket"
      @sock.close
    end
  end

  def start_watchdog
    return if @watchdog
    if @config[:watchdog]
      @watch_time = Time.now
      @watchdog = Timer.new(30) do
        interval = @config[:watchdog]
        elapsed = Time.now - @watch_time
        if elapsed > interval
          puts "#{timestamp} Watchdog interval (#{interval}) elapsed, restarting bot"
          stop
        end
      end
    else
      @watchdog = nil
    end
  end

  def stop_watchdog
    return unless @watchdog
    @watchdog.stop
    @watchdog = nil
  end

  def join_channels(channels)
    send "JOIN #{channels*','}" if channels
  end

  def part_channels(channels)
    send "PART #{channels*','}" if channels
  end

  def find_user_by_msg(msg)
    @user_pool.findUser(msg)
  end

  def find_channel_by_msg(msg)
    @channel_pool.findChannel(msg)
  end

  def post_login
    #refresh our user info once,
    #so that truncate_for_irc_client()
    #will truncate messages properly
    @user_pool.request_whois(self, @user.nick)
    join_channels(@config[:channels])
  end

  private

  # Checks to see if a string looks like valid UTF-8.
  # If not, it is re-encoded to UTF-8 from assumed CP1252.
  # This is to fix strings like "abcd\xE9f".
  def encode(str)
    str.force_encoding('UTF-8')
    if !str.valid_encoding?
      str.force_encoding('CP1252').encode!("UTF-8", {:invalid => :replace, :undef => :replace})
    end
    str
  end
end

=begin
# The IRC protocol requires that each raw message must be not longer
# than 512 characters. From this length with have to subtract the EOL
# terminators (CR+LF) and the length of ":botnick!botuser@bothost "
# that will be prepended by the server to all of our messages.

# The maximum raw message length we can send is therefore 512 - 2 - 2
# minus the length of our hostmask.

max_len = 508 - myself.fullform.size

# On servers that support IDENTIFY-MSG, we have to subtract 1, because messages
# will have a + or - prepended
if server.capabilities["identify-msg""identify-msg"]
  max_len -= 1
end

# When splitting the message, we'll be prefixing the following string:
# (e.g. "PRIVMSG #rbot :")
fixed = "#{type} #{where} :"

# And this is what's left
left = max_len - fixed.size
=end
