-- The workspaces of the repository, as jj workspace list prints them.

local action = require("jin.action")
local support = require("jin.view.support")

---The name and the root of the workspace of the line.
---@param ctx jin.ActionContext
---@return string name
---@return string root
local function workspace(ctx)
  local name = action.entry(ctx)[1]
  local result = ctx.jin.jj({ "workspace", "root", "--name", name }, { cwd = ctx.meta.parsed.root })
  if result.code ~= 0 then
    error("jin: " .. result.stderr:gsub("\n$", ""), 0)
  end
  return name, (result.stdout:gsub("\n$", ""))
end

---@param ctx jin.ActionContext
---@param scope "cd"|"lcd"|"tcd"
local function cd(ctx, scope)
  local name, root = workspace(ctx)
  ctx.host.cd(scope, root)
  -- Unlike a :tcd typed out, a key names neither the scope nor the place.
  -- The root itself is left out: a long one would wrap and wait for Enter.
  ctx.host.echo(("jin: %s to the root of workspace %s"):format(scope, name))
end

local actions = {}

for _, scope in ipairs({ "cd", "lcd", "tcd" }) do
  actions[scope] = {
    desc = (":%s to the root of the workspace"):format(scope),
    fn = function(ctx)
      cd(ctx, scope)
    end,
  }
end

actions["update-stale"] = {
  desc = "update the workspace's working copy once another workspace rewrote it",
  changes = true,
  fn = function(ctx)
    support.refuse_at_op(ctx)
    local _, root = workspace(ctx)
    -- In the workspace's own root: jj updates the workspace it runs in.
    ctx.jin.command({ "workspace", "update-stale" }, { cwd = root, quiet = true })
  end,
}

action.openers(
  actions,
  "log",
  "show the log up to the workspace's working copy",
  function(ctx, opener)
    support.open(ctx, "log", { "-r", "::" .. support.string(action.entry(ctx)[1]) .. "@" }, opener)
  end
)

action.openers(actions, "show", "show the workspace's working-copy change", function(ctx, opener)
  support.open(ctx, "show", { support.string(action.entry(ctx)[1]) .. "@" }, opener)
end)

local WORKSPACE_FIELDS, WORKSPACE_ABOUT = support.about({ "name" }, "target")

---@type jin.View
return {
  command = { "workspace", "list" },
  filetype = "jin-workspace",
  line_items = true,
  template = {
    key = "workspace_list",
    default = "builtin_workspace_list",
    fields = WORKSPACE_FIELDS,
    about = WORKSPACE_ABOUT,
  },
  detail = require("jin.view.workspace_detail").detail(),
  actions = actions,
  primary = "tcd",
  secondary = "log",
}
