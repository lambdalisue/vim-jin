-- What the detail panel tells of an operation of the operation log: its
-- whole description, the command that made it, who made it where and when,
-- and what it changed: how many changes it added, rewrote and abandoned,
-- and how many bookmarks it moved.

local change_detail = require("jin.view.change_detail")
local marker = require("jin.marker")
local text = require("jin.view.detail_text")

local M = {}

---What the panel tells of an operation; any of it may be unknown.
---@class jin.OperationDetails
---@field id? string
---@field description? string
---@field args? string the command line that made it
---@field user? string
---@field time? string
---@field ago? string
---@field lasted? string
---@field added? integer
---@field rewritten? integer
---@field abandoned? integer
---@field bookmarks? integer

-- What jj is asked of an operation, in the order of jin.OperationDetails.
local FIELDS = {
  "self.id().short()",
  "self.description()",
  "self.attributes()",
  "self.user()",
  "format_timestamp(self.time().end())",
  "self.time().end().ago()",
  "self.time().duration()",
}

-- What marks the changes jj op show lists.
local SUMMARY_FIELDS = { "self.change_id()", "self.commit_id()" }

---What the markers of the line `lnum` tell of its operation.
---@param meta jin.ViewMeta
---@param lnum integer
---@return jin.OperationDetails
local function known(meta, lnum)
  local entry = meta.entries[lnum] --[[@as string[] ]]
  return {
    id = entry[1] and entry[1]:sub(1, 12),
    description = entry[2],
    user = entry[3],
    ago = entry[4],
  }
end

---The command line among the attributes jj keeps of an operation, one a
---line as `name: value`.
---@param attributes? string
---@return string?
local function args_of(attributes)
  for line in ((attributes or "") .. "\n"):gmatch("([^\n]*)\n") do
    local value = line:match("^args: (.*)$")
    if value then
      return value
    end
  end
  return nil
end

---What jj op show tells an operation changed: the changes it added,
---rewrote and abandoned, by the change IDs it lists with and without a
---new version, and the bookmarks it moved, local or remote.
---@param lines string[]
---@return { added: integer, rewritten: integer, abandoned: integer, bookmarks: integer }
function M.count(lines)
  local section
  local plus, minus, order = {}, {}, {}
  local bookmarks = 0
  for _, line in ipairs(lines) do
    local heading = line:match("^Changed (.-):$")
    if heading then
      section = heading
    elseif section == "commits" then
      local sign = line:match("^([+-]) ")
      local _, entries = marker.parse({ line })
      local entry = entries[1]
      if sign and entry and entry[1] then
        local id = entry[1]
        if not plus[id] and not minus[id] then
          order[#order + 1] = id
        end
        if sign == "+" then
          plus[id] = true
        else
          minus[id] = true
        end
      end
    elseif
      section
      and section:match("bookmarks$")
      and line:match("^%S.*:$")
      and not line:match("^[+-] ")
    then
      bookmarks = bookmarks + 1
    end
  end
  local counts = { added = 0, rewritten = 0, abandoned = 0, bookmarks = bookmarks }
  for _, id in ipairs(order) do
    if plus[id] and minus[id] then
      counts.rewritten = counts.rewritten + 1
    elseif plus[id] then
      counts.added = counts.added + 1
    else
      counts.abandoned = counts.abandoned + 1
    end
  end
  return counts
end

---Ask jj what it tells of the operation `id` and what it changed.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param lnum integer
---@param id string
---@param done fun(details: jin.OperationDetails)
local function fetch(jin, meta, lnum, id, done)
  local argv = change_detail.at_view(meta, {
    "--config",
    marker.setting("commit_summary", SUMMARY_FIELDS, '""'),
    "op",
    "show",
    "--no-graph",
    "-T",
    marker.wrap(FIELDS, '"\\n"'),
    id,
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    local lines = {}
    for line in result.stdout:gmatch("([^\n]*)\n?") do
      lines[#lines + 1] = line
    end
    local _, entries = marker.parse({ lines[1] or "" })
    local f = result.code == 0 and entries[1]
    if not f then
      done(known(meta, lnum))
      return
    end
    local counts = M.count(lines)
    done({
      id = f[1],
      description = f[2],
      args = args_of(f[3]),
      user = f[4],
      time = f[5],
      ago = f[6],
      lasted = f[7],
      added = counts.added,
      rewritten = counts.rewritten,
      abandoned = counts.abandoned,
      bookmarks = counts.bookmarks,
    })
  end)
end

local LABELS = {
  op = { glyph = "operation", word = "Op" },
  args = { glyph = "command", word = "Args" },
  user = { glyph = "author", word = "User" },
  date = { glyph = "date", word = "Date" },
  changes = { glyph = "change", word = "Changes" },
  refs = { glyph = "bookmark", word = "Refs" },
}

---The lines telling of `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.OperationDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
local function lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, LABELS)
  local description = (details.description or ""):gsub("%s+$", "")
  local subject, body = description:match("^([^\n]*)\n?(.*)$")
  out:title(subject)
  body = body:gsub("^\n+", "")
  if body ~= "" then
    out:paragraphs(body)
  end
  if details.id then
    out:line("op", { { text = details.id, group = "JinDetailCommit" } })
  end
  if details.args then
    out:field("args", { details.args })
  end
  if details.user then
    out:field("user", { details.user })
  end
  local date = {}
  date[#date + 1] = details.time
  date[#date + 1] = details.ago and (details.time and "(" .. details.ago .. ")" or details.ago)
  if details.lasted then
    date[#date + 1] = "lasted " .. details.lasted
  end
  if #date > 0 then
    out:field("date", date)
  end
  if details.added then
    local chunks = {}
    for _, count in ipairs({
      { details.added, "added", "JinDetailAdded" },
      { details.rewritten, "rewritten", "JinDetailBody" },
      { details.abandoned, "abandoned", "JinDetailRemoved" },
    }) do
      if count[1] > 0 then
        chunks[#chunks + 1] = { text = #chunks > 0 and "  " or "", group = "JinDetailBody" }
        chunks[#chunks + 1] = { text = count[1] .. " " .. count[2], group = count[3] }
      end
    end
    if #chunks == 0 then
      chunks[1] = { text = "none", group = "JinDetailDim" }
    end
    out:line("changes", chunks)
  end
  if details.bookmarks and details.bookmarks > 0 then
    out:line("refs", {
      {
        text = details.bookmarks
          .. (details.bookmarks == 1 and " bookmark" or " bookmarks")
          .. " moved",
        group = "JinDetailRef",
      },
    })
  end
  return out:lines()
end

---The `detail` of the operation log.
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
