-- What the detail panel tells of the change an entry stands for: the first
-- line of its description, its IDs, its author and when it was made, the
-- rest of its description, its bookmarks and tags, what state it is in, and
-- the files it changes and leaves in conflict. A view whose entries stand for changes gives this as its
-- `detail`.

local marker = require("jin.marker")
local support = require("jin.view.support")
local text = require("jin.view.detail_text")
local view = require("jin.view")

local M = {}

---What the panel tells of a change; any of it may be unknown.
---@class jin.ChangeDetails
---@field change? string the shortest prefix of the change ID
---@field change_rest? string what follows it in the first eight characters
---@field commit? string the shortest prefix of the commit ID
---@field commit_rest? string what follows it in the first eight characters
---@field description? string
---@field author? string
---@field email? string
---@field time? string
---@field ago? string
---@field refs? string its bookmarks and tags, apart by spaces, as jj log shows them
---@field states? string[] such as "empty" and "immutable"
---@field files? jin.DetailFile[]
---@field conflicts? jin.DetailConflict[]

-- The states of a change jj tells, in the order they are told.
local STATES = { "empty", "immutable", "divergent", "conflict", "hidden" }

---What jj is asked of the commit `c`, a template expression such as
---"self", in the order of jin.ChangeDetails.
---@param c string
---@return string[]
function M.fields(c)
  local states = {}
  for i, state in ipairs(STATES) do
    states[i] = ('if(%s.%s(), "%s")'):format(c, state, state)
  end
  return {
    c .. ".change_id().shortest(8).prefix()",
    c .. ".change_id().shortest(8).rest()",
    c .. ".commit_id().shortest(8).prefix()",
    c .. ".commit_id().shortest(8).rest()",
    c .. ".description()",
    c .. ".author().name()",
    c .. ".author().email()",
    ("format_timestamp(commit_timestamp(%s))"):format(c),
    ("commit_timestamp(%s).ago()"):format(c),
    ('separate(" ", %s.bookmarks().join(" "), %s.tags().join(" "))'):format(c, c),
    'separate(" ", ' .. table.concat(states, ", ") .. ")",
    text.files_field(c .. ".diff()"),
    text.conflicts_field(c),
  }
end

local FIELDS = M.fields("self")

