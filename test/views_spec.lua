local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local bufname = require("jin.bufname")

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

---Load and read `name`, answering the template lookup (when the view wraps
---one) and then jj with `stdout`.
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

describe("the log view", function()
  local LOG = "jin:///repo;view=log#-r ::@"

  it("runs jj log without jj's own wrapping, keeping the user's arguments", function()
    local host, jin = setup()
    read(host, jin, LOG, "", true)
    local argv = host.runs[2].argv
    assert.same({ "log", "--config", "ui.log-word-wrap=false" }, { argv[5], argv[6], argv[7] })
    assert.same({ "-r", "::@" }, { argv[#argv - 1], argv[#argv] })
  end)

  it("opens the change of a line, by change ID, with show and diff", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, "@  " .. m("kkk", "c1") .. "x\n│  desc\n", true)
    action.run(jin, host, bufnr, "show:vsplit", 2, 2)
    action.run(jin, host, bufnr, "diff", 1, 1)
    assert.same({
      name = "jin:///repo;view=show#kkk",
      opener = "vsplit",
    }, { name = host.opened[1].name, opener = host.opened[1].opener })
    assert.equal("jin:///repo;view=diff#-r kkk", host.opened[2].name)
  end)

  it("names a divergent change by its commit ID", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("kkk", "c2", "divergent") .. "x\n", true)
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.equal("jin:///repo;view=show#c2", host.opened[1].name)
  end)

  it("names a hidden commit by its commit ID, as its change ID leads to the latest", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("kkk", "c2", "hidden") .. "x\n", true)
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.equal("jin:///repo;view=show#c2", host.opened[1].name)
  end)

  it("yanks the change or commit IDs of the lines", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, m("a", "1") .. "x\n" .. m("b", "2") .. "y\n", true)
    action.run(jin, host, bufnr, "yank:change", 1, 2)
    action.run(jin, host, bufnr, "yank:commit", 2, 2)
    assert.same({ "a\nb", "2" }, host.yanked)
  end)

  it("leads from a change to its evolog", function()
    local host, jin = setup()
    local bufnr =
      read(host, jin, LOG, m("kkk", "c1") .. "x\n" .. m("zzz", "c2", "divergent") .. "y\n", true)
    action.run(jin, host, bufnr, "evolog", 1, 1)
    action.run(jin, host, bufnr, "evolog:split", 2, 2)
    assert.equal("jin:///repo;view=evolog#-r kkk", host.opened[1].name)
    assert.same(
      { name = "jin:///repo;view=evolog#-r c2", opener = "split" },
      { name = host.opened[2].name, opener = host.opened[2].opener }
    )
  end)

  local TWO = "@  " .. m("aaa", "1") .. "x\n│  a\n○  " .. m("bbb", "2") .. "y\n│  b\n"

  it("highlights the lines of the change under the cursor once read", function()
    local host, jin = setup()
    local bufnr = host.load(LOG)
    host.cursors[bufnr] = 4
    view.read(jin, host, bufnr, LOG)
    host.finish(ok("tpl\n"))
    host.finish(ok(TWO))
    assert.same({ 3, 4 }, host.highlighted[bufnr])
  end)

  it("moves the highlight with the cursor", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, TWO, true)
    host.cursors[bufnr] = 2
    view.cursor_moved(host, bufnr)
    assert.same({ 1, 2 }, host.highlighted[bufnr])
    host.cursors[bufnr] = 3
    view.cursor_moved(host, bufnr)
    assert.same({ 3, 4 }, host.highlighted[bufnr])
  end)

  it("leaves the lines of the graph alone out of the change's highlight", function()
    local host, jin = setup()
    local output = "@  " .. m("aaa", "1") .. "x\n│  a\n│ ~  (elided revisions)\n~\n"
    local bufnr = read(host, jin, LOG, output, true)
    host.cursors[bufnr] = 1
    view.cursor_moved(host, bufnr)
    assert.same({ 1, 2 }, host.highlighted[bufnr])
    host.cursors[bufnr] = 4
    view.cursor_moved(host, bufnr)
    assert.is_false(host.highlighted[bufnr])
  end)

  it("highlights nothing on a line of no change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, LOG, "(elided)\n" .. TWO, true)
    host.cursors[bufnr] = 1
    view.cursor_moved(host, bufnr)
    assert.is_false(host.highlighted[bufnr])
  end)
