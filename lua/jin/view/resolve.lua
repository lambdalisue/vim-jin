-- The paths a change leaves in conflict, as jj resolve --list prints them.

local action = require("jin.action")
local status = require("jin.status")
local support = require("jin.view.support")
local view = require("jin.view")

---The revision listed and the path of the line acted on.
---@param ctx jin.ActionContext
---@return string rev
---@return string path
local function path_of(ctx)
  local path = ctx.meta.data.paths[ctx.first]
  if not path then
    action.nothing(ctx, "jin: no path on this line")
  end
  return support.revision_arg(ctx.meta.parsed.argv), path
end

local actions = {}

action.openers(actions, "edit", "open the file with its conflict", function(ctx, opener)
  local rev, path = path_of(ctx)
  if support.is_working_copy(ctx, rev) then
    local bufnr = ctx.host.open(ctx.meta.parsed.root .. "/" .. path, { opener = opener })
    local lnum = view.line_of(ctx.host.lines(bufnr), status.CONFLICT)
    if lnum then
      ctx.host.cursor(bufnr, lnum)
    end
    return
  end
  support.open(ctx, "file", { "-r", rev, support.fileset(path) }, opener, status.CONFLICT)
end)

action.openers(actions, "diff", "show the diff of the path in the change", function(ctx, opener)
  local rev, path = path_of(ctx)
  support.open(ctx, "diff", { "-r", rev, "--", support.fileset(path) }, opener)
end)

---@type jin.View
return {
  command = { "resolve", "--list" },
  filetype = "jin-resolve",
  line_items = true,
  decorate = function(meta)
    local paths = {}
    for lnum, line in ipairs(meta.lines) do
      paths[lnum] = status.conflicted(line)
    end
    meta.data.paths = paths
  end,
  actions = actions,
  primary = "edit",
}
