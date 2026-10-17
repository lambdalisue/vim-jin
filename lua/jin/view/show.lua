-- One or more changes with their diffs, as jj show prints them.

local action = require("jin.action")
local block = require("jin.view.block")
local support = require("jin.view.support")

local actions = {}

-- Each line belongs to the commit whose output it is part of, so the diff of
-- that commit compares its parents with it. The commit ID names the version
-- shown, which may be an older one of the change (as evolog opens).
support.jump_actions(actions, function(ctx)
  local entry = action.entry(ctx)
  local rev = entry[2]
  -- The working-copy commit's files are the files themselves, unless it was
  -- the working copy of an earlier operation.
  local current = entry[4] == "wc" and not support.at_op(ctx.meta.parsed.argv)
  return { old = rev .. "-", new = current and "@" or rev }
end)

for name, which in pairs({ parent = "parents", child = "children" }) do
  action.openers(
    actions,
    name,
    ("show the %s of the version shown, or a log of them when there are several"):format(which),
    function(ctx, opener)
      support.relative(ctx, which, action.entry(ctx)[2], opener, function(rev)
        support.open(ctx, "show", { rev }, opener)
      end)
    end
  )
end

support.describe_actions(actions)
support.commit_actions(actions)
support.select_actions(actions)
support.yank_actions(actions)

---@type jin.View
return {
  command = { "show" },
  flags = { "--color-words" },
  filetype = "jin-show",
  template = {
    key = "show",
    default = "builtin_log_detailed",
    fields = {
      support.CHANGE_FIELDS[1],
      support.CHANGE_FIELDS[2],
      support.CHANGE_FIELDS[3],
      'if(current_working_copy, "wc", "-")',
    },
  },
  decorate = support.decorate_diff,
  blocks = block.together(block.entries, block.files),
  actions = actions,
  primary = "jump",
  yank = "yank:change",
}
