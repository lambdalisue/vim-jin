local M = {}

M.ex = vim.cmd or vim.command

local function show(value)
  if type(value) ~= "table" then
    return type(value) == "string" and ("%q"):format(value) or tostring(value)
  end
  local parts = {}
  for k, v in pairs(value) do
    parts[#parts + 1] = tostring(k) .. " = " .. show(v)
  end
  table.sort(parts)
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then
    return a == b
  end
  for k, v in pairs(a) do
    if not same(v, b[k]) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

function M.eq(expected, actual)
  if not same(expected, actual) then
    error(("expected %s, got %s"):format(show(expected), show(actual)), 2)
  end
end

function M.truthy(value, message)
  if not value then
    error(message or "expected a truthy value", 2)
  end
end

---Wait until `cond` holds, as vim-jin fills buffers asynchronously; fail
---with `message` (a string or a function returning one) when it never does.
function M.eventually(cond, message)
  local host = require("jin.host")
  if not host.wait(5000, cond) then
    error(type(message) == "function" and message() or message or "timed out", 2)
  end
end

---The lines of the current buffer.
function M.lines()
  return require("jin.host").list(vim.fn.getline(1, "$"))
end

---The highlight group names vim-jin placed in `bufnr`, in order: extmarks
---in Neovim, text properties in Vim.
function M.highlights(bufnr)
  local groups = {}
  if vim.api then
    local ns = vim.api.nvim_create_namespace("jin")
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      groups[#groups + 1] = mark[4].hl_group
    end
  else
    local count = vim.fn.len(vim.fn.getbufline(bufnr, 1, "$"))
    local props = vim.fn.prop_list(1, vim.dict({ bufnr = bufnr, end_lnum = count }))
    for prop in props() do
      groups[#groups + 1] = prop.type
    end
  end
  return groups
end

---Create an empty directory and return its path with symlinks resolved.
function M.tempdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return vim.fn.resolve(path)
end

return M
