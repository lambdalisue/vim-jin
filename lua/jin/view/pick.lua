-- The parents or children of a change to choose one from, when going to a
-- file as it is in the parent or the child found several. It lists them as
-- the log does, and its buffer name remembers what the choice is for (the
-- view to open, the path and the line), so that choosing goes on to that
-- file rather than to the change, and a read again forgets nothing.

local action = require("jin.action")
local log = require("jin.view.log")
local support = require("jin.view.support")

local actions = {}
for name, entry in pairs(log.actions) do
  actions[name] = entry
end

action.openers(
  actions,
  "pick",
  "open the file the pick is for as it is in the change of the line",
  function(ctx, opener)
    local params = ctx.meta.parsed.params
    ---@type "file"|"annotate"|nil
    local kind = ({ file = "file", annotate = "annotate" })[params.open]
    local path = params.path
    if not kind or type(path) ~= "string" then
      error("jin: this pick names no file to open", 0)
    end
    local line = type(params.line) == "string" and tonumber(params.line) or nil
    local rev = support.revision(action.entry(ctx))
    support.open_file_at(ctx, kind, rev, path, opener, line, "this change")
  end
)

---@type jin.View
return {
  command = log.command,
  config = log.config,
  filetype = "jin-pick",
  entries_span_lines = true,
  blocks = require("jin.view.block").entries,
  template = log.template,
  actions = actions,
  current_entries = true,
  primary = "pick",
  secondary = "show",
  yank = "yank:change",
}
