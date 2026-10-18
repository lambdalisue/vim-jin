-- What the detail panel tells of a bookmark of the bookmark list: the change
-- it points to, by its IDs, description, author and time, and how it stands
-- against its remotes: whether each tracks it, and how far apart they are.

local change_detail = require("jin.view.change_detail")
local marker = require("jin.marker")
local support = require("jin.view.support")
local text = require("jin.view.detail_text")
local view = require("jin.view")

local M = {}

---How a remote bookmark of the same name stands.
---@class jin.BookmarkRemote
---@field remote string
---@field tracked boolean
---@field ahead? string how many changes it has that the local one lacks
---@field behind? string how many the local one has that it lacks
---@field synced boolean

---What the panel tells of a bookmark; any of it may be unknown.
---@class jin.BookmarkDetails: jin.ChangeDetails
---@field name string the bookmark, with @remote for a remote one
---@field absent? boolean it points to no change
---@field conflicted? boolean it points to several
---@field remotes? jin.BookmarkRemote[]

---A count jj may know only the lower bound of, which it then tells with
---a "+".
---@param count string
---@return string
local function size(count)
  return ('if(%s.exact(), %s.exact(), %s.lower() ++ "+")'):format(count, count, count)
end

-- What jj is asked of each bookmark of the name: its remote, how it
-- stands, and what change_detail asks of the change it points to.
local FIELDS = {
  "name",
  "if(remote, remote)",
  'if(present, "", "absent")',
  'if(conflict, "conflict")',
  'if(tracked, "tracked")',
  "if(remote, " .. size("self.tracking_ahead_count()") .. ")",
  "if(remote, " .. size("self.tracking_behind_count()") .. ")",
  'if(synced, "synced")',
}
local FIRST = #FIELDS + 1
for _, field in ipairs(change_detail.fields("normal_target")) do
  FIELDS[#FIELDS + 1] = "if(normal_target, " .. field .. ")"
end

---@param entry string[]
---@return string
local function name_of(entry)
  return entry[2] and (entry[1] .. "@" .. entry[2]) or entry[1]
end

---What the markers of the line `lnum` tell of its bookmark.
---@param meta jin.ViewMeta
---@param lnum integer
---@return jin.BookmarkDetails
local function known(meta, lnum)
  local entry = meta.entries[lnum] --[[@as string[] ]]
  local about = view.get(meta.view).template.about
  return {
    name = name_of(entry),
    absent = entry[3] == "absent",
    description = entry[about],
    author = entry[about + 1],
    ago = entry[about + 2],
  }
end

---Ask jj of every bookmark of the name of the line `lnum`, local and
---remote, and tell of the one of the line and how the others stand.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param lnum integer
---@param _ string
---@param done fun(details: jin.BookmarkDetails)
local function fetch(jin, meta, lnum, _, done)
  local entry = meta.entries[lnum] --[[@as string[] ]]
  local argv = change_detail.at_view(meta, {
    "bookmark",
    "list",
    "--all-remotes",
    "-T",
    marker.wrap(FIELDS, '"\\n"'),
    "exact:" .. support.string(entry[1]),
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    local fallback = known(meta, lnum)
    if result.code ~= 0 then
      done(fallback)
      return
    end
    local lines = {}
    for line in result.stdout:gmatch("[^\n]+") do
      lines[#lines + 1] = line
    end
    local _, entries = marker.parse(lines)
    local details, remotes = nil, {}
    for _, f in ipairs(entries) do
      if f and f[1] == entry[1] then
        if f[2] == entry[2] then
          details = change_detail.read(f, FIRST) --[[@as jin.BookmarkDetails]]
          details.name = fallback.name
          details.absent = f[3] == "absent"
          details.conflicted = f[4] == "conflict"
        end
        -- jj keeps the Git refs of a colocated repository as the remote git,
        -- which is no remote to tell of.
        if f[2] and f[2] ~= "git" and f[2] ~= entry[2] then
          remotes[#remotes + 1] = {
            remote = f[2],
            tracked = f[5] == "tracked",
            ahead = f[6],
            behind = f[7],
            synced = f[8] == "synced",
          }
        end
      end
    end
    details = details or fallback
    details.remotes = remotes
    done(details)
  end)
end

local LABELS = {
  change = change_detail.LABELS.change,
  commit = change_detail.LABELS.commit,
  author = change_detail.LABELS.author,
  date = change_detail.LABELS.date,
  about = { glyph = "about", word = "About" },
  state = change_detail.LABELS.state,
  remote = { glyph = "traffic", word = "Remote" },
}

---How `remote` stands against the local bookmark, as chunks.
---@param remote jin.BookmarkRemote
---@return jin.DetailChunk[]
local function standing(remote)
  local chunks = { { text = remote.remote, group = "JinDetailRef" } }
  if not remote.tracked then
    chunks[#chunks + 1] = { text = "  untracked", group = "JinDetailDim" }
    return chunks
  end
  chunks[#chunks + 1] = { text = "  tracked", group = "JinDetailBody" }
  if remote.synced then
    chunks[#chunks + 1] = { text = ", synced", group = "JinDetailBody" }
    return chunks
  end
  if remote.ahead and remote.ahead ~= "0" then
    chunks[#chunks + 1] = { text = ", " .. remote.ahead .. " ahead", group = "JinDetailAdded" }
  end
  if remote.behind and remote.behind ~= "0" then
    chunks[#chunks + 1] = { text = ", " .. remote.behind .. " behind", group = "JinDetailRemoved" }
  end
  return chunks
end

---The lines telling of `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.BookmarkDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
local function lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, LABELS)
  out:text(details.name, "JinDetailTitle")
  if details.absent then
    out:line("state", { { text = "points to no change", group = "JinDetailDim" } })
  elseif details.conflicted then
    out:line("state", { { text = "conflict", group = "JinDetailAlert" } })
  end
  out:id("change", details.change, details.change_rest, "JinDetailChange")
  out:id("commit", details.commit, details.commit_rest, "JinDetailCommit")
  local subject = (details.description or ""):match("^[^\n]*")
  if subject and subject ~= "" then
    out:field("about", { subject })
  elseif details.change then
    out:line("about", { { text = "(no description set)", group = "JinDetailDim" } })
  end
  change_detail.signature(out, details)
  for i, remote in ipairs(details.remotes or {}) do
    out:line(i == 1 and "remote" or nil, standing(remote))
  end
  return out:lines()
end

---The `detail` of the bookmark list.
---@return jin.ViewDetail
function M.detail()
  return {
    key = function(meta, lnum)
      local entry = meta.entries[lnum]
      return entry and (entry[1] .. "\0" .. (entry[2] or "")) or nil
    end,
    known = known,
    fetch = fetch,
    lines = lines,
  }
end

return M
