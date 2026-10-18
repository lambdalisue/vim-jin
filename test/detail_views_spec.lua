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

  it("tells of a version a line of the operation show view stands for, by commit ID", function()
    local host, jin = setup()
    local output = "op1 alice\n\nChanged commits:\n+ "
      .. m("kkk", "c2", "-")
      .. "x\n- "
      .. m("kkk", "c1", "-")
      .. "y\n"
    local bufnr = read(host, jin, "jin:///repo;view=opshow#op1", output, true)
    assert.is_true(has(words(assert(stay(jin, host, bufnr, 5))), { "-r", "c1" }))
    assert.is_nil(stay(jin, host, bufnr, 3))
  end)

  it("tells of the change of a show view's header, by commit ID", function()
    local host, jin = setup()
    local output = m("kkk", "c9", "-") .. "Commit ID: c9\nChange ID: kkk\n\n    add\n"
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", output, true)
    assert.is_true(has(words(assert(stay(jin, host, bufnr, 1))), { "-r", "c9" }))
  end)
end)

describe("the detail panel of the status view", function()
  local STATUS = "jin:///repo;view=status#"
  local OUTPUT = table.concat({
    "Working copy changes:",
    "M a.lua",
    "R {old => new}.lua",
    "Working copy  (@) : " .. m("kkk", "c1", "-") .. "x",
    "Parent commit (@-): " .. m("ppp", "c0", "-") .. "y",
    "Warning: There are unresolved conflicts at these paths:",
    "c.lua    2-sided conflict",
    "",
  }, "\n")

  it("tells of the change of a working copy or parent line", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    assert.is_true(has(words(assert(stay(jin, host, bufnr, 5))), { "-r", "ppp" }))
    host.finish(ok(change({ description = "the parent\n" })))
    assert.equal("the parent", texts(host, bufnr)[1])
  end)

  it("tells of a file of the working copy its lines added and removed", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    local argv = words(assert(stay(jin, host, bufnr, 2)))
    assert.is_true(has(argv, { "diff", "-r", "@", "--git", "--", "a.lua" }))
    assert.is_true(has(argv, { "--ignore-working-copy" }))
    host.finish(ok(table.concat({
      "diff --git a/a.lua b/a.lua",
      "index 1..2 100644",
      "--- a/a.lua",
      "+++ b/a.lua",
      "@@ -1,2 +1,3 @@",
      " keep",
      "-old",
      "+new",
      "+++more",
      "",
    }, "\n")))
    assert.same({
      "a.lua",
      "Status  modified",
      "Lines   +2 -1",
      "",
      "@@ -1,2 +1,3 @@",
      " keep",
      "-old",
      "+new",
      "+++more",
    }, texts(host, bufnr))
  end)

  it("colors the diff of a file: hunk headers dimmed, lines added and removed apart", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    stay(jin, host, bufnr, 2)
    host.finish(ok(table.concat({
      "diff --git a/a.lua b/a.lua",
      "@@ -1,2 +1,2 @@ local M = {}",
      " keep",
      "-old",
      "+new",
      "\\ No newline at end of file",
      "",
    }, "\n")))
    assert.equal("JinDetailDim", group_of(host, bufnr, "@@ -1,2 +1,2 @@ local M = {}"))
    assert.equal("JinDetailBody", group_of(host, bufnr, " keep"))
    assert.equal("JinDetailRemoved", group_of(host, bufnr, "-old"))
    assert.equal("JinDetailAdded", group_of(host, bufnr, "+new"))
    assert.equal("JinDetailDim", group_of(host, bufnr, "\\ No newline at end of file"))
  end)

  it("expands tabs in the diff and cuts a line too wide with the ellipsis glyph", function()
    local host, jin = setup()
    local bufnr = host.load(STATUS)
    host.windows[bufnr] = { width = 30, height = 60 }
    view.read(jin, host, bufnr, STATUS)
    host.finish(ok("tpl\n"))
    host.finish(ok(OUTPUT))
    stay(jin, host, bufnr, 2)
    host.finish(ok(table.concat({
      "diff --git a/a.lua b/a.lua",
      "@@ -0,0 +1 @@",
      "+\t名前名前名前名前名前名前",
      "",
    }, "\n")))
    local lines = texts(host, bufnr)
    local line = lines[#lines]
    assert.equal("+        名前名前名前名前...", line)
    assert.equal(28, host.width(line))
  end)

  it("tells no diff of a binary file, the summary saying it is one", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    stay(jin, host, bufnr, 2)
    host.finish(ok("diff --git a/a.lua b/a.lua\nindex 1..2 100644\nBinary files differ\n"))
    assert.same({ "a.lua", "Status  modified", "Lines   binary" }, texts(host, bufnr))
  end)

  it("shows the diff from the run that counted its lines, asking jj no more", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    stay(jin, host, bufnr, 2)
    local before = #host.runs
    host.finish(ok("diff --git a/a.lua b/a.lua\n@@ -1 +1 @@\n-old\n+new\n"))
    assert(stay(jin, host, bufnr, 5))
    host.finish(ok(change()))
    assert.is_nil(stay(jin, host, bufnr, 2))
    assert.equal(before + 1, #host.runs)
    assert.same(
      { "a.lua", "Status  modified", "Lines   +1 -1", "", "@@ -1 +1 @@", "-old", "+new" },
      texts(host, bufnr)
    )
  end)

  it("tells of a renamed file the path it came from, asking jj of both", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    local argv = words(assert(stay(jin, host, bufnr, 3)))
    assert.is_true(has(argv, { "--", "new.lua | old.lua" }))
    host.finish(ok(table.concat({
      "diff --git a/old.lua b/new.lua",
      "rename from old.lua",
      "rename to new.lua",
      "",
    }, "\n")))
    assert.same(
      { "new.lua", "Status  renamed", "From    old.lua", "Lines   +0 -0" },
      texts(host, bufnr)
    )
  end)

  it("tells of a conflicted file its sides and the changes they come from", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    local argv = words(assert(stay(jin, host, bufnr, 7)))
    assert.is_true(has(argv, { "--config", "ui.conflict-marker-style=snapshot" }))
    assert.is_true(has(argv, { "file", "show", "-r", "@", "--", "c.lua" }))
    host.finish(ok(table.concat({
      "keep",
      "<<<<<<< conflict 1 of 2",
      '+++++++ aaa 1111 "feat: one"',
      "one",
      '------- bbb 2222 "base"',
      "zero",
      '+++++++ ccc 3333 "feat: two"',
      "two",
      ">>>>>>> conflict 1 of 2 ends",
      "<<<<<<< conflict 2 of 2",
      '+++++++ aaa 1111 "feat: one"',
      ">>>>>>> conflict 2 of 2 ends",
      "",
    }, "\n")))
    assert.same({
      "c.lua",
      "State   2-sided conflict",
      "+ Side  aaa 1111 feat: one",
      "- Base  bbb 2222 base",
      "+ Side  ccc 3333 feat: two",
    }, texts(host, bufnr))
    assert.equal("JinDetailChange", group_of(host, bufnr, "aaa"))
  end)

  it("tells nothing of a heading", function()
    local host, jin = setup()
    local bufnr = read(host, jin, STATUS, OUTPUT, true)
    assert.is_nil(stay(jin, host, bufnr, 1))
    assert.same({}, texts(host, bufnr))
  end)
end)

describe("the detail panel of a view of a diff", function()
  local SHOW_OUTPUT = m("kkk", "c9", "-")
    .. "Commit ID: c9\n\nModified regular file a.lua:\n   1    1: keep\n        2: new\n"

  it("tells of the file of a header line in the show view, of the version shown", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    local argv = words(assert(stay(jin, host, bufnr, 3)))
    assert.is_true(has(argv, { "diff", "-r", "c9", "--git", "--", "a.lua" }))
    host.finish(ok("diff --git a/a.lua b/a.lua\n@@ -1 +1,2 @@\n keep\n+new\n"))
    assert.same({ "a.lua", "Status  modified", "Lines   +1 -0" }, texts(host, bufnr))
  end)

  it("tells of the file of the section a line inside a diff is in, without asking again", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    stay(jin, host, bufnr, 3)
    host.finish(ok("diff --git a/a.lua b/a.lua\n@@ -1 +1,2 @@\n keep\n+new\n"))
    local before = #host.runs
    host.cursors[bufnr] = 5
    detail.cursor_moved(jin, host, bufnr)
    host.fire_timers()
    for i = before + 1, #host.runs do
      assert.is_false(has(words(host.runs[i]), { "--git" }))
    end
    assert.is_true(has(texts(host, bufnr), { "", "a.lua", "Status  modified", "Lines   +1 -0" }))
  end)

  it("compares in the diff view what the view compares, and tells of a change of mode", function()
    local host, jin = setup()
    local output = "Modified executable file run.sh:\n   1    1: x\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#--from a --to b --stat", output)
    local argv = words(assert(stay(jin, host, bufnr, 1)))
    assert.is_true(has(argv, { "diff", "--from", "a", "--to", "b", "--git", "--", "run.sh" }))
    assert.is_false(has(argv, { "--stat" }))
    host.finish(ok("diff --git a/run.sh b/run.sh\nold mode 100644\nnew mode 100755\n"))
    assert.same(
      { "run.sh", "Status  modified", "Lines   +0 -0", "Mode    file -> executable" },
      texts(host, bufnr)
    )
  end)

  it("tells of a binary file that it is one", function()
    local host, jin = setup()
    local output = "Added regular file a.png:\n    (binary)\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#-r kkk", output)
    assert.is_true(has(words(assert(stay(jin, host, bufnr, 1))), { "diff", "-r", "kkk" }))
    host.finish(ok("diff --git a/a.png b/a.png\nnew file mode 100644\nBinary files differ\n"))
    assert.same({ "a.png", "Status  added", "Lines   binary" }, texts(host, bufnr))
  end)

  it("asks jj interdiff in the interdiff view", function()
    local host, jin = setup()
    local output = "Modified regular file a.lua:\n   1    1: x\n"
    local bufnr = read(host, jin, "jin:///repo;view=interdiff#--from a --to b", output)
    local argv = words(assert(stay(jin, host, bufnr, 1)))
    assert.is_true(has(argv, { "interdiff", "--from", "a", "--to", "b", "--git" }))
  end)

  it("as the header tells it when jj fails", function()
    local host, jin = setup()
    local output = "Modified regular file a.lua:\n   1    1: x\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#", output)
    stay(jin, host, bufnr, 2)
    host.finish({ code = 1, stdout = "", stderr = "boom" })
    assert.same({ "a.lua", "Status  modified" }, texts(host, bufnr))
  end)
