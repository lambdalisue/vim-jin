local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local status = require("jin.status")
local support = require("jin.view.support")

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function read(host, jin, name, stdout, with_template)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  if with_template then
    host.finish(ok("tpl\n"))
  end
  host.finish(ok(stdout))
  return bufnr
end

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

describe("the operation log view", function()
  local NAME = "jin:///repo;view=oplog#"

  it("marks each operation with its ID", function()
    local host, jin = setup()
    read(host, jin, NAME, "", true)
    assert.same({
      "op",
      "log",
      "--config",
      "ui.log-word-wrap=false",
      "-T",
      [["\x1e" ++ json(stringify(self.id())) ++ "\x1f" ++ (tpl)]],
    }, words(host.runs[2]))
  end)

  it("shows what an operation changed, and the log as it was after it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, "@  " .. m("op1") .. "snapshot\n│  args\n", true)
    action.run(jin, host, bufnr, "show", 2, 2)
    action.run(jin, host, bufnr, "log:tab", 1, 1)
    assert.equal("jin:///repo;view=opshow#op1", host.opened[1].name)
    assert.same(
      { name = "jin:///repo;view=log#--at-op op1", opener = "tabedit" },
      { name = host.opened[2].name, opener = host.opened[2].opener }
    )
  end)

  it("yanks operation IDs", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("op1") .. "a\n" .. m("op2") .. "b\n", true)
    action.run(jin, host, bufnr, "yank:operation", 1, 2)
    assert.same({ "op1\nop2" }, host.yanked)
  end)
end)

describe("the operation show view", function()
  local NAME = "jin:///repo;view=opshow#op1"
  local OUTPUT = table.concat({
    "op1 alice default@ 1 minute ago",
    "snapshot working copy",
    "",
    "Changed commits:",
    "○  + " .. m("kkk", "c1aaaaaa", "-") .. "feat",
    "   - " .. m("kkk", "c2bbbbbb", "-") .. "feat, a version rewritten away",
    "",
    "Changed working copy default@:",
    "+ " .. m("zzz", "c3cccccc", "-") .. "other",
    "",
  }, "\n")

  it("asks jj what the operation changed, in color-words, with marked summaries", function()
    local host, jin = setup()
    read(host, jin, NAME, OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "op", "show", "--color-words" }, { argv[1], argv[2], argv[5] })
    assert.same({ "op1", "--config" }, { argv[6], argv[7] })
    assert.truthy(argv[8]:find("^templates%.commit_summary="))
  end)

  it("keeps jj from wrapping the graph lines, which would split the markers", function()
    local host, jin = setup()
    read(host, jin, NAME, OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "--config", "ui.log-word-wrap=false" }, { argv[3], argv[4] })
  end)

  it("leaves a -T of the user to the operation", function()
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=opshow#-T description op1", OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "-T", "description", "op1" }, { argv[6], argv[7], argv[8] })
  end)

  it("offers nothing on a line after a summary that names no change itself", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "show", 7, 7)
    end)
  end)

  it("shows a version of a change it touched, or its diff, by commit ID", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "show", 5, 5)
    action.run(jin, host, bufnr, "diff", 6, 6)
    action.run(jin, host, bufnr, "show", 9, 9)
    assert.equal("jin:///repo;view=show#c1aaaaaa", host.opened[1].name)
    assert.equal("jin:///repo;view=diff#-r c2bbbbbb", host.opened[2].name)
    assert.equal("jin:///repo;view=show#c3cccccc", host.opened[3].name)
  end)

  it("yanks the change or commit IDs of the lines", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "yank:change", 5, 6)
    action.run(jin, host, bufnr, "yank:commit", 5, 6)
    assert.same({ "kkk\nkkk", "c1aaaaaa\nc2bbbbbb" }, host.yanked)
  end)

  it("offers nothing on a line that names no change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "show", 4, 4)
    end)
  end)
end)

describe("the evolog view", function()
  local NAME = "jin:///repo;view=evolog#-r kkk"
  local OUTPUT = m("kkk", "c3")
    .. "now\n"
    .. m("kkk", "c2")
    .. "before\n"
    .. m("kkk", "c1")
    .. "first\n"

  it("shows a version of the change by its commit ID", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "show", 2, 2)
    assert.equal("jin:///repo;view=show#c2", host.opened[1].name)
  end)

  it("compares a version's diff with the version before it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "interdiff", 1, 1)
    assert.equal("jin:///repo;view=interdiff#--from c2 --to c3", host.opened[1].name)
  end)

  it("tells why the first version has nothing to compare with", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "interdiff", 3, 3)
    end, "jin: this is the first version of the change")
  end)
