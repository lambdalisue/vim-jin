-- Reads jj's color-words diff (the format of `jj diff --color-words` and
-- `jj show`), whose lines carry the line numbers of both sides.

local args = require("jin.args")

local M = {}

local STATUSES = {
  Added = "added",
  Removed = "removed",
  Modified = "modified",
  Copied = "copied",
  Renamed = "renamed",
}

local KINDS = { "regular file", "executable file", "symlink", "conflict", "git submodule", "tree" }

---@param line string
---@return { status: string, path: string, from?: string }?
local function header(line)
  local word, rest = line:match("^(%u%l+) (.+):$")
  local status = word and STATUSES[word]
  if not status then
    return nil
  end
  for _, kind in ipairs(KINDS) do
    if rest:sub(1, #kind + 1) == kind .. " " then
      local target = rest:sub(#kind + 2)
      local path, from = target:match("^(.*) %((.*) => .*%)$")
      if path then
        return { status = status, path = path, from = from }
      end
      return { status = status, path = target }
    end
  end
  return nil
end

---@class jin.DiffLine
---@field path string
---@field from? string the path before a rename, on a header
---@field old? integer the line number on the old side
---@field new? integer the line number on the new side

---@class jin.DiffFile
---@field status string
---@field path string
---@field from? string
---@field first integer the header line
---@field last integer the last line of the section

---@param lines string[]
---@return jin.ParsedDiff
function M.parse(lines)
  local files, mapped = {}, {}
  local current
  for lnum, line in ipairs(lines) do
    local h = header(line)
    if h then
      if current then
        current.last = lnum - 1
      end
      current = { status = h.status, path = h.path, from = h.from, first = lnum, last = lnum }
      files[#files + 1] = current
      mapped[lnum] = { path = h.path, from = h.from }
    elseif current and line:match("^%a.*:$") then
      -- A section of no file, such as the description jj interdiff
      -- compares, ends the file before it; its lines lead nowhere. A line
      -- of the file starts with its number, or with spaces before it.
      current.last = lnum - 1
      current = nil
    elseif current then
      local old, new = line:match("^%s*(%d+)%s+(%d+): ")
      if not old then
        old = line:match("^%s*(%d+)%s+: ")
        new = line:match("^%s+(%d+): ")
      end
      mapped[lnum] = {
        path = current.path,
        from = current.from,
        old = tonumber(old),
        new = tonumber(new),
      }
    end
  end
  if current then
    current.last = #lines
  end
  return { files = files, lines = mapped }
end

---@alias jin.ParsedDiff { files: jin.DiffFile[], lines: table<integer, jin.DiffLine> }

---@param parsed jin.ParsedDiff
---@param lnum integer
---@return jin.DiffFile?
local function file_at(parsed, lnum)
  for _, file in ipairs(parsed.files) do
    if file.first <= lnum and lnum <= file.last then
      return file
    end
  end
  return nil
end

---The line of `file` in `parsed` whose `side` is nearest `number`, the
---first of those as near; nil when no line of it is on `side`.
---@param parsed jin.ParsedDiff
---@param file jin.DiffFile
---@param side "old"|"new"
---@param number integer
---@return integer?
local function nearest(parsed, file, side, number)
  local best, distance
  for lnum = file.first + 1, file.last do
    local at = parsed.lines[lnum] and parsed.lines[lnum][side]
    if at and (not distance or math.abs(at - number) < distance) then
      best, distance = lnum, math.abs(at - number)
    end
  end
  return best
end

---The number on `side` of line `lnum` of `file`, or of the nearest line of
---the file that has one, the one above first.
---@param parsed jin.ParsedDiff
---@param file jin.DiffFile
---@param lnum integer
---@param side "old"|"new"
---@return integer?
local function number_near(parsed, file, lnum, side)
  for distance = 0, file.last - file.first do
    for _, at in ipairs({ lnum - distance, lnum + distance }) do
      local line = at > file.first and at <= file.last and parsed.lines[at]
      if line and line[side] then
        return line[side]
      end
    end
  end
  return nil
end

---The line of `to` showing the line of the file that line `lnum` of `from`
---shows, `to` being a diff whose other side is the `side` of `from`: `old`
---when `to` is the diff of the parent, whose new side is the old side of
---`from`, and `new` when it is the diff of the child. A line not on `side`,
---as an added or a removed one, stands for the nearest line of its file
---that is. When `to` lacks the line, the nearest line of the file stands
---for it, and the file's header when none is on the other side. Nil off a
---file, or when `to` does not touch the file.
---@param from jin.ParsedDiff
---@param lnum integer
---@param to jin.ParsedDiff
---@param side "old"|"new"
---@return integer?
function M.counterpart(from, lnum, to, side)
  local file = file_at(from, lnum)
  if not file then
    return nil
  end
  -- The parent names a renamed file by its old path; the child names the
  -- path shown as its old one.
  local wanted = side == "old" and (file.from or file.path) or file.path
  local target
  for _, candidate in ipairs(to.files) do
    local name = side == "old" and candidate.path or (candidate.from or candidate.path)
    if name == wanted then
      target = candidate
      break
    end
  end
  if not target then
    return nil
  end
  if lnum == file.first then
    return target.first
  end
  local number = number_near(from, file, lnum, side)
  local other = side == "old" and "new" or "old"
  return number and nearest(to, target, other, number) or target.first
end

---The revisions on the old and new sides of a diff with these arguments:
---`jj diff` (or `jj show` when `show` is set).
---@param argv string[]
---@param show? boolean
---@return { old: string, new: string }
function M.sides(argv, show)
  local valued = { ["--from"] = "from", ["-f"] = "from", ["--to"] = "to", ["-t"] = "to" }
  for spelling, name in pairs(args.REVISIONS) do
    valued[spelling] = name
  end
  local rev, from, to
  for _, item in ipairs((args.options(argv, valued))) do
    if item.name == "revisions" then
      rev = item.value
    elseif item.name == "from" then
      from = item.value
    elseif item.name == "to" then
      to = item.value
    elseif show and not item.name and not rev and not item.words[1]:match("^%-") then
      rev = item.words[1]
    end
  end
  if from or to then
    return { old = from or "@", new = to or "@" }
  end
  rev = rev or "@"
  -- `-` binds tighter than any infix operator, so `a::b-` would be `a::(b-)`.
  local base = rev:match("^[%w_@]+$") and rev or "(" .. rev .. ")"
  return { old = base .. "-", new = rev }
end

return M
