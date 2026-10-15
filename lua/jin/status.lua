-- Reads what `jj status` prints about the working copy.

local M = {}

---The first line of a conflict jj materializes in a file, as a Lua pattern:
---seven or more <, as jj uses more when the file holds a run of seven.
M.CONFLICT = "^<<<<<<<+ "

---Expand jj's rename notation, `dir/{old => new}.ext`, into both paths.
---@param text string
---@return string new
---@return string? old
local function renamed(text)
  local before, old, new, after = text:match("^(.-){(.-) => (.-)}(.*)$")
  if not before then
    return text
  end
  return before .. new .. after, before .. old .. after
end

---The path of a line listing a path left in conflict (`path  2-sided
---conflict`), as jj status and jj resolve --list print it. jj pads the path to
---a column, but follows one longer than the column with a single space.
---@param line string
---@return string?
function M.conflicted(line)
  return line:match("^(.*%S)%s+%d+%-sided conflict")
end

---@class jin.StatusPath
---@field status string M, A, D, R, C, or "conflict"
---@field path string
---@field old? string the path before a rename or copy

---The path each line of `jj status` names: a change of the working copy
---(`M path`, `R {old => new}`, ...) or a path left in conflict.
---@param lines string[]
---@return table<integer, jin.StatusPath>
function M.parse(lines)
  local paths = {}
  local section
  for lnum, line in ipairs(lines) do
    if line:match("^Working copy changes:") then
      section = "changes"
    -- Newer jj heads the list with "Warning: ", older jj with nothing.
    elseif line:match("^%a*:? ?There are unresolved conflicts at these paths:") then
      section = "conflicts"
    elseif section == "changes" then
      local status, text = line:match("^([MADRC]) (.+)$")
      if status then
        local path, old = renamed(text)
        paths[lnum] = { status = status, path = path, old = old }
      else
        section = nil
      end
    elseif section == "conflicts" then
      local path = M.conflicted(line)
      if path then
        paths[lnum] = { status = "conflict", path = path }
      else
        section = nil
      end
    end
  end
  return paths
end

return M
