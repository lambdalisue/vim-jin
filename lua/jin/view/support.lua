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

---`fields` followed by what a commit is about, for the statusline: the first
---line of its description, its author, and how long ago it was committed.
---`commit` is the template expression of the commit; with `guard`, the
---fields are empty where it does not hold, as where there is no commit.
---@param fields string[]
---@param commit string
---@param guard? string
---@return string[] fields
---@return integer about the index of the first of them
function M.about(fields, commit, guard)
  local all = {}
  for i, field in ipairs(fields) do
    all[i] = field
  end
  for _, expr in ipairs({
    "description().first_line()",
    "author().name()",
    "committer().timestamp().ago()",
  }) do
    expr = commit .. "." .. expr
    all[#all + 1] = guard and ("if(" .. guard .. ", " .. expr .. ")") or expr
  end
  return all, #fields + 1
end

---`fields` followed by the shortest unique prefixes of the change and the
---commit IDs of `commit`, the parts jj highlights, for the statusline.
---@param fields string[]
---@param commit string
---@return string[] fields
---@return integer short the index of the first of them
function M.shortest(fields, commit)
  local all = {}
  for i, field in ipairs(fields) do
    all[i] = field
  end
  all[#all + 1] = commit .. ".change_id().shortest()"
  all[#all + 1] = commit .. ".commit_id().shortest()"
  return all, #fields + 1
end

local LOGGED_FIELDS, LOGGED_ABOUT = M.about(M.CHANGE_FIELDS, "self")
local LOGGED_SHORT
LOGGED_FIELDS, LOGGED_SHORT = M.shortest(LOGGED_FIELDS, "self")

---The template of a view listing changes, named by `key`.
---@param key string
---@param default string
---@return { key: string, default: string, fields: string[], about: integer, short: integer }
function M.logged(key, default)
  return {
    key = key,
    default = default,
    fields = LOGGED_FIELDS,
    about = LOGGED_ABOUT,
    short = LOGGED_SHORT,
  }
end

---The template jj prints a commit with inside the output of other commands,
---such as jj status and jj op show, marked with CHANGE_FIELDS and handed to
---jj as its setting.
M.SUMMARY_TEMPLATE = {
  key = "commit_summary",
  default = "format_commit_summary_with_refs(self, format_commit_ref_names(bookmarks))",
  fields = LOGGED_FIELDS,
  about = LOGGED_ABOUT,
  short = LOGGED_SHORT,
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

---A revset string literal holding `value`, which names a bookmark, remote or
---workspace whatever characters it has. Control characters are written as
---escapes, so that the literal stays on one line of a buffer name.
---@param value string
---@return string
function M.string(value)
  local escaped = value:gsub('[\\"]', "\\%0"):gsub("[%z\1-\31\127]", function(c)
    return ("\\x%02x"):format(c:byte())
  end)
  return '"' .. escaped .. '"'
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

---Whether `rev` is the working copy, and so its files are the files
---themselves. The working copy of an earlier operation never is.
---@param ctx jin.ActionContext
---@param rev string
---@return boolean
function M.is_working_copy(ctx, rev)
  if M.at_op(ctx.meta.parsed.argv) then
    return false
  end
  local result = M.query(ctx, { "log", "--no-graph", "-r", "(" .. rev .. ") & @", "-T", '"x"' })
  return result ~= nil and result.code == 0 and result.stdout ~= ""
end

---Lead to the parents or children of `rev`: `open_one` opens the only one,
---named as a view opened from a change names it; several open a log of them
---to choose from, or, given `pick`, a pick view of them with those
---parameters, whose choice goes on to what they name.
---@param ctx jin.ActionContext
---@param which "parents"|"children"
---@param rev string
---@param opener string
---@param open_one fun(rev: string)
---@param pick? table<string, string>
function M.relative(ctx, which, rev, opener, open_one, pick)
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
  elseif pick then
    M.open(ctx, "pick", { "-r", revset }, opener, nil, pick)
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

---Open `path` as it is in `rev` with the view `kind`, a file view or an
---annotation, the cursor on `line`. A revision without the file, such as
---the parent of the change that added it, is refused rather than opened;
---`where` names it in the message.
---@param ctx jin.ActionContext
---@param kind "file"|"annotate"
---@param rev string
---@param path string
---@param opener string
---@param line? integer
---@param where string
function M.open_file_at(ctx, kind, rev, path, opener, line, where)
  local result = M.query(ctx, { "file", "list", "-r", rev, "--", M.fileset(path) })
  if not result or result.code ~= 0 then
    error("jin: " .. (result and result.stderr:gsub("\n$", "") or "jj did not finish"), 0)
  end
  if result.stdout == "" then
    error(("jin: %s is not in %s"):format(path, where), 0)
  end
  if kind == "annotate" then
    -- jj file annotate takes a path, not a fileset, so file:"..." would not do.
    M.open(ctx, "annotate", { "-r", rev, "--", path }, opener, line)
  else
    M.open(ctx, "file", { "-r", rev, M.fileset(path) }, opener, line)
  end
end

---Add `parent` and `child` (each with its opener variants) to `actions`,
---opening the file of a file or annotate view with the view `kind`, on the
---same line, as it is in the parent or the child of the revision `from`
---gives, by default the one shown. Several open a pick view of them that
---goes on to the file in the one chosen.
---@param actions table<string, jin.Action>
---@param kind "file"|"annotate"
---@param from? { desc: string, rev: fun(ctx: jin.ActionContext): string }
function M.file_relatives(actions, kind, from)
  for name, which in pairs({ parent = "parents", child = "children" }) do
    action.openers(
      actions,
      name,
      ("open the file as it is in the %s of %s, or a pick of them when there are several"):format(
        which,
        from and from.desc or "the revision shown"
      ),
      function(ctx, opener)
        local rev, path = M.shown_file(ctx)
        if from then
          rev = from.rev(ctx)
        end
        M.relative(ctx, which, rev, opener, function(found)
          M.open_file_at(ctx, kind, found, path, opener, ctx.first, "the " .. name)
        end, { open = kind, path = path, line = tostring(ctx.first) })
      end
    )
  end
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
---@param line? jin.ViewLine
---@param params? table<string, string|true>
---@return integer bufnr
function M.open(ctx, name, argv, opener, line, params)
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
    params = params,
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

---Per host, per commit buffer: the name of the buffer it was opened over in
---the same window, or false when it was opened in a window of its own.
---@type table<jin.Host, table<integer, string|false>>
local returns = setmetatable({}, { __mode = "k" })

---Mark `bufnr` written, as long as it still holds the lines `written` that
---jj took: lines edited while jj ran are not written yet.
---@param host jin.Host
---@param bufnr integer
---@param written string[]
---@return boolean marked
function M.mark_saved(host, bufnr, written)
  local now = host.lines(bufnr)
  if #now ~= #written then
    return false
  end
  for i, line in ipairs(now) do
    if line ~= written[i] then
      return false
    end
  end
  host.mark_saved(bufnr)
  return true
end

---Stop showing the commit buffer `bufnr`: the window it was opened over
---shows again what it showed before, and a window or tab page opened for it
---closes.
---@param host jin.Host
---@param bufnr integer
function M.leave_commit(host, bufnr)
  local back = (returns[host] or {})[bufnr]
  if returns[host] then
    returns[host][bufnr] = nil
  end
  host.leave(bufnr, back or nil)
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

---Refuse to change the repository from a view at an earlier operation: what
---it shows is not what a change would apply to.
---@param ctx jin.ActionContext
function M.refuse_at_op(ctx)
  if M.at_op(ctx.meta.parsed.argv) then
    error("jin: this view shows an earlier operation, which is not to be changed", 0)
  end
end

---Refuse to act on a change rewritten since the view was read, as by an
---agent meanwhile: the line shows a version that is no longer the change,
---and acting on the change would act on what nobody looked at. The view is
---read again instead. A change jj cannot tell about is let through.
---@param ctx jin.ActionContext
function M.refuse_rewritten(ctx)
  local seen, names = {}, {}
  for _, entry in ipairs(ctx.entries) do
    -- Named by its commit ID, a divergent or hidden one is the version seen.
    if entry[2] and entry[3] ~= "divergent" and entry[3] ~= "hidden" then
      seen[entry[1]] = entry[2]
      names[#names + 1] = entry[1]
    end
  end
  if #names == 0 then
    return
  end
  local query = {
    "log",
    "--no-graph",
    "-r",
    table.concat(names, "|"),
    "-T",
    'change_id ++ " " ++ commit_id ++ "\\n"',
  }
  local result = ctx.jin.jj(query, { cwd = ctx.meta.parsed.root })
  if not result or result.code ~= 0 then
    return
  end
  for change_id, commit_id in result.stdout:gmatch("(%S+) (%S+)\n") do
    if seen[change_id] and seen[change_id] ~= commit_id then
      view.read(ctx.jin, ctx.host, ctx.bufnr, ctx.meta.name)
      error(
        ("jin: %s changed since the view was read, so it is read again; look before acting again"):format(
          change_id
        ),
        0
      )
    end
  end
end

---The revisions of every entry acted on, after refusing a view at an earlier
---operation and lines that name no change.
---@param ctx jin.ActionContext
---@return string[]
local function changed(ctx)
  M.refuse_at_op(ctx)
  if #ctx.entries == 0 then
    action.nothing(ctx, "jin: nothing to act on in this line")
  end
  if view.get(ctx.meta.view).current_entries then
    M.refuse_rewritten(ctx)
  end
  -- Once each: lines that each name a change, as annotate's do, would name
  -- it as many times.
  local revs, seen = {}, {}
  for _, entry in ipairs(ctx.entries) do
    local rev = M.revision(entry)
    if not seen[rev] then
      seen[rev] = true
      revs[#revs + 1] = rev
    end
  end
  return revs
end

---The words of every list in turn.
---@param ... string[]
---@return string[]
local function join(...)
  local argv = {}
  for _, list in ipairs({ ... }) do
    for _, word in ipairs(list) do
      argv[#argv + 1] = word
    end
  end
  return argv
end

---`flag` before each of `revs`.
---@param flag string
---@param revs string[]
---@return string[]
local function flagged(flag, revs)
  local argv = {}
  for _, rev in ipairs(revs) do
    argv[#argv + 1] = flag
    argv[#argv + 1] = rev
  end
  return argv
end

---Run jj with the words of every list in turn, quietly, as the views it reads
---again show the result.
---@param ctx jin.ActionContext
---@param ... string[]
local function change(ctx, ...)
  ctx.jin.command(join(...), { cwd = ctx.meta.parsed.root, quiet = true })
end

---Add describe (with its opener variants): open the description buffer of
---the change of every entry acted on.
---@param actions table<string, jin.Action>
function M.describe_actions(actions)
  action.openers(actions, "describe", "edit the description of the changes", function(ctx, opener)
    local argv = {}
    for _, rev in ipairs(changed(ctx)) do
      argv[#argv + 1] = "-r"
      argv[#argv + 1] = rev
    end
    M.open(ctx, "describe", argv, opener)
  end)
  actions.describe.changes = true
end

---The change ID of the working copy of the workspace at `root`.
---@param jin jin.Api
---@param root string
---@return string
function M.working_copy(jin, root)
  local query = { "log", "--no-graph", "-r", "@", "-T", "change_id" }
  local result = jin.jj(query, { cwd = root })
  if result.code ~= 0 then
    error("jin: " .. result.stderr:gsub("\n$", ""), 0)
  end
  return (result.stdout:gsub("\n$", ""))
end

---Add commit (with its opener variants): open the description buffer of the
---working copy, the change jj commit works on, whatever the line.
---@param actions table<string, jin.Action>
function M.commit_actions(actions)
  action.openers(actions, "commit", "commit the working copy", function(ctx, opener)
    M.refuse_at_op(ctx)
    local id = M.working_copy(ctx.jin, ctx.meta.parsed.root)
    local back = opener == "edit" and ctx.host.buffer_name(ctx.bufnr) or false
    local bufnr = M.open(ctx, "commit", { "-r", id }, opener)
    returns[ctx.host] = returns[ctx.host] or {}
    returns[ctx.host][bufnr] = back
  end)
  actions.commit.changes = true
end

---Add select, selecting the change of every entry acted on, or leaving it
---out when selected, and select:clear, clearing the selection of the
---workspace.
---@param actions table<string, jin.Action>
function M.select_actions(actions)
  local selection = require("jin.selection")
  actions.select = {
    desc = "select the changes as the other side of an action, or leave them out",
    fn = function(ctx)
      if #ctx.entries == 0 then
        action.nothing(ctx, "jin: nothing to act on in this line")
      end
      -- Once each: lines that each name a change, as annotate's do, would
      -- toggle it as many times.
      local revs, seen = {}, {}
      for _, entry in ipairs(ctx.entries) do
        local rev = M.revision(entry)
        if not seen[rev] then
          seen[rev] = true
          revs[#revs + 1] = rev
        end
      end
      selection.toggle(ctx.host, ctx.meta.parsed.root, revs)
      view.show_selected_of(ctx.host, ctx.meta.parsed.root)
    end,
  }
  actions["select:clear"] = {
    desc = "clear the selection of the workspace",
    fn = function(ctx)
      selection.clear(ctx.host, ctx.meta.parsed.root)
      view.show_selected_of(ctx.host, ctx.meta.parsed.root)
    end,
  }
end

---The selected changes of the workspace of `ctx`.
---@param ctx jin.ActionContext
---@return string[]
function M.selected(ctx)
  return require("jin.selection").list(ctx.host, ctx.meta.parsed.root)
end

---An `on_exit` for jj run with the selection of `ctx`, which leaves them out once
---jj succeeded, used up, and shows it in every view. A failure leaves them
---for the action to be tried again.
---@param ctx jin.ActionContext
---@return fun(result: jin.RunResult)
function M.clear_selected_on_success(ctx)
  local selection = require("jin.selection")
  local host, root = ctx.host, ctx.meta.parsed.root
  local taken = M.selected(ctx)
  return function(result)
    if result.code ~= 0 then
      return
    end
    -- Only those still selected: a change selected while jj ran is for the
    -- next action, and one left out meanwhile would be selected again by
    -- toggling.
    local now = {}
    for _, rev in ipairs(selection.list(host, root)) do
      now[rev] = true
    end
    local used = {}
    for _, rev in ipairs(taken) do
      if now[rev] then
        used[#used + 1] = rev
      end
    end
    if #used > 0 then
      selection.toggle(host, root, used)
      view.show_selected_of(host, root)
    end
  end
end

---Run jj as `change` does, with the selection of `ctx`.
---@param ctx jin.ActionContext
---@param ... string[]
local function change_with_selected(ctx, ...)
  local opts = { cwd = ctx.meta.parsed.root, quiet = true }
  ctx.jin.command(join(...), opts, M.clear_selected_on_success(ctx))
end

---The description of `rev` in the workspace at `root`, as a description
---buffer reads it, or nil when jj fails to tell it.
---@param jin jin.Api
---@param root string
---@param rev string
---@return string?
function M.description(jin, root, rev)
  local query = { "log", "--no-graph", "-r", rev, "-T", "description" }
  local result = jin.jj(query, { cwd = root })
  if result.code ~= 0 then
    return nil
  end
  local lines = {}
  for line in (result.stdout .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  return require("jin.description").text(lines)
end

---CHANGE_FIELDS with the description itself, for a buffer that edits it:
---the draft jj shows may add to the description, which is what jj compares
---against. The shortest prefixes follow from DESCRIBED_SHORT on.
M.DESCRIBED_FIELDS, M.DESCRIBED_SHORT =
  M.shortest({ M.CHANGE_FIELDS[1], M.CHANGE_FIELDS[2], M.CHANGE_FIELDS[3], "description" }, "self")

---The description each change of `meta` had when read, by revision, from
---the entries DESCRIBED_FIELDS marked.
---@param meta jin.ViewMeta
---@return table<string, string>
function M.originals(meta)
  local originals = {}
  for _, entry in ipairs(meta.entries) do
    if entry then
      local lines = {}
      for line in ((entry[4] or "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
      end
      originals[M.revision(entry)] = require("jin.description").text(lines)
    end
  end
  return originals
end

-- One record per commit: its change ID, its commit ID and its description.
local DESCRIPTIONS = 'change_id ++ "\\x1f" ++ commit_id ++ "\\x1f" ++ description ++ "\\x1e"'

---Refuse to write over the description of any of `revs` someone, such as an
---agent, changed since it was read as `originals` says, asking jj once for
---all of them.
---@param jin jin.Api
---@param root string
---@param originals table<string, string>
---@param revs string[]
function M.refuse_changed(jin, root, originals, revs)
  local asked = {}
  for _, rev in ipairs(revs) do
    if originals[rev] then
      asked[#asked + 1] = rev
    end
  end
  if #asked == 0 then
    return
  end
  local query = { "log", "--no-graph", "-r", table.concat(asked, "|"), "-T", DESCRIPTIONS }
  local result = jin.jj(query, { cwd = root })
  if result.code ~= 0 then
    return
  end
  local now, versions = {}, {}
  for record in result.stdout:gmatch("([^\30]*)\30") do
    local change_id, commit_id, text = record:match("^([^\31]*)\31([^\31]*)\31(.*)$")
    if change_id then
      local lines = {}
      for line in (text .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = line
      end
      text = require("jin.description").text(lines)
      now[change_id], now[commit_id] = text, text
      versions[change_id] = (versions[change_id] or 0) + 1
    end
  end
  for _, rev in ipairs(asked) do
    -- Describing a change ID describes every version it has now.
    if (versions[rev] or 0) > 1 then
      error(
        ("jin: %s has split into several versions since it was read; describe one from a view"):format(
          rev
        ),
        0
      )
    end
    if now[rev] and now[rev] ~= originals[rev] then
      error(
        ("jin: the description of %s changed since it was read; :edit! reads it again"):format(rev),
        0
      )
    end
  end
end

---@param ctx jin.ActionContext
---@param rev string
---@return string
local function description_of(ctx, rev)
  return M.description(ctx.jin, ctx.meta.parsed.root, rev) or ""
end

---The jj arguments that squash the changes of `ctx` into the selected one, or
---into their parent.
---@param ctx jin.ActionContext
---@return string[]
local function squash_argv(ctx)
  local revs = changed(ctx)
  local selected = M.selected(ctx)
  if #selected > 1 then
    error(
      ("jin: squash takes one selected change to squash into, but %d are selected"):format(
        #selected
      ),
      0
    )
  end
  local into = selected[1]
  if not into and #revs > 1 then
    error("jin: select the change to squash these into first", 0)
  end
  -- -m always: with a description on both sides, jj would otherwise
  -- open an editor to merge them, which nobody can answer from here.
  local sides = { into or (revs[1] .. "-") }
  for _, rev in ipairs(revs) do
    sides[#sides + 1] = rev
  end
  local texts = {}
  for _, rev in ipairs(sides) do
    local text = description_of(ctx, rev)
    if text ~= "" then
      texts[#texts + 1] = text
    end
  end
  local message = { "-m", table.concat(texts, "\n") }
  if not into then
    return join({ "squash", "-r", revs[1] }, message)
  end
  local from = {}
  for _, rev in ipairs(revs) do
    from[#from + 1] = "--from"
    from[#from + 1] = rev
  end
  return join({ "squash" }, from, { "--into", into }, message)
end

---Add new, edit, abandon, squash and rebase, acting on the change of every
---entry acted on, and on the selected changes for those that take two sides.
---@param actions table<string, jin.Action>
function M.change_actions(actions)
  actions.new = {
    desc = "create a change on top of the changes and the selected ones, a merge of several",
    changes = true,
    fn = function(ctx)
      local revs = changed(ctx)
      change_with_selected(ctx, { "new" }, revs, M.selected(ctx))
    end,
  }
  for where, flag in pairs({ after = "--insert-after", before = "--insert-before" }) do
    actions["new:" .. where] = {
      desc = ("insert a new change %s the changes"):format(where),
      changes = true,
      fn = function(ctx)
        change(ctx, { "new" }, flagged(flag, changed(ctx)))
      end,
    }
  end
  actions.edit = {
    desc = "make the change the working copy",
    changes = true,
    fn = function(ctx)
      change(ctx, { "edit" }, { changed(ctx)[1] })
    end,
  }
  actions.abandon = {
    desc = "abandon the changes, once confirmed",
    changes = true,
    fn = function(ctx)
      local revs = changed(ctx)
      local question = ("jin: abandon %d %s?"):format(#revs, #revs == 1 and "change" or "changes")
      if ctx.host.confirm(question) then
        change(ctx, { "abandon" }, revs)
      end
    end,
  }
  actions.squash = {
    desc = "squash the changes into the selected one, or into their parent",
    changes = true,
    fn = function(ctx)
      change_with_selected(ctx, squash_argv(ctx))
    end,
  }
  ---Rebase the changes of `ctx`, each after `which`, to the selected changes,
  ---each after `where`.
  local function rebase(which, where, desc)
    return {
      desc = desc,
      changes = true,
      fn = function(ctx)
        local revs = changed(ctx)
        local selected = M.selected(ctx)
        if #selected == 0 then
          error("jin: select the change to rebase onto first", 0)
        end
        change_with_selected(ctx, { "rebase" }, flagged(which, revs), flagged(where, selected))
      end,
    }
  end
  actions.rebase =
    rebase("-s", "-o", "rebase the changes, with their descendants, onto the selected ones")
  actions["rebase:revisions"] =
    rebase("-r", "-o", "rebase only the changes, not their descendants, onto the selected ones")
  actions["rebase:branch"] =
    rebase("-b", "-o", "rebase the whole branch of the changes onto the selected ones")
  actions["rebase:after"] =
    rebase("-r", "--insert-after", "move only the changes in after the selected ones")
  actions["rebase:before"] =
    rebase("-r", "--insert-before", "move only the changes in before the selected ones")
  -- The other way round from rebase:after and rebase:before: the selected
  -- changes go to the change of the line, as p puts what was yanked at the
  -- cursor.
  for where, flag in pairs({ after = "--insert-after", before = "--insert-before" }) do
    actions["put:" .. where] = {
      desc = ("move only the selected changes in %s the change"):format(where),
      changes = true,
      fn = function(ctx)
        local rev = changed(ctx)[1]
        local selected = M.selected(ctx)
        if #selected == 0 then
          error("jin: select the changes to put here first", 0)
        end
        change_with_selected(ctx, { "rebase" }, flagged("-r", selected), { flag, rev })
      end,
    }
  end
  actions.duplicate = {
    desc = "duplicate the changes",
    changes = true,
    fn = function(ctx)
      change(ctx, { "duplicate" }, changed(ctx))
    end,
  }
  actions.revert = {
    desc = "revert the changes on top of the selected change, or of the working copy",
    changes = true,
    fn = function(ctx)
      local revs = changed(ctx)
      local onto = M.selected(ctx)
      if #onto == 0 then
        onto = { "@" }
      end
      change_with_selected(ctx, { "revert" }, flagged("-r", revs), flagged("-o", onto))
    end,
  }
  actions.absorb = {
    desc = "absorb the change into the changes below it that last touched its lines",
    changes = true,
    fn = function(ctx)
      change(ctx, { "absorb", "--from", changed(ctx)[1] })
    end,
  }
  actions.parallelize = {
    desc = "make the changes siblings",
    changes = true,
    fn = function(ctx)
      change(ctx, { "parallelize" }, changed(ctx))
    end,
  }
  actions.bookmark = {
    desc = "set a bookmark, named when asked, to the change",
    changes = true,
    fn = function(ctx)
      local rev = changed(ctx)[1]
      local name = ctx.host.input("bookmark: ", "")
      if name then
        change(ctx, { "bookmark", "set", name, "-r", rev })
      end
    end,
  }
  for _, step in ipairs({ "next", "prev" }) do
    local which = step == "next" and "next" or "previous"
    actions[step] = {
      desc = ("move the working copy to the %s change"):format(which),
      changes = true,
      fn = function(ctx)
        M.refuse_at_op(ctx)
        change(ctx, { step })
      end,
    }
    actions[step .. ":edit"] = {
      desc = ("make the %s change the working copy"):format(which),
      changes = true,
      fn = function(ctx)
        M.refuse_at_op(ctx)
        change(ctx, { step, "--edit" })
      end,
    }
  end
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
