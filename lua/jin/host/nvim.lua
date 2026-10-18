local common = require("jin.host.common")

---@class jin.NvimHost: jin.Host
local M = {
  name = "nvim",
  cwd = common.cwd,
  bufname = common.bufname,
  realpath = common.realpath,
  is_dir = common.is_dir,
  open = common.open,
  buffers = common.buffers,
  buffer_name = common.buffer_name,
  input = common.input,
  confirm = common.confirm,
  yank = common.yank,
  cd = common.cd,
  mark_saved = common.mark_saved,
  vertical = common.vertical,
  setting = common.setting,
}

function M.leave(bufnr, previous)
  common.leave(bufnr, previous, M.list)
end

function M.setting_dict(name)
  return common.setting_dict(name, M.list)
end

local ns = vim.api.nvim_create_namespace("jin")

---@param index integer
---@return string?
local function terminal_color(index)
  return vim.g["terminal_color_" .. index]
end

function M.render(bufnr, content)
  local restore = common.keep_views(bufnr, M.list, content.fresh)
  local closed = content.folds and common.closed_folds(bufnr, M.list)
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content.lines)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  for name, style in pairs(content.groups) do
    local hl = common.highlight(style, terminal_color)
    ---@type table<string, any>
    local def = { ctermfg = hl.ctermfg, ctermbg = hl.ctermbg, fg = hl.guifg, bg = hl.guibg }
    local cterm = {}
    for _, attr in ipairs(hl.attrs) do
      def[attr] = true
      cterm[attr] = true
    end
    def.cterm = cterm
    vim.api.nvim_set_hl(0, name, def)
  end
  for _, mark in ipairs(content.highlights) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, mark.line - 1, mark.col - 1, {
      end_col = mark.end_col - 1,
      hl_group = mark.group,
    })
  end
  local padded, width = common.pad_annotations(content.annotations or {})
  for lnum, chunks in ipairs(padded) do
    local virt_text = {}
    for i, chunk in ipairs(chunks) do
      virt_text[i] = { chunk.text, chunk.group }
    end
    vim.api.nvim_buf_set_extmark(bufnr, ns, lnum - 1, 0, {
      virt_text = virt_text,
      virt_text_pos = "inline",
    })
  end
  local filetype = content.filetype
    or (content.detect and common.detect_filetype(bufnr, content.detect, M.list))
    or "jin-file"
  common.finish(bufnr, filetype, content.title, content.editable, content.fresh)
  if content.folds then
    common.folds(bufnr, content.folds, M.list, closed or nil)
  end
  if #padded > 0 then
    common.wrap_after_annotation(bufnr, M.list, width)
  end
  restore()
end

function M.run(argv, opts, on_exit)
  local system_opts = { cwd = opts.cwd, env = opts.env, stdin = opts.stdin, text = true }
  local ok, err = pcall(vim.system, argv, system_opts, function(obj)
    vim.schedule(function()
      on_exit({ code = obj.code, stdout = obj.stdout or "", stderr = obj.stderr or "" })
    end)
  end)
  if not ok then
    vim.schedule(function()
      on_exit({ code = -1, stdout = "", stderr = tostring(err) })
    end)
  end
end

function M.wait(timeout, cond)
  return (vim.wait(timeout, cond, 10))
end

function M.echo(text, hl)
  vim.api.nvim_echo({ { text, hl } }, true, {})
end

function M.doautocmd(event)
  if vim.fn.exists("#User#" .. event) == 1 then
    vim.api.nvim_exec_autocmds("User", { pattern = event, modeline = false })
  end
end

function M.now()
  return vim.uv.hrtime() / 1e6
end

function M.defer(ms, fn)
  return vim.defer_fn(fn, ms)
end

function M.cancel(timer)
  if not timer:is_closing() then
    timer:stop()
    timer:close()
  end
end

function M.list(value)
  return value
end

function M.define_actions(bufnr, names, defaults)
  common.define_actions(bufnr, names, defaults, M.list, M.to_list)
end

function M.keymaps()
  return common.keymaps(M.list)
end

function M.cursor(bufnr, lnum)
  common.cursor(bufnr, lnum, M.list)
end

function M.jump(bufnr, lnum)
  common.jump(bufnr, lnum)
end

function M.line(bufnr)
  return common.line(bufnr, M.list)
end

function M.lines(bufnr)
  return common.lines(bufnr, M.list)
end

local cursor_entry = vim.api.nvim_create_namespace("jin-cursor-entry")

function M.highlight_lines(bufnr, first, last)
  vim.api.nvim_buf_clear_namespace(bufnr, cursor_entry, 0, -1)
  for lnum = first or 1, last or 0 do
    vim.api.nvim_buf_set_extmark(bufnr, cursor_entry, lnum - 1, 0, {
      line_hl_group = "JinCursorEntry",
    })
  end
end

local selected = vim.api.nvim_create_namespace("jin-selected")
local selected_column = vim.api.nvim_create_namespace("jin-selected-column")

function M.highlight_selected(bufnr, lnums, column)
  vim.api.nvim_buf_clear_namespace(bufnr, selected, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, selected_column, 0, -1)
  for _, lnum in ipairs(lnums) do
    vim.api.nvim_buf_set_extmark(bufnr, selected, lnum - 1, 0, {
      line_hl_group = "JinSelected",
      -- Above the cursor entry and the cursor change, which are put with
      -- the default, so that the line under the cursor shows as selected.
      priority = 4097,
    })
  end
  local count = vim.api.nvim_buf_line_count(bufnr)
  for lnum, chunk in pairs(common.selected_column(bufnr, count, column, M.list)) do
    vim.api.nvim_buf_set_extmark(bufnr, selected_column, lnum - 1, 0, {
      virt_text = { { chunk.text, chunk.group } },
      virt_text_pos = "inline",
      -- Inline virtual texts at one column show the one of the lower
      -- priority first: below the default of the annotations, so that they
      -- come after the column.
      priority = 0,
    })
  end
end

local cursor_change = vim.api.nvim_create_namespace("jin-cursor-change")

function M.highlight_change(bufnr, lnums)
  vim.api.nvim_buf_clear_namespace(bufnr, cursor_change, 0, -1)
  for _, lnum in ipairs(lnums) do
    vim.api.nvim_buf_set_extmark(bufnr, cursor_change, lnum - 1, 0, {
      line_hl_group = "JinCursorChange",
    })
  end
end

function M.to_list(items)
  return items
end

return M
