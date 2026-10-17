-- jin:// buffers. A view (the `view=` parameter of the buffer name, `buffer`
-- when absent) decides which jj command fills the buffer, which configured
-- template it wraps with markers, and what each line stands for.

local ansi = require("jin.ansi")
local args = require("jin.args")
local bufname = require("jin.bufname")
local marker = require("jin.marker")
local workspace = require("jin.workspace")

local M = {}

M.SCHEME = "jin"

-- The views a buffer name may ask for, so that a name never loads an
-- arbitrary module.
local VIEWS = {
  buffer = true,
  log = true,
  show = true,
  diff = true,
  interdiff = true,
  file = true,
  oplog = true,
  opshow = true,
  evolog = true,
  status = true,
  annotate = true,
  bookmark = true,
  workspace = true,
  conflicts = true,
  resolve = true,
  describe = true,
  commit = true,
}

---How a view reads jj and makes sense of what it prints.
---@class jin.View
---@field command string[] jj words that precede the user's arguments, such as { "log" }
---@field filetype string
---@field template? { key: string, default: string, fields: string[], config?: boolean } wrap the configured templates.<key> (or the user's -T) with markers carrying `fields`; with `config`, hand it to jj as that setting rather than as -T, for a command that prints it within its own output
---@field config? string[] extra `--config` values, such as "ui.log-word-wrap=false"
---@field flags? string[] flags placed after `command`, such as "--color-words"
---@field decorate? fun(meta: jin.ViewMeta) compute view-specific data from the lines read
---@field actions? table<string, jin.Action> what can be done on its lines, beyond the actions every view has
---@field primary? string the action of <CR>: what a line of the view is most likely there for
---@field secondary? string the action of <S-CR> and <C-CR>: what a line is there for next most often
---@field yank? string the action of yy, and of y in visual mode
---@field detect? fun(meta: jin.ViewMeta): string? a path to take the filetype from, in place of `filetype`
---@field prepare? fun(argv: string[]): string[] rewrite the user's arguments before they reach jj
---@field needs_path? boolean refuse to open without the path of a file in the arguments
---@field editable? boolean a buffer to edit and hand back with `write`: read without colors, mapping no keys, and never read again by itself, which would lose what is being written
---@field write? fun(jin: jin.Api, host: jin.Host, bufnr: integer, parsed: jin.Bufname) hand what an editable buffer holds back to jj
---@field title? string[] the jj words its title names in place of `command`
---@field line_items? boolean each line stands for one thing, so the line under the cursor is highlighted as an entry would be
---@field entries_span_lines? boolean an entry, such as a change of the log, takes several lines, all highlighted while the cursor is on one
---@field scattered_changes? boolean the lines a change wrote lie apart, as in an annotation, and are all highlighted while the cursor is on one
---@field blocks? fun(meta: jin.ViewMeta): integer[] the first lines of the blocks ]] and [[ move between, in order, as jin.view.block finds them

---What a read left behind for actions to use.
---@class jin.ViewMeta
---@field name string
---@field parsed jin.Bufname
---@field view string
---@field lines string[] the text shown
---@field spans jin.AnsiSpan[] the colors jj gave `lines`; a `decorate` that replaces the lines replaces them too
---@field entries (string[]|false)[] per line, the marker fields of the entry it belongs to
---@field data table view-specific data set by `decorate`; its `folds` and `annotations` (per line, { text, style? } chunks shown before it) are shown as jin.Content says

---@class jin.ViewOptions
---@field cwd? string a directory in the workspace to show; by default the current buffer's or directory's
---@field opener? string the command that opens the buffer, `edit` by default
---@field mods? string modifiers for the opener, such as `botright` or `tab`
---@field monochrome? boolean show jj's output without colors
---@field filetype? string the filetype of the buffer, the view's own by default
---@field reload? boolean read jj again when the buffer is already open
---@field params? table<string, string|true> further view-specific parameters
---@field line? integer|string the line to put the cursor on once the buffer shows: its number, or a Lua pattern the line matches first

---The number of the line `line` stands for in `lines`: itself, or the first
---line matching it as a Lua pattern. Nil when no line matches.
---@param lines string[]
---@param line integer|string
---@return integer?
function M.line_of(lines, line)
  if type(line) == "number" then
    return line
  end
  for lnum, text in ipairs(lines) do
    if text:find(line) then
      return lnum
    end
  end
  return nil
end

---Per host, per buffer: the generation of the latest read and its result,
---and what it shows highlighted.
---@type table<jin.Host, table<integer, { generation: integer, meta?: jin.ViewMeta, line?: integer|string, change?: { meta: jin.ViewMeta, rev: string } }>>
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

---Per host, per workspace root, per template key: the template configured.
---@type table<jin.Host, table<string, table<string, string>>>
local templates = setmetatable({}, { __mode = "k" })

---@param name string
---@return jin.View
function M.get(name)
  if not VIEWS[name] then
    error("jin: unknown view: " .. tostring(name), 0)
  end
  return require("jin.view." .. name)
end

---The view a parsed vim-jin buffer name asks for.
---@param parsed jin.Bufname
---@return jin.View
local function view_of(parsed)
  local name = parsed.params.view
  return M.get(type(name) == "string" and name or "buffer")
end

---Register a view module `jin.view.{name}`.
---@param name string
function M.register(name)
  VIEWS[name] = true
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
  for k, v in pairs(opts.params or {}) do
    params[k] = v
  end
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
  local reading = opts.reload or not was_loaded
  if opts.reload then
    templates[host] = nil
  end
  if opts.line then
    if reading then
      state(host, bufnr).line = opts.line
    else
      local meta = M.meta(host, bufnr)
      local lnum = meta and M.line_of(meta.lines, opts.line)
      if lnum then
        host.cursor(bufnr, lnum)
      end
    end
  end
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

---Take the user's own -T / --template out of `argv`.
---@param argv string[]
---@return string[] rest
---@return string? template
local function take_template(argv)
  local rest, template = {}, nil
  local i = 1
  while i <= #argv do
    local a = argv[i]
    if a == "--" then
      for j = i, #argv do
        rest[#rest + 1] = argv[j]
      end
      break
    elseif (a == "-T" or a == "--template") and argv[i + 1] then
      template = argv[i + 1]
      i = i + 1
    elseif a:match("^%-%-template=") then
      template = a:sub(#"--template=" + 1)
    elseif a:match("^%-T.") then
      template = a:sub(3)
    else
      rest[#rest + 1] = a
    end
    i = i + 1
  end
  return rest, template
end

---The jj arguments that fill a buffer of `view`, with `template` wrapped.
---@param view jin.View
---@param user_argv string[]
---@param template? string
---@return string[]
local function command_line(view, user_argv, template)
  local argv = {}
  for _, word in ipairs(view.command) do
    argv[#argv + 1] = word
  end
  for _, value in ipairs(view.config or {}) do
    argv[#argv + 1] = "--config"
    argv[#argv + 1] = value
  end
  for _, flag in ipairs(view.flags or {}) do
    argv[#argv + 1] = flag
  end
  local setting
  if template and view.template.config then
    setting = marker.setting(view.template.key, view.template.fields, template)
  elseif template then
    argv[#argv + 1] = "-T"
    argv[#argv + 1] = marker.wrap(view.template.fields, template)
  end
  for _, a in ipairs(user_argv) do
    -- After the user's own settings, as the last --config of a key wins, but
    -- before `--`, after which jj takes every word for a path.
    if setting and a == "--" then
      argv[#argv + 1] = "--config"
      argv[#argv + 1] = setting
      setting = nil
    end
    argv[#argv + 1] = a
  end
  if setting then
    argv[#argv + 1] = "--config"
    argv[#argv + 1] = setting
  end
  return argv
end

---A short title for a buffer of `view` showing `argv`: the jj command, with
---the workspace left to the buffer name, IDs cut to 12 characters and words
---with spaces quoted, for a statusline to show in place of the long name.
---@param view jin.View
---@param argv string[]
---@return string
local function title_of(view, argv)
  local words = { "jj" }
  for _, list in ipairs({ view.title or view.command, argv }) do
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

  local function fill(user_argv, template)
    if view.prepare then
      user_argv = view.prepare(user_argv)
    end
    local argv = command_line(view, user_argv, template)
    local color = not parsed.params.monochrome and not view.editable
    jin.jj(argv, { cwd = parsed.root, color = color }, function(result)
      if not current() then
        return
      end
      local text = result.stdout
      if result.code ~= 0 then
        text = text .. result.stderr
      end
      local raw, entries = split_lines(text), {}
      if template then
        raw, entries = marker.parse(raw)
      end
      local lines, spans = raw, {}
      -- An editable buffer holds text to hand back as it is, which jj does
      -- not color: what looks like an escape sequence there is the text's.
      if not view.editable then
        lines, spans = ansi.parse(raw)
      end
      ---@type jin.ViewMeta
      local meta = {
        name = name,
        parsed = parsed,
        view = view_name,
        lines = lines,
        spans = spans,
        entries = entries,
        data = {},
      }
      if view.decorate then
        view.decorate(meta)
      end
      local groups = {}
      local function group_of(style)
        local group = ansi.group(style)
        groups[group] = style
        return group
      end
      local highlights = {}
      for _, span in ipairs(meta.spans) do
        highlights[#highlights + 1] =
          { line = span.line, col = span.col, end_col = span.end_col, group = group_of(span.style) }
      end
      local annotations
      if meta.data.annotations then
        annotations = {}
        for lnum, chunks in ipairs(meta.data.annotations) do
          local out = {}
          for i, chunk in ipairs(chunks) do
            out[i] = { text = chunk.text, group = chunk.style and group_of(chunk.style) or nil }
          end
          annotations[lnum] = out
        end
      end
      local previous = s.meta
      s.meta = meta
      local filetype = parsed.params.filetype
      local detect = view.detect and view.detect(meta)
      host.render(bufnr, {
        lines = meta.lines,
        title = title_of(view, parsed.argv),
        highlights = highlights,
        groups = groups,
        filetype = type(filetype) == "string" and filetype or (not detect and view.filetype or nil),
        detect = detect or nil,
        folds = meta.data.folds,
        annotations = annotations,
        editable = view.editable,
        fresh = not previous,
      })
      -- The mappings stay while the buffer is loaded; an unload forgets the
      -- previous read, so they are made again after it.
      -- An editable buffer maps no keys, as its text is there to be edited,
      -- but all its actions are there for the user to map.
      if not previous then
        local keys = view.editable and {} or require("jin.action").keys(view, host.vertical())
        host.define_actions(bufnr, require("jin.action").names(view), {
          view = view_name,
          keys = keys,
          motions = require("jin.view.block").keys(view),
        })
      end
      if s.line then
        local lnum = M.line_of(meta.lines, s.line)
        if lnum then
          host.cursor(bufnr, lnum)
        end
        s.line = nil
      end
      M.cursor_moved(host, bufnr)
    end)
  end

  if not view.template then
    fill(parsed.argv)
    return
  end
  -- A -T is the command's own when the template goes in as a setting.
  local user_argv, template = parsed.argv, nil
  if not view.template.config then
    user_argv, template = take_template(parsed.argv)
  end
  if template then
    fill(user_argv, template)
    return
  end
  templates[host] = templates[host] or {}
  local known = templates[host][parsed.root] or {}
  templates[host][parsed.root] = known
  local key = view.template.key
  if known[key] then
    fill(user_argv, known[key])
    return
  end
  jin.jj({ "config", "get", "templates." .. key }, { cwd = parsed.root }, function(result)
    local configured = result.code == 0 and result.stdout:gsub("\n$", "") or ""
    known[key] = configured ~= "" and configured or view.template.default
    if current() then
      fill(user_argv, known[key])
    end
  end)
end

-- What jj draws the graph of the log with, apart from the nodes.
local GRAPH = {
  "│",
  "├",
  "┤",
  "┬",
  "┴",
  "┼",
  "╭",
  "╮",
  "╯",
  "╰",
  "─",
  "~",
  "|",
  "/",
  "\\",
}

---Whether `line` holds nothing but the graph, and the note on revisions it
---leaves out.
---@param line string
---@return boolean
local function graph_only(line)
  for _, symbol in ipairs(GRAPH) do
    line = line:gsub(symbol:gsub("%p", "%%%0"), "")
  end
  line = line:gsub("%(elided revisions%)", "")
  return not line:find("%S")
end

---Highlight every line written by the change of the line under the cursor
---of `bufnr`, in a view where those lines lie apart.
---@param host jin.Host
---@param bufnr integer
---@param meta jin.ViewMeta
local function highlight_change(host, bufnr, meta)
  -- Required here: the views' support requires this module.
  local revision = require("jin.view.support").revision
  local lnum = host.line(bufnr)
  local entry = lnum and meta.entries[lnum]
  local rev = entry and revision(entry) or false
  local s = state(host, bufnr)
  local shown = s.change
  -- Moving within the lines of one change is the common case: go through
  -- the whole buffer again only when the change, or the read, is another.
  if shown and shown.meta == meta and shown.rev == rev then
    return
  end
  if not rev and not shown then
    return
  end
  local lnums = {}
  if rev then
    for l, e in ipairs(meta.entries) do
      if e and revision(e) == rev then
        lnums[#lnums + 1] = l
      end
    end
  end
  host.highlight_change(bufnr, lnums)
  s.change = rev and { meta = meta, rev = rev } or nil
end

---Highlight the lines of the entry under the cursor of `bufnr`, in a view
---whose entries span lines.
---@param host jin.Host
---@param bufnr integer
function M.cursor_moved(host, bufnr)
  local meta = M.meta(host, bufnr)
  if meta and M.get(meta.view).scattered_changes then
    highlight_change(host, bufnr, meta)
    return
  end
  if meta and M.get(meta.view).line_items then
    local lnum = host.line(bufnr)
    if lnum then
      host.highlight_lines(bufnr, lnum, lnum)
    end
    return
  end
  if not meta or not M.get(meta.view).entries_span_lines then
    return
  end
  local entries = meta.entries
  local lnum = host.line(bufnr)
  local entry = lnum and entries[lnum]
  if not entry then
    host.highlight_lines(bufnr)
    return
  end
  local first, last = lnum, lnum
  while first > 1 and entries[first - 1] == entry do
    first = first - 1
  end
  while entries[last + 1] == entry do
    last = last + 1
  end
  -- The markers carry an entry on to the lines after it, the graph's own
  -- among them, such as `~` below the last change shown.
  while last > first and graph_only(meta.lines[last]) do
    last = last - 1
  end
  if lnum > last then
    host.highlight_lines(bufnr)
    return
  end
  host.highlight_lines(bufnr, first, last)
end

---Jump to the first line of the block `count` blocks from the cursor of
---`bufnr`, forward or back, as ]] and [[ do; with no block that way, or in
---a view of none, the cursor stays.
---@param host jin.Host
---@param bufnr integer
---@param forward boolean
---@param count integer
function M.move_block(host, bufnr, forward, count)
  local meta = M.meta(host, bufnr)
  if not meta then
    return
  end
  local blocks = M.get(meta.view).blocks
  local lnum = blocks and host.line(bufnr)
  if not blocks or not lnum then
    return
  end
  local target = require("jin.view.block").target(blocks(meta), lnum, count, forward)
  if target then
    host.jump(bufnr, target)
  end
end

---What the latest read of `bufnr` left behind, or nil before it finished.
---@param host jin.Host
---@param bufnr integer
---@return jin.ViewMeta?
function M.meta(host, bufnr)
  local per_host = states[host]
  local s = per_host and per_host[bufnr]
  if not s or not s.meta or host.buffer_name(bufnr) ~= s.meta.name then
    return nil
  end
  return s.meta
end

---Drop what is kept for `bufnr`, as when the buffer is unloaded: its text
---and line metadata are freed, and a read still running for it is ignored.
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

---Read every loaded vim-jin buffer again, asking jj afresh for the
---configured templates too, as a jj command may have changed them.
---@param jin jin.Api
---@param host jin.Host
function M.reload(jin, host)
  templates[host] = nil
  for _, buf in ipairs(host.buffers()) do
    local parsed = bufname.parse(buf.name)
    if parsed and parsed.scheme == M.SCHEME and not view_of(parsed).editable then
      M.read(jin, host, buf.bufnr, buf.name)
    end
  end
end

---Per host, per workspace root: the latest operation `refresh` saw.
---@type table<jin.Host, table<string, string>>
local operations = setmetatable({}, { __mode = "k" })

---Whether a view of `parsed` follows the repository: a view, as the jj
---command of a raw buffer may change the repository when run again, and not
---one at a given operation, which no later one changes. An operation relative
---to the latest, such as `@-`, moves on with it.
---@param parsed jin.Bufname
---@return boolean
local function follows(parsed)
  if
    parsed.scheme ~= M.SCHEME
    or (parsed.params.view or "buffer") == "buffer"
    or view_of(parsed).editable
  then
    return false
  end
  local argv = parsed.argv
  for i, a in ipairs(argv) do
    if a == "--" then
      return true
    end
    local op = a:match("^%-%-at%-op[a-z]*=(.*)$")
    if not op and (a == "--at-op" or a == "--at-operation") then
      op = argv[i + 1] or ""
    end
    if op then
      return op:sub(1, 1) == "@"
    end
  end
  return true
end

---Read the loaded views of `bufnr`'s workspace, or of every workspace, again
---when the repository moved on since the last look, as when jj ran outside
---the editor. The first look at a workspace reads them again too, having
---nothing to compare with: a view read meanwhile may show the repository
---before the operation the look finds. Asking jj snapshots the working copy,
---so files changed without jj count too, unless every view of the workspace
---asks for no snapshot.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr? integer
function M.refresh(jin, host, bufnr)
  local only
  if bufnr then
    local name = host.buffer_name(bufnr)
    local parsed = name and bufname.parse(name)
    if not parsed or parsed.scheme ~= M.SCHEME then
      return
    end
    only = parsed.root
  end
  local by_root = {}
  for _, buf in ipairs(host.buffers()) do
    local parsed = bufname.parse(buf.name)
    if parsed and follows(parsed) and (not only or parsed.root == only) then
      by_root[parsed.root] = by_root[parsed.root] or {}
      table.insert(by_root[parsed.root], buf)
    end
  end
  operations[host] = operations[host] or {}
  local seen = operations[host]
  for root, bufs in pairs(by_root) do
    local query = { "op", "log", "--limit", "1", "--no-graph", "-T", 'id ++ "\\n"' }
    local snapshot = false
    for _, buf in ipairs(bufs) do
      -- jj takes no snapshot at an operation either, and a word after --
      -- is a path.
      local ignoring = false
      for _, a in ipairs(bufname.parse(buf.name).argv) do
        if a == "--" then
          break
        end
        ignoring = ignoring
          or a == "--ignore-working-copy"
          or a == "--at-op"
          or a == "--at-operation"
          or a:match("^%-%-at%-op[a-z]*=") ~= nil
      end
      snapshot = snapshot or not ignoring
    end
    if not snapshot then
      query[#query + 1] = "--ignore-working-copy"
    end
    jin.jj(query, { cwd = root }, function(result)
      if result.code ~= 0 then
        return
      end
      local id = result.stdout:gsub("\n$", "")
      local before = seen[root]
      seen[root] = id
      if before ~= id then
        for _, buf in ipairs(bufs) do
          if host.buffer_name(buf.bufnr) == buf.name then
            M.read(jin, host, buf.bufnr, buf.name)
          end
        end
      end
    end)
  end
end

---Hand what `bufnr` holds back to jj, as :w does in a buffer to edit.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
function M.write(jin, host, bufnr)
  local name = host.buffer_name(bufnr)
  local parsed = name and bufname.parse(name)
  if not parsed or parsed.scheme ~= M.SCHEME or not view_of(parsed).write then
    error("jin: this buffer is not to be written", 0)
  end
  view_of(parsed).write(jin, host, bufnr, parsed)
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
  -- Told here rather than by jj in the buffer: the command was typed wrong,
  -- and an empty buffer would only stand in the way.
  if M.get(view).needs_path and not require("jin.expand").file_path(rest) then
    error("jin: give the path of a file, such as %", 0)
  end
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
