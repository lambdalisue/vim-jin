-- The glyphs the statusline of a view draws with, from a preset
-- g:jin_glyph_preset chooses, each overridden by g:jin_glyphs.
-- They are read on every draw, so a change to either shows on the next.

local M = {}

---`code` as UTF-8: Lua 5.1 has no "\u{...}" escape.
---@param code integer
---@return string
function M.utf8(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  end
  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

local u = M.utf8

-- The glyphs by name, in the order the help lists them.
M.NAMES = {
  "view",
  "edit",
  "operation",
  "selected",
  "change",
  "commit",
  "author",
  "date",
  "file",
  "dot",
  "ellipsis",
  "workspace",
  "bookmark",
  "traffic",
  "alert",
  "line",
  "separator",
}

---@alias jin.Glyphs table<string, string>

---@type table<string, jin.Glyphs>
M.PRESETS = {
  nerdfont = {
    view = u(0xF441), -- nf-oct-eye
    edit = u(0xF448), -- nf-oct-pencil
    operation = u(0xF464), -- nf-oct-history
    selected = u(0xF435), -- nf-oct-pin
    change = u(0xF440), -- nf-oct-diff
    commit = u(0xF417), -- nf-oct-git_commit
    author = u(0xF007), -- nf-fa-user
    date = u(0xF017), -- nf-fa-clock_o
    file = u(0xF4A5), -- nf-oct-file
    dot = "",
    ellipsis = "…",
    workspace = u(0xF401), -- nf-oct-repo
    bookmark = u(0xF02E), -- nf-fa-bookmark
    traffic = u(0xF46A), -- nf-oct-sync
    alert = u(0xF421), -- nf-oct-alert
    line = u(0xE0A1), -- nf-pl-line_number
    separator = u(0xE0B3), -- nf-pl-right_soft_divider
  },
  unicode = {
    view = "",
    edit = "✎",
    operation = "⟲",
    selected = "●",
    change = "○",
    commit = "◉",
    author = "",
    date = "",
    file = "",
    dot = "·",
    ellipsis = "…",
    workspace = "⌂",
    bookmark = "⚑",
    traffic = "",
    alert = "⚠",
    line = "",
    separator = "│",
  },
  ascii = {
    view = "",
    edit = "",
    operation = "",
    selected = "*",
    change = "",
    commit = "",
    author = "",
    date = "",
    file = "",
    dot = "-",
    ellipsis = "...",
    workspace = "",
    bookmark = "",
    traffic = "",
    alert = "!",
    line = "",
    separator = "|",
  },
}

-- The preset used when none is chosen.
M.DEFAULT_PRESET = "nerdfont"

---The glyphs to draw with now: those of g:jin_glyph_preset, or of the
---default preset when it names none there is, with what g:jin_glyphs sets
---in place of each.
---@param host jin.Host
---@return jin.Glyphs
function M.resolve(host)
  local preset = M.PRESETS[host.setting("glyph_preset") or ""] or M.PRESETS[M.DEFAULT_PRESET]
  local glyphs = {}
  for name, value in pairs(preset) do
    glyphs[name] = value
  end
  for name, value in pairs(host.setting_dict("glyphs") or {}) do
    if preset[name] and type(value) == "string" then
      glyphs[name] = value
    end
  end
  return glyphs
end

---`value` followed by a space to set it off from what follows, or nothing
---when it is empty.
---@param value string
---@return string
function M.lead(value)
  return value ~= "" and (value .. " ") or ""
end

return M
