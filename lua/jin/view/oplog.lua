-- The operation log: every jj operation, the agent's included.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

action.openers(actions, "show", "show what the operation changed", function(ctx, opener)
  support.open(ctx, "opshow", { action.entry(ctx)[1] }, opener)
end)

action.openers(actions, "log", "show the log as it was after the operation", function(ctx, opener)
  support.open(ctx, "log", { "--at-op", action.entry(ctx)[1] }, opener)
end)

actions["yank:operation"] = {
  desc = "yank the operation IDs",
  fn = function(ctx)
    local ids = {}
    for _, entry in ipairs(ctx.entries) do
      ids[#ids + 1] = entry[1]
    end
    if #ids == 0 then
      action.nothing(ctx, "jin: nothing to yank in these lines")
    end
    ctx.host.yank(table.concat(ids, "\n"))
  end,
}

---@type jin.View
return {
  command = { "op", "log" },
  config = { "ui.log-word-wrap=false" },
  filetype = "jin-oplog",
  entries_span_lines = true,
  blocks = require("jin.view.block").entries,
  template = {
    key = "op_log",
    default = "builtin_op_log_compact",
    fields = { "self.id()" },
  },
  actions = actions,
  primary = "show",
  secondary = "log",
  yank = "yank:operation",
}
