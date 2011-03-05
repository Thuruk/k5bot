# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# IRCUserManager keeps track of all users. It keeps the user database
# updated by listening to user-related messages.

require 'IRC/IRCUser'

class IRCUserManager < IRCListener
	def initialize(router)
		super
		@usernames = {}
		@nicknames = {}
	end

	def on_353(msg)
		msg.params.last.split(/ /).each{|nickname| update nickname}
	end
	alias on_rpl_namreply on_353

	def on_privmsg(msg)
		update msg.nick, msg.user, msg.host
	end

	private
	def update(nickname=nil, username=nil, host=nil, realname=nil)
		if username
			user = @usernames[username] ||= IRCUser.new(username, host, realname)
			user.host ||= host
			user.realname ||= realname
		end
		if nickname
			@nicknames[nickname] = user || IRCUser.new(username, host, realname)
		end
	end

	def rename(oldnick, newnick)
		@nicknames[newnick] = @nicknames.delete oldnick
	end
end
