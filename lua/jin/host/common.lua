-- The members both editors provide through the same `vim.fn` calls and Ex
-- commands.

local ansi = require("jin.ansi")

local M = {}

M.ex = vim.cmd or vim.command

function M.cwd()
  return vim.fn.getcwd()
end

function M.bufname()
  return vim.fn.expand("%:p")
end

function M.realpath(path)
  return vim.fn.resolve(path)
end

function M.is_dir(path)
  return vim.fn.isdirectory(path) == 1
end

function M.open(name, opts)
  -- `:edit` of the current buffer would unload and read it again, dropping
  -- its folds and duplicating a reload the caller asked for.
  if (opts.opener or "edit") == "edit" and (opts.mods or "") == "" and vim.fn.bufname() == name then
    return vim.fn.bufnr()
  end
  local command = (opts.opener or "edit") .. " " .. vim.fn.fnameescape(name)
  if opts.mods and opts.mods ~= "" then
    command = opts.mods .. " " .. command
  end
  M.ex(command)
  return vim.fn.bufnr()
end

function M.buffer_name(bufnr)
  if vim.fn.bufloaded(bufnr) == 1 then
    return vim.fn.bufname(bufnr)
  end
  return nil
end

function M.buffers()
  local buffers = {}
  for bufnr = 1, vim.fn.bufnr("$") do
    if vim.fn.bufloaded(bufnr) == 1 then
      buffers[#buffers + 1] = {
        bufnr = bufnr,
        name = vim.fn.bufname(bufnr),
        -- bufname() is relative to the current directory when it can be.
        path = vim.fn.fnamemodify(vim.fn.bufname(bufnr), ":p"),
        modified = vim.fn.getbufvar(bufnr, "&modified") == 1,
      }
    end
  end
  return buffers
end

local ACTION_CALL = "call luaeval('require(\"jin.host.entry\").action(_A[1], _A[2], _A[3], _A[4])', "
  .. "[bufnr(), '%s', %s])<CR>"

local MOTION_CALL = "<Cmd>call luaeval('require(\"jin.host.entry\").block(_A[1], _A[2], _A[3])', "
  .. "[bufnr(), %d, v:count1])<CR>"

-- Whether each motion goes forward, as MOTION_CALL tells it.
local FORWARD = { ["next-block"] = 1, ["prev-block"] = 0 }

---Definitions made for a buffer no window showed, by buffer number.
---@type table<integer, fun()>
local waiting = {}

---Make the definitions waiting for `bufnr`, now that a window shows it.
---@param bufnr integer
function M.define_waiting(bufnr)
  local define = waiting[bufnr]
  waiting[bufnr] = nil
  if define then
    define()
  end
end

