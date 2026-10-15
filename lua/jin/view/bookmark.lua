-- Bookmarks, local and remote, as jj bookmark list prints them.

local action = require("jin.action")
local support = require("jin.view.support")

---The revset of the bookmark an entry (name, remote?) stands for.
---@param entry string[]
---@return string
local function revset(entry)
  if entry[3] then
    local name = entry[2] and (entry[1] .. "@" .. entry[2]) or entry[1]
    error("jin: " .. name .. " points to no change", 0)
  end
  if entry[2] then
    return ("remote_bookmarks(exact:%s, exact:%s)"):format(
      support.string(entry[1]),
      support.string(entry[2])
    )
  end
  return ("bookmarks(exact:%s)"):format(support.string(entry[1]))
end

local actions = {}

action.openers(actions, "log", "show the log up to the bookmark", function(ctx, opener)
  support.open(ctx, "log", { "-r", "::" .. revset(action.entry(ctx)) }, opener)
end)

action.openers(actions, "show", "show the change the bookmark points to", function(ctx, opener)
  support.open(ctx, "show", { revset(action.entry(ctx)) }, opener)
end)

actions["yank:bookmark"] = {
  desc = "yank the bookmark names, with @remote for remote ones",
  fn = function(ctx)
    local names = {}
    for _, entry in ipairs(ctx.entries) do
      names[#names + 1] = entry[2] and (entry[1] .. "@" .. entry[2]) or entry[1]
    end
    if #names == 0 then
      action.nothing(ctx, "jin: nothing to yank in these lines")
    end
    ctx.host.yank(table.concat(names, "\n"))
  end,
}

---@type jin.View
return {
  command = { "bookmark", "list" },
  filetype = "jin-bookmark",
  line_items = true,
  template = {
    key = "bookmark_list",
    default = 'format_commit_ref(self, "bookmark") ++ "\\n"',
    -- A tracked remote bookmark not pushed yet, or a deleted local one,
    -- holds no target.
    fields = { "name", "if(remote, remote)", 'if(present, "", "absent")' },
  },
  actions = actions,
  primary = "log",
  secondary = "show",
  yank = "yank:bookmark",
}
