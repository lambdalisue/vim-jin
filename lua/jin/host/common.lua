-- The members both editors provide through the same `vim.fn` calls.

local M = {}

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

return M
