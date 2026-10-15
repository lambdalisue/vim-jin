local common = require("jin.host.common")

---@class jin.VimHost: jin.Host
local M = {
  name = "vim",
  cwd = common.cwd,
  bufname = common.bufname,
  realpath = common.realpath,
  is_dir = common.is_dir,
}

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
