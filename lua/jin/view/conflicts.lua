-- The changes that hold conflicts, in the user's log template, with a way to
-- the conflicted paths of each.

local action = require("jin.action")
local args = require("jin.args")
local log = require("jin.view.log")
local support = require("jin.view.support")

local actions = {}
for name, a in pairs(log.actions) do
  actions[name] = a
end

action.openers(actions, "files", "list the conflicted paths of the change", function(ctx, opener)
  support.open(ctx, "resolve", { "-r", support.revision(action.entry(ctx)) }, opener)
end)

---Fold the user's revisions into one revset intersected with conflicts().
---jj takes several -r as their union, so passing them beside conflicts()
---would widen the log instead of narrowing it.
---@param argv string[]
---@return string[]
local function prepare(argv)
  local items, rest = args.options(argv, args.REVISIONS)
  local revsets, others = {}, {}
  for _, item in ipairs(items) do
    if item.name == "revisions" then
      revsets[#revsets + 1] = item.value
    else
      for _, word in ipairs(item.words) do
        others[#others + 1] = word
      end
    end
  end
  local revset = "conflicts()"
  if #revsets > 0 then
    revset = "conflicts() & ((" .. table.concat(revsets, ") | (") .. "))"
  end
  local argv_out = { "-r", revset }
  for _, list in ipairs({ others, rest }) do
    for _, a in ipairs(list) do
      argv_out[#argv_out + 1] = a
    end
  end
  return argv_out
end

---@type jin.View
return {
  command = { "log" },
  config = log.config,
  filetype = "jin-conflicts",
  entries_span_lines = true,
  blocks = require("jin.view.block").entries,
  template = log.template,
  prepare = prepare,
  actions = actions,
  primary = "files",
  yank = "yank:change",
}
