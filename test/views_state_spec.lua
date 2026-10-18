local fake_host = require("support.fake_host")
local api = require("jin.api")
local bufname = require("jin.bufname")
local view = require("jin.view")
local action = require("jin.action")
local cd = require("jin.command.cd")
local component = require("jin.component")

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

local function setup(opts)
  local host = fake_host.new(opts or { cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function read(host, jin, name, stdout)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok("tpl\n"))
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

describe("the bookmark view", function()
  local NAME = "jin:///repo;view=bookmark#"
  -- As jj 0.46 prints a local bookmark, a remote one, and bookmarks whose
  -- names it shows quoted, through the template marker.wrap makes.
  local OUTPUT = "\30"
    .. [["main" ""]]
    .. "\31main: kkk one\n"
    .. "\30"
    .. [["main" "origin"]]
    .. "\31  @origin: zzz\n"
    .. "\30"
    .. [["we ird" ""]]
    .. '\31"we ird": kkk\n'
    .. "\30"
    .. [["qu'ote\"d" "my remote"]]
    .. '\31  @"my remote": kkk\n'

  it("leads from a local or remote bookmark to the log up to it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT)
    action.run(jin, host, bufnr, "log", 1, 1)
    action.run(jin, host, bufnr, "log", 2, 2)
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.equal([[jin:///repo;view=log#-r ::bookmarks(exact:\"main\")]], host.opened[1].name)
    assert.equal(
      [[jin:///repo;view=log#-r ::remote_bookmarks(exact:\"main\",\ exact:\"origin\")]],
      host.opened[2].name
    )
    assert.equal([[jin:///repo;view=show#bookmarks(exact:\"main\")]], host.opened[3].name)
  end)

  it("yanks bookmark names, remote ones with @remote", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT)
    action.run(jin, host, bufnr, "yank:bookmark", 1, 2)
    assert.same({ "main\nmain@origin" }, host.yanked)
  end)

  it("leads from a bookmark whose name jj shows quoted to the bookmark itself", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT)
    action.run(jin, host, bufnr, "log", 3, 3)
    action.run(jin, host, bufnr, "show", 4, 4)
    assert.same({ "-r", [[::bookmarks(exact:"we ird")]] }, bufname.parse(host.opened[1].name).argv)
    assert.same(
      { [[remote_bookmarks(exact:"qu'ote\"d", exact:"my remote")]] },
      bufname.parse(host.opened[2].name).argv
    )
  end)

  it("yanks the names of such bookmarks as they are", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT)
    action.run(jin, host, bufnr, "yank:bookmark", 3, 4)
    assert.same({ "we ird\nqu'ote\"d@my remote" }, host.yanked)
  end)

  it("tells why a bookmark that points to no change has nothing to show", function()
    local host, jin = setup()
    -- As jj prints a tracked remote bookmark not pushed yet.
    local absent = "\30" .. [["feat" "origin" "absent"]] .. "\31  @origin (not created yet)\n"
    local bufnr = read(host, jin, NAME, absent)
    for _, name in ipairs({ "log", "show" }) do
      assert.has_error(function()
        action.run(jin, host, bufnr, name, 1, 1)
      end, "jin: feat@origin points to no change")
    end
    assert.same({}, host.opened)
    action.run(jin, host, bufnr, "yank:bookmark", 1, 1)
    assert.same({ "feat@origin" }, host.yanked)
  end)
end)

describe("the workspace view", function()
  local NAME = "jin:///repo;view=workspace#"

  it("changes to the root of the workspace on the line", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("other") .. "other: kkk\n")
    host.results = { ok("/elsewhere/other\n") }
    action.run(jin, host, bufnr, "tcd", 1, 1)
    assert.same({ "workspace", "root", "--name", "other" }, words(host.runs[3]))
    assert.same({ { scope = "tcd", path = "/elsewhere/other" } }, host.cds)
    assert.same({ { text = "jin: tcd to the root of workspace other" } }, host.messages)
  end)

  it("updates the workspace on the line when it went stale, in its own root", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("other") .. "other: kkk\n")
    host.results = { ok("/elsewhere/other\n") }
    action.run(jin, host, bufnr, "update-stale", 1, 1)
    local run = host.runs[#host.runs]
    assert.same({ "workspace", "update-stale" }, words(run))
    assert.equal("/elsewhere/other", run.cwd)
  end)

  it("leads to the log up to the workspace's working copy", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("other") .. "other: kkk\n")
    action.run(jin, host, bufnr, "log", 1, 1)
    assert.equal([[jin:///repo;view=log#-r ::\"other\"@]], host.opened[1].name)
  end)

  -- As jj 0.46 prints a workspace whose name it shows quoted, through the
  -- template marker.wrap makes.
  local QUOTED = "\30" .. [["my qu'ote\"d" ]] .. '\31"my qu\'ote\\"d": kkk\n'

  it("names a workspace whose name jj would not take as a symbol", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, QUOTED)
    action.run(jin, host, bufnr, "show", 1, 1)
    action.run(jin, host, bufnr, "log", 1, 1)
    assert.same({ [["my qu'ote\"d"@]] }, bufname.parse(host.opened[1].name).argv)
    assert.same({ "-r", [[::"my qu'ote\"d"@]] }, bufname.parse(host.opened[2].name).argv)
  end)

  it("asks jj for the root of such a workspace by its name as it is", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, QUOTED)
    host.results = { ok("/elsewhere/q\n") }
    action.run(jin, host, bufnr, "cd", 1, 1)
    assert.same({ "workspace", "root", "--name", "my qu'ote\"d" }, words(host.runs[3]))
    assert.same({ { scope = "cd", path = "/elsewhere/q" } }, host.cds)
  end)

  it("writes a control character in a workspace name as an escape", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, "\30" .. [["a\tb\u001fc"]] .. "\31x\n")
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.same({ [["a\x09b\x1fc"@]] }, bufname.parse(host.opened[1].name).argv)
  end)
end)

describe("the conflicts view", function()
  it("lists the changes with conflicts, and the conflicted paths of each", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=conflicts#", m("kkk", "c1") .. "x\n")
    local w = words(host.runs[2])
    assert.equal("log", w[1])
    assert.same({ "-r", "conflicts()" }, { w[#w - 1], w[#w] })
    action.run(jin, host, bufnr, "files", 1, 1)
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.equal("jin:///repo;view=resolve#-r kkk", host.opened[1].name)
    assert.equal("jin:///repo;view=show#kkk", host.opened[2].name)
  end)
end)

describe("the resolve view", function()
  -- As jj resolve --list prints them; a path too long for the column is
  -- followed by a single space.
  local OUTPUT = table.concat({
    "f             2-sided conflict",
    "sp ace.txt    2-sided conflict including 1 deletion",
    "a_very_long_directory_name_here/and_a_long_file_name_too.txt 3-sided conflict",
    "",
  }, "\n")

  local function resolve(host, jin, name)
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok(OUTPUT))
    return bufnr
  end

  it("lists the conflicted paths of a change", function()
    local host, jin = setup()
    resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    assert.same({ "resolve", "--list", "-r", "kkk" }, words(host.runs[1]))
  end)

  it("opens the file itself when the change is the working copy", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "edit:split", 2, 2)
    assert.same({ "log", "--no-graph", "-r", "(kkk) & @", "-T", '"x"' }, words(host.runs[2]))
    assert.same(
      { name = "/repo/sp ace.txt", opener = "split" },
      { name = host.opened[1].name, opener = host.opened[1].opener }
    )
  end)

  it("opens the file view of the change when it is not the working copy", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    host.results = { ok(""), ok("") }
    action.run(jin, host, bufnr, "edit", 2, 2)
    action.run(jin, host, bufnr, "edit", 3, 3)
    assert.same({ "-r", "kkk", [[file:"sp ace.txt"]] }, bufname.parse(host.opened[1].name).argv)
    assert.same(
      { "-r", "kkk", "a_very_long_directory_name_here/and_a_long_file_name_too.txt" },
      bufname.parse(host.opened[2].name).argv
    )
  end)

  it("puts the cursor on the first conflict of the file itself", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    host.contents["/repo/sp ace.txt"] = { "a", "<<<<<<< conflict 1 of 1", "b" }
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "edit", 2, 2)
    assert.equal(2, host.cursors[host.buffer_bufnr("/repo/sp ace.txt")])
  end)

  it("puts the cursor on the first conflict of the file view", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    host.results = { ok("") }
    action.run(jin, host, bufnr, "edit", 1, 1)
    local file = assert(host.buffer_bufnr(host.opened[1].name))
    view.read(jin, host, file, host.opened[1].name)
    host.finish(ok("a\nb\n<<<<<<<<<<< conflict 1 of 1\nc\n"))
    host.finish(ok(""))
    assert.equal(3, host.cursors[file])
  end)

  it("never takes the working copy for the files of an earlier operation", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#--at-op op1 -r kkk")
    action.run(jin, host, bufnr, "edit", 1, 1)
    assert.equal(1, #host.runs)
    assert.equal("jin:///repo;view=file#--at-op op1 -r kkk f", host.opened[1].name)
  end)

  it("shows the diff of the path in the change", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    action.run(jin, host, bufnr, "diff", 2, 2)
    assert.same(
      { "-r", "kkk", "--", [[file:"sp ace.txt"]] },
      bufname.parse(host.opened[1].name).argv
    )
  end)

  it("tells why a line without a path offers nothing", function()
    local host, jin = setup()
    local bufnr = resolve(host, jin, "jin:///repo;view=resolve#-r kkk")
    assert.has_error(function()
      action.run(jin, host, bufnr, "edit", 4, 4)
    end, "jin: no path on this line")
  end)
end)

describe("the conflicts view narrowed by the user's revisions", function()
  local function revs(argv_text)
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=conflicts#" .. argv_text, "")
    local w = words(host.runs[2])
    local found = {}
    for i, word in ipairs(w) do
      if word == "-r" then
        found[#found + 1] = w[i + 1]
      end
    end
    return found, w
  end

  it("intersects every -r given with conflicts()", function()
    assert.same({ "conflicts() & ((main..@) | (x))" }, revs("-r main..@ --revisions=x"))
    assert.same({ "conflicts() & ((a))" }, (revs("-ra")))
  end)

  it("keeps the other arguments, and paths after --", function()
    local _, w = revs("--no-graph -r a -- -r")
    assert.same({ "--no-graph", "--", "-r" }, { w[#w - 2], w[#w - 1], w[#w] })
  end)

  it("leaves the value of a global option alone, even one that looks like -r", function()
    local found, w = revs("-R -rdir --at-op op1")
    assert.same({ "conflicts()" }, found)
    assert.same({ "-R", "-rdir", "--at-op", "op1" }, { w[#w - 3], w[#w - 2], w[#w - 1], w[#w] })
  end)
end)

describe(":JinCd", function()
  it("changes to the root of the current workspace", function()
    local host, jin = setup({ cwd = "/repo/sub", dirs = { "/repo/.jj" } })
    cd.run(jin, host, "lcd")
    assert.same({ { scope = "lcd", path = "/repo" } }, host.cds)
  end)

  it("says so outside any workspace", function()
    local host, jin = setup({ cwd = "/tmp" })
    assert.has_error(function()
      cd.run(jin, host, "cd")
    end, "jin: not in a jj workspace")
  end)
end)

describe("jin.component", function()
  local US = string.char(31)
  local CHANGE = table.concat({ "kk", "feat: x", "", "conflict", "", "default@ other@" }, US)
    .. "\n"
  local BOOKMARKS = "main\n"
    .. table.concat({ "main@origin", "2", "0" }, US)
    .. "\n"
    .. table.concat({ "side@origin", "0", "0" }, US)
    .. "\n"

  ---Read a component, as a statusline would, and let the refresh it
  ---schedules start.
  local function start(jin, host)
    component.get(jin, host, "change")
    host.fire_timers()
  end

  it("schedules one refresh however often it is read before that starts", function()
    local host, jin = setup()
    for _ = 1, 5 do
      component.get(jin, host, "change")
    end
    assert.equal(1, #host.timers)
  end)

  it("leaves a workspace alone on buffer switches until a component is read", function()
    local host, jin = setup()
    component.touch(jin, host, true)
    assert.same({}, host.runs)
    start(jin, host)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    component.touch(jin, host, true)
    assert.equal(4, #host.runs)
  end)

  it("reads nothing at first, and schedules a refresh", function()
    local host, jin = setup()
    assert.equal("", component.get(jin, host, "change"))
    assert.same({}, host.runs)
    host.fire_timers()
    assert.equal(2, #host.runs)
  end)

  it("asks jj without snapshotting the working copy or adding an operation", function()
    local host, jin = setup()
    start(jin, host)
    assert.same(
      { "--at-op=@", "--ignore-working-copy", "log" },
      { words(host.runs[1])[1], words(host.runs[1])[2], words(host.runs[1])[3] }
    )
    assert.same(
      { "--at-op=@", "--ignore-working-copy", "bookmark" },
      { words(host.runs[2])[1], words(host.runs[2])[2], words(host.runs[2])[3] }
    )
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("shows what the refresh found, and fires JinComponentPost when it changed", function()
    local host, jin = setup()
    start(jin, host)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    assert.same({ "JinComponentPost" }, host.events)
    assert.equal("kk", component.get(jin, host, "change"))
    assert.equal("feat: x", component.get(jin, host, "description"))
    assert.equal("conflict", component.get(jin, host, "state"))
    assert.equal("main", component.get(jin, host, "bookmarks"))
    assert.equal("main@origin↑2", component.get(jin, host, "traffic"))
    assert.equal("default@ other@", component.get(jin, host, "workspace"))
    assert.equal("", component.get(jin, host, "nope"))
  end)

  it("does not fire JinComponentPost when nothing changed", function()
    local host, jin = setup()
    start(jin, host)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    component.touch(jin, host, true)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    assert.same({ "JinComponentPost" }, host.events)
  end)

  it(
    "leaves fresh values to buffer switches and jj commands, refreshing on read once old",
    function()
      local host, jin = setup()
      start(jin, host)
      host.finish(ok(CHANGE))
      host.finish(ok(BOOKMARKS))
      host.clock = host.clock + 5000
      component.get(jin, host, "change")
      host.fire_timers()
      assert.equal(2, #host.runs)
      host.clock = host.clock + 60000
      component.get(jin, host, "change")
      host.fire_timers()
      assert.equal(4, #host.runs)
    end
  )

  it("looks for the workspace once per buffer and directory, until a buffer switch", function()
    local host, jin = setup()
    component.get(jin, host, "change")
    local first = host.dir_lookups
    assert.truthy(first > 0)
    component.get(jin, host, "change")
    assert.equal(first, host.dir_lookups)
    host.state.cwd = "/repo/sub"
    component.get(jin, host, "change")
    assert.truthy(host.dir_lookups > first)
    local before_touch = host.dir_lookups
    component.touch(jin, host)
    assert.truthy(host.dir_lookups > before_touch)
  end)

  it("refreshes once more when jj changed the repository during a refresh", function()
    local host, jin = setup()
    start(jin, host)
    component.touch(jin, host, true)
    assert.equal(2, #host.runs)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    assert.equal(4, #host.runs)
    host.finish(ok(table.concat({ "zz", "", "", "", "", "" }, US) .. "\n"))
    host.finish(ok(""))
    assert.equal("zz", component.get(jin, host, "change"))
    assert.equal(4, #host.runs)
  end)

  it("refreshes once for buffer switches in quick succession, unless forced", function()
    local host, jin = setup()
    start(jin, host)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    component.touch(jin, host)
    assert.equal(2, #host.runs)
    component.touch(jin, host, true)
    assert.equal(4, #host.runs)
  end)

  it("shows nothing outside any workspace, and nothing for a failed query", function()
    local host, jin = setup({ cwd = "/tmp" })
    assert.equal("", component.get(jin, host, "change"))
    host.fire_timers()
    assert.same({}, host.runs)
    local host2, jin2 = setup()
    start(jin2, host2)
    host2.finish({ code = 1, stdout = "", stderr = "Error\n" })
    host2.finish({ code = 1, stdout = "", stderr = "Error\n" })
    assert.equal("", component.get(jin2, host2, "change"))
  end)

  it("shows nothing once a refresh fails, rather than what an earlier one found", function()
    local host, jin = setup()
    start(jin, host)
    host.finish(ok(CHANGE))
    host.finish(ok(BOOKMARKS))
    component.touch(jin, host, true)
    host.finish({ code = 1, stdout = "", stderr = "Error: no\n" })
    host.finish({ code = 1, stdout = "", stderr = "Error: no\n" })
    assert.equal(4, #host.runs)
    assert.equal("", component.get(jin, host, "change"))
  end)

  describe("when concurrent jj commands left the operation log diverged", function()
    local DIVERGED = {
      code = 1,
      stdout = "",
      stderr = 'Error: The "@" expression resolved to more than one operation\n'
        .. "Hint: Try specifying one of the operations by ID: 351b00d02c20, 32db5820c7cd\n",
    }

    ---Let the refresh fail on the diverged operation log.
    local function diverge(jin, host)
      start(jin, host)
      host.finish(DIVERGED)
      host.finish(DIVERGED)
    end

    it("asks each operation head when it ended, without merging them", function()
      local host, jin = setup()
      diverge(jin, host)
      assert.equal(4, #host.runs)
      for i, id in ipairs({ "351b00d02c20", "32db5820c7cd" }) do
        local w = words(host.runs[2 + i])
        assert.same({ "--at-op=" .. id, "--ignore-working-copy", "op", "log" }, {
          w[1],
          w[2],
          w[3],
          w[4],
        })
        assert.equal("/repo", host.runs[2 + i].cwd)
      end
    end)

    it("reads the components at the head that ended last", function()
      local host, jin = setup()
      diverge(jin, host)
      host.finish(ok("1792168697.607"))
      host.finish(ok("1792168699.561"))
      assert.equal(6, #host.runs)
      assert.same(
        { "--at-op=32db5820c7cd", "--ignore-working-copy", "log" },
        { words(host.runs[5])[1], words(host.runs[5])[2], words(host.runs[5])[3] }
      )
      assert.same(
        { "--at-op=32db5820c7cd", "--ignore-working-copy", "bookmark" },
        { words(host.runs[6])[1], words(host.runs[6])[2], words(host.runs[6])[3] }
      )
    end)

    it("shows what that head holds, firing JinComponentPost once", function()
      local host, jin = setup()
      diverge(jin, host)
      host.finish(ok("1792168699.607"))
      host.finish(ok("1792168697.561"))
      host.finish(ok(CHANGE))
      host.finish(ok(BOOKMARKS))
      assert.equal("--at-op=351b00d02c20", words(host.runs[5])[1])
      assert.equal("kk", component.get(jin, host, "change"))
      assert.equal("main@origin↑2", component.get(jin, host, "traffic"))
      assert.same({ "JinComponentPost" }, host.events)
      assert.equal(6, #host.runs)
    end)

    it("shows nothing when no head says when it ended", function()
      local host, jin = setup()
      diverge(jin, host)
      host.finish({ code = 1, stdout = "", stderr = "Error\n" })
      host.finish({ code = 1, stdout = "", stderr = "Error\n" })
      assert.equal(4, #host.runs)
      assert.equal("", component.get(jin, host, "change"))
    end)

    it("does not look for heads again when the chosen head fails too", function()
      local host, jin = setup()
      diverge(jin, host)
      host.finish(ok("1"))
      host.finish(ok("2"))
      host.finish(DIVERGED)
      host.finish(DIVERGED)
      assert.equal(6, #host.runs)
      assert.equal("", component.get(jin, host, "change"))
    end)
  end)

  it("does not look for heads when jj failed for another reason", function()
    local host, jin = setup()
    start(jin, host)
    host.finish({ code = 1, stdout = "", stderr = "Error: There is no jj repo\n" })
    host.finish({ code = 1, stdout = "", stderr = "Error: There is no jj repo\n" })
    assert.equal(2, #host.runs)
  end)

  it("does not look for a workspace on buffer switches before any component is read", function()
    local host, jin = setup()
    component.touch(jin, host)
    component.touch(jin, host, true)
    assert.equal(0, host.dir_lookups)
  end)

  it("finds a workspace made after a component was read outside any", function()
    local host, jin = setup({ cwd = "/repo", dirs = { "/repo" } })
    assert.equal("", component.get(jin, host, "change"))
    host.dirs["/repo/.jj"] = true
    component.touch(jin, host, true)
    assert.equal(2, #host.runs)
  end)
end)
