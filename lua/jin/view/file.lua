-- A file as it is in a revision, highlighted as the file itself would be.

local action = require("jin.action")
local support = require("jin.view.support")

local actions = {}

action.openers(actions, "annotate", "show which change wrote each line", function(ctx, opener)
  local rev, path = support.shown_file(ctx)
  -- jj file annotate takes a path, not a fileset, so file:"..." would not do.
  support.open(ctx, "annotate", { "-r", rev, "--", path }, opener, ctx.first)
end)

action.openers(
  actions,
  "log",
  "show the log of the changes that touched the file, up to this revision",
  support.file_log
)

---@type jin.View
return {
  command = { "file", "show" },
  filetype = "jin-file",
  detect = function(meta)
    return support.file_path(meta.parsed.argv)
  end,
  actions = actions,
  needs_path = true,
  primary = "annotate",
  secondary = "log",
}
