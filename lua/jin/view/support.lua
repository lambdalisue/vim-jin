-- What several views share: naming the revision an entry stands for, opening
-- another view from an action, and following a diff line to its file.

local action = require("jin.action")
local args = require("jin.args")
local diff = require("jin.diff")
local view = require("jin.view")

local M = {}

---The marker fields of a change: its change ID, its commit ID, and
---"divergent" when the change ID stands for several commits, or "hidden"
---when the commit is a version the change was rewritten from.
M.CHANGE_FIELDS =
  { "change_id", "commit_id", 'if(divergent, "divergent", if(hidden, "hidden", "-"))' }

---The template of a view listing changes, named by `key`.
---@param key string
---@param default string
---@return { key: string, default: string, fields: string[] }
function M.logged(key, default)
  return { key = key, default = default, fields = M.CHANGE_FIELDS }
end

---The template jj prints a commit with inside the output of other commands,
---such as jj status and jj op show, marked with CHANGE_FIELDS and handed to
---jj as its setting.
M.SUMMARY_TEMPLATE = {
  key = "commit_summary",
  default = "format_commit_summary_with_refs(self, format_commit_ref_names(bookmarks))",
  fields = M.CHANGE_FIELDS,
  config = true,
}

---The entries of the lines a commit summary starts on, by line. The lines
---after one belong to no summary, though the markers carry its entry on.
---@param meta jin.ViewMeta
---@return table<integer, string[]>
function M.summaries(meta)
  local found = {}
  for lnum, entry in pairs(meta.entries) do
    if entry and entry ~= meta.entries[lnum - 1] then
      found[lnum] = entry
    end
  end
  return found
end

---The revision an entry made of CHANGE_FIELDS stands for. The change ID
---follows the change through rewrites, so a view opened with it stays
---current; a divergent change ID names several commits, and that of a
---hidden commit its latest version, so the commit ID is used for them
---instead.
---@param entry string[]
---@return string
function M.revision(entry)
  if entry[3] == "divergent" or entry[3] == "hidden" then
    return entry[2]
  end
  return entry[1]
end

M.file_path = require("jin.expand").file_path

---A fileset naming exactly `path`. A plain path is itself a fileset, but one
---with spaces, quotes or operator characters has to be written as a string,
---and so does one starting with `-`, which jj would read as an option.
---@param path string
---@return string
function M.fileset(path)
  if path:match("^[%w%._/][%w%._%-/]*$") then
    return path
  end
  return 'file:"' .. path:gsub('[\\"]', "\\%0") .. '"'
end

---The operation the arguments load the repository at (--at-op), if any.
---@param argv string[]
---@return string?
function M.at_op(argv)
  for _, item in ipairs((args.options(argv))) do
    if item.name == "at-op" then
      return item.value
    end
  end
  return nil
end

