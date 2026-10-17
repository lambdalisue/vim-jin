-- The selection: changes set aside in a workspace as the other side of an
-- action, by the revision that names them (docs/adr/20261017-keep-the-
-- selection-per-workspace-as-the-other-side-of-an-action.md).

local M = {}

---Per host, per workspace root: the selected revisions, in the order selected.
---@type table<jin.Host, table<string, string[]>>
local selections = setmetatable({}, { __mode = "k" })

---@param host jin.Host
---@param root string
---@return string[]
local function of(host, root)
  selections[host] = selections[host] or {}
  selections[host][root] = selections[host][root] or {}
  return selections[host][root]
end

---The revisions selected in the workspace at `root`, in the order selected.
---@param host jin.Host
---@param root string
---@return string[]
function M.list(host, root)
  local copy = {}
  for i, rev in ipairs(of(host, root)) do
    copy[i] = rev
  end
  return copy
end

---Select each of `revs` that is not selected, and leave out each that is.
---@param host jin.Host
---@param root string
---@param revs string[]
function M.toggle(host, root, revs)
  local list = of(host, root)
  for _, rev in ipairs(revs) do
    local found
    for i, selected in ipairs(list) do
      if selected == rev then
        found = i
      end
    end
    if found then
      table.remove(list, found)
    else
      list[#list + 1] = rev
    end
  end
end

---Clear the selection of the workspace at `root`.
---@param host jin.Host
---@param root string
function M.clear(host, root)
  selections[host] = selections[host] or {}
  selections[host][root] = {}
end

return M