---What the fields of M.fields tell, read from the markers of jj's output,
---from `first` on.
---@param f string[]
---@param first? integer
---@return jin.ChangeDetails
function M.read(f, first)
  local i = (first or 1) - 1
  local states = {}
  for state in (f[i + 11] or ""):gmatch("%S+") do
    states[#states + 1] = state
  end
  return {
    change = f[i + 1],
    change_rest = f[i + 2],
    commit = f[i + 3],
    commit_rest = f[i + 4],
    description = f[i + 5],
    author = f[i + 6],
    email = f[i + 7],
    time = f[i + 8],
    ago = f[i + 9],
    refs = f[i + 10],
    states = states,
    files = text.parse_files(f[i + 12]),
    conflicts = text.parse_conflicts(f[i + 13]),
  }
end

-- States told as an alert, as jj log shows them in red.
local ALERTS = { divergent = true, conflict = true }

---@class jin.ChangeDetailOptions
---@field entry? fun(meta: jin.ViewMeta, lnum: integer): string[]? the entry a line stands for; meta.entries[lnum] unless given
---@field revision? fun(entry: string[]): string the revision of an entry; support.revision unless given
---@field available? fun(meta: jin.ViewMeta): boolean whether a read has anything to tell

---@param opts jin.ChangeDetailOptions
---@param meta jin.ViewMeta
---@param lnum integer
---@return string[]?
local function entry_of(opts, meta, lnum)
  if opts.entry then
    return opts.entry(meta, lnum)
  end
  return meta.entries[lnum] or nil
end

---What the markers of `entry` tell of its change, shown before jj tells
---more, or when it cannot.
---@param meta jin.ViewMeta
---@param entry string[]
---@return jin.ChangeDetails
function M.known_of(meta, entry)
  local template = view.get(meta.view).template or {}
  local about, short = template.about, template.short
  ---The first eight characters of `full` past `prefix`, its shortest one.
  local function rest(full, prefix)
    if full and prefix and full:sub(1, #prefix) == prefix then
      return full:sub(#prefix + 1, 8)
    end
    return nil
  end
  local change = short and entry[short] or (entry[1] and entry[1]:sub(1, 8))
  local commit = short and entry[short + 1] or (entry[2] and entry[2]:sub(1, 8))
  return {
    description = about and entry[about],
    author = about and entry[about + 1],
    ago = about and entry[about + 2],
    change = change,
    change_rest = rest(entry[1], change),
    commit = commit,
    commit_rest = rest(entry[2], commit),
  }
end

---The arguments that load the repository as the view `meta` shows it, at
---its operation and without a snapshot, followed by `argv`. A view of the
---latest operation is asked at `@` rather than at none: without `--at-op`,
---jj merges a diverged operation log, adding an operation, which asking in
---the background must never do; at `@` it refuses instead, and the panel
---keeps what the line tells.
---@param meta jin.ViewMeta
---@param argv string[]
---@return string[]
function M.at_view(meta, argv)
  local out = { "--at-op", support.at_op(meta.parsed.argv) or "@", "--ignore-working-copy" }
  for _, word in ipairs(argv) do
    out[#out + 1] = word
  end
  return out
end

---Ask jj all it tells of the change `rev`, at the operation `meta` shows,
---and call `done` with it, or with `known` when jj fails.
---@param jin jin.Api
---@param meta jin.ViewMeta
---@param rev string
---@param known? jin.ChangeDetails
---@param done fun(details?: jin.ChangeDetails)
function M.fetch_of(jin, meta, rev, known, done)
  local argv = M.at_view(meta, {
    "log",
    "--no-graph",
    "--limit",
    "1",
    "-r",
    rev,
    "-T",
    marker.wrap(FIELDS, '""'),
  })
  jin.jj(argv, { cwd = meta.parsed.root }, function(result)
    if result.code == 0 then
      local _, entries = marker.parse({ (result.stdout:gsub("\n.*", "")) })
      local f = entries[1]
      if f then
        done(M.read(f))
        return
      end
    end
    done(known)
  end)
end

-- What labels each value the panel tells of a change.
M.LABELS = {
  change = { glyph = "change", word = "Change" },
  commit = { glyph = "commit", word = "Commit" },
  author = { glyph = "author", word = "Author" },
  date = { glyph = "date", word = "Date" },
  refs = { glyph = "bookmark", word = "Refs" },
  state = { glyph = "state", word = "State" },
  files = { glyph = "files", word = "Files" },
}

---Tell the author and the time of `details` to `out`.
---@param out jin.DetailText
---@param details { author?: string, email?: string, time?: string, ago?: string }
function M.signature(out, details)
  local author = {}
  author[#author + 1] = details.author ~= "" and details.author or nil
  author[#author + 1] = details.email and details.email ~= "" and "<" .. details.email .. ">" or nil
  if #author > 0 then
    out:field("author", author)
  end
  local date = {}
  date[#date + 1] = details.time
  date[#date + 1] = details.ago and (details.time and "(" .. details.ago .. ")" or details.ago)
  if #date > 0 then
    out:field("date", date)
  end
end

---Tell `details` to `out`, whose labels hold those of M.LABELS.
---@param out jin.DetailText
---@param details jin.ChangeDetails
function M.write(out, details)
  local description = (details.description or ""):gsub("%s+$", "")
  local subject, body = description:match("^([^\n]*)\n?(.*)$")
  out:title(subject)
  out:id("change", details.change, details.change_rest, "JinDetailChange")
  out:id("commit", details.commit, details.commit_rest, "JinDetailCommit")
  M.signature(out, details)
  -- The body comes before the lists, which can run long and be cut, so
  -- that what the author wrote is read before what jj counts.
  body = body:gsub("^\n+", "")
  local refs = details.refs ~= "" and details.refs or nil
  local states = details.states or {}
  local files, conflicts = details.files or {}, details.conflicts or {}
  if body ~= "" then
    out:blank()
    out:paragraphs(body)
    if refs or #states > 0 or #files > 0 or #conflicts > 0 then
      out:blank()
    end
  end
  if refs then
    out:field("refs", { refs }, "JinDetailRef")
  end
  if #states > 0 then
    local chunks = {}
    for i, state in ipairs(states) do
      if i > 1 then
        chunks[#chunks + 1] = { text = " ", group = "JinDetailBody" }
      end
      chunks[#chunks + 1] =
        { text = state, group = ALERTS[state] and "JinDetailAlert" or "JinDetailBody" }
    end
    out:line("state", chunks)
  end
  out:files("files", files, conflicts)
end

---The lines telling of `details`, `width` cells wide.
---@param host jin.Host
---@param details jin.ChangeDetails
---@param width integer
---@param glyphs jin.Glyphs
---@return jin.DetailChunk[][]
function M.lines(host, details, width, glyphs)
  local out = text.new(host, width, glyphs, M.LABELS)
  M.write(out, details)
  return out:lines()
end

---The `detail` of a view whose entries stand for changes, as `opts` lead
---from a line to its entry and from the entry to its revision.
---@param opts? jin.ChangeDetailOptions
---@return jin.ViewDetail
function M.detail(opts)
  opts = opts or {}
  local revision = opts.revision or support.revision
  return {
    available = opts.available,
    key = function(meta, lnum)
      local entry = entry_of(opts, meta, lnum)
      return entry and revision(entry) or nil
    end,
    known = function(meta, lnum)
      return M.known_of(
        meta,
        assert(entry_of(opts, meta, lnum), "jin: nothing to tell of the line")
      )
    end,
    fetch = function(jin, meta, lnum, rev, done)
      M.fetch_of(
        jin,
        meta,
        rev,
        M.known_of(meta, assert(entry_of(opts, meta, lnum), "jin: nothing to tell of the line")),
        done
      )
    end,
    lines = M.lines,
  }
end

return M
