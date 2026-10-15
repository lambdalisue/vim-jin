-- The blocks of a view, which ]] and [[ move between as Vim's section
-- motions move between sections: only the view knows where its blocks are.

local support = require("jin.view.support")

local M = {}

---The first line of each entry, where entries span lines.
---@param meta jin.ViewMeta
---@return integer[]
function M.entries(meta)
  local starts = {}
  for lnum, entry in ipairs(meta.entries) do
    if entry and entry ~= meta.entries[lnum - 1] then
      starts[#starts + 1] = lnum
    end
  end
  return starts
end

---The first line of each run of lines one change wrote. Every line is an
---entry of its own, so the revisions are compared rather than the entries.
---@param meta jin.ViewMeta
---@return integer[]
function M.changes(meta)
  local starts, before = {}, nil
  for lnum, entry in ipairs(meta.entries) do
    local rev = entry and support.revision(entry) or nil
    if rev and rev ~= before then
      starts[#starts + 1] = lnum
    end
    before = rev
  end
  return starts
end

---The header line of each file of a diff, as `support.decorate_diff` read it.
---@param meta jin.ViewMeta
---@return integer[]
function M.files(meta)
  local starts = {}
  for _, file in ipairs(meta.data.diff and meta.data.diff.files or {}) do
    starts[#starts + 1] = file.first
  end
  return starts
end

---The blocks of every one of `kinds`, together.
---@param ... fun(meta: jin.ViewMeta): integer[]
---@return fun(meta: jin.ViewMeta): integer[]
function M.together(...)
  local kinds = { ... }
  return function(meta)
    local seen, starts = {}, {}
    for _, kind in ipairs(kinds) do
      for _, lnum in ipairs(kind(meta)) do
        if not seen[lnum] then
          seen[lnum] = true
          starts[#starts + 1] = lnum
        end
      end
    end
    table.sort(starts)
    return starts
  end
end

---The first line of the block `count` blocks from the line `lnum`, forward
---or back, among `starts`; the farthest one when the count goes past it,
---and nil when no block lies that way. Back from inside a block, its own
---first line is the first one reached.
---@param starts integer[] in order
---@param lnum integer
---@param count integer
---@param forward boolean
---@return integer?
function M.target(starts, lnum, count, forward)
  local found
  local first, last, step = 1, #starts, 1
  if not forward then
    first, last, step = #starts, 1, -1
  end
  for i = first, last, step do
    local start = starts[i]
    if (forward and start > lnum) or (not forward and start < lnum) then
      found = start
      count = count - 1
      if count == 0 then
        break
      end
    end
  end
  return found
end

---The default keys of the motions of `view_def`, as { lhs, motion, mode }:
---none unless it has blocks.
---@param view_def jin.View
---@return { [1]: string, [2]: string, [3]: string }[]
function M.keys(view_def)
  local keys = {}
  if view_def.blocks then
    for _, mode in ipairs({ "n", "x", "o" }) do
      keys[#keys + 1] = { "]]", "next-block", mode }
      keys[#keys + 1] = { "[[", "prev-block", mode }
    end
  end
  return keys
end

return M
