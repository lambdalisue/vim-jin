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
  decorate = support.decorate_diff_or("No file changed."),
  blocks = require("jin.view.block").files,
  -- The sides annotated, even for the diff of one change: what it adds is
  -- told the same, and a revset of several is no change to name.
  detail = require("jin.view.file_detail").diff_detail(function(meta)
    local file_detail = require("jin.view.file_detail")
    return {
      command = { "diff" },
      revisions = file_detail.revision_words(meta.parsed.argv),
      key = "",
      sides = diff.sides(meta.parsed.argv),
    }
  end),
  -- The revision on the new side, whose files the lines show as they are now.
  revision = function(argv)
    return diff.sides(argv).new
  end,
  file_at = function(meta, lnum)
    for _, file in ipairs(((meta.data.diff or {}).files or {})) do
      if lnum and file.first <= lnum and lnum <= file.last then
        return file.path
      end
    end
    return nil
  end,
  actions = actions,
  primary = "jump",
}
