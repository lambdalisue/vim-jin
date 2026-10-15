local M = {}

---@class jin.AnsiStyle
---@field fg? integer|string a 256-color index, or "#rrggbb"
---@field bg? integer|string
---@field bold? true
---@field italic? true
---@field underline? true
---@field reverse? true
---@field strikethrough? true

---@class jin.AnsiSpan
---@field line integer 1-based
---@field col integer 1-based byte column where the span starts
---@field end_col integer 1-based byte column just after the span
---@field style jin.AnsiStyle

local FLAGS = {
  { name = "bold", letter = "b", on = 1, off = 22 },
  { name = "italic", letter = "i", on = 3, off = 23 },
  { name = "underline", letter = "u", on = 4, off = 24 },
  { name = "reverse", letter = "r", on = 7, off = 27 },
  { name = "strikethrough", letter = "s", on = 9, off = 29 },
}

---@param params integer[]
---@param i integer the index of 38 or 48
---@return integer|string|nil color
---@return integer next index
local function extended_color(params, i)
  if params[i + 1] == 5 then
    return params[i + 2], i + 3
  elseif params[i + 1] == 2 then
    local r, g, b = params[i + 2] or 0, params[i + 3] or 0, params[i + 4] or 0
    return ("#%02x%02x%02x"):format(r, g, b), i + 5
  end
  return nil, i + 1
end

---@param style jin.AnsiStyle
---@param codes string the parameters of one SGR escape, such as "1;31"
local function apply(style, codes)
  local params = {}
  for n in (codes .. ";"):gmatch("(%d*);") do
    params[#params + 1] = tonumber(n) or 0
  end
  local i = 1
  while i <= #params do
    local n = params[i]
    i = i + 1
    if n == 0 then
      for k in pairs(style) do
        style[k] = nil
      end
    elseif n >= 30 and n <= 37 then
      style.fg = n - 30
    elseif n >= 90 and n <= 97 then
      style.fg = n - 90 + 8
    elseif n == 39 then
      style.fg = nil
    elseif n >= 40 and n <= 47 then
      style.bg = n - 40
    elseif n >= 100 and n <= 107 then
      style.bg = n - 100 + 8
    elseif n == 49 then
      style.bg = nil
    elseif n == 38 then
      style.fg, i = extended_color(params, i - 1)
    elseif n == 48 then
      style.bg, i = extended_color(params, i - 1)
    else
      for _, flag in ipairs(FLAGS) do
        if n == flag.on then
          style[flag.name] = true
        elseif n == flag.off then
          style[flag.name] = nil
        end
      end
    end
  end
end

---@param style jin.AnsiStyle
---@return jin.AnsiStyle
local function copy(style)
  local c = {}
  for k, v in pairs(style) do
    c[k] = v
  end
  return c
end

---@param a jin.AnsiStyle
---@param b jin.AnsiStyle
---@return boolean
local function same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then
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

---Split lines printed with ANSI escapes into the text they show and the
---styled byte ranges of that text. Escapes other than colors and text
---attributes are dropped.
---@param input string[]
---@return string[] lines
---@return jin.AnsiSpan[] spans
function M.parse(input)
  local lines, spans = {}, {}
  local style = {}
  for lnum, line in ipairs(input) do
    local out = {}
    local width = 0
    local function emit(text)
      if text == "" then
        return
      end
      if next(style) ~= nil then
        local last = spans[#spans]
        if last and last.line == lnum and last.end_col == width + 1 and same(last.style, style) then
          last.end_col = last.end_col + #text
        else
          spans[#spans + 1] = {
            line = lnum,
            col = width + 1,
            end_col = width + 1 + #text,
            style = copy(style),
          }
        end
      end
      out[#out + 1] = text
      width = width + #text
    end

    local pos = 1
    while true do
      local esc = line:find("\27", pos, true)
      if not esc then
        emit(line:sub(pos))
        break
      end
      emit(line:sub(pos, esc - 1))
      local codes, after = line:match("^%[([%d;]*)m()", esc + 1)
      if codes then
        apply(style, codes)
        pos = after
      else
        pos = line:match("^%[[%d;?]*[%a@]()", esc + 1)
          or line:match("^%][^\7\27]*\7()", esc + 1)
          or line:match("^%][^\27]*\27\\()", esc + 1)
          or esc + 1
      end
    end
    lines[lnum] = table.concat(out)
  end
  return lines, spans
end

---@param color integer|string
---@return string
local function repr(color)
  return type(color) == "string" and color:sub(2) or tostring(color)
end

---The name of the highlight group that shows `style`.
---@param style jin.AnsiStyle
---@return string
function M.group(style)
  local name = "JinAnsi"
  if style.fg then
    name = name .. "F" .. repr(style.fg)
  end
  if style.bg then
    name = name .. "B" .. repr(style.bg)
  end
  for _, flag in ipairs(FLAGS) do
    if style[flag.name] then
      name = name .. flag.letter
    end
  end
  return name
end

-- The colors xterm shows for indices 0-15.
local BASE16 = {
  "#000000",
  "#cd0000",
  "#00cd00",
  "#cdcd00",
  "#0000ee",
  "#cd00cd",
  "#00cdcd",
  "#e5e5e5",
  "#7f7f7f",
  "#ff0000",
  "#00ff00",
  "#ffff00",
  "#5c5cff",
  "#ff00ff",
  "#00ffff",
  "#ffffff",
}

local CUBE = { 0, 95, 135, 175, 215, 255 }

---The "#rrggbb" color of a 256-color index, as xterm shows it, or a true
---color as it is.
---@param color integer|string
---@return string
function M.hex(color)
  if type(color) == "string" then
    return color
  end
  if color < 16 then
    return BASE16[color + 1]
  elseif color < 232 then
    local n = color - 16
    local r, g, b = math.floor(n / 36), math.floor(n / 6) % 6, n % 6
    return ("#%02x%02x%02x"):format(CUBE[r + 1], CUBE[g + 1], CUBE[b + 1])
  end
  local level = 8 + 10 * (color - 232)
  return ("#%02x%02x%02x"):format(level, level, level)
end

return M
