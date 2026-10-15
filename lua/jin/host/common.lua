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
  local answer = vim.fn.input(prompt, "", completion)
  if answer == "" then
    return nil
  end
  return answer
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

---Make `bufnr` a read-only scratch buffer of `filetype`, titled `title`.
---@param bufnr integer
---@param filetype string
---@param title? string
function M.finish(bufnr, filetype, title, fresh)
  if title then
    vim.fn.setbufvar(bufnr, "jin_title", title)
  end
  vim.fn.setbufvar(bufnr, "&buftype", "nofile")
  vim.fn.setbufvar(bufnr, "&bufhidden", "unload")
  vim.fn.setbufvar(bufnr, "&swapfile", 0)
  vim.fn.setbufvar(bufnr, "&modifiable", 0)
  vim.fn.setbufvar(bufnr, "&modified", 0)
  -- Unloading takes the syntax and what plugins set up along, but keeps
  -- 'filetype': a buffer loaded again sets it anew, for FileType to run.
  if fresh or vim.fn.getbufvar(bufnr, "&filetype") ~= filetype then
    vim.fn.setbufvar(bufnr, "&filetype", filetype)
  end
end

---`annotations` with a chunk of spaces ending each line's, so that every
---one is as wide as the widest and one space parts it from the line.
---@param annotations { text: string, group?: string }[][]
---@return { text: string, group?: string }[][]
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
  return padded
end

---The first window showing `bufnr`, if any.
---@param bufnr integer
---@param list fun(value: any): any[]
---@return integer?
function M.window(bufnr, list)
  return list(vim.fn.win_findbuf(bufnr))[1]
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
