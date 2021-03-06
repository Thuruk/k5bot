# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# Internationalization plugin

require 'rubygems'
require 'bundler/setup'
require 'i18n'

require_relative '../../IRCPlugin'

class I18N < IRCPlugin
  Description = 'Internationalization plugin.'
  Commands = {
      :i18n_reload => 'reloads i18n translation files',
      :i18n_set => 'set i18n locale',
  }

  def on_privmsg(msg)
    case msg.bot_command
      when :i18n_reload
        I18n.load_path = Dir[File.join(File.dirname(__FILE__), 'locales', '*.yml')]
        I18n.backend.load_translations
        msg.reply("Reloaded translations. Available locales: #{format_available_locales}")
      when :i18n_set
        new_locale = msg.tail && msg.tail.to_sym
        unless I18n::available_locales.include?(new_locale)
          msg.reply("Unknown locale. Available locales: #{format_available_locales}")
          return
        end

        msg.reply("Changed I18n locale to #{new_locale}. Previous locale: #{I18n.locale || I18n.default_locale}")
        I18n.locale = I18n.default_locale = new_locale
    end
  end

  def format_available_locales
    I18n::available_locales.map(&:to_s).join(', ')
  end
end
