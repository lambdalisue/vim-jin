-- A diff between two revisions, as jj diff prints it.

local diff = require("jin.diff")
local support = require("jin.view.support")

local actions = {}

support.jump_actions(actions, function(ctx)
  return diff.sides(ctx.meta.parsed.argv)
end)

---@type jin.View
return {
  command = { "diff" },
  flags = { "--color-words" },
  filetype = "jin-diff",
  decorate = support.decorate_diff,
  blocks = require("jin.view.block").files,
  actions = actions,
  primary = "jump",
}
