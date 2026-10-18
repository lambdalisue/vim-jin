-- Editing a diff for jj in the editor: jj runs vim-jin's diff editor, which
-- asks for the two directories of the diff and the output to fill; vim-jin
-- lists the files that differ, lets the output of each be edited or
-- restored, and answers done or abort (docs/adr/20261018-hand-jjs-tools-to-the-running-editor-as-three-panes-answered-by-writing-the-list.md).

local tool = require("jin.tool")

local M = {}

---@class jin.DiffEdit
---@field id integer
---@field kind "diff"|"merge"
---@field base? string the base of a conflict, for a merge
---@field output string what jj takes: the directory to fill for a diff, a copy of `right` to begin with, or the result of a merge, holding jj's conflict markers to edit
---@field operation string the jj command that asked, such as "split"
---@field initial? string what jj wrote to the result of a merge, before any edit
---@field root string
---@field fifo string
---@field left string
---@field right string
---@field answered? boolean
---@field listed? jin.DiffEditFile[] the files its list shows, line by line
---@field on_abort? fun() called once the session is answered abort

---@class jin.DiffEditFile
---@field status string M modified, A added, D removed, C conflicted
---@field path string
---@field edited boolean what jj takes of it is no longer what it was handed

---Per host: the sessions asked for, by ID, and the last ID given.
---@type table<jin.Host, { last: integer, sessions: table<integer, jin.DiffEdit> }>
local registry = setmetatable({}, { __mode = "k" })

---@param host jin.Host
local function of(host)
  registry[host] = registry[host] or { last = 0, sessions = {} }
  return registry[host]
end

-- What jj puts in the right directory to explain itself, not a file of the
-- change.
local INSTRUCTIONS = "JJ-INSTRUCTIONS"

---The session `id` of `host`, or nil once it is gone.
---@param host jin.Host
---@param id integer?
---@return jin.DiffEdit?
function M.get(host, id)
  return of(host).sessions[id]
end

---What the file at `path` is, compared as a diff compares: what it points
---at for a symbolic link, its content and executable bit for a file, nil
---for none.
---@param host jin.Host
---@param path string
---@return string?
local function state(host, path)
  local link = host.link(path)
  if link then
    return "link:" .. link
  end
  local content = host.read_file(path)
  if not content then
    return nil
  end
  return (host.executable(path) and "x:" or "f:") .. content
end