end)

describe("the lines of the entry under the cursor", function()
  it("are highlighted in the operation log and the evolog too", function()
    for _, name in ipairs({ "jin:///repo;view=oplog#", "jin:///repo;view=evolog#" }) do
      local host, jin = setup()
      local bufnr = read(host, jin, name, m("a", "1") .. "x\n" .. m("b", "2") .. "y\n", true)
      host.cursors[bufnr] = 2
      view.cursor_moved(host, bufnr)
      assert.same({ 2, 2 }, host.highlighted[bufnr], name)
    end
  end)

  it("are not highlighted in views of one change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#@", m("a", "1") .. "x\ny\n", true)
    view.cursor_moved(host, bufnr)
    assert.is_nil(host.highlighted[bufnr])
  end)
end)

local DIFF_OUTPUT = table.concat({
  "Modified regular file keep.txt:",
  "   1    1: a",
  "   2     : b",
  "        2: B",
  "Modified regular file to.txt (from.txt => to.txt):",
  "   3    3: z",
  "",
}, "\n")

describe("the diff view", function()
  it("asks jj for its own color-words format", function()
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=diff#", DIFF_OUTPUT)
    local argv = host.runs[1].argv
    assert.same({ "diff", "--color-words" }, { argv[5], argv[6] })
  end)

  it("says, in gray beside an empty line, that no file changed", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", "")
    assert.same({ "" }, host.rendered[bufnr].lines)
    assert.equal("No file changed.", host.rendered[bufnr].annotations[1][1].text)
  end)

  it("folds each file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", DIFF_OUTPUT)
    assert.same({ { 1, 4 }, { 5, 6 } }, host.rendered[bufnr].folds)
  end)

  it("jumps from a line of the working copy to the file itself", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", DIFF_OUTPUT)
    action.run(jin, host, bufnr, "jump:split", 4, 4)
    assert.same({ name = "/repo/keep.txt", opener = "split" }, {
      name = host.opened[1].name,
      opener = host.opened[1].opener,
    })
    assert.equal(2, host.cursors[host.buffer_bufnr("/repo/keep.txt")])
  end)

  it("jumps to the old side of a removed line, as a file view of the parent", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", DIFF_OUTPUT)
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "jump", 3, 3)
    assert.equal("jin:///repo;view=file#-r @- keep.txt", host.opened[1].name)
  end)

  it("refuses the old side of a merge, which is no single revision", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#-r m", DIFF_OUTPUT)
    host.results = { ok("xx") }
    assert.has_error(
      function()
        action.run(jin, host, bufnr, "jump", 3, 3)
      end,
      "jin: m- is several revisions, such as the parents of a merge; jump to the new side instead"
    )
    local w = host.runs[2].argv
    assert.same({ "log", "--no-graph", "-r", "m-" }, { w[5], w[6], w[7], w[8] })
    assert.same({}, host.opened)
  end)

  it("uses the old path of a renamed file on the old side", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", DIFF_OUTPUT)
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "jump:old", 6, 6)
    assert.equal("jin:///repo;view=file#-r @- from.txt", host.opened[1].name)
  end)

  it("takes the sides from --from and --to", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#--from a --to b", DIFF_OUTPUT)
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "jump:new", 2, 2)
    action.run(jin, host, bufnr, "jump:old", 2, 2)
    assert.equal("jin:///repo;view=file#-r b keep.txt", host.opened[1].name)
    assert.equal("jin:///repo;view=file#-r a keep.txt", host.opened[2].name)
  end)

  it("tells why when a line shows no file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#", "\n" .. DIFF_OUTPUT)
    assert.has_error(function()
      action.run(jin, host, bufnr, "jump", 1, 1)
    end, "jin: no file on this line")
  end)

  it("jumps from the header of a removed file to the old side, where it still is", function()
    local host, jin = setup()
    local removed = "Removed regular file gone.txt:\n   1     : x\n"
    local bufnr = read(host, jin, "jin:///repo;view=diff#", removed)
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "jump", 1, 1)
    assert.equal("jin:///repo;view=file#-r @- gone.txt", host.opened[1].name)
  end)

  it("names a file whose path starts with - so that jj takes no option from it", function()
    local host, jin = setup()
    local bufnr =
      read(host, jin, "jin:///repo;view=diff#-r x", "Added regular file -n:\n        1: y\n")
    action.run(jin, host, bufnr, "jump", 2, 2)
    assert.equal([[jin:///repo;view=file#-r x file:\"-n\"]], host.opened[1].name)
  end)
end)

describe("the interdiff view", function()
  local NAME = "jin:///repo;view=interdiff#--from c2 --to c3"

  it("asks jj for its color-words format and folds each file", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, DIFF_OUTPUT)
    local argv = host.runs[1].argv
    assert.same({ "interdiff", "--color-words" }, { argv[5], argv[6] })
    assert.same({ { 1, 4 }, { 5, 6 } }, host.rendered[bufnr].folds)
  end)

  it("says, in gray beside an empty line, that the versions do not differ", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, "")
    assert.same({ "" }, host.rendered[bufnr].lines)
    local chunk = host.rendered[bufnr].annotations[1][1]
    assert.equal("These versions differ in neither files nor description.", chunk.text)
    assert.same({ fg = 8 }, host.rendered[bufnr].groups[chunk.group])
  end)

  it("refuses the old side, which jj rebases and no revision holds", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, DIFF_OUTPUT)
    for _, name in ipairs({ "jump", "jump:old" }) do
      assert.has_error(function()
        action.run(jin, host, bufnr, name, 3, 3)
      end, "jin: the old side of an interdiff is in no revision; jump to the new side instead")
    end
    assert.same({}, host.opened)
  end)

  it("jumps from a line to the file as it is in the later version", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, DIFF_OUTPUT)
    action.run(jin, host, bufnr, "jump", 4, 4)
    assert.equal("jin:///repo;view=file#-r c3 keep.txt", host.opened[1].name)
    local file = assert(host.buffer_bufnr(host.opened[1].name))
    view.read(jin, host, file, host.opened[1].name)
    host.finish(ok("a\nB\n"))
    assert.equal(2, host.cursors[file])
  end)
