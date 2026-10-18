-- What the detail panel tells of a file: in a diff, how many lines its
-- section adds and removes, the path it was renamed or copied from, a
-- change of its mode, and in the status the diff itself; left in conflict,
-- the sides of the conflict and the changes they come from. The views
-- listing files give these as their `detail`.

local args = require("jin.args")
local change_detail = require("jin.view.change_detail")
local detail = require("jin.view.detail")
local line_detail = require("jin.view.line_detail")
local support = require("jin.view.support")
local text = require("jin.view.detail_text")

local M = {}

---What the panel tells of a file in a diff; any of it may be unknown.
---@class jin.FileDetails
---@field path string
---@field from? string the path it was renamed or copied from
---@field status? string as jj diff names it: modified, added, renamed, ...
---@field added? integer
---@field removed? integer
---@field binary? boolean
---@field hunks? string[] its diff from the first hunk header on, the Git header left out
---@field mode? string[] its kind before and after, where it changed
---@field blame? jin.LineBlame the change that wrote the line under the cursor

---What the panel tells of a path left in conflict.
---@class jin.ConflictDetails
---@field path string
---@field sides? integer
---@field labels? { kind: "side"|"base", change?: string, commit?: string, subject?: string, text: string }[]

-- The kind of a file each Git mode stands for.
local MODES = {
  ["100644"] = "file",
  ["100755"] = "executable",
  ["120000"] = "symlink",
  ["160000"] = "submodule",
  ["040000"] = "tree",
}

---A fileset of `path`, and of `from` as well where it was renamed, so that
---jj finds the rename.
---@param path string
---@param from? string
---@return string
local function fileset(path, from)
  if from and from ~= path then
    return support.fileset(path) .. " | " .. support.fileset(from)
  end
  return support.fileset(path)
end

