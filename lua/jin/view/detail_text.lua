-- The lines the detail panel tells with: a title, values after labels lined
-- up in one column, lists of files under them, and paragraphs, each wrapped
-- or cut to the width of the panel. What a view tells is written with it.

local glyph = require("jin.glyph")

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

---@alias jin.DetailChunk { text: string, group: string }

---`text` broken into lines of at most `width` cells, between words where it
---can be and within a word longer than a line.
---@param host jin.Host
---@param text string
---@param width integer
---@return string[]
function M.wrap(host, text, width)
  local lines, line, used = {}, "", 0
  local function put(piece, cells)
    if used > 0 and used + 1 + cells <= width then
      line, used = line .. " " .. piece, used + 1 + cells
    else
      if used > 0 then
        lines[#lines + 1] = line
      end
      line, used = piece, cells
    end
  end
  for word in text:gmatch("%S+") do
    local cells = host.width(word)
    if cells <= width then
      put(word, cells)
    else
      local piece, piece_cells = "", 0
      for char in word:gmatch(CHAR) do
        local char_cells = host.width(char)
        if piece_cells > 0 and piece_cells + char_cells > width then
          put(piece, piece_cells)
          piece, piece_cells = "", 0
        end
        piece, piece_cells = piece .. char, piece_cells + char_cells
      end
      if piece_cells > 0 then
        put(piece, piece_cells)
      end
    end
  end
  lines[#lines + 1] = line
  return lines
end

---`chunks` cut to `width` cells, ending with `ellipsis` where they were cut.
---@param host jin.Host
---@param chunks jin.DetailChunk[]
---@param width integer
---@param ellipsis string
---@return jin.DetailChunk[]
function M.fit(host, chunks, width, ellipsis)
  local total = 0
  for _, chunk in ipairs(chunks) do
    total = total + host.width(chunk.text)
  end
  if total <= width then
    return chunks
  end
  local room = math.max(width - host.width(ellipsis), 0)
  local out, used = {}, 0
  for _, chunk in ipairs(chunks) do
    local kept = ""
    for char in chunk.text:gmatch(CHAR) do
      local cells = host.width(char)
      if used + cells > room then
        break
      end
      kept, used = kept .. char, used + cells
    end
    if kept ~= "" then
      out[#out + 1] = { text = kept, group = chunk.group }
    end
    if used >= room or #kept < #chunk.text then
      break
    end
  end
  out[#out + 1] = { text = ellipsis, group = "JinDetailDim" }
  return out
end

---What labels a value: the glyph of that name before the word.
---@alias jin.DetailLabel { glyph?: string, word: string }

---@class jin.DetailText
---@field host jin.Host
---@field width integer
---@field glyphs jin.Glyphs
---@field labels table<string, string>
---@field label_width integer
---@field out jin.DetailChunk[][]
local Text = {}
Text.__index = Text

---A text `width` cells wide whose values are lined up after the widest of
---`labels`, every label that may be told, so that the column stays put from
---entry to entry.
---@param host jin.Host
---@param width integer
---@param glyphs jin.Glyphs
---@param labels table<string, jin.DetailLabel>
---@return jin.DetailText
function M.new(host, width, glyphs, labels)
  local self = setmetatable({
    host = host,
    width = width,
    glyphs = glyphs,
    labels = {},
    label_width = 0,
    out = {},
  }, Text)
  for name, label in pairs(labels) do
    local text = glyph.lead(label.glyph and glyphs[label.glyph] or "") .. label.word
    self.labels[name] = text
    self.label_width = math.max(self.label_width, host.width(text) + 2)
  end
  return self
end

---@param name string
---@return string
function Text:pad(name)
  local label = self.labels[name]
  return label .. (" "):rep(self.label_width - self.host.width(label))
end

---`text` wrapped in `group`, a line each.
---@param text string
---@param group string
function Text:text(text, group)
  for _, line in ipairs(M.wrap(self.host, text, self.width)) do
    self.out[#self.out + 1] = { { text = line, group = group } }
  end
end

---The first line of a description as the title, or that it has none.
---@param subject? string
function Text:title(subject)
  if not subject or subject == "" then
    self:text("(no description set)", "JinDetailDim")
  else
    self:text(subject, "JinDetailTitle")
  end
end

function Text:blank()
  self.out[#self.out + 1] = { { text = "", group = "JinDetailBody" } }
end

---Each line of `text`, wrapped, in JinDetailBody.
---@param text string
function Text:paragraphs(text)
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    self:text(line, "JinDetailBody")
  end
end

---A value after the label `name`, or under the label before it without
---one, its lines after the first indented as far. Its `pieces` share a
---line where they fit in one, and are broken apart before any is wrapped.
---@param name? string
---@param pieces string[]
---@param group? string
function Text:field(name, pieces, group)
  local cells = math.max(self.width - self.label_width, 1)
  local lines = {}
  local whole = table.concat(pieces, " ")
  for _, piece in ipairs(self.host.width(whole) <= cells and { whole } or pieces) do
    for _, line in ipairs(M.wrap(self.host, piece, cells)) do
      lines[#lines + 1] = line
    end
  end
  for i, line in ipairs(lines) do
    self.out[#self.out + 1] = {
      {
        text = i == 1 and name and self:pad(name) or (" "):rep(self.label_width),
        group = "JinDetailDim",
      },
      { text = line, group = group or "JinDetailBody" },
    }
  end
end

---A value of `chunks` after the label `name`, or under the label before it
---without one, on a line of its own cut to the width.
---@param name? string
---@param chunks jin.DetailChunk[]
function Text:line(name, chunks)
  local cells = math.max(self.width - self.label_width, 1)
  local line = {
    { text = name and self:pad(name) or (" "):rep(self.label_width), group = "JinDetailDim" },
  }
  for _, chunk in ipairs(M.fit(self.host, chunks, cells, self.glyphs.ellipsis)) do
    line[#line + 1] = chunk
  end
  self.out[#self.out + 1] = line
end

---An ID after the label `name` as jj log shows it: its shortest prefix in
---`group`, the rest dimmed.
---@param name string
---@param prefix? string
---@param rest? string
---@param group string
function Text:id(name, prefix, rest, group)
  if prefix then
    self:line(
      name,
      { { text = prefix, group = group }, { text = rest or "", group = "JinDetailDim" } }
    )
  end
end

---How many lines were added and removed, as chunks, each count padded to
---`widths` cells (its glyph included) when given, the first on the left.
---@param added integer
---@param removed integer
---@param widths? integer[]
---@return jin.DetailChunk[]
function Text:counts(added, removed, widths)
  local plus = self.glyphs.added .. added
  local minus = self.glyphs.removed .. removed
  if widths then
    plus = (" "):rep(widths[1] - self.host.width(plus)) .. plus
    minus = minus .. (" "):rep(widths[2] - self.host.width(minus))
  end
  return {
    { text = plus, group = "JinDetailAdded" },
    { text = " ", group = "JinDetailBody" },
    { text = minus, group = "JinDetailRemoved" },
  }
end

---A file changed, as `parse_files` reads it.
---@class jin.DetailFile
---@field status string M, A, D, C or R
---@field added integer
---@field removed integer
---@field path string

---A path left in conflict, and of how many sides.
---@class jin.DetailConflict
---@field sides integer
---@field path string

-- The color of a file's status, as jj's summary shows it.
local STATUS_GROUPS = { A = "JinDetailAdded", D = "JinDetailRemoved" }

---The files of a change after the label `name`: how many and the lines
---added and removed in all, then each with its status and its own counts,
---then the paths left in conflict; nothing for none of either.
---@param name string
---@param files jin.DetailFile[]
---@param conflicts? jin.DetailConflict[]
function Text:files(name, files, conflicts)
  conflicts = conflicts or {}
  if #files == 0 and #conflicts == 0 then
    return
  end
  local added, removed, widths = 0, 0, { 0, 0 }
  for _, file in ipairs(files) do
    added, removed = added + file.added, removed + file.removed
    widths[1] = math.max(widths[1], self.host.width(self.glyphs.added .. file.added))
    widths[2] = math.max(widths[2], self.host.width(self.glyphs.removed .. file.removed))
  end
  if #files > 0 then
    local summary =
      { { text = #files .. (#files == 1 and " file" or " files"), group = "JinDetailBody" } }
    summary[#summary + 1] = { text = "  ", group = "JinDetailBody" }
    for _, chunk in ipairs(self:counts(added, removed)) do
      summary[#summary + 1] = chunk
    end
    self:line(name, summary)
  end
  for _, file in ipairs(files) do
    local chunks = { { text = file.status, group = STATUS_GROUPS[file.status] or "JinDetailBody" } }
    chunks[#chunks + 1] = { text = " ", group = "JinDetailBody" }
    for _, chunk in ipairs(self:counts(file.added, file.removed, widths)) do
      chunks[#chunks + 1] = chunk
    end
    chunks[#chunks + 1] = { text = " " .. file.path, group = "JinDetailBody" }
    self:line(nil, chunks)
  end
  for i, conflict in ipairs(conflicts) do
    self:line(#files == 0 and i == 1 and name or nil, {
      { text = glyph.lead(self.glyphs.alert) .. conflict.path, group = "JinDetailAlert" },
      { text = ("  %d-sided conflict"):format(conflict.sides), group = "JinDetailDim" },
    })
  end
end

---@return jin.DetailChunk[][]
function Text:lines()
  return self.out
end

---The files of a template field listing one a line, its status, the lines
---added and removed and its path apart by tabs.
---@param text? string
---@return jin.DetailFile[]
function M.parse_files(text)
  local files = {}
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local status, added, removed, path = line:match("^(%u)\t(%d+)\t(%d+)\t(.*)$")
    if status then
      files[#files + 1] =
        { status = status, added = tonumber(added), removed = tonumber(removed), path = path }
    end
  end
  return files
end

---The paths of a template field listing one a line after its count of
---sides and a tab.
---@param text? string
---@return jin.DetailConflict[]
function M.parse_conflicts(text)
  local conflicts = {}
  for line in ((text or "") .. "\n"):gmatch("([^\n]*)\n") do
    local sides, path = line:match("^(%d+)\t(.*)$")
    if sides then
      conflicts[#conflicts + 1] = { sides = tonumber(sides), path = path }
    end
  end
  return conflicts
end

---The template expression of what `parse_files` reads, of the TreeDiff
---`diff`, such as "self.diff()".
---@param diff string
---@return string
function M.files_field(diff)
  return diff
    .. '.stat().files().map(|f| f.status_char() ++ "\\t" ++ f.lines_added() ++ "\\t"'
    .. ' ++ f.lines_removed() ++ "\\t" ++ f.display_diff_path()).join("\\n")'
end

---The template expression of what `parse_conflicts` reads, of the commit
---`commit`.
---@param commit string
---@return string
function M.conflicts_field(commit)
  return commit
    .. '.conflicted_files().map(|f| f.conflict_side_count() ++ "\\t" ++ f.path()).join("\\n")'
end

return M