end)

describe("views shown at an earlier operation", function()
  it("open further views at that operation too", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=log#--at-op op1", m("kkk", "c1") .. "x\n", true)
    action.run(jin, host, bufnr, "show", 1, 1)
    assert.equal("jin:///repo;view=show#--at-op op1 kkk", host.opened[1].name)
  end)

  it("never take the working copy for the files of that time", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=diff#--at-op=op1", DIFF_OUTPUT)
    action.run(jin, host, bufnr, "jump", 4, 4)
    assert.equal("jin:///repo;view=file#--at-op op1 -r @ keep.txt", host.opened[1].name)
    local stdout = m("kkk", "c1", "-", "wc") .. "Commit ID: c1\n" .. DIFF_OUTPUT
    bufnr = read(host, jin, "jin:///repo;view=show#--at-operation op1 @", stdout, true)
    action.run(jin, host, bufnr, "jump", 5, 5)
    assert.equal("jin:///repo;view=file#--at-op op1 -r c1 keep.txt", host.opened[2].name)
  end)
end)

describe("the show view", function()
  it("jumps within the version shown of the change each line belongs to", function()
    local host, jin = setup()
    local stdout = m("kkk", "c1") .. "Commit ID: c1\n" .. DIFF_OUTPUT
    local bufnr = read(host, jin, "jin:///repo;view=show#c1", stdout, true)
    host.results = { ok("x") }
    action.run(jin, host, bufnr, "jump", 3, 3)
    action.run(jin, host, bufnr, "jump", 4, 4)
    -- The commit ID, so that an older version (as evolog opens) is not
    -- confused with the change's latest one.
    assert.equal("jin:///repo;view=file#-r c1 keep.txt", host.opened[1].name)
    assert.equal("jin:///repo;view=file#-r c1- keep.txt", host.opened[2].name)
  end)

  it("jumps to the file itself from the working-copy commit", function()
    local host, jin = setup()
    local stdout = m("kkk", "c1", "-", "wc") .. "Commit ID: c1\n" .. DIFF_OUTPUT
    local bufnr = read(host, jin, "jin:///repo;view=show#@", stdout, true)
    -- Line 5 is "        2: B", added on the new side.
    action.run(jin, host, bufnr, "jump", 5, 5)
    assert.equal("/repo/keep.txt", host.opened[1].name)
  end)

  local SHOWN = m("kkk", "c1") .. "Commit ID: c1\n" .. DIFF_OUTPUT

  it("opens the show view of the parent of the version shown, named as a change is", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#c1", SHOWN, true)
    host.results = { ok("ppp\n") }
    action.run(jin, host, bufnr, "parent:vsplit", 3, 3)
    assert.same({
      "log",
      "--no-graph",
      "-r",
      "parents(c1)",
      "-T",
      'if(divergent || hidden, commit_id, change_id) ++ "\\n"',
    }, words(host.runs[3]))
    assert.same(
      { name = "jin:///repo;view=show#ppp", opener = "vsplit" },
      { name = host.opened[1].name, opener = host.opened[1].opener }
    )
  end)

  it("opens a log of the children to choose from when there are several", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#c1", SHOWN, true)
    host.results = { ok("aaa\nbbb\n") }
    action.run(jin, host, bufnr, "child", 1, 1)
    assert.equal("children(c1)", words(host.runs[3])[4])
    assert.equal("jin:///repo;view=log#-r children(c1)", host.opened[1].name)
  end)

  it("tells why a change without parents or children leads nowhere", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#c1", SHOWN, true)
    host.results = { ok(""), ok("") }
    assert.has_error(function()
      action.run(jin, host, bufnr, "parent", 1, 1)
    end, "jin: the change has no parents")
    assert.has_error(function()
      action.run(jin, host, bufnr, "child", 1, 1)
    end, "jin: the change has no children")
    assert.same({}, host.opened)
  end)

  it("looks for the parent at the operation shown, and opens it there", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=show#--at-op op1 c1", SHOWN, true)
    host.results = { ok("ppp\n") }
    action.run(jin, host, bufnr, "parent", 1, 1)
    assert.same(
      { "--at-op", "op1", "log" },
      { words(host.runs[3])[1], words(host.runs[3])[2], words(host.runs[3])[3] }
    )
    assert.equal("jin:///repo;view=show#--at-op op1 ppp", host.opened[1].name)
  end)
end)

