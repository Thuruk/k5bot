# encoding: utf-8
# This file is part of the K5 bot project.
# See files README.md and COPYING for copyright and licensing information.

# Help plugin displays help

require_relative '../../IRCPlugin'

class Help < IRCPlugin
  Description = "The help plugin displays help."
  Commands = {
    :help => "lists available commands or shows information about specified command or plugin",
    :plugins => "lists the loaded plugins"
  }

  def afterLoad
    @pm = @plugin_manager
  end

  def on_privmsg(msg)
    case msg.botcommand
    when :help
      if msg.tail
        describe_word(msg, msg.tail)
      else
        msg.reply "Available commands: #{all_commands(msg.command_prefix)}"
      end
    when :plugins
      p = @pm.plugins.keys.sort*', '
      msg.reply "Loaded plugins: #{p}" if p && !p.empty?
    when :generate_help_markdown
      generate_markdown($stdout)
    end
  end

  private
  def all_commands(prefix)
    @pm.plugins.values.reject { |p| !p.commands }.collect {|p| '[' + p.commands.keys.collect {|c| "#{prefix}#{c.to_s}" } * ' ' + ']' } * ' '
  end

  def describe_word(msg, term)
    command_prefix = msg.command_prefix

    term = term.split(' ')

    word = term[0]
    found_plugin = @pm.plugins[word.to_sym]
    if found_plugin
      if found_plugin.description
        resp = browse_command_hierarchy(term[1..-1], found_plugin.description, [found_plugin.name])
        resp[:found].map! {|r| "Plugin #{r}"} if resp[:found]
        reply_with_hierarchy(msg, resp, '')
      else
        msg.reply("#{found_plugin.name} has no description.")
      end
      if term.size <= 1
        # Don't show commands if user is browsing description subkeys.
        msg.reply("#{found_plugin.name} commands: #{found_plugin.commands.keys.sort.collect{|c| "#{command_prefix}#{c.to_s}"}*', '}") if found_plugin.commands
      end
      return
    end

    plugin_list = @pm.plugins.each_pair

    word = term.shift
    #strip command prefix, if any
    word = word[/^#{Regexp.quote(command_prefix)}?(\S+)$/, 1]

    bot_command = word.downcase.to_sym

    found = plugin_list.map do |name, plugin|
      [name, plugin.commands && plugin.commands[bot_command]]
    end.select do |_, desc|
      !desc.nil?
    end

    if found.empty?
      msg.reply("There is no description for #{command_prefix}#{bot_command}.")
      return
    end

    result = {}

    found.each do |name, desc|
      resp = browse_command_hierarchy(term, desc, %W(#{command_prefix}#{bot_command}))
      resp[:found].map! {|r| "#{name} plugin: #{r}"} if resp[:found]

      result.merge!(resp) do |_, old_val, new_val|
        old_val |= new_val
        old_val
      end
    end

    reply_with_hierarchy(msg, result, command_prefix)
  end

  def reply_with_hierarchy(msg, result, command_prefix)
    if result[:found]
      result[:found].each do |r|
        msg.reply(r)
      end
      unless result[:also].empty?
        suggestion_list = format_suggestion_list(result[:also], command_prefix)
        msg.reply("See also: #{suggestion_list}")
      end
    elsif result[:fail_find]
      suggestion_list = format_suggestion_list(result[:fail_find], command_prefix)
      msg.reply("Key not found. Maybe you want: #{suggestion_list}")
    elsif result[:fail_descend]
      longest_descend = result[:fail_descend].max_by { |x| x.length }
      msg.reply("There are no sub-keys in: #{longest_descend}")
    else
      raise "Bug! Command hierarchy browsing produced: #{result}."
    end
  end

  def browse_command_hierarchy(hier_key, sub_catalog, ref_prefix)
    hier_key = hier_key.map {|x| x.downcase.to_sym}

    full_ref = ref_prefix.dup
    hier_key.each do |keyword|
      unless sub_catalog.is_a?(Hash)
        # Can't descend further. Remember how far we descended.
        return {:fail_descend => [full_ref.join(' ')]}
      end

      n = sub_catalog[keyword]
      unless n
        # Can't find keyword in current catalog. Add its keys as suggestions.
        known_keys = sub_catalog.keys.select { |x| !x.nil? }.map do |key|
          (full_ref + [key]).join(' ')
        end
        return {:fail_find => known_keys}
      end
      sub_catalog = n

      full_ref << keyword
    end

    if sub_catalog.is_a?(Hash)
      # Description comes from special 'nil' key.
      desc = sub_catalog[nil]
      # Mention sub-keys in "See also".
      see_also = sub_catalog.keys.select { |x| !x.nil? }.map do |key|
        (full_ref + [key]).join(' ')
      end
    else
      desc = sub_catalog
      see_also = []
    end
    {:found => ["#{full_ref.join(' ')}: #{desc}"], :also => see_also}
  end

  def format_suggestion_list(suggestions, command_prefix)
    suggestions.map { |r| "#{command_prefix}help #{r}" }.join(' | ')
  end

  def generate_markdown(target)
    plugin_list = @pm.plugins.each_pair

    found = plugin_list.map do |name, plugin|
      ["#{name} plugin", (plugin.commands || {}).merge({nil => plugin.description})]
    end.select do |_, desc|
      !desc.nil?
    end

    found = Hash[found]

    do_gen_markdown(target, found, 1)
  end

  MD_CHARS_MATCHER_ALL = /[\\`\*_{}\[\]\(\)#\+\-\.!]/

  def escape_markdown(text)
    text.to_s.gsub(MD_CHARS_MATCHER_ALL) do |m|
      "\\#{m}"
    end
  end

  def do_gen_markdown(target, category, level)
    if category.instance_of?(Hash)
      if category[nil]
        target << escape_markdown(category[nil])
        target << "\n"
      end
      category.each_pair do |key, subcategory|
        next if key.nil?

        target << '#' * level
        target << escape_markdown(key)
        target << "\n"

        do_gen_markdown(target, subcategory, level+1)
      end
    else
      target << escape_markdown(category)
      target << "\n"
    end
  end
end