end)

describe("the detail panel of the evolog", function()
  it(
    "tells of a version the operation that made it and how it differs from the one before",
    function()
      local host, jin = setup()
      local output = m("kkk", "c2full", "-") .. "x\n" .. m("kkk", "c1full", "-") .. "y\n"
      local bufnr = read(host, jin, "jin:///repo;view=evolog#-r kkk", output, true)
      local argv = words(assert(stay(jin, host, bufnr, 2)))
      assert.is_true(has(argv, { "evolog", "--no-graph", "--limit", "1", "-r", "c1full" }))
      assert.truthy(argv[#argv]:find("inter_diff()", 1, true))
      host.finish(
        ok(
          m(
            "kk",
            "mmmmmm",
            "c1",
            "234567",
            "add the answer\n",
            "Alice",
            "alice@example.com",
            "2026-01-01 09:00:00",
            "2 days ago",
            "",
            "",
            "",
            "",
            "0123456789ab",
            "describe commit 1234",
            "args: jj describe -m 'add the answer'",
            "2026-01-02 10:00:00",
            "1 day ago",
            "M\t1\t0\ta.lua"
          ) .. "\n"
        )
      )
      assert.same({
        "add the answer",
        "Change  kkmmmmmm",
        "Commit  c1234567",
        "Op      0123456789ab describe commit 1234",
        "Args    jj describe -m 'add the answer'",
        "Date    2026-01-02 10:00:00 (1 day ago)",
        "Files   1 file  +1 -0",
        "        M +1 -0 a.lua",
      }, texts(host, bufnr))
    end
  )

  it("says so of a version that differs in no file from the one before", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=evolog#", m("kkk", "c1", "-") .. "y\n", true)
    stay(jin, host, bufnr, 1)
    host.finish(ok(m("kk", "", "c1", "", "d\n", "", "", "", "", "", "", "", "", "op", "x") .. "\n"))
    assert.equal("Files   no change from the version before", texts(host, bufnr)[5])
  end)
end)

describe("the detail panel of the operation log", function()
  local OPLOG = "jin:///repo;view=oplog#"

  it("tells of an operation its command, user, time and what it changed", function()
    local host, jin = setup()
    local output = "@  " .. m("op1full", "snapshot working copy", "alice@laptop", "now") .. "x\n"
    local bufnr = read(host, jin, OPLOG, output, true)
    local argv = words(assert(stay(jin, host, bufnr, 1)))
    assert.is_true(has(argv, { "op", "show", "--no-graph" }))
    assert.equal("op1full", argv[#argv])
    local config = argv[(function()
      for i, word in ipairs(argv) do
        if word == "--config" then
          return i + 1
        end
      end
    end)()]
    assert.truthy(config:find("^templates%.commit_summary="))
    host.finish(ok(table.concat({
      m(
        "op1",
        "rebase commit 1234\n\nwith a body",
        "args: jj rebase -d main\nother: x",
        "alice@laptop",
        "2026-01-01 09:00:00",
        "2 days ago",
        "14 milliseconds"
      ),
      "",
      "Changed commits:",
      "+ " .. m("aaa", "c3"),
      "- " .. m("aaa", "c2"),
      "+ " .. m("bbb", "c4"),
      "- " .. m("ccc", "c5"),
      "- " .. m("ddd", "c6"),
      "",
      "Changed working copy default@:",
      "+ " .. m("bbb", "c4"),
      "",
      "Changed local bookmarks:",
      "main:",
      "+ " .. m("aaa", "c3"),
      "- " .. m("aaa", "c2"),
      "",
      "Changed remote bookmarks:",
      "main@origin:",
      "+ (absent)",
      "",
    }, "\n")))
    assert.same({
      "rebase commit 1234",
      "with a body",
      "Op       op1",
      "Args     jj rebase -d main",
      "User     alice@laptop",
      "Date     2026-01-01 09:00:00 (2 days ago) lasted 14 milliseconds",
      "Changes  1 added  1 rewritten  2 abandoned",
      "Refs     2 bookmarks moved",
    }, texts(host, bufnr))
  end)

  it("shows at once what the line tells of its operation", function()
    local host, jin = setup()
    local output = m("op1full", "snapshot working copy", "alice@laptop", "now") .. "x\n"
    local bufnr = read(host, jin, OPLOG, output, true)
    assert.same(
      { "snapshot working copy", "Op       op1full", "User     alice@laptop", "Date     now" },
      texts(host, bufnr)
    )
  end)
end)

describe("the detail panel of the bookmark view", function()
  local NAME = "jin:///repo;view=bookmark#"

  ---A row of jj bookmark list as the panel asks for it.
  local function row(remote, tracked, ahead, behind, synced)
    return m(
      "main",
      remote,
      "",
      "",
      tracked,
      ahead,
      behind,
      synced,
      "kk",
      "mmmmmm",
      "c1",
      "234567",
      "add the answer\n",
      "Alice",
      "alice@example.com",
      "2026-01-01 09:00:00",
      "2 days ago"
    ) .. "\n"
  end

  it("tells of a bookmark the change it points to and how its remotes stand", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("main", "", "") .. "main: kkk\n", true)
    local argv = words(assert(stay(jin, host, bufnr, 1)))
    assert.is_true(has(argv, { "bookmark", "list", "--all-remotes" }))
    assert.equal('exact:"main"', argv[#argv])
    host.finish(ok(table.concat({
      row("", "", "", "", ""),
      row("origin", "tracked", "2", "1+", ""),
      row("upstream", "tracked", "0", "0", "synced"),
      row("fork", "", "", "", ""),
      row("git", "tracked", "0", "0", "synced"),
    })))
    assert.same({
      "main",
      "Change  kkmmmmmm",
      "Commit  c1234567",
      "About   add the answer",
      "Author  Alice <alice@example.com>",
      "Date    2026-01-01 09:00:00 (2 days ago)",
      "Remote  origin  tracked, 2 ahead, 1+ behind",
      "        upstream  tracked, synced",
      "        fork  untracked",
    }, texts(host, bufnr))
  end)

  it("tells of a remote bookmark the other remotes alone", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("main", "origin", "") .. "main@origin: kkk\n", true)
    stay(jin, host, bufnr, 1)
    host.finish(ok(row("", "", "", "", "") .. row("origin", "tracked", "0", "0", "synced")))
    local lines = texts(host, bufnr)
    assert.equal("main@origin", lines[1])
    assert.is_nil(lines[7])
  end)

  it("says so of a bookmark that points to no change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("gone", "", "absent") .. "gone (deleted)\n", true)
    assert.same({ "gone", "State   points to no change" }, texts(host, bufnr))
  end)
end)

describe("the detail panel of the workspace view", function()
  it("tells of a workspace its root and its working-copy change", function()
    local host, jin = setup()
    local output = m("default") .. "default: kkk\n" .. m("second") .. "second: zzz\n"
    local bufnr = read(host, jin, "jin:///repo;view=workspace#", output, true)
    local argv = words(assert(stay(jin, host, bufnr, 2)))
    assert.is_true(has(argv, { "workspace", "list" }))
    host.finish(ok(table.concat({
      m("default", "/repo", "kk", "", "c1", "", "one\n") .. "\n",
      m(
        "second",
        "/second",
        "zz",
        "zzzzzz",
        "c2",
        "345678",
        "two\n",
        "Bob",
        "",
        "",
        "",
        "",
        "empty"
      ) .. "\n",
    })))
    assert.same({
      "second",
      "Path    /second",
      "Change  zzzzzzzz",
      "Commit  c2345678",
      "About   two",
      "Author  Bob",
      "State   empty",
    }, texts(host, bufnr))
  end)
end)

describe("the detail panel of the conflicted paths", function()
  it("tells of a path the sides of its conflict in the revision listed", function()
    local host, jin = setup()
    local output = "a.lua    2-sided conflict\nb.lua    3-sided conflict\n"
    local bufnr = read(host, jin, "jin:///repo;view=resolve#-r kkk", output)
    local argv = words(assert(stay(jin, host, bufnr, 2)))
    assert.is_true(has(argv, { "file", "show", "-r", "kkk", "--", "b.lua" }))
    host.finish(ok("<<<<<<< conflict 1 of 1\n+++++++ side #1\n>>>>>>> conflict 1 of 1 ends\n"))
    assert.same({ "b.lua", "State   3-sided conflict", "+ Side  side #1" }, texts(host, bufnr))
  end)
end)

describe("the detail panel of a line inside a diff", function()
  -- Lines 4 and 7 are on both sides, 5 removed and 6 added.
  local SHOW_OUTPUT = m("kkk", "c9", "-")
    .. "Commit ID: c9\n\nModified regular file a.lua:\n"
    .. "   1    1: keep\n   2     : gone\n        2: new\n   3    3: tail\n"
  local GIT = "diff --git a/a.lua b/a.lua\n@@ -1,3 +1,3 @@\n keep\n-gone\n+new\n tail\n"

  ---What jj file annotate tells of a file of `count` lines one change wrote.
  local function annotated(count, fields)
    fields = fields or {}
    local lines = {
      m(
        "p1aaaa",
        "pp",
        "mmmmmm",
        "p1",
        "234567",
        fields.description or "add keep\n",
        "Bob",
        "bob@example.com",
        "2026-01-01 08:00:00",
        "3 days ago",
        "",
        fields.states or "immutable"
      ),
    }
    for i = 2, count do
      lines[i] = m("p1aaaa")
    end
    return table.concat(lines, "\n") .. "\n"
  end

  ---Move the cursor to `lnum` and let it stay there: the words of the jj
  ---runs the panel starts.
  local function started(jin, host, bufnr, lnum)
    host.cursors[bufnr] = lnum
    detail.cursor_moved(jin, host, bufnr)
    local before = #host.runs
    host.fire_timers()
    local runs = {}
    for i = before + 1, #host.runs do
      runs[#runs + 1] = words(host.runs[i])
    end
    return runs
  end

  ---The panel blaming a line on the change annotated, after `first`.
  local function blamed(first)
    return {
      first,
      "add keep",
      "Change  ppmmmmmm",
      "Commit  p1234567",
      "Author  Bob <bob@example.com>",
      "Date    2026-01-01 08:00:00 (3 days ago)",
      "",
      "a.lua",
      "Status  modified",
      "Lines   +1 -1",
    }
  end

  it(
    "tells of a line on both sides the change that last wrote it on the new side, above the file",
    function()
      local host, jin = setup()
      local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
      local runs = started(jin, host, bufnr, 4)
      assert.equal(2, #runs)
      assert.is_true(has(runs[1], { "diff", "-r", "c9", "--git" }))
      assert.is_true(has(runs[2], { "--ignore-working-copy", "file", "annotate", "-r", "c9" }))
      assert.is_true(has(runs[2], { "--", "a.lua" }))
      host.finish(ok(GIT))
      host.finish(ok(annotated(3)))
      assert.same(blamed("Line    1 of a.lua, last written by"), texts(host, bufnr))
      assert.equal("JinDetailChange", group_of(host, bufnr, "pp"))
      assert.equal("JinDetailTitle", group_of(host, bufnr, "add keep"))
    end
  )

  it("tells of a removed line the change that last wrote it on the old side", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    local runs = started(jin, host, bufnr, 5)
    assert.is_true(has(runs[2], { "file", "annotate", "-r", "c9-" }))
    host.finish(ok(GIT))
    host.finish(ok(annotated(3)))
    assert.same(blamed("Line    2 of a.lua, removed, last written by"), texts(host, bufnr))
  end)

  it(
    "tells of a removed line of a renamed file the change that wrote it at its old path",
    function()
      local host, jin = setup()
      local output = m("kkk", "c9", "-")
        .. "Commit ID: c9\n\nModified regular file new.lua (old.lua => new.lua):\n"
        .. "   1     : gone\n"
      local bufnr = read(host, jin, "jin:///repo;view=show#kkk", output, true)
      local runs = started(jin, host, bufnr, 4)
      assert.is_true(has(runs[2], { "-r", "c9-" }))
      assert.is_true(has(runs[2], { "--", "old.lua" }))
      host.finish(ok("diff --git a/old.lua b/new.lua\nrename from old.lua\nrename to new.lua\n"))
      host.finish(ok(annotated(1)))
      assert.equal("Line    1 of old.lua, removed, last written by", texts(host, bufnr)[1])
    end
  )

  it("tells of a line the show view adds the version shown, asking jj of it alone", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    local runs = started(jin, host, bufnr, 6)
    assert.equal(2, #runs)
    assert.is_true(has(runs[2], { "log", "--no-graph", "--limit", "1", "-r", "c9" }))
    host.finish(ok(GIT))
    host.finish(ok(change()))
    assert.same({
      "Line    2 of a.lua, last written by",
      "add the answer",
      "Change  kkmmmmmm",
      "Commit  c1234567",
      "Author  Alice <alice@example.com>",
      "Date    2026-01-01 09:00:00 (2 days ago)",
      "",
      "a.lua",
      "Status  modified",
      "Lines   +1 -1",
    }, texts(host, bufnr))
  end)

  it("annotates a file once per read, revision and path, however the cursor moves", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    started(jin, host, bufnr, 4)
    host.finish(ok(GIT))
    host.finish(ok(annotated(3)))
    assert.same({}, started(jin, host, bufnr, 7))
    assert.same(blamed("Line    3 of a.lua, last written by"), texts(host, bufnr))
    assert.same({}, started(jin, host, bufnr, 3))
    assert.equal("a.lua", texts(host, bufnr)[1])
    -- Told at once, before the cursor stayed.
    host.cursors[bufnr] = 4
    detail.cursor_moved(jin, host, bufnr)
    assert.same(blamed("Line    1 of a.lua, last written by"), texts(host, bufnr))
  end)

  it("tells of the file alone where jj cannot annotate it, and asks no more", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    started(jin, host, bufnr, 4)
    host.finish(ok(GIT))
    host.finish({ code = 1, stdout = "", stderr = "Error: No such path: a.lua" })
    assert.same({ "a.lua", "Status  modified", "Lines   +1 -1" }, texts(host, bufnr))
    assert.same({}, started(jin, host, bufnr, 7))
    assert.same({ "a.lua", "Status  modified", "Lines   +1 -1" }, texts(host, bufnr))
  end)

  it("tells of the file alone on a line without line numbers, as of a binary file", function()
    local host, jin = setup()
    local output = "Added regular file a.png:\n    (binary)\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#-r kkk", output)
    local runs = started(jin, host, bufnr, 2)
    assert.equal(1, #runs)
    host.finish(ok("diff --git a/a.png b/a.png\nnew file mode 100644\nBinary files differ\n"))
    assert.same({ "a.png", "Status  added", "Lines   binary" }, texts(host, bufnr))
  end)

  it("annotates in the diff view the side of the line it compares", function()
    local host, jin = setup()
    local output = "Modified regular file a.lua:\n   1     : gone\n        1: new\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#--from a --to b", output)
    assert.is_true(has(started(jin, host, bufnr, 2)[2], { "file", "annotate", "-r", "a" }))
    assert.is_true(has(started(jin, host, bufnr, 3)[1], { "file", "annotate", "-r", "b" }))
  end)

  it("annotates in the interdiff view the new side alone, the old being in no revision", function()
    local host, jin = setup()
    local output = "Modified regular file a.lua:\n   1     : gone\n        1: new\n"
    local bufnr = read(host, jin, "jin:///repo;view=interdiff#--from a --to b", output)
    assert.equal(1, #started(jin, host, bufnr, 2))
    assert.is_true(has(started(jin, host, bufnr, 3)[1], { "file", "annotate", "-r", "b" }))
  end)

  it("annotates at the operation the view shows", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#--at-op op1 kkk", SHOW_OUTPUT, true)
    local runs = started(jin, host, bufnr, 4)
    assert.is_true(has(runs[2], { "--at-op", "op1", "--ignore-working-copy", "file", "annotate" }))
  end)

  it("tells of a change written by a hidden or divergent commit its state", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    started(jin, host, bufnr, 4)
    host.finish(ok(GIT))
    host.finish(ok(annotated(3, { states = "immutable divergent hidden" })))
    assert.equal("State   divergent hidden", texts(host, bufnr)[7])
    assert.equal("JinDetailAlert", group_of(host, bufnr, "hidden"))
  end)

  it("tells the rest of the description of the change last, after the file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    started(jin, host, bufnr, 4)
    host.finish(ok(GIT))
    host.finish(ok(annotated(3, { description = "add keep\n\nIt is kept.\n\nFor good.\n" })))
    local wanted = blamed("Line    1 of a.lua, last written by")
    for _, line in ipairs({ "", "About   It is kept.", "", "        For good." }) do
      wanted[#wanted + 1] = line
    end
    assert.same(wanted, texts(host, bufnr))
  end)

  it("cuts what does not fit in the panel with the ellipsis glyph", function()
    local host, jin = setup()
    host.settings.detail_height = "9"
    local bufnr = read(host, jin, "jin:///repo;view=show#kkk", SHOW_OUTPUT, true)
    started(jin, host, bufnr, 4)
    host.finish(ok(GIT))
    host.finish(ok(annotated(3)))
    local lines = texts(host, bufnr)
    assert.equal("Line    1 of a.lua, last written by", lines[1])
    assert.equal("...", lines[#lines])
  end)
end)

describe("the detail panel", function()
  it("is no part of a buffer to edit, nor of the diff editor", function()
    for _, name in ipairs({ "describe", "commit", "diffedit", "merge", "arrange" }) do
      assert.equal(nil, view.get(name).detail, name)
    end
  end)
end)
