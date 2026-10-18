-- How the diff of one version of a change differs from another's, as jj
-- interdiff prints it: a diff, read and followed as the diff view does.

local diff = require("jin.diff")
local support = require("jin.view.support")

local actions = {}

-- jj compares the earlier version rebased onto the later one's parents, a tree
-- no revision holds, so its old side leads nowhere.
support.jump_actions(actions, function(ctx)
  return {
    new = diff.sides(ctx.meta.parsed.argv).new,
    missing = "jin: the old side of an interdiff is in no revision; jump to the new side instead",
  }
end)

---@type jin.View
return {
  command = { "interdiff" },
  flags = { "--color-words" },
  filetype = "jin-diff",
  decorate = support.decorate_diff_or("These versions differ in neither files nor description."),
  blocks = require("jin.view.block").files,
  detail = require("jin.view.file_detail").diff_detail(function(meta)
    local file_detail = require("jin.view.file_detail")
    return {
      command = { "interdiff" },
      revisions = file_detail.revision_words(meta.parsed.argv),
      key = "",
      sides = { new = diff.sides(meta.parsed.argv).new },
    }
  end),
  actions = actions,
  primary = "jump",
}
