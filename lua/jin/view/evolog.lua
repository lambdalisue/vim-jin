-- The evolution of a change: each version it went through, newest first.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

action.openers(actions, "show", "show this version of the change", function(ctx, opener)
  support.open(ctx, "show", { action.entry(ctx)[2] }, opener)
end)

---The version listed after `entry`, which is the one before it.
---@param ctx jin.ActionContext
---@param entry string[]
---@return string[]?
local function previous(ctx, entry)
  local seen = false
  for _, e in ipairs(ctx.meta.entries) do
    if e == entry then
      seen = true
    elseif seen and e then
      return e
    end
  end
  return nil
end

action.openers(
  actions,
  "interdiff",
  "show how this version's diff differs from the version before it",
  function(ctx, opener)
    local entry = action.entry(ctx)
    local before = previous(ctx, entry)
    if not before then
      error("jin: this is the first version of the change", 0)
    end
    support.open(ctx, "interdiff", { "--from", before[2], "--to", entry[2] }, opener)
  end
)

support.describe_actions(actions)
support.commit_actions(actions)
support.yank_actions(actions)

-- Divergent and hidden as well, as the views name such a commit by its commit ID.
local EVOLOG_FIELDS = {
  "commit.change_id()",
  "commit.commit_id()",
  'if(commit.divergent(), "divergent", if(commit.hidden(), "hidden", "-"))',
}

---@type jin.View
return {
  command = { "evolog" },
  config = { "ui.log-word-wrap=false" },
  filetype = "jin-evolog",
  entries_span_lines = true,
  blocks = require("jin.view.block").entries,
  template = {
    key = "evolog",
    default = "builtin_evolog_compact",
    fields = EVOLOG_FIELDS,
  },
  actions = actions,
  primary = "interdiff",
  secondary = "show",
  yank = "yank:change",
}
