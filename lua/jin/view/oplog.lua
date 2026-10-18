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

actions.restore = {
  desc = "restore the repository to how it was after the operation, once confirmed",
  changes = true,
  fn = function(ctx)
    support.refuse_at_op(ctx)
    local id = action.entry(ctx)[1]
    if ctx.host.confirm(("jin: restore the repository to %s?"):format(id)) then
      ctx.jin.command({ "op", "restore", id }, { cwd = ctx.meta.parsed.root, quiet = true })
    end
  end,
}

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
    -- What an operation is about, as support.about tells of a commit.
    fields = {
      "self.id()",
      "self.description().first_line()",
      "self.user()",
      "self.time().end().ago()",
    },
    about = 2,
  },
  actions = actions,
  primary = "show",
  secondary = "log",
  yank = "yank:operation",
}
