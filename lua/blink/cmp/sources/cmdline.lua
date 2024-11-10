-- credit to https://github.com/hrsh7th/cmp-cmdline for the original implementation

--- @class blink.cmp.Source
local cmdline = {}

---@param patterns string[]
---@param head boolean
---@return table #regex object
local function create_regex(patterns, head)
  local pattern = [[\%(]] .. table.concat(patterns, [[\|]]) .. [[\)]]
  if head then
    pattern = '^' .. pattern
  end
  return vim.regex(pattern)
end

local MODIFIER_REGEX = create_regex({
  [=[\s*abo\%[veleft]\s*]=],
  [=[\s*bel\%[owright]\s*]=],
  [=[\s*bo\%[tright]\s*]=],
  [=[\s*bro\%[wse]\s*]=],
  [=[\s*conf\%[irm]\s*]=],
  [=[\s*hid\%[e]\s*]=],
  [=[\s*keepal\s*t]=],
  [=[\s*keeppa\%[tterns]\s*]=],
  [=[\s*lefta\%[bove]\s*]=],
  [=[\s*loc\%[kmarks]\s*]=],
  [=[\s*nos\%[wapfile]\s*]=],
  [=[\s*rightb\%[elow]\s*]=],
  [=[\s*sil\%[ent]\s*]=],
  [=[\s*tab\s*]=],
  [=[\s*to\%[pleft]\s*]=],
  [=[\s*verb\%[ose]\s*]=],
  [=[\s*vert\%[ical]\s*]=],
}, true)

local COUNT_RANGE_REGEX = create_regex({
  [=[\s*\%(\d\+\|\$\)\%[,\%(\d\+\|\$\)]\s*]=],
  [=[\s*'\%[<,'>]\s*]=],
  [=[\s*\%(\d\+\|\$\)\s*]=],
}, true)

local ONLY_RANGE_REGEX = create_regex({
  [=[^\s*\%(\d\+\|\$\)\%[,\%(\d\+\|\$\)]\s*$]=],
  [=[^\s*'\%[<,'>]\s*$]=],
  [=[^\s*\%(\d\+\|\$\)\s*$]=],
}, true)

-- Option name completion pattern
local OPTION_NAME_COMPLETION_REGEX = create_regex({
  [=[se\%[tlocal][^=]*$]=],
}, true)

---@param word string
---@return boolean?
local function is_boolean_option(word)
  local ok, opt = pcall(function()
    return vim.opt[word]:get()
  end)
  if ok then
    return type(opt) == 'boolean'
  end
end

function cmdline.new(opts)
  local self = setmetatable({}, { __index = cmdline })

  opts = vim.tbl_deep_extend('keep', opts or {}, {
    ignore_cmds = { '!', 'Man' },
    treat_trailing_slash = true,
  })
  vim.validate({
    ignore_cmds = { opts.ignore_cmds, 'table' },
    treat_trailing_slash = { opts.treat_trailing_slash, 'boolean' },
  })

  self.opts = opts
  return self
end

function cmdline:get_trigger_characters() return { ' ', '.', '#', '-' } end

function cmdline:enabled() return vim.fn.mode() == 'c' end

function cmdline:get_completions(context, callback)
  local cursor_before_line = context.line:sub(1, context.cursor[2])

  local transformed_callback = function(items)
    callback({
      context = context,
      is_incomplete_forward = false,
      is_incomplete_backward = false,
      items = items,
    })
  end

  if ONLY_RANGE_REGEX:match_str(cursor_before_line) then
    transformed_callback({})
    return function() end
  end

  -- Parse command line
  local target = cursor_before_line
  local s, e = COUNT_RANGE_REGEX:match_str(target)
  if s and e then
    target = target:sub(e + 1)
  end

  local parsed = {}
  pcall(function()
    parsed = vim.api.nvim_parse_cmd(target, {}) or {}
  end)

  -- Check ignored commands
  if vim.tbl_contains(self.opts.ignore_cmds, parsed.cmd) then
    transformed_callback({})
    return function() end
  end

  local cleaned_line = cursor_before_line
  while true do
    local ms, me = MODIFIER_REGEX:match_str(cleaned_line)
    if not ms then
      break
    end
    cleaned_line = cleaned_line:sub(1, ms) .. cleaned_line:sub(me + 1)
  end

  local items = {} ---@type table<string,lsp.CompletionItem>
  local escaped = cleaned_line:gsub([[\\]], [[\\\\]])
  local completions = vim.fn.getcompletion(escaped, 'cmdline')

  for _, word in ipairs(completions) do
    if word then
      local item = {
        label = word,
        kind = require('blink.cmp.types').CompletionItemKind.Text,
        insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
        insertText = word,
      }

      -- Handle boolean options
      if OPTION_NAME_COMPLETION_REGEX:match_str(cleaned_line) and is_boolean_option(word) then
        table.insert(items, item)
        table.insert(items, {
          label = 'no' .. word,
          kind = vim.lsp.protocol.CompletionItemKind.Text
        })
      else
        table.insert(items, item)
      end
    end
  end

  -- Handle trailing slashes for paths
  if self.opts.treat_trailing_slash then
    for _, item in ipairs(items) do
      local is_target = string.match(item.label, [[/$]])
      is_target = is_target and not string.match(item.label, [[~/$]])
      is_target = is_target and not string.match(item.label, [[%./$]])
      is_target = is_target and not string.match(item.label, [[%.%./$]])
      if is_target then
        item.label = item.label:sub(1, -2)
      end
    end
  end

  transformed_callback(items)
end

return cmdline
