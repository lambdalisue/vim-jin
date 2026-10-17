-- A line of changes, newest first, one per line, to reorder by moving the
-- lines; written, it rebases the changes into that order
-- (docs/adr/20261017-arrange-a-line-of-changes-by-reordering-the-lines-of-a-buffer.md).

local args = require("jin.args")
local support = require("jin.view.support")

-- The change ID leads each line, as what is left of a line after editing
-- still names its change by it.
local TEMPLATE =
  'change_id.short(12) ++ " " ++ if(description, description.first_line(), "(no description set)") ++ "\\n"'

-- Each change of the line, whether it is divergent, and its parents.
local SHAPE = 'change_id.short(12) ++ " " ++ if(divergent, "divergent", "-") ++ " " '
  .. '++ parents.map(|p| p.change_id().short(12)).join(" ") ++ "\\n"'

---What `arrange` lists when given no revisions.
local DEFAULT = "::@ & mutable()"

---Fold the user's revisions into one revset, or the mutable ancestors of the
---working copy when there are none.
---@param argv string[]
---@return string[]
local function prepare(argv)
  local items, rest = args.options(argv, args.REVISIONS)
  local revsets, out = {}, {}
  for _, item in ipairs(items) do
    if item.name == "revisions" then
      revsets[#revsets + 1] = item.value
    else
      for _, word in ipairs(item.words) do
        out[#out + 1] = word
      end
    end
  end
  local revset = #revsets > 0 and "(" .. table.concat(revsets, ") | (") .. ")" or DEFAULT
  table.insert(out, 1, revset)
  table.insert(out, 1, "-r")
  for _, a in ipairs(rest) do
    out[#out + 1] = a
  end
  return out
end

---The change IDs `lines` lead with, top first.
---@param lines string[]
---@return string[]
local function ids_of(lines)
  local ids = {}
  for _, line in ipairs(lines) do
    local id = line:match("^(%S+)")
    if id and not line:match("^JJ:") then
      ids[#ids + 1] = id
    end
  end
  return ids
end

---Ask jj `query`, failing as jj does.
---@param jin jin.Api
---@param root string
---@param query string[]
---@return string
local function ask(jin, root, query)
  local result = jin.jj(query, { cwd = root })
  if result.code ~= 0 then
    error("jin: " .. result.stderr:gsub("\n$", ""), 0)
  end
  return result.stdout
end

---The rebases that put the changes `order`, bottom first, into that order,
---after checking with jj that they are one line, and the changes outside
---the list on its top, which move along.
---@param jin jin.Api
---@param root string
---@param order string[]
---@return string[][]
local function rebases(jin, root, order)
  local set = table.concat(order, "|")
  local listed, parent_of, child_of = {}, {}, {}
  for _, id in ipairs(order) do
    listed[id] = true
  end
  for line in ask(jin, root, { "log", "--no-graph", "-r", set, "-T", SHAPE }):gmatch("[^\n]+") do
    local id, state, parents = line:match("^(%S+) (%S+) ?(.*)$")
    if state == "divergent" then
      error(("jin: %s is divergent; arrange takes a line of changes"):format(id), 0)
    end
    local list = {}
    for parent in parents:gmatch("%S+") do
      list[#list + 1] = parent
    end
    if #list ~= 1 then
      error(("jin: %s is a merge; arrange takes a line of changes"):format(id), 0)
    end
    parent_of[id] = list[1]
    if listed[list[1]] then
      if child_of[list[1]] then
        error(
          "jin: the changes listed are not one line; arrange takes changes each on the one before",
          0
        )
      end
      child_of[list[1]] = id
    end
  end
  local bottom
  for _, id in ipairs(order) do
    if not listed[parent_of[id]] then
      if bottom then
        error(
          "jin: the changes listed are not one line; arrange takes changes each on the one before",
          0
        )
      end
      bottom = id
    end
  end
  local top, count = bottom, 1
  while child_of[top] do
    top, count = child_of[top], count + 1
  end
  if count ~= #order then
    error(
      "jin: the changes listed are not one line; arrange takes changes each on the one before",
      0
    )
  end
  -- Each change on the top one, with its parents: a merge keeps the others.
  local outside = {}
  local query = { "log", "--no-graph", "-r", ("children(%s) ~ (%s)"):format(set, set), "-T", SHAPE }
  for line in ask(jin, root, query):gmatch("[^\n]+") do
    local id, _, parents = line:match("^(%S+) (%S+) ?(.*)$")
    local list = {}
    for parent in parents:gmatch("%S+") do
      list[#list + 1] = parent
      if listed[parent] and parent ~= top then
        error(
          ("jin: %s has %s on it outside the list; take it in, or leave %s out"):format(
            parent,
            id,
            parent
          ),
          0
        )
      end
    end
    outside[#outside + 1] = { id = id, parents = list }
  end
  local steps, below = {}, parent_of[bottom]
  for _, id in ipairs(order) do
    steps[#steps + 1] = { "rebase", "-r", id, "-o", below }
    below = id
  end
  for _, child in ipairs(outside) do
    local step = { "rebase", "-s", child.id }
    for _, parent in ipairs(child.parents) do
      step[#step + 1] = "-o"
      step[#step + 1] = parent == top and below or parent
    end
    steps[#steps + 1] = step
  end
  return steps
end

---@type jin.View
return {
  command = { "log" },
  flags = { "--no-graph", "-T", TEMPLATE },
  title = { "arrange" },
  filetype = "jin-arrange",
  editable = true,
  prepare = prepare,
  decorate = function(meta)
    meta.data.ids = ids_of(meta.lines)
  end,
  ---Rebase the changes into the order the lines are in now, one rebase after
  ---another, stopping at the first jj refuses.
  write = function(jin, host, bufnr, parsed)
    if support.at_op(parsed.argv) then
      error("jin: this view shows an earlier operation, which is not to be changed", 0)
    end
    local meta = require("jin.view").meta(host, bufnr)
    local before = meta and meta.data.ids or {}
    local written = host.lines(bufnr)
    local after = ids_of(written)
    local count = {}
    for _, id in ipairs(before) do
      count[id] = (count[id] or 0) + 1
    end
    for _, id in ipairs(after) do
      count[id] = (count[id] or 0) - 1
    end
    local same = #before == #after
    for _, n in pairs(count) do
      same = same and n == 0
    end
    if not same then
      error(
        "jin: reorder the lines only: every change listed stays, once; abandon or add changes from a view",
        0
      )
    end
    local moved = false
    for i, id in ipairs(after) do
      moved = moved or before[i] ~= id
    end
    if not moved then
      support.mark_saved(host, bufnr, written)
      return
    end
    -- The line as the buffer was read, asked again: the order of its lines
    -- would otherwise put back what was done to the line meanwhile, as by a
    -- split or a rebase elsewhere, to changes nobody moved here.
    local query = { "log", "--no-graph", "-T", 'change_id.short(12) ++ "\\n"' }
    for _, word in ipairs(prepare(parsed.argv)) do
      query[#query + 1] = word
    end
    local now = {}
    for id in ask(jin, parsed.root, query):gmatch("[^\n]+") do
      now[#now + 1] = id
    end
    local unmoved = #now == #before
    for i, id in ipairs(before) do
      unmoved = unmoved and now[i] == id
    end
    if not unmoved then
      error("jin: the changes moved since this buffer was read; :edit to read them again", 0)
    end
    local order = {}
    for i = #after, 1, -1 do
      order[#order + 1] = after[i]
    end
    local steps = rebases(jin, parsed.root, order)
    local function step(i)
      if not steps[i] then
        -- What the next write is compared with: the order jj holds now.
        if meta then
          meta.data.ids = after
        end
        support.mark_saved(host, bufnr, written)
        return
      end
      jin.command(steps[i], { cwd = parsed.root, quiet = true }, function(result)
        if result.code == 0 then
          step(i + 1)
        end
      end)
    end
    step(1)
  end,
}
