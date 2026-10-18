local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local block = require("jin.view.block")

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

---A marker of annotate, carrying the content of the line.
local function mc(change, commit, content, divergent)
  return "\30"
    .. ('"%s" "%s" "%s" "%s\\n"'):format(change, commit, divergent and "divergent" or "-", content)
    .. "\31"
end

---The first lines of the blocks of the buffer `name` reads as `stdout`.
local function starts(name, stdout, with_template)
  local host, jin = setup()
  local bufnr = read(host, jin, name, stdout, with_template)
  local meta = assert(view.meta(host, bufnr))
  local of = view.get(meta.view).blocks
  return of and of(meta) or nil
end

describe("the blocks of a view", function()
  it("are the runs of lines one change wrote, in an annotation", function()
    local output = mc("kkk", "c1", "a")
      .. "kkk a\n"
      .. mc("kkk", "c1", "b")
      .. "kkk b\n"
      .. mc("zzz", "c9", "c")
      .. "zzz c\n"
      .. mc("kkk", "c1", "d")
      .. "kkk d\n"
    assert.same({ 1, 3, 4 }, starts("jin:///repo;view=annotate#a.lua", output, true))
  end)

  it("tell the commits of a divergent change apart, in an annotation", function()
    local output = mc("zzz", "c9", "a", true)
      .. "zzz a\n"
      .. mc("zzz", "c8", "b", true)
      .. "zzz b\n"
      .. mc("zzz", "c8", "c", true)
      .. "zzz c\n"
    assert.same({ 1, 2 }, starts("jin:///repo;view=annotate#a.lua", output, true))
  end)

  it("are the entries, each over its lines, in the views listing them", function()
    local two = "@  " .. m("aaa", "1") .. "x\n│  a\n○  " .. m("bbb", "2") .. "y\n│  b\n"
    for _, name in ipairs({
      "jin:///repo;view=log#",
      "jin:///repo;view=evolog#",
      "jin:///repo;view=oplog#",
      "jin:///repo;view=pick#",
      "jin:///repo;view=conflicts#",
    }) do
      assert.same({ 1, 3 }, starts(name, two, true), name)
    end
  end)

  it("start at no line that belongs to no entry, as the graph's notes", function()
    local output = "(elided revisions)\n@  "
      .. m("aaa", "1")
      .. "x\n│ ~\n○  "
      .. m("bbb", "2")
      .. "y\n"
    assert.same({ 2, 4 }, starts("jin:///repo;view=log#", output, true))
  end)

  local DIFF = table.concat({
    "Modified regular file a.txt:",
    "   1    1: a",
    "Added regular file b.txt:",
    "        1: b",
    "",
  }, "\n")

  it("are the files, in a diff and an interdiff", function()
    assert.same({ 1, 3 }, starts("jin:///repo;view=diff#", DIFF))
    assert.same({ 1, 3 }, starts("jin:///repo;view=interdiff#--from a --to b", DIFF))
  end)

  it("are the header of each change and its files, in a show", function()
    local output = m("aaa", "1", "-", "-")
      .. "Commit ID: 1\n"
      .. "    desc\n"
      .. "\n"
      .. DIFF
      .. m("bbb", "2", "-", "-")
      .. "Commit ID: 2\n"
      .. "Modified regular file c.txt:\n"
      .. "   1    1: c\n"
    assert.same({ 1, 4, 6, 8, 9 }, starts("jin:///repo;view=show#aaa | bbb", output, true))
  end)

  it("are none in a view of one thing a line", function()
    assert.is_nil(starts("jin:///repo;view=status#", "Working copy changes:\nM a.txt\n", true))
    assert.is_nil(starts("jin:///repo;view=bookmark#", m("main", "") .. "main: kkk\n", true))
    assert.is_nil(starts("jin:///repo;view=workspace#", m("default") .. "default: kkk\n", true))
    assert.is_nil(starts("jin:///repo;view=resolve#", "a.lua    2-sided conflict\n"))
  end)
end)

describe("jin.view.block.target", function()
  local STARTS = { 2, 5, 9 }

  it("is the first line of the next block", function()
    assert.equal(5, block.target(STARTS, 2, 1, true))
    assert.equal(5, block.target(STARTS, 3, 1, true))
    assert.equal(2, block.target(STARTS, 1, 1, true))
  end)

  it("is the first line of the block before the cursor's, or of its own from inside it", function()
    assert.equal(2, block.target(STARTS, 5, 1, false))
    assert.equal(5, block.target(STARTS, 7, 1, false))
  end)

  it("goes as many blocks as the count", function()
    assert.equal(9, block.target(STARTS, 2, 2, true))
    assert.equal(2, block.target(STARTS, 10, 3, false))
  end)

  it("stops at the last block a count goes past, as Vim's own motions stop", function()
    assert.equal(9, block.target(STARTS, 2, 5, true))
    assert.equal(2, block.target(STARTS, 9, 5, false))
  end)

  it("is none with no block that way", function()
    assert.is_nil(block.target(STARTS, 9, 1, true))
    assert.is_nil(block.target(STARTS, 12, 1, true))
    assert.is_nil(block.target(STARTS, 2, 1, false))
    assert.is_nil(block.target({}, 1, 1, true))
  end)
end)

describe("jin.view.move_block", function()
  local OUTPUT = "@  "
    .. m("aaa", "1")
    .. "x\n│  a\n○  "
    .. m("bbb", "2")
    .. "y\n│  b\n○  "
    .. m("ccc", "3")
    .. "z\n"

  it("jumps to the first line of the block the count leads to", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", OUTPUT, true)
    host.cursors[bufnr] = 2
    view.move_block(host, bufnr, true, 2)
    assert.same({ { bufnr = bufnr, lnum = 5 } }, host.jumps)
  end)

  it("jumps back as well", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", OUTPUT, true)
    host.cursors[bufnr] = 4
    view.move_block(host, bufnr, false, 1)
    assert.same({ { bufnr = bufnr, lnum = 3 } }, host.jumps)
  end)

  it("stays, leaving the jumplist alone, with no block that way", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#", OUTPUT, true)
    host.cursors[bufnr] = 5
    view.move_block(host, bufnr, true, 1)
    assert.same({}, host.jumps)
  end)

  it("stays in a view of no blocks, and before the buffer has been read", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=bookmark#", m("main", "") .. "main: k\n", true)
    view.move_block(host, bufnr, true, 1)
    local unread = host.load("jin:///repo;view=log#-r @")
    view.move_block(host, unread, true, 1)
    assert.same({}, host.jumps)
  end)
end)

describe("jin.view.block.keys", function()
  it("maps ]] and [[ in normal, visual and operator-pending mode in a view of blocks", function()
    local keys = {}
    for _, key in ipairs(block.keys(view.get("log"))) do
      keys[#keys + 1] = table.concat(key, " ")
    end
    table.sort(keys)
    assert.same({
      "[[ prev-block n",
      "[[ prev-block o",
      "[[ prev-block x",
      "]] next-block n",
      "]] next-block o",
      "]] next-block x",
    }, keys)
  end)

  it("maps none in a view of no blocks", function()
    assert.same({}, block.keys(view.get("status")))
  end)
end)
