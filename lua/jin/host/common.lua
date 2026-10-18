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
  return list(vim.fn.getbufline(bufnr, 1, "$"))
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
function M.finish(bufnr, filetype, title, editable, fresh)
  if title then
    vim.fn.setbufvar(bufnr, "jin_title", title)
  end
  vim.fn.setbufvar(bufnr, "&buftype", editable and "acwrite" or "nofile")
  vim.fn.setbufvar(bufnr, "&bufhidden", editable and "hide" or "unload")
  vim.fn.setbufvar(bufnr, "&swapfile", 0)
  vim.fn.setbufvar(bufnr, "&modifiable", editable and 1 or 0)
  vim.fn.setbufvar(bufnr, "&modified", 0)
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
