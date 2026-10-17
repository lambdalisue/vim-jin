local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")

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

local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

local NAME = "jin:///repo;view=arrange#"
-- c on b on a on base, newest first, as the view lists them.
local LISTED = "ccc third\nbbb second\naaa first\n"
-- What jj answers for the shape of the line: each change, whether it is
-- divergent, and its parents.
local SHAPE = "ccc - bbb\nbbb - aaa\naaa - base\n"
-- What jj answers for the line as the buffer was read, when it has not moved.
local NOW = "ccc\nbbb\naaa\n"

local function read(host, jin, name)
  name = name or NAME
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok(LISTED))
  return bufnr
end

---The jj runs from `first` on, as lists of words.
local function runs_from(host, first)
  local all = {}
  for i = first, #host.runs do
    all[#all + 1] = words(host.runs[i])
  end
  return all
end

describe("the arrange buffer", function()
  it("lists the mutable ancestors of the working copy, newest first, to be edited", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    local argv = words(host.runs[1])
    assert.same({ "log", "--no-graph", "-T" }, { argv[1], argv[2], argv[3] })
    assert.same({ "-r", "::@ & mutable()" }, { argv[5], argv[6] })
    assert.same({ "ccc third", "bbb second", "aaa first" }, host.rendered[bufnr].lines)
    assert.is_true(host.rendered[bufnr].editable)
  end)

  it("lists the revisions given instead", function()
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=arrange#-r a|b")
    local argv = words(host.runs[1])
    assert.same({ "-r", "(a|b)" }, { argv[5], argv[6] })
  end)

  it("rebases the changes into the order of the lines, the descendants moving along", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
    host.results = { ok(NOW), ok(SHAPE), ok("www - ccc\n") }
    local first = #host.runs + 1
    view.write(jin, host, bufnr)
    for _ = 1, 4 do
      host.finish(ok())
    end
    assert.same({
      { "log", "--no-graph", "-T", host.runs[first].argv[8], "-r", "::@ & mutable()" },
      { "log", "--no-graph", "-r", "aaa|ccc|bbb", "-T", host.runs[first + 1].argv[10] },
      {
        "log",
        "--no-graph",
        "-r",
        "children(aaa|ccc|bbb) ~ (aaa|ccc|bbb)",
        "-T",
        host.runs[first + 2].argv[10],
      },
      { "rebase", "-r", "aaa", "-o", "base" },
      { "rebase", "-r", "ccc", "-o", "aaa" },
      { "rebase", "-r", "bbb", "-o", "ccc" },
      { "rebase", "-s", "www", "-o", "bbb" },
    }, runs_from(host, first))
    assert.is_true(host.saved[bufnr])
  end)

  it("keeps the other parents of a merge on the top change", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
    host.results = { ok(NOW), ok(SHAPE), ok("mmm - xxx ccc\n") }
    view.write(jin, host, bufnr)
    for _ = 1, 3 do
      host.finish(ok())
    end
    assert.same({ "rebase", "-s", "mmm", "-o", "xxx", "-o", "bbb" }, words(host.runs[#host.runs]))
  end)

  it("compares the next write with the order it wrote", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
    host.results = { ok(NOW), ok(SHAPE), ok("") }
    view.write(jin, host, bufnr)
    for _ = 1, 3 do
      host.finish(ok())
    end
    host.contents[NAME] = { "ccc third", "bbb second", "aaa first" }
    host.results = { ok("bbb\nccc\naaa\n"), ok("bbb - ccc\nccc - aaa\naaa - base\n"), ok("") }
    local before = #host.runs
    view.write(jin, host, bufnr)
    assert.equal(before + 4, #host.runs)
    assert.same({ "rebase", "-r", "aaa", "-o", "base" }, words(host.runs[before + 4]))
  end)

  it("refuses to write from a line that moved since it was read, changing nothing", function()
    for _, now in ipairs({
      -- Reordered meanwhile, as by a rebase from the log.
      "ccc\naaa\nbbb\n",
      -- A change added in it, as by a split.
      "ccc\nddd\nbbb\naaa\n",
      -- One gone from it, as by an abandon.
      "ccc\naaa\n",
    }) do
      local host, jin = setup()
      local bufnr = read(host, jin)
      host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
      host.results = { ok(now), ok(SHAPE), ok("") }
      local before = #host.runs
      assert.has_error(function()
        view.write(jin, host, bufnr)
      end, "jin: the changes moved since this buffer was read; :edit to read them again")
      assert.equal(before + 1, #host.runs)
      assert.is_nil(host.saved[bufnr])
    end
  end)

  it("arranges nothing in a view at an earlier operation", function()
    local host, jin = setup()
    local name = "jin:///repo;view=arrange#--at-op abc"
    local bufnr = read(host, jin, name)
    host.contents[name] = { "bbb second", "ccc third", "aaa first" }
    local before = #host.runs
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: this view shows an earlier operation, which is not to be changed")
    assert.equal(before, #host.runs)
  end)

  it("stops at the first rebase jj refuses", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
    host.results = { ok(NOW), ok(SHAPE), ok("") }
    local first = #host.runs + 1
    view.write(jin, host, bufnr)
    host.finish({ code = 1, stdout = "", stderr = "Error: immutable\n" })
    assert.equal(first + 3, #host.runs)
    assert.is_nil(host.saved[bufnr])
  end)

  it("runs nothing when the order is the same", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[NAME] = { "ccc third, retitled", "bbb", "aaa first" }
    local before = #host.runs
    view.write(jin, host, bufnr)
    assert.equal(before, #host.runs)
    assert.is_true(host.saved[bufnr])
  end)

  it("refuses lines added or removed, as it only reorders", function()
    for _, lines in ipairs({
      { "ccc third", "aaa first" },
      { "ccc third", "bbb second", "aaa first", "ddd fourth" },
      { "ccc third", "ccc again", "aaa first" },
    }) do
      local host, jin = setup()
      local bufnr = read(host, jin)
      host.contents[NAME] = lines
      assert.has_error(
        function()
          view.write(jin, host, bufnr)
        end,
        "jin: reorder the lines only: every change listed stays, once; abandon or add changes from a view"
      )
    end
  end)

  it("refuses changes that are not one line", function()
    for _, case in ipairs({
      {
        "ccc - bbb\nbbb - aaa\naaa - base other\n",
        "",
        "jin: aaa is a merge; arrange takes a line of changes",
      },
      {
        "ccc - aaa\nbbb - aaa\naaa - base\n",
        "",
        "jin: the changes listed are not one line; arrange takes changes each on the one before",
      },
      {
        "ccc - bbb\nbbb divergent aaa\naaa - base\n",
        "",
        "jin: bbb is divergent; arrange takes a line of changes",
      },
      {
        SHAPE,
        "www - bbb\n",
        "jin: bbb has www on it outside the list; take it in, or leave bbb out",
      },
    }) do
      local host, jin = setup()
      local bufnr = read(host, jin)
      host.contents[NAME] = { "bbb second", "ccc third", "aaa first" }
      host.results = { ok(NOW), ok(case[1]), ok(case[2]) }
      local before = #host.runs
      assert.has_error(function()
        view.write(jin, host, bufnr)
      end, case[3])
      for i = before + 1, #host.runs do
        assert.are_not.equal("rebase", words(host.runs[i])[1])
      end
    end
  end)
end)
