local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local diffedit = require("jin.diffedit")

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  host.settings.glyph_preset = "ascii"
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local OUTPUT = "/t/output_a.lua"
local LIST = "jin:///repo;view=diffedit#1"
local MERGE = "jin:///repo;view=merge#1 a.lua"
local CONFLICT = {
  "a",
  "<<<<<<< conflict 1 of 1",
  "%%%%%%% diff from: base",
  "\\\\\\\\\\\\\\        to: left",
  "-base",
  "+left",
  "+++++++ right",
  "right",
  ">>>>>>> conflict 1 of 1 ends",
  "z",
}

---Run jj resolve through vim-jin's merge tool, open the conflicted file from
---the list and read the result in its merge buffer.
local function merging(host, jin)
  host.fs = { [OUTPUT] = table.concat(CONFLICT, "\n") .. "\n" }
  diffedit.run(jin, host, { "resolve", "-r", "kkk" }, { cwd = "/repo", merge = true })
  host.runs[1].on_stderr(
    "\30jin-merge\31/tmp/jin1.fifo\31/t/base_a.lua\31/t/left_a.lua\31/t/right_a.lua\31" .. OUTPUT
  )
  local list = assert(host.buffer_bufnr(LIST))
  view.read(jin, host, list, LIST)
  action.run(jin, host, list, "open", 1, 1)
  local bufnr = host.load(MERGE)
  view.read(jin, host, bufnr, MERGE)
  host.contents[MERGE] = host.rendered[bufnr].lines
  return bufnr
end

describe("the merge buffer", function()
  it("opens between the two sides of the conflicted file", function()
    local host, jin = setup()
    merging(host, jin)
    assert.same(
      { "/t/left_a.lua", MERGE, "/t/right_a.lua" },
      { host.panes[1].left.path, host.panes[1].output.path, host.panes[1].right.path }
    )
  end)

  it("holds the result jj wrote, conflict markers included, to be edited", function()
    local host, jin = setup()
    local bufnr = merging(host, jin)
    assert.same(CONFLICT, host.rendered[bufnr].lines)
    assert.is_true(host.rendered[bufnr].editable)
    assert.equal("a.lua", host.rendered[bufnr].detect)
  end)

  it("keeps :w on the list from answering while the output holds an edit not written", function()
    local host, jin = setup()
    local bufnr = merging(host, jin)
    for _, buf in ipairs(host.loaded) do
      if buf.bufnr == bufnr then
        buf.modified = true
      end
    end
    local list = assert(host.buffer_bufnr(LIST))
    assert.has_error(function()
      view.write(jin, host, list)
    end, "jin: write what is edited first (:wall), or jj takes the files as they are: a.lua")
    assert.is_nil(host.answered["/tmp/jin1.fifo"])
  end)

  it(
    "writes what it holds to the result on :w, then shows the list again with the file edited",
    function()
      local host, jin = setup()
      local bufnr = merging(host, jin)
      host.contents[MERGE] = { "a", "both", "z" }
      view.write(jin, host, bufnr)
      assert.equal("a\nboth\nz\n", host.fs[OUTPUT])
      assert.is_true(host.saved[bufnr])
      host.fire_timers()
      local list = assert(host.buffer_bufnr(LIST))
      assert.same({ { bufnr = bufnr, back = list } }, host.closed_tabs)
      assert.equal("C a.lua  edited", host.rendered[list].lines[1])
    end
  )

  it(
    "keeps the result without a final newline when it had none, and an emptied one empty",
    function()
      local host, jin = setup()
      local bufnr = merging(host, jin)
      host.fs[OUTPUT] = "a\nb"
      host.contents[MERGE] = { "a", "x" }
      view.write(jin, host, bufnr)
      assert.equal("a\nx", host.fs[OUTPUT])
      host.contents[MERGE] = {}
      view.write(jin, host, bufnr)
      assert.equal("", host.fs[OUTPUT])
      host.fs[OUTPUT] = "a\n"
      host.contents[MERGE] = { "" }
      view.write(jin, host, bufnr)
      assert.equal("\n", host.fs[OUTPUT])
    end
  )

  it(
    "leaves out the carriage return jj ended a CRLF result with when it had no final newline",
    function()
      local host, jin = setup()
      local bufnr = merging(host, jin)
      host.fs[OUTPUT] = "a\r\n<<<<<<< x\r\nl\r\n=======\r\nr\r\n>>>>>>> y"
      host.contents[MERGE] = { "a\r", "l\r" }
      view.write(jin, host, bufnr)
      assert.equal("a\r\nl", host.fs[OUTPUT])
    end
  )

  it("holds the bytes of the result as they are, escape sequences included", function()
    local host, jin = setup()
    host.fs = { [OUTPUT] = "\27[31mred\27[0m\n" }
    diffedit.run(jin, host, { "resolve", "-r", "kkk" }, { cwd = "/repo", merge = true })
    host.runs[1].on_stderr(
      "\30jin-merge\31/tmp/jin1.fifo\31/t/base_a.lua\31/t/left_a.lua\31/t/right_a.lua\31" .. OUTPUT
    )
    local bufnr = host.load(MERGE)
    view.read(jin, host, bufnr, MERGE)
    assert.same({ "\27[31mred\27[0m" }, host.rendered[bufnr].lines)
  end)

  it("takes a side, the base or both sides in place of the conflict of the line", function()
    for _, case in ipairs({
      { "diffget-l", { "a", "left", "z" } },
      { "diffget-r", { "a", "right", "z" } },
      { "diffget-base", { "a", "base", "z" } },
      { "diffget-all", { "a", "left", "right", "z" } },
      { "diffget", { "a", "left", "right", "z" } },
      { "diffget-all-reversed", { "a", "right", "left", "z" } },
    }) do
      local host, jin = setup()
      local bufnr = merging(host, jin)
      action.run(jin, host, bufnr, case[1], 6, 6)
      assert.same(case[2], host.contents[MERGE])
    end
  end)

  it("gets the hunk of a line outside any conflict from a side, which has no base", function()
    local host, jin = setup()
    local bufnr = merging(host, jin)
    host.contents[MERGE] = { "a", "resolved", "z" }
    host.fs["/t/left_a.lua"] = "b\nresolved\nz\n"
    action.run(jin, host, bufnr, "diffget-l", 1, 1)
    assert.same({ "b", "resolved", "z" }, host.contents[MERGE])
    assert.has_error(function()
      action.run(jin, host, bufnr, "diffget-base", 1, 1)
    end, "jin: no conflict on this line")
  end)

  it("takes the side dp puts in place of the whole conflict its hunk lies in", function()
    local host, jin = setup()
    local bufnr = merging(host, jin)
    host.fs["/t/left_a.lua"] = "a\nleft\nz\n"
    require("jin.view.middle").put(host, bufnr, "left", 2)
    assert.same({ "a", "left", "z" }, host.contents[MERGE])
  end)

  it("maps the do keys that get a side, the base or both", function()
    local host, jin = setup()
    local bufnr = merging(host, jin)
    assert.same({
      { "do", "diffget" },
      { "dol", "diffget-l" },
      { "dor", "diffget-r" },
      { "dob", "diffget-base" },
      { "doa", "diffget-all" },
      { "doA", "diffget-all-reversed" },
    }, host.keys[bufnr].keys)
    local defined = {}
    for _, name in ipairs(host.defined[bufnr]) do
      defined[name] = true
    end
    assert.is_true(defined["diffget-l"])
  end)
end)
