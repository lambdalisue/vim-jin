-- What the detail panel tells of a workspace of the workspace list: where
-- its root is, and its working-copy change, by its IDs, description, author,
-- time and state.

local change_detail = require("jin.view.change_detail")
local marker = require("jin.marker")
local text = require("jin.view.detail_text")
local view = require("jin.view")

local M = {}

---What the panel tells of a workspace; any of it may be unknown.
---@class jin.WorkspaceDetails: jin.ChangeDetails
---@field name string
---@field root? string

-- What jj is asked of each workspace: its name and root, then what
-- change_detail asks of its working-copy commit.
local FIELDS = { "name", "if(root, root)" }
local FIRST = #FIELDS + 1
for _, field in ipairs(change_detail.fields("target")) do
  FIELDS[#FIELDS + 1] = field
end

---What the markers of the line `lnum` tell of its workspace.
---@param meta jin.ViewMeta
---@param lnum integer
---@return jin.WorkspaceDetails
local function known(meta, lnum)
  local entry = meta.entries[lnum] --[[@as string[] ]]
  local about = view.get(meta.view).template.about
  return {
    name = entry[1],
    description = entry[about],
    author = entry[about + 1],
    ago = entry[about + 2],
  }
end

---Ask jj of every workspace, and tell of the one of the line `lnum`.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param lnum integer
---@param name string
---@param done fun(details: jin.WorkspaceDetails)
local function fetch(jin, meta, lnum, name, done)
  local argv = change_detail.at_view(meta, {
    "workspace",
    "list",
    "-T",
    marker.wrap(FIELDS, '"\\n"'),
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    if result.code == 0 then
      local lines = {}
      for line in result.stdout:gmatch("[^\n]+") do
        lines[#lines + 1] = line
      end
      local _, entries = marker.parse(lines)
      for _, f in ipairs(entries) do
        if f and f[1] == name then
          local details = change_detail.read(f, FIRST) --[[@as jin.WorkspaceDetails]]
          details.name = name
          details.root = f[2]
          done(details)
          return
        end
      end
    end
    done(known(meta, lnum))
  end)
end

local LABELS = {
  path = { glyph = "path", word = "Path" },
  change = change_detail.LABELS.change,
  commit = change_detail.LABELS.commit,
  about = { glyph = "about", word = "About" },
  author = change_detail.LABELS.author,
  date = change_detail.LABELS.date,
  state = change_detail.LABELS.state,
}

---The lines telling of `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.WorkspaceDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
local function lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, LABELS)
  out:text(details.name, "JinDetailTitle")
  if details.root then
    out:field("path", { details.root })
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
  if details.states and #details.states > 0 then
    out:field("state", { table.concat(details.states, " ") })
  end
  return out:lines()
end

---The `detail` of the workspace list.
---@return jin.ViewDetail
function M.detail()
  return {
    key = function(meta, lnum)
      local entry = meta.entries[lnum]
      return entry and entry[1] or nil
    end,
    known = known,
    fetch = fetch,
    lines = lines,
  }
end

return M
