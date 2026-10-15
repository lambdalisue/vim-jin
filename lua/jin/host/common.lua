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
      buffers[#buffers + 1] = { bufnr = bufnr, name = vim.fn.bufname(bufnr) }
    end
  end
  return buffers
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
