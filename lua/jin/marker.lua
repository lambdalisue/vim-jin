-- Marks where each entry of jj's templated output starts, so that every line
-- can be mapped back to the change (or operation, ...) it shows.

local M = {}

local OPEN, CLOSE = "\30", "\31"

---Wrap `template` so that each entry it prints starts with a marker holding
---the values of `fields`, each as a JSON string, separated by spaces.
---@param fields string[] template expressions, such as "change_id"
---@param template string the template expression to show
---@return string
function M.wrap(fields, template)
  local encoded = {}
  for i, field in ipairs(fields) do
    -- A value can hold any character, the separators too; JSON keeps every
    -- value whole and unambiguous.
    encoded[i] = "json(stringify(" .. field .. "))"
  end
  return '"\\x1e" ++ '
    .. table.concat(encoded, ' ++ " " ++ ')
    .. ' ++ "\\x1f" ++ ('
    .. template
    .. ")"
end

-- The characters a TOML basic string spells with an escape of their own.
local TOML_ESCAPES = {
  ["\b"] = "\\b",
  ["\t"] = "\\t",
  ["\n"] = "\\n",
  ["\f"] = "\\f",
  ["\r"] = "\\r",
  ['"'] = '\\"',
  ["\\"] = "\\\\",
}

---The --config setting of templates.`key` to `template` wrapped as `wrap`
---wraps it, for a command that prints the template within its own output.
---jj reads the value as TOML, so the template goes in as a TOML string.
---@param key string
---@param fields string[]
---@param template string
---@return string
function M.setting(key, fields, template)
  local wrapped = M.wrap(fields, template):gsub('[%c\\"]', function(c)
    return TOML_ESCAPES[c] or ("\\u%04x"):format(c:byte())
  end)
  return ('templates.%s="%s"'):format(key, wrapped)
end

---The UTF-8 encoding of the code point `cp`.
---@param cp integer
---@return string
local function utf8_char(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(
      0xE0 + math.floor(cp / 0x1000),
      0x80 + math.floor(cp / 0x40) % 0x40,
      0x80 + cp % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

local SIMPLE =
  { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

---Decode the JSON strings separated by spaces in `text`. An empty string
---stands for an absent value and leaves its place nil.
---@param text string
---@return string[]? values nil when `text` is not such a list
local function decode(text)
  local values, count, pos = {}, 0, 1
  while true do
    pos = text:find("[^ ]", pos) or #text + 1
    if pos > #text then
      return count > 0 and values or nil
    end
    if text:sub(pos, pos) ~= '"' then
      return nil
    end
    pos = pos + 1
    local parts = {}
    while true do
      local stop = text:find('["\\]', pos)
      if not stop then
        return nil
      end
      parts[#parts + 1] = text:sub(pos, stop - 1)
      if text:sub(stop, stop) == '"' then
        pos = stop + 1
        break
      end
      local esc = text:sub(stop + 1, stop + 1)
      if SIMPLE[esc] then
        parts[#parts + 1] = SIMPLE[esc]
        pos = stop + 2
      elseif esc == "u" then
        local cp = tonumber(text:sub(stop + 2, stop + 5):match("^%x%x%x%x$") or "", 16)
        if not cp then
          return nil
        end
        pos = stop + 6
        local low = cp >= 0xD800 and cp < 0xDC00 and text:match("^\\u(%x%x%x%x)", pos)
        if low and tonumber(low, 16) >= 0xDC00 and tonumber(low, 16) < 0xE000 then
          cp = 0x10000 + (cp - 0xD800) * 0x400 + (tonumber(low, 16) - 0xDC00)
          pos = pos + 6
        end
        parts[#parts + 1] = utf8_char(cp)
      else
        return nil
      end
    end
    count = count + 1
    local value = table.concat(parts)
    if value ~= "" then
      values[count] = value
    end
  end
end

---Strip the markers from `input` and map every line to the fields of the
---entry it belongs to. A line belongs to the entry whose marker last
---started; `false` stands for no entry, which is the case before the first
---marker, and from a line holding several markers, or a marker that is not
---one of ours, until the next entry.
---@param input string[]
---@return string[] lines
---@return (string[]|false)[] entries
function M.parse(input)
  local lines, entries = {}, {}
  local current = false
  for lnum, line in ipairs(input) do
    local found = {}
    local text = line:gsub(OPEN .. "([^" .. CLOSE .. "]*)" .. CLOSE, function(fields)
      -- stringify() drops the labels jj colors values by, but a marker is
      -- read the same with colors around its fields.
      found[#found + 1] = decode((fields:gsub("\27%[[%d;]*m", ""))) or false
      return ""
    end)
    if #found == 1 then
      current = found[1]
    elseif #found > 1 then
      current = false
    end
    lines[lnum] = text
    entries[lnum] = current
  end
  return lines, entries
end

return M