---Map <Plug>(jin-action-{name}) on `bufnr` for each of `names`, in normal
---mode on the cursor line and in visual mode on the selected lines, and
---record the names for completion. Map <Plug>(jin-{motion}) in normal,
---visual and operator-pending mode for each motion `defaults.motions` names,
---moving the cursor as ]] and [[ do. With `defaults`, map its keys to their
---actions and its motions' keys to them, in normal mode or in the mode a
---key names, leaving alone a key the buffer has a mapping of its own for,
---such as one an ftplugin of the user made. The mappings are made in a
---window showing the buffer, so for a hidden buffer they wait until one
---does.
---@param bufnr integer
---@param names string[]
---@param defaults? { view: string, keys: { [1]: string, [2]: string, [3]?: string }[], motions?: { [1]: string, [2]: string, [3]: string }[] }
---@param list fun(value: any): any[]
---@param to_list fun(items: any[]): any
function M.define_actions(bufnr, names, defaults, list, to_list)
  local winid = list(vim.fn.win_findbuf(bufnr))[1]
  if not winid then
    -- Kept on the Lua side rather than written into the autocmd: `defaults`
    -- nests lists, which would come back from Vim script as editor lists.
    waiting[bufnr] = function()
      M.define_actions(bufnr, names, defaults, list, to_list)
    end
    M.ex(
      ("autocmd BufWinEnter <buffer=%d> ++once call luaeval("):format(bufnr)
        .. ("'require(\"jin.host.common\").define_waiting(_A)', %d)"):format(bufnr)
    )
    return
  end
  for _, name in ipairs(names) do
    local plug = "<Plug>(jin-action-" .. name .. ")"
    vim.fn.win_execute(
      winid,
      "nnoremap <buffer><silent> "
        .. plug
        .. " <Cmd>"
        .. ACTION_CALL:format(name, "line('.'), line('.')")
    )
    vim.fn.win_execute(
      winid,
      "xnoremap <buffer><silent> "
        .. plug
        .. " <Esc><Cmd>"
        .. ACTION_CALL:format(name, [[line("'<"), line("'>")]])
    )
  end
  local motions = defaults and defaults.motions or {}
  local defined = {}
  for _, motion in ipairs(motions) do
    if not defined[motion[2]] then
      defined[motion[2]] = true
      local call = MOTION_CALL:format(FORWARD[motion[2]])
      for _, mode in ipairs({ "n", "x", "o" }) do
        vim.fn.win_execute(
          winid,
          ("%snoremap <buffer><silent> <Plug>(jin-%s) %s"):format(mode, motion[2], call)
        )
      end
    end
  end
  local disabled = defaults
    and vim.fn.eval(("!!get(g:, 'jin_%s_disable_default_mappings')"):format(defaults.view)) == 1
  if defaults and not disabled then
    -- A key that starts another of them waits for the rest, as do waits
    -- to see whether dol is typed; the others act at once.
    local starts = {}
    for _, key in ipairs(defaults.keys) do
      for _, other in ipairs(defaults.keys) do
        if #other[1] > #key[1] and other[1]:sub(1, #key[1]) == key[1] then
          starts[key[1]] = true
        end
      end
    end
    local function map(key, plug)
      local mode = key[3] or "n"
      vim.fn.win_execute(
        winid,
        ("if !get(maparg('%s', '%s', 0, 1), 'buffer', 0) | execute '%smap <buffer>%s %s <Plug>(jin-%s)' | endif"):format(
          key[1],
          mode,
          mode,
          starts[key[1]] and "" or "<nowait>",
          key[1],
          plug
        )
      )
    end
    for _, key in ipairs(defaults.keys) do
      map(key, "action-" .. key[2])
    end
    for _, key in ipairs(motions) do
      map(key, key[2])
    end
  end
  vim.fn.setbufvar(bufnr, "jin_actions", to_list(names))
end

---The lines of `bufnr`.
---@param bufnr integer
---@param list fun(value: any): any[]
---@return string[]
function M.lines(bufnr, list)
  local lines = list(vim.fn.getbufline(bufnr, 1, "$"))
  -- An empty buffer reads as one empty line; only its byte count, which
  -- wordcount() takes in a window showing it, tells the two apart.
  if #lines == 1 and lines[1] == "" then
    local winid = M.window(bufnr, list)
    if winid and vim.fn.win_execute(winid, "echon wordcount().bytes") == "0" then
      return {}
    end
  end
  return lines
end

---@param bufnr integer
---@param first integer
---@param last integer
---@param lines string[]
---@param to_list fun(items: any[]): any
function M.replace_lines(bufnr, first, last, lines, to_list)
  local old, new = last - first + 1, #lines
  local head, tail = {}, {}
  for i, line in ipairs(lines) do
    if i <= old then
      head[#head + 1] = line
    else
      tail[#tail + 1] = line
    end
  end
  if #head > 0 then
    vim.fn.setbufline(bufnr, first, to_list(head))
  end
  if new < old then
    vim.fn.deletebufline(bufnr, first + new, last)
  elseif #tail > 0 then
    vim.fn.appendbufline(bufnr, last, to_list(tail))
  end
end

---Whether the user splits diffs vertically ('diffopt' has "vertical").
---@return boolean
function M.vertical()
  return vim.fn.eval("&diffopt"):find("vertical") ~= nil
end

---The mappings local to the current buffer.
---@param list fun(value: any): any[]
---@return { lhs: string, rhs: string, mode: string }[]
function M.keymaps(list)
  local maps = {}
  for _, m in ipairs(list(vim.fn.maplist())) do
    -- A mapping to a Lua function, as Neovim allows, has a callback and no
    -- right-hand side, and so leads to no action.
    if m.buffer == 1 and m.rhs then
      maps[#maps + 1] = { lhs = m.lhs, rhs = m.rhs, mode = m.mode }
    end
  end
  return maps
end

function M.input(prompt, completion)
  -- input() rejects an empty completion with E180, so none is given then.
  local answer = completion ~= "" and vim.fn.input(prompt, "", completion) or vim.fn.input(prompt)
  if answer == "" then
    return nil
  end
  return answer
end

---Make a named pipe and return its path.
---@return string
function M.fifo()
  if vim.fn.has("win32") == 1 then
    error("jin: the diff editor needs named pipes, which Windows does not have", 0)
  end
  local path = vim.fn.tempname()
  vim.fn.system("mkfifo " .. vim.fn.shellescape(path))
  if vim.fn.getftype(path) ~= "fifo" then
    error("jin: could not make a named pipe at " .. path, 0)
  end
  return path
end

---Write `content` to `path` byte for byte, as writefile() in binary mode
---takes lines.
---@param path string
---@param content string
local function write_bytes(path, content)
  vim.fn.writefile(vim.fn.split(content, "\n", 1), path, "b")
end

function M.answer(path, text)
  write_bytes(path, text)
end

---@param dir string
---@param list fun(value: any): any[]
---@return string[]
function M.files(dir, list)
  local found = {}
  local function walk(rel)
    local base = rel == "" and dir or dir .. "/" .. rel
    for _, name in ipairs(list(vim.fn.readdir(base))) do
      local path = rel == "" and name or rel .. "/" .. name
      -- getftype() rather than isdirectory(), which follows a symbolic link:
      -- a link to a directory is a file of the diff, and one to an ancestor
      -- would be walked forever.
      if vim.fn.getftype(dir .. "/" .. path) == "dir" then
        walk(path)
      else
        found[#found + 1] = path
      end
    end
  end
  if vim.fn.isdirectory(dir) == 1 then
    walk("")
  end
  table.sort(found)
  return found
end

-- Files are read and written with io rather than readfile() and
-- writefile(), which turn a NUL into a newline and back, so that a binary
-- file would come out changed.

---@param path string
---@return string?
function M.read_file(path)
  if vim.fn.filereadable(path) ~= 1 then
    return nil
  end
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

function M.write_file(path, content)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  -- Opening a symbolic link writes where it points, which may lie outside
  -- the directory jj handed over.
  if vim.fn.getftype(path) == "link" then
    vim.fn.delete(path)
  elseif vim.fn.getftype(path) == "dir" and vim.fn.delete(path, "rf") ~= 0 then
    -- A directory where a file is to be goes with what it holds.
    error("jin: could not remove " .. path, 0)
  end
  local f = assert(io.open(path, "wb"))
  assert(f:write(content))
  assert(f:close())
end

function M.make_directory(path)
  vim.fn.mkdir(path, "p")
end

-- Vim has no function that reads a link as written; resolve() follows it
-- to the end. The diff editor runs through a POSIX shell anyway.
function M.link(path)
  if vim.fn.getftype(path) ~= "link" then
    return nil
  end
  local target = vim.fn.system("readlink " .. vim.fn.shellescape(path))
  if vim.v.shell_error ~= 0 then
    error("jin: could not read the link " .. path, 0)
  end
  return (target:gsub("\n$", ""))
end

function M.make_link(path, target)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  -- A directory goes with what it holds; ln would make the link inside it.
  if vim.fn.getftype(path) == "dir" and vim.fn.delete(path, "rf") ~= 0 then
    error("jin: could not remove " .. path, 0)
  end
  vim.fn.delete(path)
  -- --: a target starting with a dash is still a target, not an option.
  vim.fn.system("ln -s -- " .. vim.fn.shellescape(target) .. " " .. vim.fn.shellescape(path))
  if vim.v.shell_error ~= 0 then
    error("jin: could not make the link " .. path, 0)
  end
end

function M.executable(path)
  return vim.fn.getfperm(path):sub(3, 3) == "x"
end

function M.set_executable(path, on)
  local perm = vim.fn.getfperm(path)
  local bits = on and { "x", "x", "x" } or { "-", "-", "-" }
  local new = perm:sub(1, 2)
    .. bits[1]
    .. perm:sub(4, 5)
    .. (perm:sub(4, 4) == "r" and bits[2] or "-")
    .. perm:sub(7, 8)
    .. (perm:sub(7, 7) == "r" and bits[3] or "-")
  vim.fn.setfperm(path, new)
end

function M.delete_file(path)
  vim.fn.delete(path)
end

-- What the statusline or the winbar of a pane draws.
local PANE_LINE = "%!jin#statusline#pane()"

---Whether the default mappings of the view the buffer `name` shows are off.
---@param name string
---@return boolean
local function mappings_disabled(name)
  local parsed = require("jin.bufname").parse(name)
  local view = parsed and parsed.params.view
  return type(view) == "string"
    and vim.fn.eval(("!!get(g:, 'jin_%s_disable_default_mappings')"):format(view)) == 1
end

---@param left jin.Pane
---@param output jin.Pane
---@param right jin.Pane
---@param to_dict fun(value: table): any
function M.open_panes(left, output, right, to_dict)
  M.ex("silent tabnew " .. vim.fn.fnameescape(output.path))
  local middle, middle_win = vim.fn.bufnr(), vim.fn.win_getid()
  M.ex("silent leftabove vsplit " .. vim.fn.fnameescape(left.path))
  local left_win = vim.fn.win_getid()
  vim.fn.win_gotoid(middle_win)
  M.ex("silent rightbelow vsplit " .. vim.fn.fnameescape(right.path))
  local right_win = vim.fn.win_getid()
  -- The statusline is the user's where they keep it in views; the winbar,
  -- where there is one, then names the pane instead.
  local option = (vim.fn.exists("+winbar") == 1 and M.setting("statusline") == "0") and "winbar"
    or "statusline"
  local disabled = mappings_disabled(output.path)
  for _, pane in ipairs({
    { left_win, left, "left" },
    { middle_win, output },
    { right_win, right, "right" },
  }) do
    local winid, spec, side = pane[1], pane[2], pane[3]
    vim.fn.setbufvar(
      vim.fn.winbufnr(winid),
      "jin_pane",
      to_dict({ title = spec.title, about = spec.about, editable = not side })
    )
    vim.fn.setwinvar(winid, "&" .. option, PANE_LINE)
    if side then
      vim.fn.win_execute(winid, "setlocal readonly nomodifiable bufhidden=wipe")
      vim.fn.win_execute(
        winid,
        ("nnoremap <buffer><silent> <Plug>(jin-diffput) <Cmd>call luaeval(%s, [%d, '%s', line('.')])<CR>"):format(
          [["require('jin.host.entry').diffput(_A[1], _A[2], _A[3])"]],
          middle,
          side
        )
      )
      if not disabled then
        vim.fn.win_execute(
          winid,
          "if !get(maparg('dp', 'n', 0, 1), 'buffer', 0) | execute 'nmap <buffer> dp <Plug>(jin-diffput)' | endif"
        )
      end
    end
  end
  for _, winid in ipairs({ left_win, middle_win, right_win }) do
    vim.fn.win_execute(winid, "silent diffthis")
  end
  vim.fn.win_gotoid(middle_win)
end

function M.close_tab(bufnr, back, list)
  local winid = list(vim.fn.win_findbuf(bufnr))[1]
  if winid then
    local tabnr = list(vim.fn.win_id2tabwin(winid))[1]
    local buffers = list(vim.fn.tabpagebuflist(tabnr))
    if vim.fn.tabpagenr("$") > 1 then
      M.ex("silent tabclose! " .. tabnr)
    else
      vim.fn.win_gotoid(winid)
      M.ex("silent only!")
    end
    for _, buf in ipairs(buffers) do
      if buf ~= back and vim.fn.bufexists(buf) == 1 and #list(vim.fn.win_findbuf(buf)) == 0 then
        M.ex("silent bwipeout! " .. buf)
      end
    end
  end
  if vim.fn.bufexists(bufnr) == 1 then
    M.ex("silent bwipeout! " .. bufnr)
  end
  local back_win = back and list(vim.fn.win_findbuf(back))[1]
  if back_win then
    vim.fn.win_gotoid(back_win)
  end
end

function M.wipe(bufnr)
  M.ex("bwipeout! " .. bufnr)
end

---@param bufnr integer
---@param previous? string
---@param list fun(value: any): any[]
function M.leave(bufnr, previous, list)
  if previous then
    local back = vim.fn.win_getid()
    for _, winid in ipairs(list(vim.fn.win_findbuf(bufnr))) do
      vim.fn.win_gotoid(winid)
      M.ex("silent edit " .. vim.fn.fnameescape(previous))
    end
    vim.fn.win_gotoid(back)
  end
  -- :bwipeout closes the windows still showing it, and a tab page with them.
  if vim.fn.bufexists(bufnr) == 1 then
    M.ex("bwipeout " .. bufnr)
  end
end

---Split the chunks a process prints into lines, handing each whole one to
---`on_line` as soon as it is complete; `flush` hands over what is left once
---the process ended, a last line without a newline.
---@param on_line fun(line: string)
---@return fun(chunk: string) feed
---@return fun() flush
function M.line_splitter(on_line)
  local pending = ""
  local function feed(chunk)
    pending = pending .. chunk
    while true do
      local line, rest = pending:match("^(.-)\n(.*)$")
      if not line then
        break
      end
      pending = rest
      on_line(line)
    end
  end
  local function flush()
    if pending ~= "" then
      on_line(pending)
      pending = ""
    end
  end
  return feed, flush
end

function M.confirm(prompt)
  return vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
end

function M.cd(scope, path)
  M.ex(scope .. " " .. vim.fn.fnameescape(path))
end

function M.yank(text)
  vim.fn.setreg(vim.fn.eval("v:register"), text)
end

---Remember the view of every window showing `bufnr`, and return a function
---that restores them. The first content since the buffer was loaded, as
---after an unload, has no views to keep, so its windows go back to where the
---cursor was when it was last left (b:jin_cursor) instead.
---@param bufnr integer
---@param list fun(value: any): any[]
---@param fresh? boolean
---@return fun()
function M.keep_views(bufnr, list, fresh)
  local winids = list(vim.fn.win_findbuf(bufnr))
  if fresh then
    return function()
      for _, winid in ipairs(winids) do
        -- Not the '" mark: Neovim forgets it when the buffer is unloaded.
        vim.fn.win_execute(winid, "if exists('b:jin_cursor') | call cursor(b:jin_cursor) | endif")
      end
    end
  end
  for _, winid in ipairs(winids) do
    vim.fn.win_execute(winid, "let w:jin_view = winsaveview()")
  end
  return function()
    for _, winid in ipairs(winids) do
      vim.fn.win_execute(winid, "call winrestview(w:jin_view) | unlet w:jin_view")
    end
  end
end

---Make `bufnr` a read-only scratch buffer of `filetype`, titled `title`; with
---`editable`, one to edit that :w hands back through BufWriteCmd, and that is
---hidden rather than unloaded when left, keeping what is being written.
---@param bufnr integer
---@param filetype string
---@param title? string
---@param editable? boolean
---@param writable? boolean one :w hands back, though not to edit
---@param modified? boolean left modified, so that leaving it asks first
function M.finish(bufnr, filetype, title, editable, fresh, writable, modified)
  if title then
    vim.fn.setbufvar(bufnr, "jin_title", title)
  end
  vim.fn.setbufvar(bufnr, "&buftype", (editable or writable) and "acwrite" or "nofile")
  vim.fn.setbufvar(bufnr, "&bufhidden", editable and "hide" or "unload")
  vim.fn.setbufvar(bufnr, "&swapfile", 0)
  vim.fn.setbufvar(bufnr, "&modifiable", editable and 1 or 0)
  vim.fn.setbufvar(bufnr, "&modified", modified and 1 or 0)
  -- Unloading takes the syntax and what plugins set up along, but keeps
  -- 'filetype': a buffer loaded again sets it anew, for FileType to run.
  if fresh or vim.fn.getbufvar(bufnr, "&filetype") ~= filetype then
    vim.fn.setbufvar(bufnr, "&filetype", filetype)
  end
end

-- Characters of the description shown before it is cut.
local ABOUT_WIDTH = 48

---`value` cut to `width` characters, with `ellipsis` where it was cut.
---@param value string
---@param width integer
---@param ellipsis string
---@return string
local function cut(value, width, ellipsis)
  local chars = {}
  for char in value:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #chars == width then
      chars[width] = ellipsis
      break
    end
    chars[#chars + 1] = char
  end
  return table.concat(chars)
end

---A 'statusline' format for a view of `parts`, drawn with `glyphs`: the
---view as a badge, then on the statusline's own background, told apart by
---the color of their text, the operation it stays at and the selection on the
---left; what the line under the cursor is about, the file the view shows,
---what the line stands for or the revision of the file, the workspace and
---where the cursor is on the right, parted by the separator.
---Only an `active` window gets colors; nil parts, before the view is read,
---give its name alone.
---@param parts? jin.StatuslineParts
---@param active boolean
---@param glyphs jin.Glyphs
---@return string
function M.statusline(parts, active, glyphs)
  local function text(value)
    return (tostring(value):gsub("%%", "%%%%"))
  end
  -- The glyph `name` and a space, or nothing for an empty one.
  local function lead(name)
    return text(require("jin.glyph").lead(glyphs[name]))
  end
  local out = {}
  -- Text in the color of JinStatusline{name} over the background of
  -- JinStatusline, as plugin/jin.vim makes JinStatuslineInk{name}.
  local function put(name, body)
    if active then
      out[#out + 1] = name and ("%#JinStatuslineInk" .. name .. "#") or "%#JinStatusline#"
    end
    out[#out + 1] = body
  end
  if not parts then
    put(nil, " %f%=%l/%L ")
    return table.concat(out)
  end
  if active then
    out[#out + 1] = "%#JinStatuslineInk" .. (parts.editable and "Edit" or "View") .. "#"
  end
  out[#out + 1] = " "
    .. lead(parts.editable and "edit" or "view")
    .. text(parts.view:upper())
    .. " "
  put(nil, "%<")
  -- Next to the view, as what the view is of; a long path is cut first.
  if parts.file then
    put(nil, " " .. lead("file") .. text(parts.file))
  end
  if parts.at_op then
    put("Alert", "  " .. lead("operation") .. "at op " .. text(parts.at_op))
  end
  if parts.selected > 0 then
    put("Selected", "  " .. lead("selected") .. parts.selected .. " selected")
  end
  -- A view is never modified; a buffer to hand back to jj may be.
  put(nil, (parts.editable and " %m" or "") .. "%=")
  -- Each part on the right after the separator, the first after a space.
  local separator = glyphs.separator ~= "" and (" " .. text(glyphs.separator) .. " ") or "   "
  local started = false
  local function gap()
    put("Dim", started and separator or " ")
    started = true
  end
  local about = parts.about
  if about then
    started = true
    put(nil, text(cut(about.what or "(no description)", ABOUT_WIDTH, glyphs.ellipsis)))
    local meta = {}
    if about.who then
      meta[#meta + 1] = lead("author") .. text(about.who)
    end
    if about.when then
      meta[#meta + 1] = lead("date") .. text(about.when)
    end
    if #meta > 0 then
      local dot = glyphs.dot ~= "" and (" " .. text(glyphs.dot) .. " ") or "  "
      put("Dim", "  " .. table.concat(meta, dot))
    end
  end
  local prefixes = parts.prefixes
  local change, commit = (parts.entry or ""):match("^(%S+) (%S+)$")
  if prefixes and change then
    -- As jj log shows them: the shortest unique prefixes in colors, the
    -- rest of each ID dimmed, and a divergent change's in red.
    gap()
    put(parts.divergent and "Alert" or "Entry", lead("change") .. text(change:sub(1, prefixes[1])))
    put("Dim", text(change:sub(prefixes[1] + 1)))
    put("Commit", " " .. lead("commit") .. text(commit:sub(1, prefixes[2])))
    put("Dim", text(commit:sub(prefixes[2] + 1)))
  elseif change then
    gap()
    put(parts.divergent and "Alert" or "Entry", lead("change") .. text(change))
    put("Dim", " " .. lead("commit") .. text(commit))
  elseif parts.entry then
    local head, rest = parts.entry:match("^(%S+)(.*)$")
    gap()
    put("Entry", (parts.kind and lead(parts.kind) or "") .. text(head))
    put("Dim", text(rest))
  end
  local here = parts.here
  if here then
    gap()
    put("Here", lead("workspace") .. text(here.root))
    for _, word in ipairs({
      here.change ~= "" and ("@" .. text(here.change)) or "",
      here.bookmarks ~= "" and (lead("bookmark") .. text(here.bookmarks)) or "",
      here.traffic ~= "" and (lead("traffic") .. text(here.traffic)) or "",
    }) do
      if word ~= "" then
        put("Dim", " " .. word)
      end
    end
    if here.state ~= "" then
      put("Alert", " " .. lead("alert") .. text(here.state))
    end
  end
  gap()
  put("Dim", lead("line") .. "%l/%L ")
  return table.concat(out)
end

---A 'statusline' format naming a pane of the diff editor: its title as a
---badge, the edit badge for the pane to edit and the view badge for a side,
---then what it is or what to do with it, drawn with `glyphs`; only an
---`active` window gets colors.
---@param pane { title: string, about: string, editable: boolean }
---@param active boolean
---@param glyphs jin.Glyphs
---@return string
function M.pane_statusline(pane, active, glyphs)
  local function text(value)
    return (tostring(value):gsub("%%", "%%%%"))
  end
  local out = {}
  if active then
    out[#out + 1] = "%#JinStatuslineInk" .. (pane.editable and "Edit" or "View") .. "#"
  end
  out[#out + 1] = " "
    .. text(require("jin.glyph").lead(glyphs[pane.editable and "edit" or "view"]))
    .. text(pane.title)
    .. " "
  if active then
    out[#out + 1] = "%#JinStatusline#"
  end
  out[#out + 1] = "%< " .. text(pane.about) .. (pane.editable and " %m" or "") .. "%="
  if active then
    out[#out + 1] = "%#JinStatuslineInkDim#"
  end
  out[#out + 1] = " %l/%L "
  return table.concat(out)
end

---Mark `bufnr` as written, as a :w that succeeded does.
---@param bufnr integer
function M.mark_saved(bufnr)
  vim.fn.setbufvar(bufnr, "&modified", 0)
end

---`annotations` with a chunk of spaces ending each line's, so that every
---one is as wide as the widest and one space parts it from the line, and
---how many cells each takes so.
---@param annotations { text: string, group?: string }[][]
---@return { text: string, group?: string }[][]
---@return integer
function M.pad_annotations(annotations)
  local widths, widest = {}, 0
  for lnum, chunks in ipairs(annotations) do
    local texts = {}
    for i, chunk in ipairs(chunks) do
      texts[i] = chunk.text
    end
    widths[lnum] = vim.fn.strdisplaywidth(table.concat(texts))
    widest = math.max(widest, widths[lnum])
  end
  local padded = {}
  for lnum, chunks in ipairs(annotations) do
    local out = {}
    for i, chunk in ipairs(chunks) do
      out[i] = chunk
    end
    out[#out + 1] = { text = (" "):rep(widest - widths[lnum] + 1) }
    padded[lnum] = out
  end
  return padded, widest + 1
end

---Make the lines of `bufnr` that wrap go on after its annotation, `width`
---cells wide (or as wide as it was last told), and the selection column before
---it, in every window showing it: 'breakindent' on, and the shift of
---'breakindentopt' that wide, its other items kept. Set locally, the
---options hold for the window while it shows the buffer; a window showing
---another buffer has that buffer's.
---Without a min of the user's, the one of the editor, 20, would cut the
---shift in a narrow window, and the lines would go on below the
---annotation; 1 keeps them beside it.
---@param bufnr integer
---@param list fun(value: any): any[]
---@param width? integer
function M.wrap_after_annotation(bufnr, list, width)
  if width then
    vim.fn.setbufvar(bufnr, "jin_annotation_width", width)
  end
  width = tonumber(vim.fn.getbufvar(bufnr, "jin_annotation_width", 0)) or 0
  if width <= 0 then
    return
  end
  width = width + (tonumber(vim.fn.getbufvar(bufnr, "jin_selected_column", 0)) or 0)
  for _, winid in ipairs(list(vim.fn.win_findbuf(bufnr))) do
    local items, min = {}, false
    for item in tostring(vim.fn.getwinvar(winid, "&breakindentopt")):gmatch("[^,]+") do
      if not item:match("^shift:") then
        items[#items + 1] = item
        min = min or item:match("^min:") ~= nil
      end
    end
    if not min then
      items[#items + 1] = "min:1"
    end
    items[#items + 1] = "shift:" .. width
    vim.fn.setwinvar(winid, "&breakindent", 1)
    vim.fn.setwinvar(winid, "&breakindentopt", table.concat(items, ","))
  end
end

---The selection column before each of the `count` lines of `bufnr`, as the view
---tells it with `column`: per line, blank as wide as the glyph and a space,
---or the glyph and a space as JinSelectedSign on `column.lnums`; none without
---`column`. Remembers its width, by which wrapped lines go on further.
---@param bufnr integer
---@param count integer
---@param column? { lnums: integer[], text: string }
---@param list fun(value: any): any[]
---@return { text: string, group?: string }[]
function M.selected_column(bufnr, count, column, list)
  local texts = {}
  local width = column and vim.fn.strdisplaywidth(column.text) + 1 or 0
  if column then
    local blank = (" "):rep(width)
    for lnum = 1, count do
      texts[lnum] = { text = blank }
    end
    for _, lnum in ipairs(column.lnums) do
      if texts[lnum] then
        texts[lnum] = { text = column.text .. " ", group = "JinSelectedSign" }
      end
    end
  end
  vim.fn.setbufvar(bufnr, "jin_selected_column", width)
  M.wrap_after_annotation(bufnr, list)
  return texts
end

---The first window showing `bufnr`, if any.
---@param bufnr integer
---@param list fun(value: any): any[]
---@return integer?
function M.window(bufnr, list)
  return list(vim.fn.win_findbuf(bufnr))[1]
end

---The window showing `bufnr` as the host's `window` tells it.
---@param bufnr integer
---@param list fun(value: any): any[]
---@return { id: integer, height: integer, width: integer, textoff: integer, row: integer, wrap: boolean, current: boolean }?
function M.window_geometry(bufnr, list)
  local winid = vim.fn.bufnr() == bufnr and vim.fn.win_getid() or M.window(bufnr, list)
  if not winid then
    return nil
  end
  local info = list(vim.fn.getwininfo(winid))[1]
  return {
    id = winid,
    height = info.height,
    width = info.width,
    textoff = info.textoff,
    row = tonumber(vim.fn.win_execute(winid, "echon winline()")),
    wrap = vim.fn.getwinvar(winid, "&wrap") ~= 0,
    current = winid == vim.fn.win_getid(),
  }
end

---Where the cursor of the window `winid` is in its buffer and on the
---screen, and how its view is scrolled.
---@param winid integer
---@return { cursor: string, view: string, row: integer, col: integer, leftcol: integer }
local function whereabouts(winid)
  local said = vim.fn.win_execute(
    winid,
    "echon join([line('.'), col('.'), winsaveview().topline,"
      .. " get(winsaveview(), 'topfill', 0), winsaveview().leftcol, winline(), wincol()])"
  )
  local n = {}
  for word in said:gmatch("%-?%d+") do
    n[#n + 1] = tonumber(word)
  end
  return {
    cursor = n[1] .. " " .. n[2],
    view = n[3] .. " " .. n[4] .. " " .. n[5],
    leftcol = n[5],
    row = n[6],
    col = n[7],
  }
end

-- The keys that scroll the view a line down and up, and move the cursor so.
local SCROLL_DOWN, SCROLL_UP = "\5", "\25"

---Bring the cursor of the window `winid` out from under the detail panel
---`room` is made for. After the cursor moved, the view scrolls to bring
---it out, as 'scrolloff' would; after only the view scrolled, as by
---CTRL-Y, the cursor moves instead, or the two would undo each other.
---'scrolloff' itself is no help: it keeps as many lines on both sides,
---counts no virtual line, and Neovim scrolls no virtual line after the
---last into view for it.
---@param winid integer
---@param room jin.DetailRoom
---@param list fun(value: any): any[]
function M.detail_keep(winid, room, list)
  local info = list(vim.fn.getwininfo(winid))[1]
  if not info then
    return
  end
  local now = whereabouts(winid)
  local last = vim.fn.getwinvar(winid, "jin_detail_kept", "")
  local scrolled = last ~= ""
    and last:match("^[^|]*") == now.cursor
    and last ~= now.cursor .. "|" .. now.view
  ---Run `keys` until `done` holds, or they change nothing more.
  local function until_done(keys, done)
    for _ = 1, info.height + (room.above or 0) + (room.below or 0) do
      if done(now) then
        return
      end
      local before = now.cursor .. "|" .. now.view
      vim.fn.win_execute(winid, "normal! " .. keys)
      now = whereabouts(winid)
      if now.cursor .. "|" .. now.view == before then
        return
      end
    end
  end
  if room.below then
    local limit = info.height - room.below
    until_done(scrolled and "k" or SCROLL_DOWN, function(at)
      return at.row <= limit
    end)
  elseif room.above then
    until_done(scrolled and "j" or SCROLL_UP, function(at)
      return at.row > room.above
    end)
  elseif room.right then
    local limit = info.width - room.right
    if now.col > limit then
      if scrolled then
        until_done("h", function(at)
          return at.col <= limit
        end)
      else
        vim.fn.win_execute(
          winid,
          ("call winrestview({'leftcol': %d})"):format(now.leftcol + now.col - limit)
        )
        now = whereabouts(winid)
      end
    end
  end
  vim.fn.setwinvar(winid, "jin_detail_kept", now.cursor .. "|" .. now.view)
end

function M.width(text)
  return vim.fn.strdisplaywidth(text)
end

---@param name string
---@param list fun(value: any): any[]
---@return table<string, any>?
function M.setting_dict(name, list)
  local var = "g:jin_" .. name
  if vim.fn.exists(var) == 0 or vim.fn.eval("type(" .. var .. ") == v:t_dict") == 0 then
    return nil
  end
  -- Its items, as Vim hands a dictionary to Lua as one it cannot iterate.
  local out = {}
  for _, item in ipairs(list(vim.fn.eval("items(" .. var .. ")"))) do
    local pair = list(item)
    out[pair[1]] = pair[2]
  end
  return out
end

function M.setting(name)
  local var = "g:jin_" .. name
  if vim.fn.exists(var) == 0 then
    return nil
  end
  return tostring(vim.fn.eval(var))
end

---The filetype the editor gives a file at `path`, or nil.
---@param bufnr integer
---@param path string
---@param list fun(value: any): any[]
---@return string?
function M.detect_filetype(bufnr, path, list)
  if vim.filetype and vim.filetype.match then
    return vim.filetype.match({ filename = path })
  end
  local winid = M.window(bufnr, list)
  if not winid or vim.fn.exists("#filetypedetect") == 0 then
    return nil
  end
  vim.fn.win_execute(winid, "doautocmd filetypedetect BufRead " .. vim.fn.fnameescape(path))
  local filetype = vim.fn.getbufvar(bufnr, "&filetype")
  return filetype ~= "" and filetype or nil
end

---Fold each of `ranges` in the windows showing `bufnr`, leaving them open
---except those starting where `closed` (from `closed_folds`) had one.
---@param bufnr integer
---@param ranges { [1]: integer, [2]: integer }[]
---@param list fun(value: any): any[]
---@param closed? table<integer, table<integer, true>>
function M.folds(bufnr, ranges, list, closed)
  for _, winid in ipairs(list(vim.fn.win_findbuf(bufnr))) do
    local commands = { "setlocal foldmethod=manual", "silent! normal! zE" }
    for _, r in ipairs(ranges) do
      commands[#commands + 1] = ("silent! %d,%dfold"):format(r[1], r[2])
    end
    commands[#commands + 1] = "silent! normal! zR"
    -- Close again what the user had closed, where a fold still starts.
    local was_closed = (closed or {})[winid] or {}
    for _, r in ipairs(ranges) do
      if was_closed[r[1]] then
        commands[#commands + 1] = ("silent! %dfoldclose"):format(r[1])
      end
    end
    for _, command in ipairs(commands) do
      vim.fn.win_execute(winid, command)
    end
  end
end

---Per window showing `bufnr`, the first lines of its closed folds, taken
---before the lines are replaced (which drops the folds).
---@param bufnr integer
---@param list fun(value: any): any[]
---@return table<integer, table<integer, true>>
function M.closed_folds(bufnr, list)
  local closed = {}
  for _, winid in ipairs(list(vim.fn.win_findbuf(bufnr))) do
    local starts = {}
    local out =
      vim.fn.win_execute(winid, "echo filter(range(1, line('$')), 'foldclosed(v:val) == v:val')")
    for n in out:gmatch("%d+") do
      starts[tonumber(n)] = true
    end
    closed[winid] = starts
  end
  return closed
end

---Move the cursor of the window showing `bufnr` to line `lnum`.
---@param bufnr integer
---@param lnum integer
---@param list fun(value: any): any[]
function M.cursor(bufnr, lnum, list)
  local winid = M.window(bufnr, list)
  if winid then
    vim.fn.win_execute(winid, ("call cursor(%d, 1) | normal! zv"):format(lnum))
  end
end

---Move the cursor of the current window, when it shows `bufnr`, to the first
---column of line `lnum`, leaving where it was in the jumplist, and in normal
---mode open the folds there when 'foldopen' asks it of "block" motions, as
---Vim's section motions do.
---@param bufnr integer
---@param lnum integer
function M.jump(bufnr, lnum)
  if vim.fn.bufnr() ~= bufnr then
    return
  end
  M.ex("mark '")
  vim.fn.cursor(lnum, 1)
  local foldopen = vim.fn.eval("&foldopen")
  if vim.fn.mode(1) == "n" and (foldopen:find("block") or foldopen:find("all")) then
    M.ex("normal! zv")
  end
end

---The line of the cursor in the current window when it shows `bufnr`, or
---else in the first window that does; nil when none does.
---@param bufnr integer
---@param list fun(value: any): any[]
---@return integer?
function M.line(bufnr, list)
  local winid = vim.fn.bufnr() == bufnr and vim.fn.win_getid() or M.window(bufnr, list)
  if not winid then
    return nil
  end
  return vim.fn.line(".", winid)
end

---What a highlight group showing `style` is made of, in both color modes.
---A 16-color index takes the terminal's own color when the editor knows it.
---@param style jin.AnsiStyle
---@param terminal_color fun(index: integer): string?
---@return { ctermfg?: integer, ctermbg?: integer, guifg?: string, guibg?: string, attrs: string[] }
function M.highlight(style, terminal_color)
  local function gui(color)
    if type(color) == "number" and color < 16 then
      return terminal_color(color) or ansi.hex(color)
    end
    return ansi.hex(color)
  end
  local attrs = {}
  for _, attr in ipairs({ "bold", "italic", "underline", "reverse", "strikethrough" }) do
    if style[attr] then
      attrs[#attrs + 1] = attr
    end
  end
  return {
    ctermfg = type(style.fg) == "number" and style.fg or nil,
    ctermbg = type(style.bg) == "number" and style.bg or nil,
    guifg = style.fg and gui(style.fg) or nil,
    guibg = style.bg and gui(style.bg) or nil,
    attrs = attrs,
  }
end

return M