end)

describe("the marker of a change in a template of its own", function()
  -- An older version is a hidden commit, which its change ID would name the
  -- latest version for, so these views mark it as the log does.
  for _, name in ipairs({ "evolog", "annotate" }) do
    it(("marks a hidden commit in the %s, to be named by its commit ID"):format(name), function()
      local marker = view.get(name).template.fields[3]
      assert.truthy(marker:find("hidden()", 1, true))
      assert.truthy(marker:find('"hidden"', 1, true))
    end)
  end
end)

describe("the annotate view", function()
  it("leads from a line to the change that wrote it", function()
    local host, jin = setup()
    local name = "jin:///repo;view=annotate#a.lua"
    local bufnr = read(
      host,
      jin,
      name,
      m("kkk", "c1") .. "kkk x\n" .. m("zzz", "c9", "divergent") .. "zzz y\n",
      true
    )
    action.run(jin, host, bufnr, "show", 1, 1)
    action.run(jin, host, bufnr, "diff", 2, 2)
    assert.equal("jin:///repo;view=show#kkk", host.opened[1].name)
    assert.equal("jin:///repo;view=diff#-r c9", host.opened[2].name)
    assert.same({ "file", "annotate" }, { words(host.runs[2])[1], words(host.runs[2])[2] })
  end)

  it("leads from a line to the log up to the change that wrote it", function()
    local host, jin = setup()
    local name = "jin:///repo;view=annotate#a.lua"
    local bufnr = read(
      host,
      jin,
      name,
      m("kkk", "c1") .. "kkk x\n" .. m("zzz", "c9", "divergent") .. "zzz y\n",
      true
    )
    action.run(jin, host, bufnr, "log", 1, 1)
    action.run(jin, host, bufnr, "log:vsplit", 2, 2)
    assert.equal("jin:///repo;view=log#-r ::kkk", host.opened[1].name)
    assert.equal("jin:///repo;view=log#-r ::c9", host.opened[2].name)
  end)

  ---A marker carrying the content of the line, as JSON.
  local function mc(change, commit, content)
    local json = content:gsub('[\\"]', "\\%0"):gsub("\n", "\\n"):gsub("\t", "\\t")
    return "\30" .. ('"%s" "%s" "-" "%s"'):format(change, commit, json) .. "\31"
  end

  local ANNOTATED = mc("kkk", "c1", "a\n")
    .. "\27[1mkkk\27[0m alice 1: a\n"
    .. mc("zzz", "c9", "\tb  \n")
    .. "zzz bob   2: \27[31m\tb\27[0m  \n"
    .. mc("zzz", "c9", "\n")
    .. "zzz bob   3: \n"
    .. mc("zzz", "c9", "d")
    .. "zzz bob   4: d"

  it("asks jj for the content of each line along with the change that wrote it", function()
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=annotate#a.lua", "", true)
    local argv = words(host.runs[2])
    assert.truthy(argv[4]:find('json(stringify(content)) ++ "\\x1f" ++ (tpl)', 1, true))
  end)

  it("fills the buffer with the file itself, highlighted as the file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#-r @- -- a.lua", ANNOTATED, true)
    local rendered = host.rendered[bufnr]
    assert.same({ "a", "\tb  ", "", "d" }, rendered.lines)
    assert.same({}, rendered.highlights)
    assert.is_nil(rendered.filetype)
    assert.equal("a.lua", rendered.detect)
  end)

  it("shows beside each line what the template prints before it, in jj's colors", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", ANNOTATED, true)
    local rendered = host.rendered[bufnr]
    local bold = next(rendered.groups)
    assert.same({ bold = true }, rendered.groups[bold])
    assert.same({
      { { text = "kkk", group = bold }, { text = " alice 1:" } },
      { { text = "zzz bob   2:" } },
      { { text = "zzz bob   3:" } },
      { { text = "zzz bob   4:" } },
    }, rendered.annotations)
  end)

  it("acts on the change that wrote each line of the file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", ANNOTATED, true)
    action.run(jin, host, bufnr, "show", 2, 2)
    action.run(jin, host, bufnr, "yank:change", 1, 4)
    assert.equal("jin:///repo;view=show#zzz", host.opened[1].name)
    assert.same({ "kkk\nzzz\nzzz\nzzz" }, host.yanked)
  end)

  it("shows jj's output whole when the template does not end with the content", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      "jin:///repo;view=annotate#a.lua",
      mc("kkk", "c1", "a\n") .. "a\n| kkk\n" .. mc("zzz", "c9", "b\n") .. "b\n| zzz\n",
      true
    )
    local rendered = host.rendered[bufnr]
    assert.same({ "a", "| kkk", "b", "| zzz" }, rendered.lines)
    assert.equal("jin-annotate", rendered.filetype)
    assert.is_nil(rendered.annotations)
    action.run(jin, host, bufnr, "show", 4, 4)
    assert.equal("jin:///repo;view=show#zzz", host.opened[1].name)
  end)

  it("shows jj's output whole when the template prints no content", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      "jin:///repo;view=annotate#a.lua",
      mc("kkk", "c1", "a\n") .. "kkk\n" .. mc("zzz", "c9", "b\n") .. "zzz\n",
      true
    )
    assert.same({ "kkk", "zzz" }, host.rendered[bufnr].lines)
    assert.is_nil(host.rendered[bufnr].annotations)
  end)

  it("refuses a command without a path before opening anything", function()
    for _, name in ipairs({ "annotate", "file" }) do
      for _, line in ipairs({ "", "-r @-", "-T content" }) do
        local host, jin = setup()
        assert.has_error(function()
          view.command(jin, host, name, line, {})
        end, "jin: give the path of a file, such as %")
        assert.same({}, host.opened)
        assert.same({}, host.runs)
      end
    end
  end)

  it("highlights every line the change under the cursor wrote once read", function()
    local host, jin = setup()
    local name = "jin:///repo;view=annotate#a.lua"
    local bufnr = host.load(name)
    host.cursors[bufnr] = 3
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(ANNOTATED))
    assert.same({ 2, 3, 4 }, host.change_highlighted[bufnr])
  end)

  it("moves the highlight of the change with the cursor", function()
    local host, jin = setup()
    local output = mc("kkk", "c1", "a\n")
      .. "kkk a\n"
      .. mc("zzz", "c9", "b\n")
      .. "zzz b\n"
      .. mc("kkk", "c1", "c\n")
      .. "kkk c\n"
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", output, true)
    host.cursors[bufnr] = 1
    view.cursor_moved(host, bufnr)
    assert.same({ 1, 3 }, host.change_highlighted[bufnr])
    host.cursors[bufnr] = 2
    view.cursor_moved(host, bufnr)
    assert.same({ 2 }, host.change_highlighted[bufnr])
  end)

  it("tells the commits of a divergent change apart in the highlight", function()
    local host, jin = setup()
    local output = m("zzz", "c9", "divergent", "a")
      .. "zzz a\n"
      .. m("zzz", "c8", "divergent", "b")
      .. "zzz b\n"
      .. m("zzz", "c9", "divergent", "c")
      .. "zzz c\n"
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", output, true)
    host.cursors[bufnr] = 3
    view.cursor_moved(host, bufnr)
    assert.same({ 1, 3 }, host.change_highlighted[bufnr])
  end)

  it("leaves the highlight as it is while the cursor stays on the same change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", ANNOTATED, true)
    host.cursors[bufnr] = 2
    view.cursor_moved(host, bufnr)
    host.change_highlighted[bufnr] = nil
    host.cursors[bufnr] = 4
    view.cursor_moved(host, bufnr)
    assert.is_nil(host.change_highlighted[bufnr])
  end)

  it("highlights the change again once the annotation is read again", function()
    local host, jin = setup()
    local name = "jin:///repo;view=annotate#a.lua"
    local bufnr = read(host, jin, name, ANNOTATED, true)
    host.cursors[bufnr] = 1
    view.cursor_moved(host, bufnr)
    view.read(jin, host, bufnr, name)
    host.finish(ok(mc("kkk", "c1", "a\n") .. "kkk a\n" .. mc("kkk", "c1", "b\n") .. "kkk b\n"))
    assert.same({ 1, 2 }, host.change_highlighted[bufnr])
  end)

  it("highlights no change on a line of none", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#a.lua", ANNOTATED, true)
    host.cursors[bufnr] = 1
    view.cursor_moved(host, bufnr)
    host.cursors[bufnr] = 5
    view.cursor_moved(host, bufnr)
    assert.same({}, host.change_highlighted[bufnr])
  end)

  it("leaves the lines of a change unhighlighted in other views", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", m("kkk", "c1") .. "x\n", true)
    view.cursor_moved(host, bufnr)
    assert.is_nil(host.change_highlighted[bufnr])
  end)

  it("shows what jj says when it fails", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;view=annotate#")
    view.read(jin, host, bufnr, "jin:///repo;view=annotate#")
    host.finish(ok("tpl\n"))
    host.finish({ code = 2, stdout = "", stderr = "error: a path is required\n" })
    assert.same({ "error: a path is required" }, host.rendered[bufnr].lines)
    assert.equal("jin-annotate", host.rendered[bufnr].filetype)
  end)

  local ANNOTATE = "jin:///repo;view=annotate#--at-op op1 -r @- -- src/main.lua"

  it("turns the annotation off by opening the file view on the same line", function()
    local host, jin = setup()
    local bufnr = read(host, jin, ANNOTATE, ANNOTATED, true)
    action.run(jin, host, bufnr, "file", 3, 3)
    assert.equal("jin:///repo;view=file#--at-op op1 -r @- src/main.lua", host.opened[1].name)
    local file = assert(host.buffer_bufnr(host.opened[1].name))
    view.read(jin, host, file, host.opened[1].name)
    host.finish(ok("a\nb\nc\n"))
    assert.equal(3, host.cursors[file])
  end)

  it("shows the log of the changes that touched the file with log:file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=annotate#-r @- -- a.lua", ANNOTATED, true)
    action.run(jin, host, bufnr, "log:file", 1, 1)
    assert.equal("jin:///repo;view=log#-r ::(@-) -- a.lua", host.opened[1].name)
  end)
