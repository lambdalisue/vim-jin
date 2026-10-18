-- A panel docked at an edge of the window of a view, telling more of the
-- entry under the cursor than its line has room for. While the view is
-- shown in the current window it stays open, its size fixed, and only its
-- content changes as the cursor moves. K shows or hides it, in each window
-- on its own. What it tells comes from the view's definition, its `detail`.

local glyph = require("jin.glyph")
local view = require("jin.view")

local M = {}

---What a view tells in the detail panel.
---@class jin.ViewDetail
---@field available? fun(meta: jin.ViewMeta): boolean whether the read has anything to tell; it has unless given
---@field key fun(meta: jin.ViewMeta, lnum: integer): string? what the content of the line `lnum` is of, the same for lines telling the same; nil for nothing to tell
---@field known fun(meta: jin.ViewMeta, lnum: integer): table what the line itself tells, shown at once
---@field fetch fun(jin: jin.Api, meta: jin.ViewMeta, lnum: integer, key: string, done: fun(details: table)) find out all there is to tell, calling `done` once
---@field lines fun(host: jin.Host, details: table, width: integer, glyphs: jin.Glyphs): { text: string, group: string }[][] the content telling of `details`, `width` cells wide

---What the panel shows, and where: `row` and `col` count from 0 at the
---top-left cell of the window `window`, and the box, `width` by `height`
---cells, includes its border. It has exactly a line for each row inside.
---@class jin.DetailPanel
---@field window any
---@field row integer
---@field col integer
---@field width integer
---@field height integer
---@field border string[] its characters, clockwise from the top-left corner
---@field lines { text: string, group: string }[][] each line in chunks of a highlight group
---@field footer? { text: string, group: string }[] what to draw at the right of the bottom border, given only to a host that draws it there (`detail_footer`)

---The room made around the lines of a buffer so that each can be brought
---out from under the panel: so many virtual lines before the first or after
---the last, or virtual columns after every line of a window that does not
---wrap them.
---@class jin.DetailRoom
---@field above? integer
---@field below? integer
---@field right? integer

-- How long the cursor stays on an entry before what is not known yet is
-- asked for, so that passing over entries starts no command for each.
M.DEBOUNCE = 100

-- The width of the panel, its border included, unless set, and the least
-- size of a side: a row or column of content within the border.
local WIDTH, LEAST = 50, 3

local POSITIONS = { bottom = true, top = true, auto = true, right = true }

---How many of `total` cells g:jin_{view}_detail_{side}, or else
---g:jin_detail_{side}, gives the panel: a whole number of them from 1, or
---a fraction of `total` between 0 and 1; nil where neither gives one.
---@param host jin.Host
---@param name string the view
---@param side "height"|"width"
---@param total integer
---@return integer?
local function size(host, name, side, total)
  for _, var in ipairs({ name .. "_detail_" .. side, "detail_" .. side }) do
    local value = tonumber(host.setting(var) or "")
    if value and value > 0 and value < 1 then
      return math.floor(total * value)
    elseif value and value >= 1 and value == math.floor(value) then
      return value
    end
  end
  return nil
end

---@class jin.DetailState
---@field shown? string what was drawn last, to draw again only on a change
---@field room? string the room made, as `room_key` tells it
---@field wanted? { meta: jin.ViewMeta, key: string } what the cursor waits on being told
---@field timer? any running out while the cursor stays, to ask then
---@field hint? string|false the key hiding the panel, false for none; looked up again as the window is entered

---Per host, per buffer.
---@type table<jin.Host, table<integer, jin.DetailState>>
local states = setmetatable({}, { __mode = "k" })

---Per host, per window: whether K left the panel shown there.
---@type table<jin.Host, table<any, boolean>>
local windows = setmetatable({}, { __mode = "k" })

---Per read, per key: what was told, or the callbacks waiting for it.
---@type table<jin.ViewMeta, table<string, { details?: table, waiting?: fun()[] }>>
local cache = setmetatable({}, { __mode = "k" })

---@param host jin.Host
---@param bufnr integer
---@return jin.DetailState
local function state(host, bufnr)
  states[host] = states[host] or {}
  local s = states[host][bufnr]
  if not s then
    s = {}
    states[host][bufnr] = s
  end
  return s
end

---Whether the panel shows in the window `winid`: as K left it there, or as
---g:jin_detail says for a window K was never pressed in.
---@param host jin.Host
---@param winid any
---@return boolean
local function shown_in(host, winid)
  local set = (windows[host] or {})[winid]
  if set ~= nil then
    return set
  end
  local value = host.setting("detail")
  return not (value == "0" or value == "false" or value == "v:false")
end

