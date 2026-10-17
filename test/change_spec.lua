local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")

local function ok(stdout, stderr)
  return { code = 0, stdout = stdout or "", stderr = stderr or "" }
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

local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

local LOG = "jin:///repo;view=log#"
local OUTPUT = m("kkk", "c1", "-") .. "x\n" .. m("zzz", "c2", "-") .. "y\n"

-- What jj answers when asked for the latest versions of the changes shown.
local FRESH = ok("kkk c1\nzzz c2\n")

---What jj ran last.
local function last(host)
  return words(host.runs[#host.runs])
end

---A log showing kkk on line 1 and zzz on line 2.
local function log(host, jin, name)
  name = name or LOG
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok("tpl\n"))
  host.finish(ok(OUTPUT))
  host.results = { FRESH }
  return bufnr
end

describe("new", function()
  it("creates a change on top of the change of the line", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "new", 1, 1)
    assert.same({ "new", "kkk" }, last(host))
    host.finish(ok("", "Working copy now at: xxx\n"))
    assert.same({}, host.messages)
  end)

  it("takes a change once when several lines selected name it, as annotate's do", function()
    local host, jin = setup()
    local name = "jin:///repo;view=log#"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-") .. "x\n" .. m("kkk", "c1", "-") .. "y\n"))
    action.run(jin, host, bufnr, "new", 1, 2)
    assert.same({ "new", "kkk" }, words(host.runs[#host.runs]))
  end)

  it("merges the changes of every line selected", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "new", 1, 2)
    assert.same({ "new", "kkk", "zzz" }, last(host))
    host.finish(ok())
  end)
end)

describe("edit", function()
  it("makes the change of the line the working copy", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "edit", 2, 2)
    assert.same({ "edit", "zzz" }, last(host))
  end)
end)

describe("abandon", function()
  it("abandons the changes of the lines once confirmed", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.confirms = { true }
    action.run(jin, host, bufnr, "abandon", 1, 2)
    assert.same({ "jin: abandon 2 changes?" }, host.asked)
    assert.same({ "abandon", "kkk", "zzz" }, last(host))
  end)

  it("abandons only the version of the line of a divergent change in the evolog", function()
    local host, jin = setup()
    local name = "jin:///repo;view=evolog#-r kkk"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "divergent") .. "x\n"))
    local asks_divergent = false
    for _, word in ipairs(words(host.runs[2])) do
      asks_divergent = asks_divergent or word:find("commit.divergent()", 1, true) ~= nil
    end
    assert.is_true(asks_divergent)
    host.confirms = { true }
    action.run(jin, host, bufnr, "abandon", 1, 1)
    assert.same({ "abandon", "c1" }, words(host.runs[#host.runs]))
  end)

  it("does nothing unless confirmed", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "abandon", 1, 1)
    assert.same({ "jin: abandon 1 change?" }, host.asked)
    assert.equal("log", last(host)[1])
  end)
end)

