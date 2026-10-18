-- What the detail panel tells of a version of a change in its evolution:
-- the operation that made it, by its description, the command and when,
-- and how it differs from the version before it, file by file.

local change_detail = require("jin.view.change_detail")
local marker = require("jin.marker")
local text = require("jin.view.detail_text")

local M = {}

---What the panel tells of a version; any of it may be unknown.
---@class jin.VersionDetails: jin.ChangeDetails
---@field op? string the ID of the operation that made it
---@field op_description? string
---@field args? string the command line of that operation
---@field op_time? string
---@field op_ago? string
---@field changes? jin.DetailFile[] how it differs from the version before it

local CHANGE = change_detail.fields("commit")

-- What jj is asked of a version: what change_detail asks of its commit,
-- then of the operation and the files it differs in from the one before.
local FIELDS = {}
for i, field in ipairs(CHANGE) do
  FIELDS[i] = field
end
for _, field in ipairs({
  "self.operation().id().short()",
  "self.operation().description()",
  "self.operation().attributes()",
  "format_timestamp(self.operation().time().end())",
  "self.operation().time().end().ago()",
  text.files_field("self.inter_diff()"),
}) do
  FIELDS[#FIELDS + 1] = field
end

---What the markers of the line `lnum` tell of its version.
---@param meta jin.ViewMeta
---@param lnum integer
---@return jin.VersionDetails
local function known(meta, lnum)
  local entry = meta.entries[lnum] --[[@as string[] ]]
  return change_detail.known_of(meta, entry) --[[@as jin.VersionDetails]]
end

---Ask jj of the version `commit`, the first evolog lists from it.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param lnum integer
---@param commit string
---@param done fun(details: jin.VersionDetails)
local function fetch(jin, meta, lnum, commit, done)
  local argv = change_detail.at_view(meta, {
    "evolog",
    "--no-graph",
    "--limit",
    "1",
    "-r",
    commit,
    "-T",
    marker.wrap(FIELDS, '""'),
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    local _, entries = marker.parse({ (result.stdout:gsub("\n.*", "")) })
    local f = result.code == 0 and entries[1]
    if not f then
      done(known(meta, lnum))
      return
    end
    local details = change_detail.read(f) --[[@as jin.VersionDetails]]
    local n = #CHANGE
    details.op = f[n + 1]
    details.op_description = f[n + 2]
    for line in ((f[n + 3] or "") .. "\n"):gmatch("([^\n]*)\n") do
      details.args = details.args or line:match("^args: (.*)$")
    end
    details.op_time = f[n + 4]
    details.op_ago = f[n + 5]
    details.changes = text.parse_files(f[n + 6])
    done(details)
  end)
end

local LABELS = {
  change = change_detail.LABELS.change,
  commit = change_detail.LABELS.commit,
  op = { glyph = "operation", word = "Op" },
  args = { glyph = "command", word = "Args" },
  date = { glyph = "date", word = "Date" },
  files = { glyph = "files", word = "Files" },
}

---The lines telling of `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.VersionDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
local function lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, LABELS)
  local description = (details.description or ""):gsub("%s+$", "")
  out:title((description:match("^[^\n]*")))
  out:id("change", details.change, details.change_rest, "JinDetailChange")
  out:id("commit", details.commit, details.commit_rest, "JinDetailCommit")
  if details.op then
    out:line("op", {
      { text = details.op, group = "JinDetailCommit" },
      { text = " " .. (details.op_description or ""):gsub("%s+$", ""), group = "JinDetailBody" },
    })
  end
  if details.args then
    out:field("args", { details.args })
  end
  local date = {}
  date[#date + 1] = details.op_time
  date[#date + 1] = details.op_ago
    and (details.op_time and "(" .. details.op_ago .. ")" or details.op_ago)
  if #date > 0 then
    out:field("date", date)
  end
  if details.changes then
    if #details.changes == 0 then
      out:line("files", { { text = "no change from the version before", group = "JinDetailDim" } })
    else
      out:files("files", details.changes)
    end
  end
  return out:lines()
end

---The `detail` of the evolog: a line stands for a version by its commit ID.
---@return jin.ViewDetail
function M.detail()
  return {
    key = function(meta, lnum)
      local entry = meta.entries[lnum]
      return entry and entry[2] or nil
    end,
    known = known,
    fetch = fetch,
    lines = lines,
  }
end

return M
