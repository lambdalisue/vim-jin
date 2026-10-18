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

---The name of an entry, with @remote for a remote one.
---@param entry string[]
---@return string
local function display(entry)
  return entry[2] and (entry[1] .. "@" .. entry[2]) or entry[1]
end

---The entries of the lines acted on, after refusing a view at an earlier
---operation and lines that name no bookmark.
---@param ctx jin.ActionContext
---@return string[][]
local function bookmarks(ctx)
  support.refuse_at_op(ctx)
  if #ctx.entries == 0 then
    action.nothing(ctx, "jin: no bookmark on this line")
  end
  return ctx.entries
end

---Run jj bookmark with `argv`, quietly, as the views it reads again show the
---result.
---@param ctx jin.ActionContext
---@param argv string[]
---@param on_exit? fun(result: jin.RunResult)
local function bookmark(ctx, argv, on_exit)
  table.insert(argv, 1, "bookmark")
  ctx.jin.command(argv, { cwd = ctx.meta.parsed.root, quiet = true }, on_exit)
end

for _, word in ipairs({ "delete", "forget" }) do
  actions[word] = {
    desc = word == "delete" and "delete the bookmarks, once confirmed" or "forget the bookmarks",
    changes = true,
    fn = function(ctx)
      local argv, seen = { word }, {}
      local entries = bookmarks(ctx)
      for _, entry in ipairs(entries) do
        -- A remote bookmark goes once the deletion of the local one is
        -- pushed; jj deletes none by itself.
        if not seen[entry[1]] and not (word == "delete" and entry[2]) then
          seen[entry[1]] = true
          argv[#argv + 1] = "exact:" .. support.string(entry[1])
        end
      end
      if #argv == 1 then
        error(
          ("jin: %s is a remote bookmark; delete the local one and push it"):format(
            display(entries[1])
          ),
          0
        )
      end
      if word == "forget" then
        argv[#argv + 1] = "--include-remotes"
      else
        local count = #argv - 1
        local question = ("jin: delete %d %s?"):format(
          count,
          count == 1 and "bookmark" or "bookmarks"
        )
        if not ctx.host.confirm(question) then
          return
        end
      end
      bookmark(ctx, argv)
    end,
  }
end

for _, word in ipairs({ "track", "untrack" }) do
  actions[word] = {
    desc = word .. " the remote bookmarks",
    changes = true,
    fn = function(ctx)
      local argv = { word }
      local entries = bookmarks(ctx)
      for _, entry in ipairs(entries) do
        -- The name@remote form takes no exact: pattern, but a name a remote
        -- holds can have no glob character, as Git refuses them.
        if entry[2] then
          argv[#argv + 1] = support.string(entry[1]) .. "@" .. support.string(entry[2])
        end
      end
      if #argv == 1 then
        error(("jin: %s is a local bookmark; %s a remote one"):format(entries[1][1], word), 0)
      end
      bookmark(ctx, argv)
    end,
  }
end

actions.move = {
  desc = "move the bookmark to the selected change",
  changes = true,
  fn = function(ctx)
    local entry = bookmarks(ctx)[1]
    if entry[2] then
      error(("jin: %s is a remote bookmark; move a local one"):format(display(entry)), 0)
    end
    local selected = support.selected(ctx)
    if #selected == 0 then
      error("jin: select the change to move the bookmark to first", 0)
    elseif #selected > 1 then
      error(
        ("jin: move takes one selected change to move the bookmark to, but %d are selected"):format(
          #selected
        ),
        0
      )
    end
    -- --allow-backwards: the selected change is where the user chose to move it,
    -- an ancestor or a sibling as well as a descendant.
    bookmark(ctx, {
      "move",
      "exact:" .. support.string(entry[1]),
      "--to",
      selected[1],
      "--allow-backwards",
    }, support.clear_selected_on_success(ctx))
  end,
}

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

-- A conflicted bookmark has no single target to tell about.
local BOOKMARK_FIELDS, BOOKMARK_ABOUT = support.about(
  { "name", "if(remote, remote)", 'if(present, "", "absent")' },
  "normal_target",
  "normal_target"
)

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
    fields = BOOKMARK_FIELDS,
    about = BOOKMARK_ABOUT,
  },
  detail = require("jin.view.bookmark_detail").detail(),
  actions = actions,
  primary = "log",
  secondary = "show",
  yank = "yank:bookmark",
}