end)

describe("jin.status.parse", function()
  it("reads the changes and the conflicts of the working copy", function()
    local paths = status.parse({
      "Working copy changes:",
      "M bin.dat",
      "A my file.txt",
      "R {from.txt => to.txt}",
      "R d/{one.txt => two.txt}",
      "There are unresolved conflicts at these paths:",
      "c.txt    2-sided conflict",
      "Working copy  (@) : kkk c1 (no description set)",
    })
    assert.same({
      [2] = { status = "M", path = "bin.dat" },
      [3] = { status = "A", path = "my file.txt" },
      [4] = { status = "R", path = "to.txt", old = "from.txt" },
      [5] = { status = "R", path = "d/two.txt", old = "d/one.txt" },
      [7] = { status = "conflict", path = "c.txt" },
    }, paths)
  end)

  it("reads the conflicts jj lists under a warning", function()
    local paths = status.parse({
      "The working copy has no changes.",
      "Warning: There are unresolved conflicts at these paths:",
      "hello.lua    2-sided conflict",
    })
    assert.same({ [3] = { status = "conflict", path = "hello.lua" } }, paths)
  end)
end)

describe("the status view", function()
  local NAME = "jin:///repo;view=status#"
  local OUTPUT = "Working copy changes:\nM a.lua\nA my file.txt\n"

  it("opens the file of a line, its diff and its annotation", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "edit:vsplit", 2, 2)
    action.run(jin, host, bufnr, "diff", 3, 3)
    action.run(jin, host, bufnr, "annotate", 2, 2)
    assert.same(
      { name = "/repo/a.lua", opener = "vsplit" },
      { name = host.opened[1].name, opener = host.opened[1].opener }
    )
    assert.equal([[jin:///repo;view=diff#-- file:\"my\ file.txt\"]], host.opened[2].name)
    assert.equal("jin:///repo;view=annotate#-- a.lua", host.opened[3].name)
  end)

  it("hands jj a path starting with - as a path, not as an option", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, "Working copy changes:\nM -n\n", true)
    action.run(jin, host, bufnr, "diff", 2, 2)
    action.run(jin, host, bufnr, "annotate", 2, 2)
    assert.equal([[jin:///repo;view=diff#-- file:\"-n\"]], host.opened[1].name)
    assert.equal("jin:///repo;view=annotate#-- -n", host.opened[2].name)
  end)

  it("yanks the paths of the lines", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "yank:path", 1, 3)
    assert.same({ "a.lua\nmy file.txt" }, host.yanked)
  end)

  -- The summaries carry the markers of the template vim-jin wraps, whatever
  -- the user's templates.commit_summary prints.
  local SUMMARY = OUTPUT
    .. "Working copy  (@) : "
    .. m("kkk", "c1", "-")
    .. "my own summary\n"
    .. "Parent commit (@-): "
    .. m("qqq", "c3", "divergent")
    .. "another\n"
    .. "Hint: a line after the last summary\n"

  it("wraps the user's commit summary template with markers", function()
    local host, jin = setup()
    read(host, jin, NAME, SUMMARY, true)
    assert.same({ "config", "get", "templates.commit_summary" }, words(host.runs[1]))
    local argv = words(host.runs[2])
    assert.same({ "status", "--config" }, { argv[1], argv[2] })
    -- A TOML string, as --config reads its value as TOML.
    local value = argv[3]:match('^templates%.commit_summary="(.*)"$')
    assert.truthy(value)
    assert.truthy(value:find("json(stringify(change_id))", 1, true))
    assert.truthy(value:find("++ (tpl)", 1, true))
  end)

  it(
    "puts its template after the user's settings, which would override it, and before --",
    function()
      local host, jin = setup()
      local name = [[jin:///repo;view=status#--config templates.commit_summary=x -- a.lua]]
      read(host, jin, name, SUMMARY, true)
      local argv = words(host.runs[2])
      assert.same({ "status", "--config", "templates.commit_summary=x", "--config" }, {
        argv[1],
        argv[2],
        argv[3],
        argv[4],
      })
      assert.truthy(argv[5]:find('^templates%.commit_summary="'))
      assert.same({ "--", "a.lua" }, { argv[6], argv[7] })
    end
  )

  it("writes a template of several lines as a TOML string jj can read", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("change_id\n\t++ commit_id\r\n"))
    host.finish(ok(""))
    local value = words(host.runs[2])[3]
    assert.is_nil(value:find("[\r\n\t]"))
    assert.truthy(value:find("change_id\\n\\t++ commit_id", 1, true))
  end)

  it("shows the change of a working copy or parent line, by commit ID when divergent", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, SUMMARY, true)
    action.run(jin, host, bufnr, "inspect", 4, 4)
    action.run(jin, host, bufnr, "inspect", 5, 5)
    action.run(jin, host, bufnr, "inspect", 6, 6)
    assert.equal("jin:///repo;view=show#kkk", host.opened[1].name)
    assert.equal("jin:///repo;view=show#c3", host.opened[2].name)
    assert.is_nil(host.opened[3])
  end)

  it("opens the file of a line with open, and shows the change of a working copy line", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, SUMMARY, true)
    action.run(jin, host, bufnr, "open", 2, 2)
    action.run(jin, host, bufnr, "open:split", 4, 4)
    assert.equal("/repo/a.lua", host.opened[1].name)
    assert.same(
      { name = "jin:///repo;view=show#kkk", opener = "split" },
      { name = host.opened[2].name, opener = host.opened[2].opener }
    )
  end)

  it("inspects the diff of a path line, and shows the change of a working copy line", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, SUMMARY, true)
    action.run(jin, host, bufnr, "inspect", 2, 2)
    action.run(jin, host, bufnr, "inspect:split", 4, 4)
    action.run(jin, host, bufnr, "inspect", 1, 1)
    assert.equal("jin:///repo;view=diff#-- a.lua", host.opened[1].name)
    assert.same(
      { name = "jin:///repo;view=show#kkk", opener = "split" },
      { name = host.opened[2].name, opener = host.opened[2].opener }
    )
    assert.is_nil(host.opened[3])
    assert.same({}, host.messages)
  end)

  it("opens a conflicted file at its first conflict", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      NAME,
      "Warning: There are unresolved conflicts at these paths:\nc.txt    2-sided conflict\n",
      true
    )
    host.contents["/repo/c.txt"] = { "a", "<<<<<<< conflict 1 of 1" }
    action.run(jin, host, bufnr, "open", 2, 2)
    assert.equal(2, host.cursors[host.buffer_bufnr("/repo/c.txt")])
  end)

  it("opens nothing, quietly, on a line that names neither a path nor a change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, SUMMARY, true)
    action.run(jin, host, bufnr, "open", 1, 1)
    assert.same({}, host.opened)
    assert.same({}, host.messages)
  end)

  it("tells why a line without a path offers nothing", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "edit", 1, 1)
    end, "jin: no path on this line")
  end)
end)

describe("jin.view.support.fileset", function()
  it("keeps a plain path, and quotes one jj would read as an expression", function()
    assert.equal("src/a-b_c.lua", support.fileset("src/a-b_c.lua"))
    assert.equal([[file:"my file.txt"]], support.fileset("my file.txt"))
    assert.equal([[file:"a\"b\\c"]], support.fileset([[a"b\c]]))
    assert.equal([[file:"-n"]], support.fileset("-n"))
  end)
end)
