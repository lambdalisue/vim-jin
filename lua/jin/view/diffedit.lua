-- The files a diff editor session leaves to edit, with which of them are
-- edited; :w on the list answers jj done, and leaving it answers abort.

local action = require("jin.action")
local diffedit = require("jin.diffedit")
local glyph = require("jin.glyph")

---The session of the list `parsed` names.
---@param host jin.Host
---@param parsed jin.Bufname
---@return jin.DiffEdit
local function session_named(host, parsed)
  local session = diffedit.get(host, tonumber(parsed.argv[1]))
  if not session then
    error("jin: this edit has been answered already", 0)
  end
  return session
end

---The session of the list `ctx` acts in.
---@param ctx jin.ActionContext
---@return jin.DiffEdit
local function session_of(ctx)
  return session_named(ctx.host, ctx.meta.parsed)
end

---Refuse `file` when a directory above it is a symbolic link in one of
---`dirs`, every directory of the session by default.
---@param ctx jin.ActionContext
---@param session jin.DiffEdit
---@param file jin.DiffEditFile
---@param dirs? string[]
local function refuse_linked_parent(ctx, session, file, dirs)
  local parent = diffedit.linked_parent(ctx.host, session, file.path, dirs)
  if parent then
    error(
      ("jin: %s lies under %s, a symbolic link on one side; take the left side of %s first"):format(
        file.path,
        parent,
        parent
      ),
      0
    )
  end
end

