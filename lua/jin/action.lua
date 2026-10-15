-- Actions: what can be done on the lines of a vim-jin buffer. Each is mapped
-- as <Plug>(jin-action-{name}) on the buffer; key mappings are left to the
-- ftplugin and the user.

local view = require("jin.view")

local M = {}

---@class jin.Action
---@field desc string
---@field fn fun(ctx: jin.ActionContext)

---@class jin.ActionContext
---@field jin jin.Api
---@field host jin.Host
---@field bufnr integer
---@field meta jin.ViewMeta
---@field first integer the first line acted on
---@field last integer the last line acted on
---@field entries string[][] the entries of those lines, once each, in order
---@field key? boolean whether a key asked for the action, rather than its name

---The openers an action that opens a view comes with.
local OPENERS = {
  { suffix = "", opener = "edit" },
  { suffix = ":split", opener = "split" },
  { suffix = ":vsplit", opener = "vsplit" },
  { suffix = ":tab", opener = "tabedit" },
}

---Make `name` and its `:split`, `:vsplit` and `:tab` variants, each calling
---`fn` with the opener to use.
---@param actions table<string, jin.Action>
---@param name string
---@param desc string
---@param fn fun(ctx: jin.ActionContext, opener: string)
function M.openers(actions, name, desc, fn)
  for _, o in ipairs(OPENERS) do
    actions[name .. o.suffix] = {
      desc = o.suffix == "" and desc or desc .. " (" .. o.opener .. ")",
      fn = function(ctx)
        fn(ctx, o.opener)
      end,
    }
  end
end

-- What an action raises, asked for by a key, on a line that names nothing.
local NOTHING = setmetatable({}, {
  __tostring = function()
    return "jin: nothing here"
  end,
})

---Raise `message`, telling why the lines acted on name nothing to act on;
---nothing at all when a key asked for the action.
---@param ctx jin.ActionContext
---@param message string
function M.nothing(ctx, message)
  if ctx.key then
    error(NOTHING, 0)
  end
  error(message, 0)
end

---Per host, per buffer: the action last chosen by name, for `repeat`.
---@type table<jin.Host, table<integer, string>>
local chosen = setmetatable({}, { __mode = "k" })

---@param view_def jin.View
---@return table<string, jin.Action>
local function actions_of(view_def)
  local all = {}
  for name, action in pairs(view_def.actions or {}) do
    all[name] = action
  end
  all.choice = {
    desc = "choose an action by name",
    fn = function(ctx)
      local name = ctx.host.input("action: ", "customlist,jin#action#complete")
      if not name or name == "" then
        return
      end
      -- Remembering choice or repeat would make repeat call itself.
      if name ~= "choice" and name ~= "repeat" then
        chosen[ctx.host] = chosen[ctx.host] or {}
        chosen[ctx.host][ctx.bufnr] = name
      end
      M.run(ctx.jin, ctx.host, ctx.bufnr, name, ctx.first, ctx.last)
    end,
  }
  all["repeat"] = {
    desc = "repeat the action last chosen by name",
    fn = function(ctx)
      local name = (chosen[ctx.host] or {})[ctx.bufnr]
      if not name then
        ctx.host.echo("jin: no action to repeat", "WarningMsg")
        return
      end
      M.run(ctx.jin, ctx.host, ctx.bufnr, name, ctx.first, ctx.last)
    end,
  }
  all.help = {
    desc = "list the actions and the keys mapped to them",
    fn = function(ctx)
      ctx.host.echo(M.help(ctx.host, all))
    end,
  }
  return all
end

---@param all table<string, jin.Action>
---@return string[]
local function sorted_names(all)
  local names = {}
  for name in pairs(all) do
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

---The action names of `view_def`, sorted.
---@param view_def jin.View
---@return string[]
function M.names(view_def)
  return sorted_names(actions_of(view_def))
end

---The key going to what each action opens, by the action, as gf goes to a
---file.
local GOES = {
  file = "gf",
  edit = "gf",
  diff = "gd",
  interdiff = "gd",
  parent = "gp",
  child = "gc",
}