---Run jj for an action and wait for it, in the workspace of the buffer acted
---on and at the operation it shows.
---@param ctx jin.ActionContext
---@param argv string[]
---@return jin.RunResult?
function M.query(ctx, argv)
  local op = M.at_op(ctx.meta.parsed.argv)
  if op then
    local with_op = { "--at-op", op }
    for _, a in ipairs(argv) do
      with_op[#with_op + 1] = a
    end
    argv = with_op
  end
  return ctx.jin.jj(argv, { cwd = ctx.meta.parsed.root })
end

---Lead to the parents or children of `rev`: `open_one` opens the only one,
---named as a view opened from a change names it; several open a log of them
---to choose from.
---@param ctx jin.ActionContext
---@param which "parents"|"children"
---@param rev string
---@param opener string
---@param open_one fun(rev: string)
function M.relative(ctx, which, rev, opener, open_one)
  local revset = which .. "(" .. rev .. ")"
  local result = M.query(ctx, {
    "log",
    "--no-graph",
    "-r",
    revset,
    "-T",
    -- A hidden commit, such as the parent of an older version, is named by
    -- its commit ID too, as its change ID leads to the latest version.
    'if(divergent || hidden, commit_id, change_id) ++ "\\n"',
  })
  if not result or result.code ~= 0 then
    error("jin: " .. (result and result.stderr:gsub("\n$", "") or "jj did not finish"), 0)
  end
  local revs = {}
  for line in result.stdout:gmatch("[^\n]+") do
    revs[#revs + 1] = line
  end
  if #revs == 0 then
    error("jin: the change has no " .. which, 0)
  elseif #revs == 1 then
    open_one(revs[1])
  else
    M.open(ctx, "log", { "-r", revset }, opener)
  end
end

---The revision `-r` names in the arguments of a command that takes one, the
---working copy when none is given.
---@param argv string[]
---@return string
function M.revision_arg(argv)
  local rev = "@"
  for _, item in ipairs((args.options(argv, args.REVISIONS))) do
    if item.name == "revisions" then
      rev = item.value or rev
    end
  end
  return rev
end

---The revision and the path a file or annotate view shows.
---@param ctx jin.ActionContext
---@return string rev
---@return string path
function M.shown_file(ctx)
  local argv = ctx.meta.parsed.argv
  local path = M.file_path(argv)
  if not path then
    error("jin: this view shows no file", 0)
  end
  return M.revision_arg(argv), path
end

---Show the log of the changes that touched the file of a file or annotate
---view, up to the revision shown.
---@param ctx jin.ActionContext
---@param opener string
function M.file_log(ctx, opener)
  local rev, path = M.shown_file(ctx)
  -- `::a|b` would be `(::a)|b`.
  local base = rev:match("^[%w_@]+$") and rev or "(" .. rev .. ")"
  M.open(ctx, "log", { "-r", "::" .. base, "--", M.fileset(path) }, opener)
end

---Open `name` from an action, in the workspace of the buffer acted on and,
---when that buffer shows an earlier operation, at that operation too.
---@param ctx jin.ActionContext
---@param name string
---@param argv string[]
---@param opener string
---@param line? integer
---@return integer bufnr
function M.open(ctx, name, argv, opener, line)
  local op = M.at_op(ctx.meta.parsed.argv)
  if op then
    local with_op = { "--at-op", op }
    for _, a in ipairs(argv) do
      with_op[#with_op + 1] = a
    end
    argv = with_op
  end
  return view.open(ctx.jin, ctx.host, name, argv, {
    cwd = ctx.meta.parsed.root,
    opener = opener,
    line = line,
  })
end

---Mark each file section of a color-words diff for folding and following.
---@param meta jin.ViewMeta
function M.decorate_diff(meta)
  local parsed = diff.parse(meta.lines)
  meta.data.diff = parsed
  local folds = {}
  for _, file in ipairs(parsed.files) do
    if file.last > file.first then
      folds[#folds + 1] = { file.first, file.last }
    end
  end
  meta.data.folds = folds
end

---A decorate for a view of a diff alone, as `decorate_diff` does, that says
---`note` in gray beside an empty line when jj printed nothing, so that an
---empty buffer is not taken for one still being read or gone wrong.
---@param note string
---@return fun(meta: jin.ViewMeta)
function M.decorate_diff_or(note)
  return function(meta)
    for _, line in ipairs(meta.lines) do
      if line ~= "" then
        return M.decorate_diff(meta)
      end
    end
    meta.lines = { "" }
    meta.data.annotations = { { { text = note, style = { fg = 8 } } } }
  end
end

---The status of the file whose section holds line `lnum` of a parsed diff.
---@param parsed { files: jin.DiffFile[] }
---@param lnum integer
---@return string?
local function status_at(parsed, lnum)
  for _, file in ipairs(parsed.files) do
    if file.first <= lnum and lnum <= file.last then
      return file.status
    end
  end
  return nil
end

---Open the file a diff line shows, at that line, on the side asked for (by
---default the new side, or the old one for a removed line or file). A side
---that is the working copy opens the file itself; any other revision, and
---the working copy of an earlier operation, opens the file view.
---@param ctx jin.ActionContext
---@param opener string
---@param side? "old"|"new"
---@param sides { old?: string, new: string, missing?: string } a side that is in no revision is nil, and jumping there fails with `missing`
function M.jump(ctx, opener, side, sides)
  local parsed = ctx.meta.data.diff
  local info = parsed and parsed.lines[ctx.first]
  if not info then
    action.nothing(ctx, "jin: no file on this line")
  end
  side = side
    or (info.new and "new")
    or (info.old and "old")
    or (status_at(parsed, ctx.first) == "removed" and "old")
    or "new"
  local lnum = info[side] or 1
  local path = side == "old" and info.from or info.path
  local rev = sides[side]
  if not rev then
    error(sides.missing or "jin: this side is in no revision", 0)
  end
  if side == "old" and rev ~= "@" then
    -- The old side of a merge is the parents merged together, which no
    -- revision holds; jj file show would only say the revset is ambiguous.
    local result = M.query(ctx, { "log", "--no-graph", "-r", rev, "--limit", "2", "-T", '"x"' })
    if result and result.code == 0 and #result.stdout > 1 then
      error(
        ("jin: %s is several revisions, such as the parents of a merge; jump to the new side instead"):format(
          rev
        ),
        0
      )
    end
  end
  if rev == "@" and not M.at_op(ctx.meta.parsed.argv) then
    local bufnr = ctx.host.open(ctx.meta.parsed.root .. "/" .. path, { opener = opener })
    ctx.host.cursor(bufnr, lnum)
    return
  end
  M.open(ctx, "file", { "-r", rev, M.fileset(path) }, opener, lnum)
end

---Add jump, jump:old and jump:new (each with its opener variants) to
---`actions`, taking the sides of each line from `sides_of`.
---@param actions table<string, jin.Action>
---@param sides_of fun(ctx: jin.ActionContext): { old?: string, new: string, missing?: string }
function M.jump_actions(actions, sides_of)
  action.openers(actions, "jump", "open the file at this line", function(ctx, opener)
    M.jump(ctx, opener, nil, sides_of(ctx))
  end)
  action.openers(
    actions,
    "jump:old",
    "open the file before the change at this line",
    function(ctx, opener)
      M.jump(ctx, opener, "old", sides_of(ctx))
    end
  )
  action.openers(
    actions,
    "jump:new",
    "open the file after the change at this line",
    function(ctx, opener)
      M.jump(ctx, opener, "new", sides_of(ctx))
    end
  )
end

---Add yank:change and yank:commit, yanking the IDs of every entry acted on.
---@param actions table<string, jin.Action>
function M.yank_actions(actions)
  local function yank(index)
    return function(ctx)
      local ids = {}
      for _, entry in ipairs(ctx.entries) do
        ids[#ids + 1] = entry[index]
      end
      if #ids == 0 then
        action.nothing(ctx, "jin: nothing to yank in these lines")
      end
      ctx.host.yank(table.concat(ids, "\n"))
    end
  end
  actions["yank:change"] = { desc = "yank the change IDs", fn = yank(1) }
  actions["yank:commit"] = { desc = "yank the commit IDs", fn = yank(2) }
end

return M