---The files of the lines acted on.
---@param ctx jin.ActionContext
---@return jin.DiffEditFile[]
local function files_of(ctx)
  -- The files as listed, not as read back from the lines: a name's control
  -- characters are shown otherwise, and taking the line for the name could
  -- lead anywhere.
  local listed = session_of(ctx).listed or {}
  local files = {}
  for lnum = ctx.first, ctx.last do
    local file = ctx.meta.data.files[lnum] and listed[lnum]
    if file then
      if not diffedit.inside(file.path) then
        error(("jin: %s is no path inside the diff"):format(ctx.meta.lines[lnum]), 0)
      end
      files[#files + 1] = file
    end
  end
  if #files == 0 then
    action.nothing(ctx, "jin: no file on this line")
  end
  return files
end

-- What :w in the middle pane makes of it, by the jj command that asked.
local RESULT = {
  split = "Edit this and :w to keep it as the first change",
  diffedit = "Edit this and :w to make it the change",
  squash = "Edit this and :w to squash it",
}

---The three panes of `file`: its two sides around the pane to edit, each
---named and telling what it is.
---@param ctx jin.ActionContext
---@param session jin.DiffEdit
---@param file jin.DiffEditFile
---@return jin.Pane left
---@return jin.Pane output
---@return jin.Pane right
local function panes(ctx, session, file)
  local middle = require("jin.view").name(
    ctx.jin,
    ctx.host,
    "result",
    { tostring(session.id), file.path },
    { cwd = session.root }
  )
  return {
    path = session.left .. "/" .. file.path,
    title = "BEFORE",
    about = "read-only: the change's parent",
  }, {
    path = middle,
    title = "RESULT",
    about = RESULT[session.operation] or "Edit this and :w to keep it",
  }, {
    path = session.right .. "/" .. file.path,
    title = "AFTER",
    about = "read-only: the change as it is",
  }
end

---Close the tab pages of the middle panes of `session` once the editor is
---done with the command that closes them, as a window cannot go from
---within it.
---@param host jin.Host
---@param session jin.DiffEdit
local function close_panes(host, session)
  local found = diffedit.panes(host, session)
  host.defer(0, function()
    for _, pane in ipairs(found) do
      if host.buffer_name(pane.bufnr) then
        host.close_tab(pane.bufnr)
      end
    end
  end)
end

local actions = {}

actions.open = {
  desc = "open the file in three panes: the result to edit between its two sides",
  fn = function(ctx)
    local session = session_of(ctx)
    local file = files_of(ctx)[1]
    refuse_linked_parent(ctx, session, file)
    -- Editing a symbolic link would write where it points, which may be
    -- anywhere.
    for _, dir in ipairs({ session.left, session.right, session.output }) do
      if ctx.host.link(dir .. "/" .. file.path) then
        error(
          ("jin: %s is a symbolic link on one side, taken or left as a whole: take:left takes the left one"):format(
            file.path
          ),
          0
        )
      end
    end
    ctx.host.open_panes(panes(ctx, session, file))
  end,
}

actions["take:left"] = {
  desc = "take the left side of the files, none of their change",
  changes = true,
  fn = function(ctx)
    local session = session_of(ctx)
    local files = files_of(ctx)
    -- Restoring under an edit not written would leave the edit to be
    -- written back over what was restored.
    local unsaved = diffedit.unsaved(ctx.host, session)
    for _, file in ipairs(files) do
      -- Where it is read from and where it is written; jj's right side
      -- stays as it is.
      refuse_linked_parent(ctx, session, file, { session.left, session.output })
      -- The file itself, or one under it when a directory gives way to it.
      for _, path in ipairs(unsaved) do
        if path == file.path or path:sub(1, #file.path + 1) == file.path .. "/" then
          error(
            ("jin: %s is edited but not written; write it, or undo the edit, first"):format(path),
            0
          )
        end
      end
    end
    for _, file in ipairs(files) do
      local output = session.output .. "/" .. file.path
      local left_path = session.left .. "/" .. file.path
      local link = ctx.host.link(left_path)
      local left = not link and ctx.host.read_file(left_path)
      if link then
        ctx.host.make_link(output, link)
      elseif left then
        ctx.host.write_file(output, left)
        ctx.host.set_executable(output, ctx.host.executable(left_path))
      else
        ctx.host.delete_file(output)
      end
    end
    require("jin.view").read(ctx.jin, ctx.host, ctx.bufnr, ctx.meta.name)
  end,
}

-- What the key of the open action runs, and the key it has by default.
local OPEN, OPEN_KEY = "<Plug>(jin-action-open)", "<CR>"

---The key of Normal mode that opens a file: the default one unless the
---default mappings are off, then one the current buffer maps to open, if any.
---@param host jin.Host
---@return string?
local function open_key(host)
  local disabled = host.setting("diffedit_disable_default_mappings")
  if not disabled or disabled == "" or disabled == "0" then
    return OPEN_KEY
  end
  for _, map in ipairs(host.keymaps()) do
    local normal = map.mode == "n" or map.mode == " "
    if normal and map.rhs == OPEN and not map.lhs:match("^<Plug>") then
      return map.lhs
    end
  end
  return nil
end

---The line telling how to open a file and how to answer, the parts parted
---by the dot glyph.
---@param host jin.Host
---@param glyphs jin.Glyphs
---@return string
local function hint(host, glyphs)
  local parts = {}
  local key = open_key(host)
  if key then
    parts[#parts + 1] = key .. " open"
  end
  parts[#parts + 1] = ":w apply"
  parts[#parts + 1] = ":q cancel"
  local dot = glyphs.dot ~= "" and (" " .. glyphs.dot .. " ") or "  "
  return table.concat(parts, dot)
end

-- Colors of jj's palette, as the lines are read as jj's output is.
local EDITED, DIM = "\27[33m", "\27[90m"
local RESET = "\27[0m"

---@type jin.View
return {
  title = { "diffedit" },
  filetype = "jin-diffedit",
  line_items = true,
  ---The files of the session, those edited said so, above how to answer;
  ---nothing once it has been answered.
  source = function(host, parsed)
    local session = diffedit.get(host, tonumber(parsed.argv[1]))
    if not session then
      return ""
    end
    session.listed = diffedit.files(host, session)
    local glyphs = glyph.resolve(host)
    local lines = {}
    for _, file in ipairs(session.listed) do
      local line = file.status .. " " .. file.path:gsub("%c", "?")
      if file.edited then
        line = line .. "  " .. EDITED .. glyph.lead(glyphs.edit) .. "edited" .. RESET
      end
      lines[#lines + 1] = line .. "\n"
    end
    lines[#lines + 1] = DIM .. hint(host, glyphs) .. RESET .. "\n"
    return table.concat(lines)
  end,
  decorate = function(meta)
    meta.data.files = {}
    -- The last line is the hint, whatever key it names.
    for lnum = 1, #meta.lines - 1 do
      if meta.lines[lnum]:match("^[MAD] .") then
        meta.data.files[lnum] = true
      end
    end
  end,
  ---Edited while any file is, so that leaving the list without :w asks
  ---first, as for any buffer holding an edit.
  modified = function(host, parsed)
    local session = diffedit.get(host, tonumber(parsed.argv[1]))
    for _, file in ipairs(session and session.listed or {}) do
      if file.edited then
        return true
      end
    end
    return false
  end,
  ---Hand jj what the output holds, refusing while a pane is edited but not
  ---written, as jj takes the files as they are; then close the list and
  ---the panes.
  write = function(_, host, bufnr, parsed)
    local session = session_named(host, parsed)
    -- An edit not written yet would be lost without a word.
    local unsaved = diffedit.unsaved(host, session)
    if #unsaved > 0 then
      error(
        "jin: write what is edited first (:wall), or jj takes the files as they are: "
          .. table.concat(unsaved, ", "),
        0
      )
    end
    close_panes(host, session)
    diffedit.answer(host, session, "done")
    host.mark_saved(bufnr)
    host.defer(0, function()
      if host.buffer_name(bufnr) then
        host.leave(bufnr)
      end
    end)
  end,
  ---A list closed without an answer answers abort, so that jj never waits
  ---for one nobody will give.
  forget = function(host, parsed)
    local session = diffedit.get(host, tonumber(parsed.argv[1]))
    if session then
      close_panes(host, session)
      diffedit.answer(host, session, "abort")
    end
  end,
  actions = actions,
  primary = "open",
}
