-- What a description buffer holds, read the way jj reads what its editor
-- returns.

local M = {}

---The description `lines` hold: without the lines starting with JJ:, and
---without anything from `JJ: ignore-rest` on, ending in one newline, or ""
---when nothing is left.
---@param lines string[]
---@return string
function M.text(lines)
  local kept = {}
  for _, line in ipairs(lines) do
    if line:match("^JJ: ignore%-rest") then
      break
    elseif not line:match("^JJ:") then
      kept[#kept + 1] = line
    end
  end
  while #kept > 0 and not kept[#kept]:find("%S") do
    kept[#kept] = nil
  end
  return #kept > 0 and table.concat(kept, "\n") .. "\n" or ""
end

return M
