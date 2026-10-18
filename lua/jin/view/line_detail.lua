-- What the detail panel tells of a line inside a diff: the change that last
-- wrote it, on the side of the diff the line is on. The views of diffs tell
-- it above the file the line is in, through file_detail.

local change_detail = require("jin.view.change_detail")
local detail = require("jin.view.detail")
local marker = require("jin.marker")

local M = {}

---The revisions on the sides of a view's diff: `old` where a revision holds
---it, `new`, and `shown` where the diff is of one change, which wrote every
---line it adds, with `known`, what the view's line tells of that change.
---@class jin.LineSides
---@field old? string
---@field new string
---@field shown? string
---@field known? jin.ChangeDetails

---Where to look for the change that wrote a line: the line `number` of
---`path` in the revision `rev`, or the change `shown` itself.
---@class jin.LineSide
---@field rev? string
---@field shown? string
---@field known? jin.ChangeDetails
---@field path string
---@field number integer
---@field removed boolean whether the line is on the old side alone

---What the panel tells of a line: where it is and the change that wrote it.
---@class jin.LineBlame
---@field side jin.LineSide
---@field change jin.ChangeDetails

---Where to look for the change that wrote the diff line `line`, its view
---comparing `sides`. A removed line was last written as of the old side,
---and is found there at its old number and path; any other line is found
---on the new side, where a line on both sides was last written before, but
---a line added in the diff of one change was written by that change. Nil
---for a line without line numbers, or a removed one no revision holds.
---@param line jin.DiffLine
---@param sides jin.LineSides
---@return jin.LineSide?
function M.side(line, sides)
  if line.old and not line.new then
    if not sides.old then
      return nil
    end
    return { rev = sides.old, path = line.from or line.path, number = line.old, removed = true }
  elseif line.new and not line.old and sides.shown then
    return {
      shown = sides.shown,
      known = sides.known,
      path = line.path,
      number = line.new,
      removed = false,
    }
  elseif line.new then
    return { rev = sides.new, path = line.path, number = line.new, removed = false }
  end
  return nil
end

---A key telling `side` apart from every other.
---@param side jin.LineSide
---@return string
function M.key(side)
  local where = side.shown and ("=" .. side.shown) or side.rev
  return ("%s\0%s\0%d"):format(where, side.path, side.number)
end

-- Every field of change_detail but the files, which a diff per line would
-- cost; the commit ID first, the line's alone where the hunk was told.
local FIELDS = { "commit.commit_id()" }
for i, field in ipairs(change_detail.fields("commit")) do
  if i <= 11 then
    FIELDS[#FIELDS + 1] = field
  end
end

-- What jj file annotate prints of each line: the change on the first line of
-- each run of lines it wrote, so that a description is told once a run.
M.TEMPLATE = "if(first_line_in_hunk, "
  .. marker.wrap(FIELDS, '""')
  .. ", "
  .. marker.wrap({ "commit.commit_id()" }, '""')
  .. ') ++ "\\n"'

---What TEMPLATE tells of each line, by line number.
---@param stdout string
---@return table<integer, jin.ChangeDetails>
function M.parse(stdout)
  local input = {}
  for line in stdout:gmatch("([^\n]*)\n") do
    input[#input + 1] = line
  end
  local _, entries = marker.parse(input)
  local commits, lines = {}, {}
  for lnum, f in ipairs(entries) do
    if f and f[1] then
      if f[2] then
        commits[f[1]] = change_detail.read(f, 2)
      end
      lines[lnum] = commits[f[1]]
    end
  end
  return lines
end

---Ask jj of the change that wrote the line `side` tells of, at the
---operation `meta` shows, once per read for each revision and path
---annotated, or each change shown, and call `done` with it, or with nil
---where jj cannot tell.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param side jin.LineSide
---@param done fun(blame: jin.LineBlame?)
function M.fetch(jin, meta, side, done)
  if side.shown then
    detail.shared(meta, "change\0" .. side.shown, function(told)
      change_detail.fetch_of(jin, meta, side.shown, side.known, told)
    end, function(change)
      done(change and { side = side, change = change } or nil)
    end)
    return
  end
  detail.shared(meta, "annotate\0" .. side.rev .. "\0" .. side.path, function(told)
    local argv = change_detail.at_view(
      meta,
      { "file", "annotate", "-r", side.rev, "-T", M.TEMPLATE, "--", side.path }
    )
    jin.jj(argv, { cwd = meta.parsed.root }, function(result)
      told(result.code == 0 and M.parse(result.stdout) or false)
    end)
  end, function(lines)
    local change = lines and lines[side.number]
    done(change and { side = side, change = change } or nil)
  end)
end

---What is known now of the change that wrote the line `side` tells of: what
---jj told, or else what the view's line tells of the change shown.
---@param meta jin.ViewMeta
---@param side jin.LineSide
---@return jin.LineBlame?
function M.known(meta, side)
  local change
  if side.shown then
    change = detail.told(meta, "change\0" .. side.shown) or side.known
  else
    local lines = detail.told(meta, "annotate\0" .. side.rev .. "\0" .. side.path)
    change = lines and lines[side.number]
  end
  return change and { side = side, change = change } or nil
end

-- What labels each value told of a line, besides those of a change.
M.LABELS = {
  line = { glyph = "line", word = "Line" },
  about = { glyph = "about", word = "About" },
}
for name, label in pairs(change_detail.LABELS) do
  M.LABELS[name] = label
end

-- The states of a change that tell how it is named, or that what it wrote
-- may not stay: the rest are as good as said by the line being there.
local STATES = { divergent = true, conflict = true, hidden = true }

---Tell where the line of `blame` is and the change that wrote it, up to its
---date and state, to `out`, whose labels hold M.LABELS.
---@param out jin.DetailText
---@param blame jin.LineBlame
function M.write(out, blame)
  local side, change = blame.side, blame.change
  out:field("line", {
    ("%d of %s,"):format(side.number, side.path),
    side.removed and "removed, last written by" or "last written by",
  })
  local description = (change.description or ""):gsub("%s+$", "")
  out:title((description:match("^[^\n]*")))
  out:id("change", change.change, change.change_rest, "JinDetailChange")
  out:id("commit", change.commit, change.commit_rest, "JinDetailCommit")
  change_detail.signature(out, change)
  local states = {}
  for _, state in ipairs(change.states or {}) do
    if STATES[state] then
      states[#states + 1] = { text = state, group = "JinDetailAlert" }
      states[#states + 1] = { text = " ", group = "JinDetailBody" }
    end
  end
  if #states > 0 then
    states[#states] = nil
    out:line("state", states)
  end
end

---Tell the rest of the description of the change that wrote the line of
---`blame`, after its first line, to `out`, set off by a blank row; nothing
---where it has none.
---@param out jin.DetailText
---@param blame jin.LineBlame
function M.write_body(out, blame)
  local description = (blame.change.description or ""):gsub("%s+$", "")
  local body = (description:match("^[^\n]*\n(.*)$") or ""):gsub("^\n+", "")
  if body == "" then
    return
  end
  out:blank()
  local first = true
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do
    if line == "" then
      out:blank()
    else
      out:field(first and "about" or nil, { line })
    end
    first = false
  end
end

return M