---What a Git diff of one file tells of it.
---@param stdout string
---@param known jin.FileDetails
---@return jin.FileDetails
function M.parse_git(stdout, known)
  local details = {
    path = known.path,
    from = known.from,
    status = known.status,
    added = 0,
    removed = 0,
    hunks = {},
  }
  local old_mode, new_mode
  local in_header, in_hunk = false, false
  for line in stdout:gmatch("([^\n]*)\n?") do
    if line:match("^diff %-%-git ") then
      in_header, in_hunk = true, false
    elseif in_header then
      local mode = line:match("^old mode (%d+)")
      old_mode = mode or old_mode
      mode = line:match("^new mode (%d+)")
      new_mode = mode or new_mode
      local moved = line:match("^rename from (.*)$") or line:match("^copy from (.*)$")
      if moved then
        details.from = moved
        details.status = line:match("^rename") and "renamed" or "copied"
      end
      if line:match("^new file mode ") then
        details.status = "added"
      elseif line:match("^deleted file mode ") then
        details.status = "removed"
      elseif line:match("^Binary files ") then
        details.binary = true
      elseif line:match("^@@ ") then
        in_header, in_hunk = false, true
        details.hunks[#details.hunks + 1] = line
      end
    elseif in_hunk and line ~= "" then
      -- A context line is never empty, as it keeps its leading space.
      details.hunks[#details.hunks + 1] = line
      if line:match("^%+") then
        details.added = details.added + 1
      elseif line:match("^%-") then
        details.removed = details.removed + 1
      end
    end
  end
  if old_mode and new_mode and old_mode ~= new_mode then
    details.mode = { MODES[old_mode] or old_mode, MODES[new_mode] or new_mode }
  end
  if not details.status and (details.added > 0 or details.removed > 0 or details.mode) then
    details.status = "modified"
  end
  return details
end

---Ask jj for the Git diff of a file, `command` and `revisions` saying of
---what, at the operation `meta` shows, and call `done` with what it tells,
---or with `known` when jj fails.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param command string[]
---@param revisions string[]
---@param known jin.FileDetails
---@param done fun(details: jin.FileDetails)
function M.fetch_diff(jin, meta, command, revisions, known, done)
  local argv = {}
  for _, list in ipairs({ command, revisions, { "--git", "--", fileset(known.path, known.from) } }) do
    for _, word in ipairs(list) do
      argv[#argv + 1] = word
    end
  end
  jin.jj(change_detail.at_view(meta, argv), { cwd = meta.parsed.root }, function(result)
    done(result.code == 0 and M.parse_git(result.stdout, known) or known)
  end)
end

-- What labels each value the panel tells of a file.
local FILE_LABELS = {
  status = { glyph = "state", word = "Status" },
  from = { glyph = "path", word = "From" },
  lines = { glyph = "change", word = "Lines" },
  mode = { glyph = "files", word = "Mode" },
}

-- Those of a file with a line of it blamed: a label of each, lined up alike.
local BLAMED_LABELS = {}
for _, labels in ipairs({ FILE_LABELS, line_detail.LABELS }) do
  for name, label in pairs(labels) do
    BLAMED_LABELS[name] = label
  end
end

---The text telling of the file `details`, `width` cells wide. Where a line
---of it is blamed, the change that wrote the line comes first, as what is
---told of the line under the cursor itself, and the rest of its
---description last, so that the lines added and removed stay in sight.
---@param host jin.Host
---@param details jin.FileDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailText
local function file_text(host, details, width, glyphs)
  local blame = details.blame
  local out = text.new(host, width, glyphs, blame and BLAMED_LABELS or FILE_LABELS)
  if blame then
    line_detail.write(out, blame)
    out:blank()
  end
  out:text(details.path, "JinDetailTitle")
  if details.status then
    out:field("status", { details.status })
  end
  if details.from then
    out:field("from", { details.from })
  end
  if details.binary then
    out:field("lines", { "binary" }, "JinDetailDim")
  elseif details.added then
    out:line("lines", out:counts(details.added, details.removed))
  end
  if details.mode then
    out:field("mode", { details.mode[1] .. " -> " .. details.mode[2] })
  end
  if blame then
    line_detail.write_body(out, blame)
  end
  return out
end

---The lines telling of the file `details`, `width` cells wide: as
---`file_text` writes them.
---@param host jin.Host
---@param details jin.FileDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
function M.file_lines(host, details, width, glyphs)
  return file_text(host, details, width, glyphs):lines()
end

---The lines telling of the changed file `details`, `width` cells wide: what
---`file_lines` tells, then its diff, hunk by hunk.
---@param host jin.Host
---@param details jin.FileDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
function M.changed_lines(host, details, width, glyphs)
  local out = file_text(host, details, width, glyphs)
  if details.hunks and #details.hunks > 0 then
    out:blank()
    out:diff(details.hunks)
  end
  return out:lines()
end

---The revision options of `argv`, those of `jj diff` and `jj interdiff`
---saying what is compared.
---@param argv string[]
---@return string[]
function M.revision_words(argv)
  local valued = { ["--from"] = "from", ["-f"] = "from", ["--to"] = "to", ["-t"] = "to" }
  for spelling, name in pairs(args.REVISIONS) do
    valued[spelling] = name
  end
  local words = {}
  for _, item in ipairs((args.options(argv, valued))) do
    if item.name == "revisions" or item.name == "from" or item.name == "to" then
      for _, word in ipairs(item.words) do
        words[#words + 1] = word
      end
    end
  end
  return words
end

---The file section of the diff `meta` holds that line `lnum` is in.
---@param meta jin.ViewMeta
---@param lnum integer
---@return jin.DiffFile?
local function section(meta, lnum)
  for _, file in ipairs(((meta.data.diff or {}).files or {})) do
    if file.first <= lnum and lnum <= file.last then
      return file
    end
  end
  return nil
end

---@param file jin.DiffFile
---@return jin.FileDetails
local function known_file(file)
  return { path = file.path, from = file.from, status = file.status }
end

---What a line's diff is of: the command and the revision options to run it
---with, a key telling diffs apart, and the revisions of its sides where a
---line of it can be blamed on them.
---@alias jin.DiffOf { command: string[], revisions: string[], key: string, sides?: jin.LineSides }

---Where to look for the change that wrote line `lnum` inside the section
---`file` of a diff `diff` is of; nil on its header and where it cannot be.
---@param meta jin.ViewMeta
---@param lnum integer
---@param file jin.DiffFile
---@param diff jin.DiffOf
---@return jin.LineSide?
local function side_of(meta, lnum, file, diff)
  local line = lnum ~= file.first and meta.data.diff.lines[lnum]
  return line and diff.sides and line_detail.side(line, diff.sides) or nil
end

---`file` with `blame` told of a line of it, or `file` itself without.
---@param file jin.FileDetails
---@param blame? jin.LineBlame
---@return jin.FileDetails
local function blamed(file, blame)
  if not blame then
    return file
  end
  local copy = { blame = blame }
  for name, value in pairs(file) do
    copy[name] = value
  end
  return copy
end

---The `detail` of a view of diffs, telling of the file of the section the
---line is in, and of a line inside it with numbers the change that wrote
---the line, where `of` gives the sides of the line's diff.
---@param of fun(meta: jin.ViewMeta, lnum: integer): jin.DiffOf?
---@return jin.ViewDetail
function M.diff_detail(of)
  ---What the line tells of: its file, the key of its diff and file, and
  ---where to blame it.
  local function told(meta, lnum)
    local file = assert(section(meta, lnum), "jin: nothing to tell of the line")
    local diff = assert(of(meta, lnum), "jin: nothing to tell of the line")
    return file, "file\0" .. diff.key .. "\0" .. file.path, side_of(meta, lnum, file, diff), diff
  end
  return {
    key = function(meta, lnum)
      local file = section(meta, lnum)
      local diff = file and of(meta, lnum)
      if not (file and diff) then
        return nil
      end
      local side = side_of(meta, lnum, file, diff)
      local key = diff.key .. "\0" .. file.path
      return side and (key .. "\0" .. line_detail.key(side)) or key
    end,
    known = function(meta, lnum)
      local file, key, side = told(meta, lnum)
      local details = detail.told(meta, key) or known_file(file)
      return blamed(details, side and line_detail.known(meta, side))
    end,
    fetch = function(jin, meta, lnum, _, done)
      local file, key, side, diff = told(meta, lnum)
      local details, blame
      local pending = side and 2 or 1
      local function settle()
        pending = pending - 1
        if pending == 0 then
          done(blamed(details, blame))
        end
      end
      detail.shared(meta, key, function(found)
        M.fetch_diff(jin, meta, diff.command, diff.revisions, known_file(file), found)
      end, function(value)
        details = value
        settle()
      end)
      if side then
        line_detail.fetch(jin, meta, side, function(value)
          blame = value
          settle()
        end)
      end
    end,
    lines = M.file_lines,
  }
end

-- The words jj diff names a status by, by the letter jj status shows.
local STATUSES = { M = "modified", A = "added", D = "removed", R = "renamed", C = "copied" }

---The `detail` of lines naming a changed file, as jj status lists those of
---the working copy: `file_of` gives the file of a line, nil on one naming
---none, and its diff is that of `revisions` run with `command`.
---@param file_of fun(meta: jin.ViewMeta, lnum: integer): jin.StatusPath?
---@param command string[]
---@param revisions string[]
---@return jin.ViewDetail
function M.path_detail(file_of, command, revisions)
  local function known(meta, lnum)
    local file = assert(file_of(meta, lnum), "jin: nothing to tell of the line")
    return { path = file.path, from = file.old, status = STATUSES[file.status] }
  end
  return {
    key = function(meta, lnum)
      local file = file_of(meta, lnum)
      return file and file.path or nil
    end,
    known = known,
    fetch = function(jin, meta, lnum, _, done)
      M.fetch_diff(jin, meta, command, revisions, known(meta, lnum), done)
    end,
    lines = M.changed_lines,
  }
end

---The labels of a conflict as jj writes them in the "snapshot" style, in
---order and each once: the sides after `+++++++` and the bases after
---`-------`.
---@param stdout string
---@return { kind: "side"|"base", change?: string, commit?: string, subject?: string, text: string }[]
function M.parse_labels(stdout)
  local labels, seen = {}, {}
  for line in stdout:gmatch("([^\n]*)\n?") do
    -- Seven signs or more, as jj uses more when the file holds a run of seven.
    local run, label = line:match("^(%++) (.*)$")
    if not run then
      run, label = line:match("^(%-+) (.*)$")
    end
    local sign = run and #run >= 7 and run:sub(1, 1)
    if sign and not seen[sign .. label] then
      seen[sign .. label] = true
      local change, commit, subject = label:match('^(%l+) (%x+) "(.*)"$')
      labels[#labels + 1] = {
        kind = sign == "+" and "side" or "base",
        change = change,
        commit = commit,
        subject = subject,
        text = label,
      }
    end
  end
  return labels
end

---Ask jj for the file `path` of `rev` with its conflict written out, and
---call `done` with the sides and bases it is labelled with.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param rev string
---@param known jin.ConflictDetails
---@param done fun(details: jin.ConflictDetails)
function M.fetch_conflict(jin, meta, rev, known, done)
  local argv = change_detail.at_view(meta, {
    "--config",
    "ui.conflict-marker-style=snapshot",
    "file",
    "show",
    "-r",
    rev,
    "--",
    support.fileset(known.path),
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    if result.code ~= 0 then
      done(known)
      return
    end
    done({ path = known.path, sides = known.sides, labels = M.parse_labels(result.stdout) })
  end)
end

local CONFLICT_LABELS = {
  state = { glyph = "state", word = "State" },
  side = { glyph = "added", word = "Side" },
  base = { glyph = "removed", word = "Base" },
}

---The lines telling of the conflict `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.ConflictDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
function M.conflict_lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, CONFLICT_LABELS)
  out:text(details.path, "JinDetailTitle")
  out:line("state", {
    {
      text = details.sides and ("%d-sided conflict"):format(details.sides) or "conflict",
      group = "JinDetailAlert",
    },
  })
  for _, label in ipairs(details.labels or {}) do
    if label.change then
      out:line(label.kind, {
        { text = label.change, group = "JinDetailChange" },
        { text = " ", group = "JinDetailBody" },
        { text = label.commit, group = "JinDetailCommit" },
        { text = " " .. label.subject, group = "JinDetailBody" },
      })
    else
      out:line(label.kind, { { text = label.text, group = "JinDetailBody" } })
    end
  end
  return out:lines()
end

---How many sides `line` says its path is left in conflict with.
---@param line? string
---@return integer?
function M.sides_of(line)
  return tonumber((line or ""):match("(%d+)%-sided conflict"))
end

---The `detail` of a line naming a path left in conflict in `rev`: `path_of`
---gives its path, nil on a line naming none.
---@param path_of fun(meta: jin.ViewMeta, lnum: integer): string?
---@param rev_of fun(meta: jin.ViewMeta): string
---@return jin.ViewDetail
function M.conflict_detail(path_of, rev_of)
  local function known(meta, lnum)
    return {
      path = assert(path_of(meta, lnum), "jin: nothing to tell of the line"),
      sides = M.sides_of(meta.lines[lnum]),
    }
  end
  return {
    key = function(meta, lnum)
      local path = path_of(meta, lnum)
      return path and (rev_of(meta) .. "\0" .. path) or nil
    end,
    known = known,
    fetch = function(jin, meta, lnum, _, done)
      M.fetch_conflict(jin, meta, rev_of(meta), known(meta, lnum), done)
    end,
    lines = M.conflict_lines,
  }
end

return M
