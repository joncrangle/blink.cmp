local config = require('blink.cmp.config').trigger.completion
local sources = require('blink.cmp.sources.lib')
local utils = require('blink.cmp.utils')

local cmdline_trigger = {
  current_context_id = -1,
  --- @type blink.cmp.Context | nil
  context = nil,
  event_targets = {
    --- @type fun(context: blink.cmp.Context)
    on_show = function() end,
    --- @type fun()
    on_hide = function() end,
  },
}

function cmdline_trigger.activate_autocmds()
  local last_char = ''

  vim.api.nvim_create_autocmd('CmdlineChanged', {
    callback = function()
      if utils.is_blocked_buffer() then
        cmdline_trigger.hide()
        return
      end

      local cmdline = vim.fn.getcmdline()
      local cmdpos = vim.fn.getcmdpos()
      last_char = cmdpos > 1 and cmdline:sub(cmdpos - 1, cmdpos - 1) or ''

      -- Check if we're on a trigger character
      if vim.tbl_contains(sources.get_trigger_characters(), last_char) then
        cmdline_trigger.context = nil
        cmdline_trigger.show({ trigger_character = last_char })
        -- Check if we're typing a keyword
      elseif last_char:match(config.keyword_regex) ~= nil then
        cmdline_trigger.show()
      else
        cmdline_trigger.hide()
      end
    end
  })

  vim.api.nvim_create_autocmd('CmdlineChanged', {
    callback = function()
      if utils.is_blocked_buffer() then return end

      local cmdpos = vim.fn.getcmdpos()
      local cmdline = vim.fn.getcmdline()
      local char_under_cursor = cmdpos <= #cmdline and cmdline:sub(cmdpos, cmdpos) or ''

      local is_on_trigger = vim.tbl_contains(sources.get_trigger_characters(), char_under_cursor)
      local is_on_context_char = char_under_cursor:match(config.keyword_regex) ~= nil

      if cmdline_trigger.within_cmdline_bounds(cmdpos) then
        cmdline_trigger.show()
      elseif is_on_trigger and cmdline_trigger.context ~= nil then
        cmdline_trigger.context = nil
        cmdline_trigger.show({ trigger_character = char_under_cursor })
      elseif is_on_context_char and cmdline_trigger.context ~= nil then
        cmdline_trigger.show()
      else
        cmdline_trigger.hide()
      end
    end
  })

  vim.api.nvim_create_autocmd('CmdlineLeave', {
    callback = function()
      last_char = ''
      cmdline_trigger.hide()
    end
  })

  return cmdline_trigger
end

--- @param opts { trigger_character?: string, send_upstream?: boolean, force?: boolean } | nil
function cmdline_trigger.show(opts)
  opts = opts or {}

  local cmdpos = vim.fn.getcmdpos()
  local cmdline = vim.fn.getcmdline()

  if
      not opts.force
      and cmdline_trigger.context ~= nil
      and cmdpos == cmdline_trigger.context.cursor[2]
  then
    return
  end

  if cmdline_trigger.context == nil then
    cmdline_trigger.current_context_id = cmdline_trigger.current_context_id + 1
  end

  cmdline_trigger.context = {
    id = cmdline_trigger.current_context_id,
    bufnr = -1,
    cursor = { 1, cmdpos }, -- Using 1 as row since cmdline is single line
    line = cmdline,
    bounds = cmdline_trigger.get_cmdline_bounds(config.keyword_regex),
    trigger = {
      kind = opts.trigger_character and vim.lsp.protocol.CompletionTriggerKind.TriggerCharacter
          or vim.lsp.protocol.CompletionTriggerKind.Invoked,
      character = opts.trigger_character,
    },
  }

  if opts.send_upstream ~= false then
    cmdline_trigger.event_targets.on_show(cmdline_trigger.context)
  end
end

function cmdline_trigger.hide()
  if not cmdline_trigger.context then return end
  cmdline_trigger.context = nil
  cmdline_trigger.event_targets.on_hide()
end

--- @param callback fun(context: blink.cmp.Context)
function cmdline_trigger.listen_on_show(callback)
  cmdline_trigger.event_targets.on_show = callback
end

--- @param callback fun()
function cmdline_trigger.listen_on_hide(callback)
  cmdline_trigger.event_targets.on_hide = callback
end

--- @param cmdpos number
--- @return boolean
function cmdline_trigger.within_cmdline_bounds(cmdpos)
  if not cmdline_trigger.context then return false end

  local bounds = cmdline_trigger.context.bounds
  return cmdpos >= bounds.start_col and cmdpos <= bounds.end_col
end

--- @param regex string
--- @return blink.cmp.ContextBounds
function cmdline_trigger.get_cmdline_bounds(regex)
  local cmdpos = vim.fn.getcmdpos()
  local cmdline = vim.fn.getcmdline()

  local start_col = cmdpos
  while start_col > 1 do
    local char = cmdline:sub(start_col - 1, start_col - 1)
    if char:match(regex) == nil then
      break
    end
    start_col = start_col - 1
  end

  local end_col = cmdpos - 1
  while end_col < #cmdline do
    local char = cmdline:sub(end_col + 1, end_col + 1)
    if char:match(regex) == nil then break end
    end_col = end_col + 1
  end

  local length = end_col - start_col + 1
  if start_col == end_col and cmdline:sub(start_col, end_col):match(regex) == nil then
    length = 0
  end

  return {
    line_number = 1,
    start_col = start_col,
    end_col = end_col,
    length = length
  }
end

return cmdline_trigger
