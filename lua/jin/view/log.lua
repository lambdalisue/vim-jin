-- The change graph, in the user's own log template.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

action.openers(actions, "show", "show the change", function(ctx, opener)
  support.open(ctx, "show", { support.revision(action.entry(ctx)) }, opener)
end)

action.openers(actions, "diff", "show the diff of the change", function(ctx, opener)
  support.open(ctx, "diff", { "-r", support.revision(action.entry(ctx)) }, opener)
end)

action.openers(actions, "evolog", "show the versions the change went through", function(ctx, opener)
  support.open(ctx, "evolog", { "-r", support.revision(action.entry(ctx)) }, opener)
end)

support.yank_actions(actions)

---@type jin.View
return {
  command = { "log" },
  -- jj's own wrapping would count the markers as visible text.
  config = { "ui.log-word-wrap=false" },
  filetype = "jin-log",
  entries_span_lines = true,
  blocks = require("jin.view.block").entries,
  template = support.logged("log", "builtin_log_compact"),
  actions = actions,
  primary = "show",
  secondary = "diff",
  yank = "yank:change",
}
