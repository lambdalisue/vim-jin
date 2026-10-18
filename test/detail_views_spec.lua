local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local detail = require("jin.view.detail")

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  -- The ascii preset labels with the words alone; a panel tall enough for
  -- all a line tells.
  host.settings.glyph_preset = "ascii"
  host.settings.detail_height = "24"
  host.windows = setmetatable({}, {
    __index = function()
      return { height = 60 }
    end,
  })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0"):gsub("\n", "\\n"):gsub("\t", "\\t") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

---Read the view `name` from `stdout`, after the template lookup when
---`template` is set.
local function read(host, jin, name, stdout, template)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  if template then
    host.finish(ok("tpl\n"))
  end
  host.finish(ok(stdout))
  return bufnr
end

---Move the cursor to `lnum` and let it stay there: the jj run the panel
---starts, or nil when it starts none.
local function stay(jin, host, bufnr, lnum)
  host.cursors[bufnr] = lnum
  detail.cursor_moved(jin, host, bufnr)
  local before = #host.runs
  host.fire_timers()
  return #host.runs > before and host.runs[#host.runs] or nil
end

---The words of a run after jj's own leading options.
local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

---Whether `argv` holds `seq` one after another.
local function has(argv, seq)
  for i = 1, #argv - #seq + 1 do
    local found = true
    for j, word in ipairs(seq) do
      found = found and argv[i + j - 1] == word
    end
    if found then
      return true
    end
  end
  return false
end

---The texts of the lines of the panel of `bufnr`, trailing blank rows left out.
local function texts(host, bufnr)
  local out = {}
  for i, line in ipairs(host.details[bufnr].lines) do
    local parts = {}
    for j, chunk in ipairs(line) do
      parts[j] = chunk.text
    end
    out[i] = table.concat(parts)
  end
  while out[#out] == "" do
    out[#out] = nil
  end
  return out
end

---The group of the chunk holding `text` in the panel of `bufnr`.
local function group_of(host, bufnr, text)
  for _, line in ipairs(host.details[bufnr].lines) do
    for _, chunk in ipairs(line) do
      if chunk.text == text then
        return chunk.group
      end
    end
  end
  return nil
end

---What jj tells of a change, as change_detail asks for it.
local function change(fields)
  fields = fields or {}
  return m(
    fields.change or "kk",
    fields.change_rest or "mmmmmm",
    fields.commit or "c1",
    fields.commit_rest or "234567",
    fields.description or "add the answer\n",
    "Alice",
    "alice@example.com",
    "2026-01-01 09:00:00",
    "2 days ago",
    fields.refs or "",
    fields.states or "",
    fields.files or "",
    fields.conflicts or ""
  ) .. "\n"
end

describe("the detail panel of a view of changes", function()
  local LOG = "jin:///repo;view=log#"

  it("tells of the change of a log line its refs, its state and the files it changes", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, "@  " .. m("kkk", "c1", "-") .. "x\n│  y\n", true)
    local run = assert(stay(jin, host, bufnr, 2))
    assert.is_true(has(words(run), { "--ignore-working-copy", "log", "--no-graph" }))
    assert.is_true(has(words(run), { "-r", "kkk" }))
    host.finish(ok(change({
      refs = "main topic@origin",
      states = "empty conflict",
      files = "M\t10\t2\ta.lua\nA\t2\t2\tb.lua",
      conflicts = "2\tc.lua",
    })))
    assert.same({
      "add the answer",
      "Change  kkmmmmmm",
      "Commit  c1234567",
      "Author  Alice <alice@example.com>",
      "Date    2026-01-01 09:00:00 (2 days ago)",
      "Refs    main topic@origin",
      "State   empty conflict",
      "Files   2 files  +12 -4",
      "        M +10 -2 a.lua",
      "        A  +2 -2 b.lua",
      "        ! c.lua  2-sided conflict",
    }, texts(host, bufnr))
    assert.equal("JinDetailRef", group_of(host, bufnr, "main topic@origin"))
    assert.equal("JinDetailAlert", group_of(host, bufnr, "conflict"))
    assert.equal("JinDetailBody", group_of(host, bufnr, "empty"))
    assert.equal("JinDetailAdded", group_of(host, bufnr, "+10"))
    assert.equal("JinDetailRemoved", group_of(host, bufnr, "-4"))
  end)

  it("tells the body of the description after the date, before refs, state and files", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("kkk", "c1", "-") .. "x\n", true)
    assert(stay(jin, host, bufnr, 1))
    host.finish(ok(change({
      description = "add the answer\n\nIt is 42.\n\nSee the guide.\n",
      refs = "main",
      states = "empty",
      files = "M\t1\t0\ta.lua",
      conflicts = "2\tc.lua",
    })))
    assert.same({
      "add the answer",
      "Change  kkmmmmmm",
      "Commit  c1234567",
      "Author  Alice <alice@example.com>",
      "Date    2026-01-01 09:00:00 (2 days ago)",
      "",
      "It is 42.",
      "",
      "See the guide.",
      "",
      "Refs    main",
      "State   empty",
      "Files   1 file  +1 -0",
      "        M +1 -0 a.lua",
      "        ! c.lua  2-sided conflict",
    }, texts(host, bufnr))
  end)

  it("ends with the body, no blank row after it, where nothing follows it", function()
    local host = setup()
    local lines = require("jin.view.change_detail").lines(host, {
      description = "add the answer\n\nIt is 42.\n",
      states = {},
      files = {},
    }, 60, require("jin.glyph").resolve(host))
    assert.equal(3, #lines)
    assert.equal("It is 42.", lines[3][1].text)
  end)

  it("asks jj of the files and states in the same command as the rest", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("kkk", "c1", "-") .. "x\n", true)
    local template = words(assert(stay(jin, host, bufnr, 1)))
    template = template[#template]
    assert.truthy(template:find("self.diff().stat().files()", 1, true))
    assert.truthy(template:find("self.conflicted_files()", 1, true))
    assert.truthy(template:find("self.bookmarks()", 1, true))
    assert.truthy(template:find("self.immutable()", 1, true))
  end)

  it("leaves out refs, state and files a change has none of", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("kkk", "c1", "-") .. "x\n", true)
    stay(jin, host, bufnr, 1)
    host.finish(ok(change()))
    assert.equal(5, #texts(host, bufnr))
  end)

  it("cuts a file too long for the panel with the ellipsis glyph", function()
    local host, jin = setup()
    local bufnr = host.load(LOG)
    host.windows[bufnr] = { width = 30, height = 60 }
    view.read(jin, host, bufnr, LOG)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-") .. "x\n"))
    stay(jin, host, bufnr, 1)
    host.finish(ok(change({ files = "M\t1\t1\tsrc/a/very/long/path/to/a/file.lua" })))
    local lines = texts(host, bufnr)
    local line = lines[#lines]
    assert.equal("        M +1 -1 src/a/ver...", line)
    assert.equal(28, host.width(line))
  end)

  it("tells the same in the pick and the conflicts views", function()
    for _, name in ipairs({ "jin:///repo;view=pick#", "jin:///repo;view=conflicts#" }) do
      local host, jin = setup()
      local bufnr = read(host, jin, name, m("kkk", "c1", "-") .. "x\n", true)
      assert.equal(true, has(words(assert(stay(jin, host, bufnr, 1))), { "-r", "kkk" }), name)
    end
  end)
end)

describe("the detail panel", function()
  it("is no part of a buffer to edit", function()
    for _, name in ipairs({ "describe", "commit", "arrange" }) do
      assert.equal(nil, view.get(name).detail, name)
    end
  end)
end)
