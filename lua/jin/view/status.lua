-- The working copy: what it changes, and what it leaves in conflict.

local action = require("jin.action")
local status = require("jin.status")
local support = require("jin.view.support")
local view = require("jin.view")

---@param ctx jin.ActionContext
---@return jin.StatusPath
local function path_of(ctx)
  local found = ctx.meta.data.paths[ctx.first]
  if not found then
    action.nothing(ctx, "jin: no path on this line")
  end
  return found
end

local actions = {}

---Open the file of `found` in the working copy, a conflicted one at its
---first conflict.
---@param ctx jin.ActionContext
---@param found jin.StatusPath
---@param opener string
local function open_file(ctx, found, opener)
  local bufnr = ctx.host.open(ctx.meta.parsed.root .. "/" .. found.path, { opener = opener })
  local lnum = found.status == "conflict" and view.line_of(ctx.host.lines(bufnr), status.CONFLICT)
  if lnum then
    ctx.host.cursor(bufnr, lnum)
  end
end

action.openers(actions, "edit", "open the file of the working copy", function(ctx, opener)
  open_file(ctx, path_of(ctx), opener)
end)

-- open and inspect are what <CR> and its kin do on any line: a line that
-- names nothing is no mistake to tell about, as it is for an action asked
-- for by name.
action.openers(
  actions,
  "open",
  "open the file of the line, or show the change of a working copy or parent line",
  function(ctx, opener)
    local found = ctx.meta.data.paths[ctx.first]
    local revision = ctx.meta.data.revisions[ctx.first]
    if found then
      open_file(ctx, found, opener)
    elseif revision then
      support.open(ctx, "show", { revision }, opener)
    end
  end
)

action.openers(
  actions,
  "inspect",
  "show the diff of the path of the line, or the change of a working copy or parent line",
  function(ctx, opener)
    local found = ctx.meta.data.paths[ctx.first]
    local revision = ctx.meta.data.revisions[ctx.first]
    if found then
      support.open(ctx, "diff", { "--", support.fileset(found.path) }, opener)
    elseif revision then
      support.open(ctx, "show", { revision }, opener)
    end
  end
)

action.openers(actions, "diff", "show the diff of the path", function(ctx, opener)
  support.open(ctx, "diff", { "--", support.fileset(path_of(ctx).path) }, opener)
end)

action.openers(actions, "annotate", "show which change wrote each line", function(ctx, opener)
  -- jj file annotate takes a path, not a fileset, so file:"..." would not do.
  support.open(ctx, "annotate", { "--", path_of(ctx).path }, opener)
end)

support.commit_actions(actions)

actions["yank:path"] = {
  desc = "yank the paths",
  fn = function(ctx)
    local paths = {}
    for lnum = ctx.first, ctx.last do
      local found = ctx.meta.data.paths[lnum]
      if found then
        paths[#paths + 1] = found.path
      end
    end
    if #paths == 0 then
      action.nothing(ctx, "jin: nothing to yank in these lines")
    end
    ctx.host.yank(table.concat(paths, "\n"))
  end,
}

---@type jin.View
return {
  command = { "status" },
  filetype = "jin-status",
  line_items = true,
  -- jj prints the working copy and its parents with this template, so the
  -- markers name their changes whatever the user made it print.
  template = support.SUMMARY_TEMPLATE,
  decorate = function(meta)
    meta.data.paths = status.parse(meta.lines)
    local revisions = {}
    for lnum, entry in pairs(support.summaries(meta)) do
      revisions[lnum] = support.revision(entry)
    end
    meta.data.revisions = revisions
  end,
  actions = actions,
  primary = "inspect",
  secondary = "open",
  yank = "yank:path",
}