---The files that differ between the two sides of `session`, by path, each
---with its status: M modified, its content or its executable bit, A added
---on the right, D only on the left; and whether it is edited, its output
---no longer the right side.
---@param host jin.Host
---@param session jin.DiffEdit
---@return jin.DiffEditFile[]
function M.files(host, session)
  if session.kind == "merge" then
    -- jj names the files of a conflict output_<name>, base_<name> and so on.
    local name = session.output:match("output_([^/]*)$") or session.output
    local edited = host.read_file(session.output) ~= session.initial
    return { { status = "C", path = name, edited = edited } }
  end
  local seen, paths = {}, {}
  for _, dir in ipairs({ session.left, session.right }) do
    for _, path in ipairs(host.files(dir)) do
      if not seen[path] and path ~= INSTRUCTIONS then
        seen[path] = true
        paths[#paths + 1] = path
      end
    end
  end
  table.sort(paths)
  local files = {}
  for _, path in ipairs(paths) do
    -- A symbolic link is what it points at, not the file it leads to.
    local left = state(host, session.left .. "/" .. path)
    local right = state(host, session.right .. "/" .. path)
    if left ~= right then
      local status = (not left and "A") or (not right and "D") or "M"
      local edited = state(host, session.output .. "/" .. path) ~= right
      files[#files + 1] = { status = status, path = path, edited = edited }
    end
  end
  return files
end

---The view of the pane in the middle, where what jj takes is edited.
---@param session jin.DiffEdit
---@return "merge"|"result"
function M.pane_view(session)
  return session.kind == "merge" and "merge" or "result"
end

---The middle panes of `session` that are loaded, each with the path of its
---file, by buffer.
---@param host jin.Host
---@param session jin.DiffEdit
---@return { bufnr: integer, path: string, modified: boolean }[]
function M.panes(host, session)
  local found = {}
  for _, buf in ipairs(host.buffers()) do
    local parsed = require("jin.bufname").parse(buf.name)
    if
      parsed
      and parsed.params.view == M.pane_view(session)
      and parsed.argv[1] == tostring(session.id)
      and parsed.argv[2]
    then
      found[#found + 1] = { bufnr = buf.bufnr, path = parsed.argv[2], modified = buf.modified }
    end
  end
  return found
end

---The paths of the files of `session` whose middle pane is edited but not
---written.
---@param host jin.Host
---@param session jin.DiffEdit
---@return string[]
function M.unsaved(host, session)
  local paths = {}
  for _, pane in ipairs(M.panes(host, session)) do
    if pane.modified then
      paths[#paths + 1] = pane.path
    end
  end
  return paths
end

---Whether `path` names a file inside a directory jj handed over, and none
---outside it, such as through "..".
---@param path string
---@return boolean
function M.inside(path)
  for part in (path .. "/"):gmatch("([^/]*)/") do
    if part == "" or part == "." or part == ".." then
      return false
    end
  end
  return true
end

---The directory of `path`, or of a directory above it, that is a symbolic
---link in one of `dirs` of `session`, its sides and its output by default,
---if any. Going through it would reach wherever it points.
---@param host jin.Host
---@param session jin.DiffEdit
---@param path string
---@param dirs? string[]
---@return string?
function M.linked_parent(host, session, path, dirs)
  local parent = ""
  for part in path:gmatch("([^/]+)/") do
    parent = parent == "" and part or parent .. "/" .. part
    for _, dir in ipairs(dirs or { session.left, session.right, session.output }) do
      if host.link(dir .. "/" .. parent) then
        return parent
      end
    end
  end
  return nil
end

---Answer `session` with `word`, done or abort, once.
---@param host jin.Host
---@param session jin.DiffEdit
---@param word "done"|"abort"
function M.answer(host, session, word)
  if session.answered then
    return
  end
  session.answered = true
  of(host).sessions[session.id] = nil
  if word == "abort" and session.on_abort then
    session.on_abort()
  end
  host.answer(session.fifo, word .. "\n")
end

---Answer abort to every session still waiting, as when the editor exits:
---jj would otherwise wait for an answer nobody gives.
---@param host jin.Host
function M.abort_all(host)
  for _, session in pairs(of(host).sessions) do
    M.answer(host, session, "abort")
  end
end

---Run jj `argv` with vim-jin's diff editor, opening the list of the files
---to edit when it asks.
---@param jin jin.Api
---@param host jin.Host
---@param argv string[]
---@param opts { cwd: string, merge?: boolean, on_exit?: fun(result: jin.RunResult) } `merge` for vim-jin's merge tool, as jj resolve runs; `on_exit` receives jj's result once it has exited
function M.run(jin, host, argv, opts)
  local fifo = host.fifo()
  local full, paths = {}, {}
  for _, word in ipairs(argv) do
    -- After --, jj takes every word for a path, the tool's options included.
    if word == "--" or #paths > 0 then
      paths[#paths + 1] = word
    else
      full[#full + 1] = word
    end
  end
  for _, list in ipairs({ opts.merge and tool.merge_args(fifo) or tool.args(fifo), paths }) do
    for _, word in ipairs(list) do
      full[#full + 1] = word
    end
  end
  local aborted = false
  local asked = {}
  jin.command(full, {
    cwd = opts.cwd,
    -- Silent: jj fails once the edit is aborted, which the user asked for.
    silent = true,
    on_stderr = function(line)
      local ask = tool.parse(line)
      if not ask then
        return
      end
      local registered = of(host)
      registered.last = registered.last + 1
      local session = {
        id = registered.last,
        kind = ask.kind,
        root = opts.cwd,
        fifo = ask.fifo,
        left = ask.left,
        right = ask.right,
        base = ask.base,
        output = ask.output,
        operation = argv[1],
        initial = ask.kind == "merge" and host.read_file(ask.output) or nil,
      }
      session.on_abort = function()
        aborted = true
      end
      registered.sessions[session.id] = session
      asked[#asked + 1] = session
      -- In a window of its own, so that leaving it, as :q does, leads back
      -- to where the user was rather than out of the editor.
      require("jin.view").open(
        jin,
        host,
        "diffedit",
        { tostring(session.id) },
        { cwd = opts.cwd, opener = "split", mods = "botright" }
      )
    end,
  }, function(result)
    -- jj waits on no session once it has exited, and the pipe goes with it:
    -- an answer now would only write a stray file where the pipe was.
    for _, session in ipairs(asked) do
      session.answered = true
      of(host).sessions[session.id] = nil
    end
    host.delete_file(fifo)
    if result.code ~= 0 and not aborted then
      local own = {}
      for line in result.stderr:gmatch("[^\n]+") do
        if not tool.parse(line) then
          own[#own + 1] = line
        end
      end
      if #own > 0 then
        host.echo(table.concat(own, "\n"), "ErrorMsg")
      end
    end
    if opts.on_exit then
      opts.on_exit(result)
    end
  end)
end

return M