---The default keys of `view_def` as { lhs, action, mode }, in normal mode
---unless `mode` says otherwise. A key that opens a view in a new window
---splits it vertically when `vertical`.
---@param view_def jin.View
---@param vertical boolean
---@return { [1]: string, [2]: string, [3]?: string }[]
function M.keys(view_def, vertical)
  local all = actions_of(view_def)
  local keys = { { "a", "choice" }, { ".", "repeat" }, { "?", "help" } }
  if view_def.primary then
    keys[#keys + 1] = { "<CR>", view_def.primary }
  end
  if view_def.secondary then
    -- Both, as terminals tell apart one or the other, or neither.
    keys[#keys + 1] = { "<S-CR>", view_def.secondary }
    keys[#keys + 1] = { "<C-CR>", view_def.secondary }
  end
  if view_def.primary and all[view_def.primary .. ":split"] then
    local split = vertical and ":vsplit" or ":split"
    keys[#keys + 1] = { "<C-w><CR>", view_def.primary .. split }
  end
  if view_def.yank then
    keys[#keys + 1] = { "yy", view_def.yank }
    keys[#keys + 1] = { "y", view_def.yank, "x" }
  end
  for _, name in ipairs(sorted_names(all)) do
    if name == "yank:commit" then
      keys[#keys + 1] = { "YY", name }
      keys[#keys + 1] = { "Y", name, "x" }
    end
    local goes = GOES[name]
    if goes then
      keys[#keys + 1] = { goes, name }
    end
  end
  return keys
end

---The help text: one line per action with the keys mapped to it.
---@param host jin.Host
---@param actions table<string, jin.Action>
---@return string
function M.help(host, actions)
  local keys = {}
  for _, map in ipairs(host.keymaps()) do
    local name = map.rhs:match("^<Plug>%(jin%-action%-(.+)%)$")
    if name and not map.lhs:match("^<Plug>") then
      keys[name] = keys[name] and (keys[name] .. " " .. map.lhs) or map.lhs
    end
  end
  -- The window variants of an action share its line, and their keys join its
  -- own: they differ in nothing but where the view opens.
  local names, variants = {}, {}
  for name in pairs(actions) do
    local base
    for _, o in ipairs(OPENERS) do
      if o.suffix ~= "" and name:sub(-#o.suffix) == o.suffix then
        base = name:sub(1, -#o.suffix - 1)
      end
    end
    if base and actions[base] then
      variants[base] = true
      if keys[name] then
        keys[base] = keys[base] and (keys[base] .. " " .. keys[name]) or keys[name]
      end
    else
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local key_width, name_width = 0, 0
  for _, name in ipairs(names) do
    key_width = math.max(key_width, #(keys[name] or ""))
    name_width = math.max(name_width, #name)
  end
  local lines = {}
  for _, name in ipairs(names) do
    local key = keys[name] or ""
    lines[#lines + 1] = key
      .. (" "):rep(key_width - #key + 2)
      .. name
      .. (" "):rep(name_width - #name + 2)
      .. actions[name].desc
      .. (variants[name] and " (also :split, :vsplit, :tab)" or "")
  end
  return table.concat(lines, "\n")
end

---Run the action `name` of the buffer `bufnr` on its lines `first`..`last`.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
---@param name string
---@param first integer
---@param last integer
---@param opts? { key?: boolean } `key` when a key asked for it: a line that
---names nothing then makes it do nothing, quietly, as a key pressed in the
---wrong place should, while an action chosen by name says why.
function M.run(jin, host, bufnr, name, first, last, opts)
  local meta = view.meta(host, bufnr)
  if not meta then
    error("jin: the buffer is still being read", 0)
  end
  local action = actions_of(view.get(meta.view))[name]
  if not action then
    error("jin: no action named " .. name .. " here", 0)
  end
  if first > last then
    first, last = last, first
  end
  local entries, seen = {}, {}
  for lnum = first, last do
    local entry = meta.entries[lnum]
    if entry and not seen[entry] then
      seen[entry] = true
      entries[#entries + 1] = entry
    end
  end
  local key = opts and opts.key or false
  local ok, err = pcall(action.fn, {
    jin = jin,
    host = host,
    bufnr = bufnr,
    meta = meta,
    first = first,
    last = last,
    entries = entries,
    key = key,
  })
  if not ok and err ~= NOTHING then
    error(err, 0)
  end
end

---The single entry acted on, or an error telling why there is none.
---@param ctx jin.ActionContext
---@return string[]
function M.entry(ctx)
  if #ctx.entries == 0 then
    M.nothing(ctx, "jin: nothing to act on in this line")
  end
  return ctx.entries[1]
end

return M
