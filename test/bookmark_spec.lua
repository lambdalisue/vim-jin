local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local selection = require("jin.selection")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

local NAME = "jin:///repo;view=bookmark#"
-- A local bookmark, a remote one, and a local one whose name globs.
local OUTPUT = "\30"
  .. [["main" ""]]
  .. "\31main: kkk one\n"
  .. "\30"
  .. [["main" "origin"]]
  .. "\31  @origin: zzz\n"
  .. "\30"
  .. [["ma*in" ""]]
  .. '\31"ma*in": kkk\n'

---Run action `name` on lines `first` to `last` of the bookmark view, and
---return what jj ran last.
local function run(name, first, last, prepare)
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  local bufnr = host.load(NAME)
  view.read(jin, host, bufnr, NAME)
  host.finish(ok("tpl\n"))
  host.finish(ok(OUTPUT))
  if prepare then
    prepare(host)
  end
  action.run(jin, host, bufnr, name, first, last or first)
  return words(host.runs[#host.runs]), host
end

describe("the bookmark view", function()
  it("deletes the local bookmarks or forgets the bookmarks of the lines, by exact name", function()
    local argv, host = run("delete", 1, 3, function(h)
      h.confirms = { true }
    end)
    assert.same({ "jin: delete 2 bookmarks?" }, host.asked)
    assert.same({ "bookmark", "delete", 'exact:"main"', 'exact:"ma*in"' }, argv)
    assert.same(
      { "bookmark", "forget", 'exact:"main"', "--include-remotes" },
      (run("forget", 1, 2))
    )
  end)

  it("deletes nothing unless confirmed", function()
    local argv, host = run("delete", 1)
    assert.same({ "jin: delete 1 bookmark?" }, host.asked)
    assert.equal("list", argv[2])
  end)

  it("deletes no remote bookmark, which goes once the deletion is pushed", function()
    assert.has_error(function()
      run("delete", 2)
    end, "jin: main@origin is a remote bookmark; delete the local one and push it")
  end)

  it("tracks or untracks the remote bookmarks of the lines", function()
    assert.same({ "bookmark", "track", '"main"@"origin"' }, (run("track", 1, 3)))
    assert.same({ "bookmark", "untrack", '"main"@"origin"' }, (run("untrack", 2)))
    assert.has_error(function()
      run("track", 1)
    end, "jin: main is a local bookmark; track a remote one")
  end)

  it("moves the bookmark of the line to the selected change, wherever it is", function()
    local argv, host = run("move", 1, 1, function(h)
      selection.toggle(h, "/repo", { "yyy" })
    end)
    assert.same({ "bookmark", "move", 'exact:"main"', "--to", "yyy", "--allow-backwards" }, argv)
    host.finish(ok())
    assert.same({}, selection.list(host, "/repo"))
    assert.has_error(function()
      run("move", 1)
    end, "jin: select the change to move the bookmark to first")
    local selected
    assert.has_error(function()
      run("move", 1, 1, function(h)
        selected = h
        selection.toggle(h, "/repo", { "yyy", "xxx" })
      end)
    end, "jin: move takes one selected change to move the bookmark to, but 2 are selected")
    assert.same(2, #selection.list(selected, "/repo"))
  end)
end)
