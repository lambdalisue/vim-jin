local common = require("jin.host.common")

---@class jin.NvimHost: jin.Host
local M = {
  name = "nvim",
  cwd = common.cwd,
  bufname = common.bufname,
  realpath = common.realpath,
  is_dir = common.is_dir,
}

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

return M