describe("undo and redo", function()
  it("undo the latest operation without asking, as u undoes in Vim", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "undo", 1, 1)
    assert.same({}, host.asked)
    assert.same({ "undo" }, last(host))
  end)

  it("redo the operation last undone without asking", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "redo", 1, 1)
    assert.same({}, host.asked)
    assert.same({ "redo" }, last(host))
  end)

  it("are there in every view, a line naming nothing included", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;view=status#")
    view.read(jin, host, bufnr, "jin:///repo;view=status#")
    host.finish(ok("tpl\n"))
    host.finish(ok("The working copy has no changes.\n"))
    action.run(jin, host, bufnr, "undo", 1, 1, { key = true })
    assert.same({ "undo" }, words(host.runs[#host.runs]))
    action.run(jin, host, bufnr, "redo", 1, 1, { key = true })
    assert.same({ "redo" }, words(host.runs[#host.runs]))
  end)
end)

describe("changing the repository", function()
  it("never runs in a view at an earlier operation", function()
    for _, name in ipairs({ "new", "edit", "abandon", "undo", "redo" }) do
      local host, jin = setup()
      local bufnr = log(host, jin, "jin:///repo;view=log#--at-op op1")
      host.confirms = { true }
      assert.has_error(function()
        action.run(jin, host, bufnr, name, 1, 1)
      end, "jin: this view shows an earlier operation, which is not to be changed")
      assert.equal(2, #host.runs)
    end
  end)
end)

describe("actions on the selected changes", function()
  local selection = require("jin.selection")

  local function described(rev)
    return { "log", "--no-graph", "-r", rev, "-T", "description" }
  end

  it("squash a change into its parent, with both descriptions, with nothing selected", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { FRESH, ok("parent\n"), ok("child\n") }
    action.run(jin, host, bufnr, "squash", 1, 1)
    assert.same(described("kkk-"), words(host.runs[4]))
    assert.same(described("kkk"), words(host.runs[5]))
    assert.same({ "squash", "-r", "kkk", "-m", "parent\n\nchild\n" }, last(host))
  end)

  it("squash the changes of the lines into the selected change, and clear the selection", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz" })
    host.results = { FRESH, ok("into\n"), ok("") }
    action.run(jin, host, bufnr, "squash", 1, 1)
    assert.same(
      { "squash", "--from", "kkk", "--into", "zzz", "-m", "into\n" },
      words(host.runs[#host.runs])
    )
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
  end)

  it("refuse to squash into several selected changes", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz", "yyy" })
    assert.has_error(function()
      action.run(jin, host, bufnr, "squash", 1, 1)
    end, "jin: squash takes one selected change to squash into, but 2 are selected")
  end)

  it("rebase the changes of the lines, with their descendants, onto the selected ones", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz" })
    action.run(jin, host, bufnr, "rebase", 1, 1)
    assert.same({ "rebase", "-s", "kkk", "-o", "zzz" }, last(host))
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
  end)

  it(
    "keep the selection while jj runs, and when it fails, for the action to be tried again",
    function()
      local host, jin = setup()
      local bufnr = log(host, jin)
      selection.toggle(host, "/repo", { "zzz" })
      action.run(jin, host, bufnr, "rebase", 1, 1)
      assert.same({ "zzz" }, selection.list(host, "/repo"))
      host.finish({ code = 1, stdout = "", stderr = "Error: cycle\n" })
      assert.same({ "zzz" }, selection.list(host, "/repo"))
    end
  )

  it("leave out only the changes they took, keeping those selected while jj ran", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz" })
    action.run(jin, host, bufnr, "rebase", 1, 1)
    selection.toggle(host, "/repo", { "yyy" })
    host.finish(ok())
    assert.same({ "yyy" }, selection.list(host, "/repo"))
  end)

  it("refuse to rebase with nothing selected to rebase onto", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    assert.has_error(function()
      action.run(jin, host, bufnr, "rebase", 1, 1)
    end, "jin: select the change to rebase onto first")
  end)

  it("merge the changes of the lines with the selected ones in a new change", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz" })
    action.run(jin, host, bufnr, "new", 1, 1)
    assert.same({ "new", "kkk", "zzz" }, last(host))
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
  end)

  it("put the selected changes in after or before the change of the line", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    selection.toggle(host, "/repo", { "zzz" })
    action.run(jin, host, bufnr, "put:after", 1, 1)
    assert.same({ "rebase", "-r", "zzz", "--insert-after", "kkk" }, last(host))
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
    selection.toggle(host, "/repo", { "zzz" })
    host.results = { FRESH }
    action.run(jin, host, bufnr, "put:before", 1, 1)
    assert.same({ "rebase", "-r", "zzz", "--insert-before", "kkk" }, last(host))
  end)

  it("refuse to put with nothing selected to put there", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    assert.has_error(function()
      action.run(jin, host, bufnr, "put:after", 1, 1)
    end, "jin: select the changes to put here first")
  end)
end)

describe("more changes", function()
  local selection = require("jin.selection")

  local function run(name, first, final, prepare)
    local host, jin = setup()
    local bufnr = log(host, jin)
    if prepare then
      prepare(host)
    end
    action.run(jin, host, bufnr, name, first, final or first)
    return words(host.runs[#host.runs]), host
  end

  it("duplicate the changes of the lines", function()
    assert.same({ "duplicate", "kkk", "zzz" }, (run("duplicate", 1, 2)))
  end)

  it(
    "revert the changes of the lines on top of the working copy, or of the selected one",
    function()
      assert.same({ "revert", "-r", "kkk", "-o", "@" }, (run("revert", 1)))
      local argv, host = run("revert", 1, 1, function(h)
        selection.toggle(h, "/repo", { "zzz" })
      end)
      assert.same({ "revert", "-r", "kkk", "-o", "zzz" }, argv)
      host.finish(ok())
      assert.same({}, selection.list(host, "/repo"))
    end
  )

  it("absorb the change of the line into the changes below it", function()
    assert.same({ "absorb", "--from", "kkk" }, (run("absorb", 1)))
  end)

  it("parallelize the changes of the lines", function()
    assert.same({ "parallelize", "kkk", "zzz" }, (run("parallelize", 1, 2)))
  end)

  it("set a bookmark, named when asked, to the change of the line", function()
    local argv = run("bookmark", 1, 1, function(h)
      h.answers = { "my topic" }
    end)
    assert.same({ "bookmark", "set", "my topic", "-r", "kkk" }, argv)
  end)

  it("set no bookmark when no name is given", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    action.run(jin, host, bufnr, "bookmark", 1, 1)
    assert.equal("log", last(host)[1])
  end)

  it("move the working copy to the next or the previous change", function()
    assert.same({ "next" }, (run("next", 1)))
    assert.same({ "prev" }, (run("prev", 1)))
  end)

  it("move the working copy by editing the next or the previous change", function()
    assert.same({ "next", "--edit" }, (run("next:edit", 1)))
    assert.same({ "prev", "--edit" }, (run("prev:edit", 1)))
  end)

  it("insert a new change after or before the changes of the lines", function()
    assert.same(
      { "new", "--insert-after", "kkk", "--insert-after", "zzz" },
      (run("new:after", 1, 2))
    )
    assert.same({ "new", "--insert-before", "kkk" }, (run("new:before", 1)))
  end)

  it(
    "rebase only the changes of the lines, or their whole branch, onto the selected ones",
    function()
      local function selected(h)
        selection.toggle(h, "/repo", { "zzz" })
      end
      assert.same({ "rebase", "-r", "kkk", "-o", "zzz" }, (run("rebase:revisions", 1, 1, selected)))
      assert.same({ "rebase", "-b", "kkk", "-o", "zzz" }, (run("rebase:branch", 1, 1, selected)))
    end
  )

  it("rebase only the changes of the lines after or before the selected ones", function()
    local function selected(h)
      selection.toggle(h, "/repo", { "zzz" })
    end
    local argv, host = run("rebase:after", 1, 1, selected)
    assert.same({ "rebase", "-r", "kkk", "--insert-after", "zzz" }, argv)
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
    assert.same(
      { "rebase", "-r", "kkk", "--insert-before", "zzz" },
      (run("rebase:before", 1, 1, selected))
    )
  end)

  it("restore the repository to the operation of the line, once confirmed", function()
    local host, jin = setup()
    local name = "jin:///repo;view=oplog#"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("op1") .. "describe\n"))
    action.run(jin, host, bufnr, "restore", 1, 1)
    assert.equal(2, #host.runs)
    host.confirms = { true }
    action.run(jin, host, bufnr, "restore", 1, 1)
    assert.same(
      { "jin: restore the repository to op1?", "jin: restore the repository to op1?" },
      host.asked
    )
    assert.same({ "op", "restore", "op1" }, words(host.runs[3]))
  end)
end)

describe("a change from a view read before the change was rewritten", function()
  local CURRENT =
    { "log", "--no-graph", "-r", "kkk", "-T", 'change_id ++ " " ++ commit_id ++ "\\n"' }

  it("runs when the line still shows the latest version", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { ok("kkk c1\n") }
    action.run(jin, host, bufnr, "edit", 1, 1, { key = true })
    assert.same(CURRENT, words(host.runs[3]))
    assert.same({ "edit", "kkk" }, words(host.runs[4]))
  end)

  it("does not run, and reads the view again, when the change was rewritten since", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { ok("kkk c9\n") }
    assert.has_error(function()
      action.run(jin, host, bufnr, "edit", 1, 1, { key = true })
    end, "jin: kkk changed since the view was read, so it is read again; look before acting again")
    assert.equal(4, #host.runs)
    assert.same("log", words(host.runs[4])[1])
  end)
end)
