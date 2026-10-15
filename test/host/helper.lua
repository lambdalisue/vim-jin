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

---Create an empty directory and return its path with symlinks resolved.
function M.tempdir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return vim.fn.resolve(path)
end

return M
