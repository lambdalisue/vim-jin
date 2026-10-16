-- Statusline components: short strings about the workspace of the current
-- buffer. Reading one never runs jj; it returns what the last refresh found
-- and asks for a refresh, which runs in the background without snapshotting
-- the working copy or adding an operation.

local jj = require("jin.jj")

local M = {}

-- A component shown longer than this is refreshed when it is next read. Buffer
-- switches, focus and jj commands refresh it sooner; this only catches what
-- changes the repository while the editor keeps focus, such as an agent.
local TTL = 30000

local SEP = "\31"

-- The working-copy change, one value per field, separated by SEP.
local CHANGE = table.concat({
  "change_id.shortest()",
  "description.first_line()",
  'if(empty, "empty")',
  'if(conflict, "conflict")',
  'if(divergent, "divergent")',
  "working_copies",
}, ' ++ "\\x1f" ++ ')

-- The nearest bookmarks: a local one as its name, a tracked remote one as
-- name@remote with how far the local bookmark is ahead of and behind it.
local BOOKMARKS = 'if(remote, if(tracked, name ++ "@" ++ remote ++ "\\x1f"'
  .. ' ++ self.tracking_behind_count().lower() ++ "\\x1f"'
  .. ' ++ self.tracking_ahead_count().lower() ++ "\\n"), name ++ "\\n")'

-- When the operation that ended, in seconds since the epoch.
local ENDED = 'time.end().format("%s%.3f")'

---The components, by name, and what each shows.
M.NAMES = {
  change = "the shortest unique prefix of the working-copy change ID",
  description = "the first line of the working-copy change's description",
  state = "empty, conflict and divergent, as they apply to the working-copy change",
  bookmarks = "the nearest bookmarks at or below the working copy",
  traffic = "how far the nearest bookmarks are ahead (↑) of and behind (↓) their remotes",
  workspace = "the workspaces whose working copy is this change, when there are several",
}

---Per host, per workspace root: the values found and when.
---@type table<jin.Host, table<string, { values?: table<string, string>, time?: number, running?: boolean, again?: boolean, scheduled?: boolean, wanted?: boolean }>>
local states = setmetatable({}, { __mode = "k" })

---Per host, per buffer name and directory: the workspace root, or false
---outside any workspace. A statusline reads components on every redraw, and
---looking for the root walks up the directory tree.
---@type table<jin.Host, table<string, string|false>>
local roots = setmetatable({}, { __mode = "k" })

---@param host jin.Host
---@return string?
local function root_of(host)
  roots[host] = roots[host] or {}
  local key = host.bufname() .. "\n" .. host.cwd()
  local root = roots[host][key]
  if root == nil then
    root = jj.root(host) or false
    roots[host][key] = root
  end
  return root or nil
end

---@param host jin.Host
---@param root string
local function state(host, root)
  states[host] = states[host] or {}
  local s = states[host][root]
  if not s then
    s = {}
    states[host][root] = s
  end
  return s
end

