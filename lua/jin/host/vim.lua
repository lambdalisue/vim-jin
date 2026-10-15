local common = require("jin.host.common")

---@class jin.VimHost: jin.Host
local M = {
  name = "vim",
  cwd = common.cwd,
  bufname = common.bufname,
  realpath = common.realpath,
  is_dir = common.is_dir,
  open = common.open,
  buffers = common.buffers,
  buffer_name = common.buffer_name,
}

---@param index integer
---@return string?
local function terminal_color(index)
  local colors = M.list(vim.eval("get(g:, 'terminal_ansi_colors', [])"))
  return colors[index + 1]
end

---@param name string
---@param style jin.AnsiStyle
local function define(name, style)
  local hl = common.highlight(style, terminal_color)
  local attrs = #hl.attrs > 0 and table.concat(hl.attrs, ",") or "NONE"
  local parts = { "highlight", name, "cterm=" .. attrs, "gui=" .. attrs }
  if hl.ctermfg then
    parts[#parts + 1] = "ctermfg=" .. hl.ctermfg
  end
  if hl.ctermbg then
    parts[#parts + 1] = "ctermbg=" .. hl.ctermbg
  end
  if hl.guifg then
    parts[#parts + 1] = "guifg=" .. hl.guifg
  end
  if hl.guibg then
    parts[#parts + 1] = "guibg=" .. hl.guibg
  end
  vim.command(table.concat(parts, " "))
  if vim.fn.empty(vim.fn.prop_type_get(name)) == 1 then
    vim.fn.prop_type_add(name, vim.dict({ highlight = name }))
  end
end

function M.render(bufnr, content)
  local restore = common.keep_views(bufnr, M.list, content.fresh)
  local lines = #content.lines > 0 and content.lines or { "" }
  local old = vim.fn.len(vim.fn.getbufline(bufnr, 1, "$"))
  vim.fn.setbufvar(bufnr, "&modifiable", 1)
  vim.fn.setbufline(bufnr, 1, vim.list(lines))
  if old > #lines then
    vim.fn.deletebufline(bufnr, #lines + 1, "$")
  end
  vim.fn.prop_clear(1, #lines, vim.dict({ bufnr = bufnr }))
  for name, style in pairs(content.groups) do
    define(name, style)
  end
  for _, mark in ipairs(content.highlights) do
    vim.fn.prop_add(
      mark.line,
      mark.col,
      vim.dict({ end_col = mark.end_col, type = mark.group, bufnr = bufnr })
    )
  end
  common.finish(bufnr, content.filetype, content.title, content.fresh)
  restore()
end

function M.run(argv, opts, on_exit)
  local stdout, stderr = {}, {}
  local code, closed
  local function finish()
    -- exit_cb may come before the last output is read, so the result is
    -- complete only once the channel has closed as well.
    if code ~= nil and closed then
      on_exit({ code = code, stdout = table.concat(stdout), stderr = table.concat(stderr) })
    end
  end
  local job_opts = {
    in_io = "null",
    out_mode = "raw",
    err_mode = "raw",
    out_cb = function(_, msg)
      stdout[#stdout + 1] = msg
    end,
    err_cb = function(_, msg)
      stderr[#stderr + 1] = msg
    end,
    exit_cb = function(_, status)
      code = status
      finish()
    end,
    close_cb = function()
      closed = true
      finish()
    end,
  }
  if opts.cwd then
    -- job_start rejects a missing directory with E475 and never calls back.
    if vim.fn.isdirectory(opts.cwd) ~= 1 then
      M.defer(0, function()
        on_exit({ code = -1, stdout = "", stderr = "jin: no such directory: " .. opts.cwd })
      end)
      return
    end
    job_opts.cwd = opts.cwd
  end
  if opts.env then
    job_opts.env = vim.dict(opts.env)
  end
  -- The returned job cannot cross into Lua (it arrives as nil), so a command
  -- that fails to start is reported through exit_cb like any other failure.
  vim.fn.job_start(vim.list(argv), vim.dict(job_opts))
end

function M.wait(timeout, cond)
  local start = vim.fn.reltime()
  while not cond() do
    if vim.fn.reltimefloat(vim.fn.reltime(start)) * 1000 >= timeout then
      return false
    end
    vim.command("sleep 10m")
  end
  return true
end

function M.echo(text, hl)
  vim.command("echohl " .. (hl or "None"))
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    vim.command("echomsg " .. vim.fn.string(line))
  end
  vim.command("echohl None")
end

function M.doautocmd(event)
  if vim.fn.exists("#User#" .. event) == 1 then
    vim.command("doautocmd <nomodeline> User " .. event)
  end
end

function M.now()
  return vim.fn.reltimefloat(vim.fn.reltime()) * 1000
end

function M.defer(ms, fn)
  return vim.fn.timer_start(ms, function()
    fn()
  end)
end

function M.cancel(timer)
  vim.fn.timer_stop(timer)
end

function M.list(value)
  if type(value) == "table" then
    return value
  end
  local items = {}
  for item in value() do
    items[#items + 1] = item
  end
  return items
end

function M.to_list(items)
  return vim.list(items)
end

return M
