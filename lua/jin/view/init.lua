-- jin:// buffers. A view (the `view=` parameter of the buffer name, `buffer`
-- when absent) decides which jj command fills the buffer.

local ansi = require("jin.ansi")
local args = require("jin.args")
local bufname = require("jin.bufname")
local workspace = require("jin.workspace")

local M = {}

M.SCHEME = "jin"

-- The views a buffer name may ask for, so that a name never loads an
-- arbitrary module.
local VIEWS = {
  buffer = true,
}

---How a view reads jj.
---@class jin.View
---@field command string[] jj words that precede the user's arguments, such as { "log" }
---@field filetype string

---@class jin.ViewOptions
---@field cwd? string a directory in the workspace to show; by default the current buffer's or directory's
---@field opener? string the command that opens the buffer, `edit` by default
---@field mods? string modifiers for the opener, such as `botright` or `tab`
---@field monochrome? boolean show jj's output without colors
---@field filetype? string the filetype of the buffer, the view's own by default
---@field reload? boolean read jj again when the buffer is already open

---Per host, per buffer: the generation of the latest read, and whether a
---read was shown since the buffer was loaded.
---@type table<jin.Host, table<integer, { generation: integer, shown?: boolean }>>
local states = setmetatable({}, { __mode = "k" })

---@param host jin.Host
---@param bufnr integer
local function state(host, bufnr)
  local per_host = states[host]
  if not per_host then
    per_host = {}
    states[host] = per_host
  end
  local s = per_host[bufnr]
  if not s then
    s = { generation = 0 }
    per_host[bufnr] = s
  end
  return s
end

---@param name string
---@return jin.View
function M.get(name)
  if not VIEWS[name] then
    error("jin: unknown view: " .. tostring(name), 0)
  end
  return require("jin.view." .. name)
end

---@param host jin.Host
---@param name string
---@return integer?
local function loaded(host, name)
  for _, buf in ipairs(host.buffers()) do
    if buf.name == name then
      return buf.bufnr
    end
  end
  return nil
end

---The buffer name of `view` showing `argv` with `opts`.
---@param jin jin.Api
---@param host jin.Host
---@param view string
---@param argv string[]
---@param opts jin.ViewOptions
---@return string
function M.name(jin, host, view, argv, opts)
  M.get(view)
  local root = jin.root(opts.cwd)
    or workspace.absolute(opts.cwd or host.cwd(), host.cwd(), host.realpath)
  local params = {}
  if view ~= "buffer" then
    params.view = view
  end
  if opts.monochrome then
    params.monochrome = true
  end
  if opts.filetype then
    params.filetype = opts.filetype
  end
  return bufname.format({ scheme = M.SCHEME, root = root, params = params, argv = argv })
end

---Open the buffer of `view` showing `argv`. Reading it is left to the editor
---(BufReadCmd), which calls `read`; an open buffer is read again only with
---`opts.reload`.
---@param jin jin.Api
---@param host jin.Host
---@param view string
---@param argv string[]
---@param opts jin.ViewOptions
---@return integer bufnr
function M.open(jin, host, view, argv, opts)
  local name = M.name(jin, host, view, argv, opts)
  local was_loaded = loaded(host, name) ~= nil
  local bufnr = host.open(name, { opener = opts.opener, mods = opts.mods })
  if opts.reload and was_loaded then
    M.read(jin, host, bufnr, name)
  end
  return bufnr
end

---@param text string
---@return string[]
local function split_lines(text)
  local lines = {}
  for line in text:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local rest = text:match("[^\n]*$")
  if rest ~= "" then
    lines[#lines + 1] = rest
  end
  return lines
end

---A short title for a buffer of `view` showing `argv`: the jj command, with
---the workspace left to the buffer name, IDs cut to 12 characters and words
---with spaces quoted, for a statusline to show in place of the long name.
---@param view jin.View
---@param argv string[]
---@return string
local function title_of(view, argv)
  local words = { "jj" }
  for _, list in ipairs({ view.command, argv }) do
    for _, word in ipairs(list) do
      if word:match("^%x+$") and #word > 12 then
        word = word:sub(1, 12)
      elseif word:find("[%s'\"]") then
        word = "'" .. word:gsub("'", "'\\''") .. "'"
      end
      words[#words + 1] = word
    end
  end
  return table.concat(words, " ")
end

---Fill the buffer `bufnr` named `name` with what jj prints for it. The read
---is asynchronous; a result is dropped when a newer read started meanwhile,
---or when the buffer no longer holds `name`.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
---@param name string
function M.read(jin, host, bufnr, name)
  local parsed = bufname.parse(name)
  if not parsed or parsed.scheme ~= M.SCHEME then
    error("jin: not a vim-jin buffer: " .. name, 0)
  end
  local view_name = parsed.params.view
  view_name = type(view_name) == "string" and view_name or "buffer"
  local view = M.get(view_name)
  local s = state(host, bufnr)
  s.generation = s.generation + 1
  local generation = s.generation

  local function current()
    return s.generation == generation and host.buffer_name(bufnr) == name
  end

  local argv = {}
  for _, list in ipairs({ view.command, parsed.argv }) do
    for _, a in ipairs(list) do
      argv[#argv + 1] = a
    end
  end
  jin.jj(argv, { cwd = parsed.root, color = not parsed.params.monochrome }, function(result)
    if not current() then
      return
    end
    local text = result.stdout
    if result.code ~= 0 then
      text = text .. result.stderr
    end
    local lines, spans = ansi.parse(split_lines(text))
    local groups, highlights = {}, {}
    for _, span in ipairs(spans) do
      local group = ansi.group(span.style)
      groups[group] = span.style
      highlights[#highlights + 1] =
        { line = span.line, col = span.col, end_col = span.end_col, group = group }
    end
    local fresh = not s.shown
    s.shown = true
    local filetype = parsed.params.filetype
    host.render(bufnr, {
      lines = lines,
      title = title_of(view, parsed.argv),
      highlights = highlights,
      groups = groups,
      filetype = type(filetype) == "string" and filetype or view.filetype,
      fresh = fresh,
    })
  end)
end

---Drop what is kept for `bufnr`, as when the buffer is unloaded: a read
---still running for it is ignored.
---@param host jin.Host
---@param bufnr integer
function M.forget(host, bufnr)
  local per_host = states[host]
  local s = per_host and per_host[bufnr]
  if s then
    s.generation = s.generation + 1
    per_host[bufnr] = nil
  end
end

---Read every loaded vim-jin buffer again.
---@param jin jin.Api
---@param host jin.Host
function M.reload(jin, host)
  for _, buf in ipairs(host.buffers()) do
    local parsed = bufname.parse(buf.name)
    if parsed and parsed.scheme == M.SCHEME then
      M.read(jin, host, buf.bufnr, buf.name)
    end
  end
end

M.OPTIONS = { opener = "value", monochrome = "flag", filetype = "value" }

---Open `view` for the arguments of its Ex command as typed.
---@param jin jin.Api
---@param host jin.Host
---@param view string
---@param line string
---@param opts { bang?: boolean, mods?: string }
---@return integer bufnr
function M.command(jin, host, view, line, opts)
  local options, rest = args.parse(args.split(line, require("jin.expand").expander(host)))
  args.validate(options, M.OPTIONS)
  local opener = options.opener
  local filetype = options.filetype
  return M.open(jin, host, view, rest, {
    opener = type(opener) == "string" and opener or nil,
    filetype = type(filetype) == "string" and filetype or nil,
    monochrome = options.monochrome ~= nil,
    mods = opts.mods,
    reload = opts.bang,
  })
end

return M