---@param text string
---@return string[]
local function fields(text)
  local values = {}
  for value in (text .. SEP):gmatch("(.-)" .. SEP) do
    values[#values + 1] = value
  end
  return values
end

---@param change jin.RunResult
---@param bookmarks jin.RunResult
---@return table<string, string>
local function compute(change, bookmarks)
  local values = {}
  for name in pairs(M.NAMES) do
    values[name] = ""
  end
  if change.code == 0 then
    local f = fields((change.stdout:gsub("\n$", "")))
    values.change = f[1] or ""
    values.description = f[2] or ""
    local state_words = {}
    for i = 3, 5 do
      if f[i] and f[i] ~= "" then
        state_words[#state_words + 1] = f[i]
      end
    end
    values.state = table.concat(state_words, " ")
    values.workspace = f[6] or ""
  end
  if bookmarks.code == 0 then
    local names, traffic = {}, {}
    for line in bookmarks.stdout:gmatch("[^\n]+") do
      local f = fields(line)
      if #f == 1 then
        names[#names + 1] = f[1]
      else
        local ahead, behind = tonumber(f[2]) or 0, tonumber(f[3]) or 0
        if ahead > 0 or behind > 0 then
          traffic[#traffic + 1] = f[1]
            .. (ahead > 0 and ("↑" .. ahead) or "")
            .. (behind > 0 and ("↓" .. behind) or "")
        end
      end
    end
    values.bookmarks = table.concat(names, " ")
    values.traffic = table.concat(traffic, " ")
  end
  return values
end

---The operation heads jj named when `result` failed because the operation
---log has diverged, or nil when it failed otherwise.
---@param result jin.RunResult
---@return string[]?
local function diverged_heads(result)
  if result.code == 0 or not result.stderr:find("resolved to more than one operation", 1, true) then
    return nil
  end
  local heads = {}
  for id in (result.stderr:match("by ID: ([^\n]*)") or ""):gmatch("%x+") do
    heads[#heads + 1] = id
  end
  return #heads > 0 and heads or nil
end

---Call `on_found` with the head among `heads` whose operation ended last, or
---nil when none says. jj refuses `--at-op=@` while the operation log has
---diverged, and leaving `--at-op` out would merge the heads, adding an
---operation, which watching must never do.
---@param jin jin.Api
---@param root string
---@param heads string[]
---@param on_found fun(id: string?)
local function newest_head(jin, root, heads, on_found)
  local ended, pending = {}, #heads
  for i, id in ipairs(heads) do
    local argv =
      { "--at-op=" .. id, "--ignore-working-copy", "op", "log", "-n1", "--no-graph", "-T", ENDED }
    jin.jj(argv, { cwd = root }, function(result)
      ended[i] = result.code == 0 and tonumber((result.stdout:gsub("%s+$", ""))) or false
      pending = pending - 1
      if pending > 0 then
        return
      end
      local best
      for j = 1, #heads do
        if ended[j] and (not best or ended[j] > ended[best]) then
          best = j
        end
      end
      on_found(best and heads[best] or nil)
    end)
  end
end

---Refresh the components of the workspace at `root` in the background, and
---fire User JinComponentPost when any of them changed. Asked while a refresh
---is running, it refreshes once more after that one, which may have looked
---before the repository changed.
---@param jin jin.Api
---@param host jin.Host
---@param root string
function M.refresh(jin, host, root)
  local s = state(host, root)
  if s.running then
    s.again = true
    return
  end
  s.running = true
  local change, bookmarks
  local query
  local function done(at)
    if not change or not bookmarks then
      return
    end
    local heads = at == "@" and (diverged_heads(change) or diverged_heads(bookmarks))
    if heads then
      newest_head(jin, root, heads, function(id)
        if id then
          query(id)
        else
          done()
        end
      end)
      return
    end
    s.running = false
    s.time = host.now()
    local values = compute(change, bookmarks)
    local changed = not s.values
    for name, value in pairs(values) do
      changed = changed or s.values[name] ~= value
    end
    s.values = values
    if changed then
      host.doautocmd("JinComponentPost")
    end
    if s.again then
      s.again = false
      M.refresh(jin, host, root)
    end
  end
  ---Look at the repository as of the operation `at`, neither snapshotting
  ---the working copy nor adding an operation.
  ---@param at string
  function query(at)
    change, bookmarks = nil, nil
    local quiet = { "--at-op=" .. at, "--ignore-working-copy" }
    local argv = { quiet[1], quiet[2], "log", "--no-graph", "-r", "@", "-T", CHANGE }
    jin.jj(argv, { cwd = root }, function(result)
      change = result
      done(at)
    end)
    argv = {
      quiet[1],
      quiet[2],
      "bookmark",
      "list",
      "-r",
      "heads(::@ & bookmarks())",
      "-T",
      BOOKMARKS,
    }
    jin.jj(argv, { cwd = root }, function(result)
      bookmarks = result
      done(at)
    end)
  end
  query("@")
end

---The component `name` for the current buffer's workspace: what the last
---refresh found, "" before that or outside any workspace. When that is
---missing or old, a refresh is scheduled; reading never runs jj itself, so
---a statusline may call this freely.
---@param jin jin.Api
---@param host jin.Host
---@param name string
---@return string
function M.get(jin, host, name)
  if not M.NAMES[name] then
    return ""
  end
  local root = root_of(host)
  if not root then
    return ""
  end
  local s = state(host, root)
  -- Only a workspace whose components are read is ever refreshed.
  s.wanted = true
  if not s.running and not s.scheduled and (not s.time or host.now() - s.time >= TTL) then
    -- The statusline may be drawn many times before the refresh starts.
    s.scheduled = true
    host.defer(0, function()
      s.scheduled = false
      M.refresh(jin, host, root)
    end)
  end
  return s.values and s.values[name] or ""
end

-- Switching buffers in quick succession refreshes once in this long.
local TOUCH_INTERVAL = 500

---Refresh the components of the current buffer's workspace now, as after
---switching buffers, unless that was just done; with `force`, as once jj
---changed the repository, refresh regardless. A workspace whose components
---were never read is left alone, so that nobody who does not show them pays
---for running jj.
---@param jin jin.Api
---@param host jin.Host
---@param force? boolean
function M.touch(jin, host, force)
  -- Every read looks for a root first, found or not, so no roots means no
  -- component was ever read.
  if not roots[host] then
    return
  end
  -- Components read here outside any workspace are wanted in the workspace
  -- made here since.
  local outside = roots[host][host.bufname() .. "\n" .. host.cwd()] == false
  -- A workspace may have been made or removed since the roots were found.
  roots[host] = nil
  local root = root_of(host)
  if not root then
    return
  end
  local s = (states[host] or {})[root]
  if outside then
    s = state(host, root)
    s.wanted = true
  end
  if not s or not s.wanted then
    return
  end
  if not force and s.time and host.now() - s.time < TOUCH_INTERVAL then
    return
  end
  M.refresh(jin, host, root)
end

return M
