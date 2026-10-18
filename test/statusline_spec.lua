local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local selection = require("jin.selection")
local statusline = require("jin.statusline")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

local function read(host, jin, name, output, template)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  if template then
    host.finish(ok("tpl\n"))
  end
  host.finish(ok(output))
  return bufnr
end

describe("the statusline of a view", function()
  it("names the view and the change under the cursor, leaving the jj command out", function()
    local host, jin = setup()
    local output = m("kmkuslswpqwqponm", "30c5cb310237275150b3", "-") .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#-r ::@", output, true)
    host.cursors[bufnr] = 1
    assert.same({
      view = "log",
      editable = false,
      entry = "kmkuslsw 30c5cb31",
      kind = "change",
      selected = 0,
    }, statusline.parts(host, bufnr))
  end)

  it("tells what the change under the cursor is about: description, author and when", function()
    local host, jin = setup()
    local output = m("kmkuslsw", "30c5cb31", "-", "feat: say goodbye", "alice", "2 days ago")
      .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    host.cursors[bufnr] = 1
    assert.same(
      { what = "feat: say goodbye", who = "alice", when = "2 days ago" },
      assert(statusline.parts(host, bufnr)).about
    )
  end)

  it("tells the user of an operation without the host", function()
    local host, jin = setup()
    local output = m("5febfae502c1", "snapshot working copy", "alice@laptop", "now") .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=oplog#", output, true)
    host.cursors[bufnr] = 1
    assert.same(
      { what = "snapshot working copy", who = "alice", when = "now" },
      assert(statusline.parts(host, bufnr)).about
    )
  end)

  it("tells nothing about a bookmark that has no single target", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=bookmark#", m("main", "", "") .. "x\n", true)
    host.cursors[bufnr] = 1
    assert.is_nil(assert(statusline.parts(host, bufnr)).about)
  end)

  it("tells the workspace only when asked, by its directory name", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", "x\n", true)
    assert.is_nil(assert(statusline.parts(host, bufnr)).here)
    assert.equal("repo", assert(statusline.parts(host, bufnr, jin)).here.root)
  end)

  it(
    "names the operation, the bookmark or the workspace under the cursor, and which it is",
    function()
      for _, case in ipairs({
        {
          "jin:///repo;view=oplog#",
          m("5febfae502c1889ecf4a") .. "x\n",
          "5febfae502c1",
          "operation",
        },
        {
          "jin:///repo;view=bookmark#",
          m("main", "origin", "") .. "x\n",
          "main@origin",
          "bookmark",
        },
        {
          "jin:///repo;view=workspace#",
          m("second", "fix login", "alice", "now") .. "x\n",
          "second",
          "workspace",
        },
      }) do
        local host, jin = setup()
        local bufnr = read(host, jin, case[1], case[2], true)
        host.cursors[bufnr] = 1
        local parts = assert(statusline.parts(host, bufnr))
        assert.same({ case[3], case[4] }, { parts.entry, parts.kind }, case[1])
      end
    end
  )

  it("reads the entry on the line it is given, of the window drawn", function()
    local host, jin = setup()
    local output = m("aaaaaaaa", "11111111", "-")
      .. "a\n"
      .. m("bbbbbbbb", "22222222", "-")
      .. "b\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    host.cursors[bufnr] = 1
    assert.equal("bbbbbbbb 22222222", assert(statusline.parts(host, bufnr, nil, 2)).entry)
  end)

  it("tells the shortest prefixes of the change and commit, the parts jj highlights", function()
    local host, jin = setup()
    local output = m(
      "kmkuslswpqwqponmkmkuslswpqwqponm",
      "30c5cb310237275150b330c5cb310237275150b3",
      "-",
      "feat",
      "alice",
      "now",
      "kmk",
      "30c5"
    ) .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    host.cursors[bufnr] = 1
    local parts = assert(statusline.parts(host, bufnr))
    assert.equal("kmkuslsw 30c5cb31", parts.entry)
    assert.same({ 3, 4 }, parts.prefixes)
  end)

  it("highlights no more of an ID than the 8 characters it shows", function()
    local host, jin = setup()
    local output = m("kmkuslswpq", "30c5cb3102", "-", "", "", "", "kmkuslswpq", "30c5cb3") .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    host.cursors[bufnr] = 1
    assert.same({ 8, 7 }, assert(statusline.parts(host, bufnr)).prefixes)
  end)

  it("tells a divergent change, whose prefix jj log shows in red", function()
    local host, jin = setup()
    local output = m("kmkuslswpq", "30c5cb3102", "divergent", "", "", "", "k", "3")
      .. "x\n"
      .. m("zzzzzzzzzz", "0000000000", "-", "", "", "", "z", "0")
      .. "y\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    local parts = assert(statusline.parts(host, bufnr, nil, 1))
    assert.same({ 1, 1 }, parts.prefixes)
    assert.is_true(parts.divergent)
    assert.is_nil(assert(statusline.parts(host, bufnr, nil, 2)).divergent)
  end)

  it("tells a divergent line of an annotation too", function()
    local host, jin = setup()
    local output = m("kkk", "c1", "divergent", "a", "", "", "", "k", "c") .. "kkk a\n"
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", output, true)
    assert.is_true(assert(statusline.parts(host, bufnr, nil, 1)).divergent)
  end)

  it("tells no prefixes of an entry printed without them", function()
    local host, jin = setup()
    local output = m("kmkuslsw", "30c5cb31", "-") .. "x\n"
    local bufnr = read(host, jin, "jin:///repo;view=log#", output, true)
    host.cursors[bufnr] = 1
    local parts = assert(statusline.parts(host, bufnr))
    assert.equal("kmkuslsw 30c5cb31", parts.entry)
    assert.is_nil(parts.prefixes)
  end)

  it("asks jj for the shortest prefixes in every view naming a change and its commit", function()
    for _, name in ipairs({
      "log",
      "show",
      "evolog",
      "annotate",
      "status",
      "opshow",
      "conflicts",
      "pick",
      "describe",
      "commit",
    }) do
      local template = assert(view.get(name).template, name)
      local short = assert(template.short, name)
      assert(template.fields[short]:find("change_id%(%)%.shortest%(%)$"), name)
      assert(template.fields[short + 1]:find("commit_id%(%)%.shortest%(%)$"), name)
    end
  end)

  it("names nothing on a line that stands for nothing", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", "(elided)\n", true)
    host.cursors[bufnr] = 1
    assert.is_nil(statusline.parts(host, bufnr).entry)
  end)

  it("tells the operation a view stays at, and how many changes are selected", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#--at-op 5febfae502c1889e", "x\n", true)
    selection.toggle(host, "/repo", { "aaa", "bbb" })
    local parts = assert(statusline.parts(host, bufnr))
    assert.equal("5febfae502c1", parts.at_op)
    assert.equal(2, parts.selected)
  end)

  describe("of a file view", function()
    local CHANGE = ("kmkuslsw"):rep(4)
    local COMMIT = ("30c5cb31"):rep(5)

    ---What jj prints for the change and commit of each revision a file view
    ---asks about, each given as whether it is divergent.
    local function revisions(...)
      local out = {}
      for _, divergent in ipairs({ ... }) do
        out[#out + 1] = table.concat(
          { CHANGE, "kmk", COMMIT, "30c5", divergent and "divergent" or "-" },
          " "
        ) .. "\n"
      end
      return ok(table.concat(out))
    end

    ---The jj arguments of `run`, after those every run of jj starts with.
    local function words(run)
      local w = {}
      for i = 5, #run.argv do
        w[#w + 1] = run.argv[i]
      end
      return w
    end

    ---Read the file view `name`, jj printing the file and then `answer` for
    ---its revision.
    local function read_file(name, answer)
      local host, jin = setup()
      local bufnr = host.load(name)
      view.read(jin, host, bufnr, name)
      host.finish(ok("print('hello')\n"))
      host.finish(answer)
      return host, bufnr
    end

    it("names the file and the change and commit of the revision it is shown at", function()
      local host, bufnr = read_file("jin:///repo;view=file#-r xyz -- hello.py", revisions(false))
      local parts = assert(statusline.parts(host, bufnr))
      assert.equal("hello.py", parts.file)
      assert.equal("kmkuslsw 30c5cb31", parts.entry)
      assert.equal("change", parts.kind)
      assert.same({ 3, 4 }, parts.prefixes)
      assert.is_nil(parts.divergent)
    end)

    it("tells a divergent change, whose prefix jj log shows in red", function()
      local host, bufnr = read_file("jin:///repo;view=file#hello.py", revisions(true))
      assert.is_true(assert(statusline.parts(host, bufnr)).divergent)
    end)

    it("names the file alone when the revision is no single one, or jj fails", function()
      for _, answer in ipairs({
        revisions(false, false),
        ok(""),
        { code = 1, stdout = "", stderr = "Error: Revision `xyz` doesn't exist" },
      }) do
        local host, bufnr = read_file("jin:///repo;view=file#-r xyz hello.py", answer)
        local parts = assert(statusline.parts(host, bufnr))
        assert.equal("hello.py", parts.file)
        assert.is_nil(parts.entry)
        assert.is_nil(parts.prefixes)
      end
    end)

    it("asks jj once the read snapshotted the working copy, at the latest operation", function()
      local host, jin = setup()
      local name = "jin:///repo;view=file#hello.py"
      local bufnr = host.load(name)
      view.read(jin, host, bufnr, name)
      assert.equal(1, #host.runs)
      host.finish(ok("print('hello')\n"))
      assert.is_nil(host.rendered[bufnr])
      local query = words(assert(host.runs[2]))
      assert.same(
        { "--at-op", "@", "--ignore-working-copy", "log", "--no-graph" },
        { query[1], query[2], query[3], query[4], query[5] }
      )
      assert.equal("@", query[#query - 2])
      host.finish(revisions(false))
      assert.equal("kmkuslsw 30c5cb31", assert(statusline.parts(host, bufnr)).entry)
    end)

    it("asks jj alongside the read at the operation the view stays at", function()
      local host, jin = setup()
      local op = ("0123456789abcdef"):rep(8)
      local name = "jin:///repo;view=file#--at-op " .. op .. " -r @- hello.py"
      local bufnr = host.load(name)
      view.read(jin, host, bufnr, name)
      local query = words(assert(host.runs[2]))
      assert.same({ "--at-op", op }, { query[1], query[2] })
      assert.equal("@-", query[#query - 2])
      host.finish(ok("print('hello')\n"))
      host.finish(revisions(false))
      assert.equal("kmkuslsw 30c5cb31", assert(statusline.parts(host, bufnr)).entry)
    end)

    it("runs no jj when the cursor moves", function()
      local host, bufnr = read_file("jin:///repo;view=file#hello.py", revisions(false))
      local runs = #host.runs
      host.cursors[bufnr] = 1
      statusline.parts(host, bufnr, nil, 1)
      view.cursor_moved(host, bufnr)
      assert.equal(runs, #host.runs)
    end)
  end)

  it("names no file in a view of changes", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", "x\n", true)
    assert.is_nil(assert(statusline.parts(host, bufnr)).file)
  end)

  it("is nothing for a buffer that is no view, or one not read yet", function()
    local host = setup()
    assert.is_nil(statusline.parts(host, host.load("/repo/hello.py")))
    assert.is_nil(statusline.parts(host, host.load("jin:///repo;view=log#")))
  end)
end)
