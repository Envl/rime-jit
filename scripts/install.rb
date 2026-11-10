require 'fileutils'
require 'tempfile'
require 'yaml'

# Edit the user's existing patch in place, preserving comments and other keys.
dir = ENV.fetch('RIME_USER_DIR', File.expand_path('~/Library/Rime'))
abort '找不到小鹤双拼方案' unless File.file?(File.join(dir, 'double_pinyin_flypy.schema.yaml'))
path = File.join(dir, 'double_pinyin_flypy.custom.yaml')
original = File.exist?(path) ? File.read(path, encoding: 'UTF-8') : "patch:\n"
component = 'lua_translator@*screen_words'
key = 'engine/translators/+'
parse = ->(text) { YAML.safe_load(text) || {} }
config = parse.call(original)
patch = config.fetch('patch') || {}
complete = [patch[key], patch['engine/translators']].any? { |list| Array(list).include?(component) } ||
  patch.any? { |k, v| k.start_with?('engine/translators/@') && v == component }
updated = original
unless complete
  # Rime's @next inserts a single translator, even if a separate '+' list already exists.
  slot = 'engine/translators/@next'
  abort "已有 #{slot} 配置，请将 #{component} 添加到现有 translators 列表。" if patch.key?(slot)
  updated = original.sub(/^patch:[ \t]*(?:#[^\n]*)?$/) { |line| "#{line}\n  \"#{slot}\": #{component}" }
  abort '当前补丁格式需要手动添加 translator' unless parse.call(updated)['patch'] == patch.merge(slot => component)
end

def atomic_write(path, data)
  Tempfile.create(['screenwords-', '.tmp'], File.dirname(path)) do |file|
    file.write(data)
    file.close
    File.rename(file.path, path)
  end
end

lua = File.join(dir, 'lua', 'screen_words.lua')
FileUtils.mkdir_p(File.dirname(lua))
source = File.read(File.expand_path('../Rime/screen_words.lua', __dir__))
if File.exist?(lua) && File.read(lua) != source && !File.read(lua).start_with?('-- RimeScreenWords')
  abort "已有同名脚本，请先检查 #{lua}"
end
atomic_write(lua, source) unless File.exist?(lua) && File.read(lua) == source
atomic_write(path, updated) unless updated == original
puts '已配置小鹤双拼屏幕词 translator'