---Where the panel lies in `win`, and the room it needs; nil where the
---window has no room for a row of it.
---@param host jin.Host
---@param name string the view
---@param win { height: integer, width: integer, textoff: integer, row: integer, wrap: boolean }
---@return { row: integer, col: integer, width: integer, height: integer }?
---@return jin.DetailRoom?
local function place(host, name, win)
  local position = host.setting("detail_position")
  position = POSITIONS[position or ""] and position or "bottom"
  if position == "right" then
    -- Half the text at most, so that what is under it can be scrolled out.
    local text = win.width - win.textoff
    local width =
      math.min(math.max(size(host, name, "width", text) or WIDTH, LEAST), math.floor(text / 2))
    if width < LEAST or win.height < LEAST then
      return nil
    end
    local frame = { row = 0, col = win.width - width, width = width, height = win.height }
    return frame, (not win.wrap) and { right = width } or nil
  end
  -- Half the window at most, so that the cursor always has room beside it,
  -- and in "auto", the half it is not in. A third by default leaves the
  -- view the most of the window while the content of an entry still fits.
  local height = math.min(
    math.max(size(host, name, "height", win.height) or math.floor(win.height / 3), LEAST),
    math.floor(win.height / 2)
  )
  if height < LEAST or win.width < LEAST then
    return nil
  end
  local top = position == "top" or (position == "auto" and win.row * 2 > win.height)
  local frame =
    { row = top and 0 or win.height - height, col = 0, width = win.width, height = height }
  if position == "top" then
    return frame, { above = height }
  elseif position == "bottom" then
    return frame, { below = height }
  end
  return frame, nil
end

---@param room? jin.DetailRoom
---@return string?
local function room_key(room)
  if not room then
    return nil
  end
  return ("%s:%s:%s"):format(room.above or "", room.below or "", room.right or "")
end

