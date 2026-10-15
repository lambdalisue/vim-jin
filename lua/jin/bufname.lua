local args = require("jin.args")

local M = {}

---@class jin.Bufname
---@field scheme string
---@field root string the workspace root
---@field params table<string, string|true> options that shape the content
---@field argv string[] the jj arguments

---@param text string
---@return string
local function encode(text)
  local encoded = text:gsub("[%%;#=]", function(c)
    return ("%%%02X"):format(c:byte())
  end)
  return encoded
end

---@param text string
---@return string
local function decode(text)
  local decoded = text:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return decoded
end

---Write `{scheme}://{root};{key}={value};{flag}#{args}`.
---@param name { scheme: string, root: string, params?: table<string, string|true>, argv: string[] }
---@return string
function M.format(name)
  local keys = {}
  for key in pairs(name.params or {}) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  local parts = { name.scheme, "://", encode(name.root) }
  for _, key in ipairs(keys) do
    local value = name.params[key]
    parts[#parts + 1] = ";" .. encode(key)
    if value ~= true then
      parts[#parts + 1] = "=" .. encode(value)
    end
  end
  local escaped = {}
  for i, arg in ipairs(name.argv) do
    escaped[i] = args.escape(arg)
  end
  parts[#parts + 1] = "#" .. table.concat(escaped, " ")
  return table.concat(parts)
end

---Read a name written by `format`, or return nil for any other name.
---@param text string
---@return jin.Bufname?
function M.parse(text)
  local scheme, rest = text:match("^(%w+)://(.*)$")
  local head, fragment = (rest or ""):match("^([^#]*)#(.*)$")
  if not scheme or not head then
    return nil
  end
  local root, query = head:match("^([^;]*)(.*)$")
  local params = {}
  for param in query:gmatch(";([^;]*)") do
    local key, value = param:match("^([^=]*)=(.*)$")
    if key then
      params[decode(key)] = decode(value)
    else
      params[decode(param)] = true
    end
  end
  return { scheme = scheme, root = decode(root), params = params, argv = args.split(fragment) }
end

return M
