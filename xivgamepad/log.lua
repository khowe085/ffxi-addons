-- Central logging (contract: .planning/xivgamepad-contracts.md, "Logger").
-- Leaf module: depends only on the windower global and the files library.

local files = require('files')

local addon_path = nil
local debug_enabled = false
local pending_session = false

local chat_color_info  = 207
local chat_color_error = 167
local chat_prefix      = 'XIVGamepad: '
-- The Windower files API resolves paths relative to windower.addon_path;
-- only windower.create_dir takes absolute paths (see ensure_data_dir).
local log_file_relpath = 'data/debug.log'

local M = {}

local append_line, emit, ensure_data_dir, format_message, path_parts, start_session

function M.debug(fmt, ...)
  if not debug_enabled then return end
  emit('debug', chat_color_info, format_message(fmt, ...))
end

function M.error(fmt, ...)
  emit('error', chat_color_error, format_message(fmt, ...))
end

function M.info(fmt, ...)
  emit('info', chat_color_info, format_message(fmt, ...))
end

function M.init(path)
  addon_path = path
  if pending_session then
    pending_session = false
    start_session()
  end
end

function M.is_debug()
  return debug_enabled
end

function M.set_debug(enabled)
  enabled = not not enabled
  local turning_on = enabled and not debug_enabled
  debug_enabled = enabled
  if not enabled then
    pending_session = false
    return
  end
  if turning_on then
    if addon_path then
      start_session()
    else
      pending_session = true
    end
  end
end

function M.toggle()
  M.set_debug(not debug_enabled)
  return debug_enabled
end

append_line = function(level, message)
  if not addon_path then return end
  local f = files.new(log_file_relpath)
  f:append(os.date('%Y-%m-%d %H:%M:%S') .. ' [' .. level .. '] ' .. message .. '\n')
end

emit = function(level, color, message)
  windower.add_to_chat(color, chat_prefix .. message)
  if debug_enabled then
    append_line(level, message)
  end
end

-- create_dir takes an absolute path and is not recursive: create only the
-- single data level beneath addon_path (which always exists), never walking
-- above it.
ensure_data_dir = function()
  if not (windower and windower.create_dir) then return end
  local base, sep = path_parts()
  windower.create_dir(base .. sep .. 'data')
end

-- A log call must never raise: with no varargs the message passes through
-- verbatim (so literal % is safe); a failed string.format falls back to fmt.
format_message = function(fmt, ...)
  fmt = tostring(fmt)
  if select('#', ...) == 0 then
    return fmt
  end
  local ok, formatted = pcall(string.format, fmt, ...)
  if ok then
    return formatted
  end
  return fmt
end

path_parts = function()
  local sep = addon_path:find('\\', 1, true) and '\\' or '/'
  return (addon_path:gsub('[/\\]+$', '')), sep
end

start_session = function()
  ensure_data_dir()
  local f = files.new(log_file_relpath)
  f:write('=== XIVGamepad debug session started ' .. os.date('%Y-%m-%d %H:%M:%S') .. ' ===\n')
end

return M