---@param panel jin.DetailPanel
---@return string
local function panel_key(panel)
  local parts = { tostring(panel.window), panel.row, panel.col, panel.width, panel.height }
  for _, char in ipairs(panel.border) do
    parts[#parts + 1] = char
  end
  for _, line in ipairs(panel.lines) do
    for _, chunk in ipairs(line) do
      parts[#parts + 1] = chunk.group .. ":" .. chunk.text
    end
    parts[#parts + 1] = "\n"
  end
  for _, chunk in ipairs(panel.footer or {}) do
    parts[#parts + 1] = chunk.group .. ":" .. chunk.text
  end
  return table.concat(parts, "\0")
end

-- What the key of the detail action runs, and the key it has by default.
local PLUG, KEY = "<Plug>(jin-action-detail)", "K"

---The key of Normal mode in the current buffer that leads to the detail
---action, K before any other; nil for none.
---@param host jin.Host
---@return string?
local function hiding_key(host)
  local found
  for _, map in ipairs(host.keymaps()) do
    local normal = map.mode == "n" or map.mode == " "
    if normal and map.rhs == PLUG and not map.lhs:match("^<Plug>") then
      if map.lhs == KEY then
        return KEY
      end
      found = found or map.lhs
    end
  end
  return found
end

---@param host jin.Host
---@param s jin.DetailState
local function stop_waiting(host, s)
  if s.timer then
    host.cancel(s.timer)
    s.timer = nil
  end
  s.wanted = nil
end

---Close the panel of `bufnr` and take its room away, as when its window or
---the buffer is left.
---@param host jin.Host
---@param bufnr integer
function M.close(host, bufnr)
  local s = (states[host] or {})[bufnr]
  if not s then
    return
  end
  stop_waiting(host, s)
  if s.shown then
    s.shown = nil
    host.close_detail(bufnr)
  end
  if s.room then
    s.room = nil
    host.detail_padding(bufnr, nil)
  end
end

local update

---Ask what `def` tells of `key` once the cursor stayed on it for a moment,
---and show it then if the cursor is still on it.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
---@param s jin.DetailState
---@param meta jin.ViewMeta
---@param def jin.ViewDetail
---@param lnum integer
---@param key string
local function ask(jin, host, bufnr, s, meta, def, lnum, key)
  if s.wanted and s.wanted.meta == meta and s.wanted.key == key then
    return
  end
  stop_waiting(host, s)
  local wanted = { meta = meta, key = key }
  s.wanted = wanted
  s.timer = host.defer(M.DEBOUNCE, function()
    s.timer = nil
    if s.wanted ~= wanted then
      return
    end
    local function told()
      if s.wanted == wanted then
        s.wanted = nil
        update(jin, host, bufnr)
      end
    end
    cache[meta] = cache[meta] or {}
    local known = cache[meta][key]
    if known then
      -- Asked already, as the cursor came back before the answer.
      table.insert(known.waiting, told)
      return
    end
    known = { waiting = { told } }
    cache[meta][key] = known
    def.fetch(jin, meta, lnum, key, function(details)
      known.details = details
      local waiting = known.waiting
      known.waiting = nil
      for _, fn in ipairs(waiting or {}) do
        fn()
      end
    end)
  end)
end

---Show the panel of `bufnr` as the cursor, the window and the setting have
---it now, or close it where it shows nothing.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
---@param moved? boolean only the cursor moved, so the key hiding the panel is as it was
function update(jin, host, bufnr, moved)
  local meta = view.meta(host, bufnr)
  local def = meta and view.get(meta.view).detail
  local win = def and host.window(bufnr)
  if
    not (meta and def and win and win.current)
    or (def.available and not def.available(meta))
    or not shown_in(host, win.id)
  then
    M.close(host, bufnr)
    return
  end
  local frame, room = place(host, meta.view, win)
  if not frame then
    M.close(host, bufnr)
    return
  end
  local s = state(host, bufnr)
  local lnum = host.line(bufnr)
  local key = lnum and lnum <= #meta.lines and def.key(meta, lnum) or nil
  local details
  if key and lnum then
    local known = (cache[meta] or {})[key]
    if known and known.details then
      details = known.details
      stop_waiting(host, s)
    else
      details = def.known(meta, lnum)
      ask(jin, host, bufnr, s, meta, def, lnum, key)
    end
  else
    stop_waiting(host, s)
  end
  -- None found is looked for again, as the keys may be mapped later on.
  if not moved or not s.hint then
    s.hint = hiding_key(host) or false
  end
  local glyphs = glyph.resolve(host)
  local rows = frame.height - 2
  ---@type string?
  local hint
  if s.hint then
    -- The first that leaves room for a corner and a space on either side.
    for _, form in ipairs({ "Press %s to hide", "[%s] hide" }) do
      local text = form:format(s.hint)
      if host.width(text) <= frame.width - 4 then
        hint = text
        break
      end
    end
  end
  -- Where the editor cannot draw it in the border, the last row is its own.
  local hint_row = not host.detail_footer and rows >= 2 and hint or nil
  if hint_row then
    rows = rows - 1
  end
  local lines = details and def.lines(host, details, frame.width - 2, glyphs) or {}
  if #lines > rows then
    for i = #lines, rows, -1 do
      lines[i] = nil
    end
    lines[rows] = { { text = glyphs.ellipsis, group = "JinDetailDim" } }
  end
  while #lines < rows do
    lines[#lines + 1] = { { text = "", group = "JinDetailBody" } }
  end
  if hint_row then
    lines[#lines + 1] = {
      { text = (" "):rep(frame.width - 2 - host.width(hint_row)), group = "JinDetailBody" },
      { text = hint_row, group = "JinDetailDim" },
    }
  end
  local panel = {
    window = win.id,
    row = frame.row,
    col = frame.col,
    width = frame.width,
    height = frame.height,
    border = glyph.border(glyphs),
    lines = lines,
    footer = hint and host.detail_footer and { { text = hint, group = "JinDetailDim" } } or nil,
  }
  local drawn = panel_key(panel)
  if s.shown ~= drawn then
    host.open_detail(bufnr, panel)
    s.shown = drawn
  end
  local made = room_key(room)
  if s.room ~= made then
    host.detail_padding(bufnr, room)
    s.room = made
  end
  if room then
    host.detail_keep(win.id, room)
  end
end

---Follow the cursor of `bufnr` (CursorMoved).
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
function M.cursor_moved(jin, host, bufnr)
  update(jin, host, bufnr, true)
end

---Show the panel again in the window of `bufnr` entered (BufEnter, WinEnter).
M.entered = update

---Show the panel of `bufnr` afresh, as the view was read again: what it
---told of may be gone, and the room made went with the lines.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
function M.reread(jin, host, bufnr)
  local s = (states[host] or {})[bufnr]
  if s then
    stop_waiting(host, s)
    -- Kept set, not cleared, so that a read leaving nothing to tell still
    -- closes what is shown; no drawing has an empty key, so the panel and
    -- its room are made again otherwise.
    s.shown = s.shown and ""
    s.room = s.room and ""
  end
  update(jin, host, bufnr)
end

---Put every panel shown back in place, as after a window scrolled or was
---resized (WinScrolled).
---@param jin jin.Api
---@param host jin.Host
function M.scrolled(jin, host)
  for bufnr, s in pairs(states[host] or {}) do
    if s.shown then
      update(jin, host, bufnr)
    end
  end
end

---Show the panel in the window of `bufnr` if it is hidden there, or hide
---it; hidden, it shows there again only by this. False when the view has
---nothing to tell.
---@param jin jin.Api
---@param host jin.Host
---@param bufnr integer
---@return boolean
function M.toggle(jin, host, bufnr)
  local meta = view.meta(host, bufnr)
  local def = meta and view.get(meta.view).detail
  local win = def and host.window(bufnr)
  if not (meta and def and win) or (def.available and not def.available(meta)) then
    return false
  end
  windows[host] = windows[host] or {}
  windows[host][win.id] = not shown_in(host, win.id)
  update(jin, host, bufnr)
  return true
end

---Forget whether the panel shows in the window `winid`, which was closed
---(WinClosed): a window that takes its ID later starts afresh.
---@param host jin.Host
---@param winid any
function M.window_closed(host, winid)
  if windows[host] then
    windows[host][winid] = nil
  end
end

---Close the panel of `bufnr` and forget it, as when the buffer is unloaded.
---@param host jin.Host
---@param bufnr integer
function M.forget(host, bufnr)
  M.close(host, bufnr)
  if states[host] then
    states[host][bufnr] = nil
  end
end

return M