describe("the file view", function()
  it("shows the file of a revision with the filetype of its path", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=file#-r @- src/main.lua", "x\n")
    local argv = host.runs[1].argv
    assert.same(
      { "file", "show", "-r", "@-", "src/main.lua" },
      { argv[5], argv[6], argv[7], argv[8], argv[9] }
    )
    assert.is_nil(host.rendered[bufnr].filetype)
    assert.equal("src/main.lua", host.rendered[bufnr].detect)
  end)

  it("puts the cursor on the line asked for once it is read", function()
    local host, jin = setup()
    local bufnr = view.open(jin, host, "file", { "-r", "x", "a.txt" }, { line = 5 })
    assert.is_nil(host.cursors[bufnr])
    view.read(jin, host, bufnr, host.opened[1].name)
    host.finish(ok("1\n2\n3\n4\n5\n"))
    assert.equal(5, host.cursors[bufnr])
  end)

  it("leads to the log of the changes that touched the path up to its revision", function()
    local host, jin = setup()
    local bufnr = read(host, jin, [[jin:///repo;view=file#-r x|y file:\"sp\ ace.txt\"]], "x\n")
    action.run(jin, host, bufnr, "log", 1, 1)
    assert.same(
      { "-r", "::(x|y)", "--", [[file:"sp ace.txt"]] },
      bufname.parse(host.opened[1].name).argv
    )
  end)

  it("stays at the operation it shows", function()
    local host, jin = setup()
    local bufnr = read(host, jin, "jin:///repo;view=file#--at-op op1 -r kkk a.txt", "x\n")
    action.run(jin, host, bufnr, "log", 1, 1)
    assert.equal("jin:///repo;view=log#--at-op op1 -r ::kkk -- a.txt", host.opened[1].name)
  end)
end)
