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
---@return { files: jin.DiffFile[], lines: table<integer, jin.DiffLine> }
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
