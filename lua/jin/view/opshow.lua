-- What an operation changed, as jj op show prints it, with the changes it
-- touched leading on.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

-- By commit ID: a line stands for one version of the change, often one the
-- operation rewrote away, which the change ID would not reach.
action.openers(actions, "show", "show this version of the change", function(ctx, opener)
  support.open(ctx, "show", { action.entry(ctx)[2] }, opener)
end)

action.openers(actions, "diff", "show the diff of this version of the change", function(ctx, opener)
  support.open(ctx, "diff", { "-r", action.entry(ctx)[2] }, opener)
end)

support.select_actions(actions)
support.yank_actions(actions)

---@type jin.View
return {
  command = { "op", "show" },
  -- jj would wrap the graph lines, and the markers in them with the words.
  config = { "ui.log-word-wrap=false" },
  flags = { "--color-words" },
  filetype = "jin-opshow",
  -- jj lists the changes an operation touched with this template, so the
  -- markers name them whatever the user made it print.
  template = support.SUMMARY_TEMPLATE,
  decorate = function(meta)
    local summaries = support.summaries(meta)
    for lnum in ipairs(meta.lines) do
      meta.entries[lnum] = summaries[lnum] or false
    end
  end,
  -- By commit ID, as a line stands for one version of the change.
  detail = require("jin.view.change_detail").detail({
    revision = function(entry)
      return entry[2]
    end,
  }),
  actions = actions,
  primary = "show",
  secondary = "diff",
  yank = "yank:change",
}
