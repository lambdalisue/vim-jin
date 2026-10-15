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
}

local ns = vim.api.nvim_create_namespace("jin")

---@param index integer
---@return string?
local function terminal_color(index)
  return vim.g["terminal_color_" .. index]
end

function M.render(bufnr, content)
  local restore = common.keep_views(bufnr, M.list, content.fresh)
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
  common.finish(bufnr, content.filetype, content.title, content.fresh)
  restore()
end

function M.run(argv, opts, on_exit)
  local system_opts = { cwd = opts.cwd, env = opts.env, text = true }
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

function M.to_list(items)
  return items
end

return M
