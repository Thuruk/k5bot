# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# IRCMessageHandler routes messages to its listeners

require 'set'
require_relative 'IRCListener'

class IRCMessageRouter < IRCListener
  def initialize()
    @listeners = []
  end

  alias :dispatch_message_to_self :receive_message
  def receive_message(msg)
    @listeners.each do |listener|
      begin
        listener.receive_message(msg)
      rescue => e
        puts "Listener error: #{e}\n\t#{e.backtrace.join("\n\t")}"
      end
    end
  end
  alias :dispatch_message_to_children :receive_message

  def register(listener)
    @listeners << listener if listener
  end

  def unregister(listener)
    @listeners.delete_if{|l| l == listener}
  end
end
