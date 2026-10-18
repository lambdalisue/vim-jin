local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local diffedit = require("jin.diffedit")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  host.settings.glyph_preset = "ascii"
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

local LEFT, RIGHT, OUTPUT = "/tmp/jj-diff/left", "/tmp/jj-diff/right", "/tmp/jj-diff/output"
local LIST = "jin:///repo;view=diffedit#1"
local ASK = "\30jin\31/tmp/jin1.fifo\31" .. LEFT .. "\31" .. RIGHT .. "\31" .. OUTPUT
local HINT = "<CR> open - :w apply - :q cancel"

---The name of the result pane of `path` in the first session.
local function result(path)
  return "jin:///repo;view=result#1 " .. path
end

---Have jj, run with `argv` through vim-jin's diff editor, hand over `fs`,
---the output a copy of the right side as jj makes it, and read the list.
---@return integer bufnr
local function ask(host, jin, fs, argv)
  host.fs = {}
  for path, content in pairs(fs) do
    host.fs[path] = content
    if path:sub(1, #RIGHT + 1) == RIGHT .. "/" then
      host.fs[OUTPUT .. path:sub(#RIGHT + 1)] = content
    end
  end
  -- Collected first: adding keys to a table while pairs walks it may skip
  -- some of them.
  local copies = {}
  for path, target in pairs(host.links) do
    if path:sub(1, #RIGHT + 1) == RIGHT .. "/" then
      copies[OUTPUT .. path:sub(#RIGHT + 1)] = target
    end
  end
  for path, target in pairs(copies) do
    host.links[path] = target
  end
  host.fs[OUTPUT .. "/JJ-INSTRUCTIONS"] = "help\n"
  diffedit.run(jin, host, argv or { "split", "-i", "-r", "kkk" }, { cwd = "/repo" })
  host.runs[1].on_stderr("Warning: something of jj's own")
  host.runs[1].on_stderr(ASK)
  local bufnr = assert(host.buffer_bufnr(LIST))
  view.read(jin, host, bufnr, LIST)
  return bufnr
end

---Run jj split through vim-jin's diff editor, have it ask for an edit of a
---modified, an added, a removed and an unchanged file, and read the list.
local function asked(host, jin, argv)
  return ask(host, jin, {
    [LEFT .. "/a.txt"] = "a\n",
    [RIGHT .. "/a.txt"] = "A\n",
    [RIGHT .. "/b.txt"] = "b\n",
    [LEFT .. "/c.txt"] = "c\n",
    [LEFT .. "/same.txt"] = "s\n",
    [RIGHT .. "/same.txt"] = "s\n",
  }, argv)
end

---Pretend the result pane of `path` is loaded, modified or not.
local function load_result(host, path, modified)
  host.loaded[#host.loaded + 1] =
    { bufnr = 90 + #host.loaded, name = result(path), modified = modified }
  return host.loaded[#host.loaded].bufnr
end

describe("the diff editor", function()
  it("runs jj with vim-jin's diff editor, answering through a pipe of its own", function()
    local host, jin = setup()
    diffedit.run(jin, host, { "split", "-i", "-r", "kkk" }, { cwd = "/repo" })
    local argv = words(host.runs[1])
    assert.same({ "split", "-i", "-r", "kkk", "--tool", "jin" }, {
      argv[1],
      argv[2],
      argv[3],
      argv[4],
      argv[5],
      argv[6],
    })
    assert.truthy(argv[#argv]:find("/tmp/jin1.fifo", 1, true))
  end)

  it("runs no jj when no named pipe can be made, as on Windows", function()
    local host, jin = setup()
    rawset(host, "fifo", function()
      error("jin: the diff editor needs named pipes, which Windows does not have", 0)
    end)
    assert.has_error(function()
      diffedit.run(jin, host, { "split", "-i", "-r", "kkk" }, { cwd = "/repo" })
    end, "jin: the diff editor needs named pipes, which Windows does not have")
    assert.same({}, host.runs)
  end)

  it("lists the files that differ, but not jj's instructions, above how to answer", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    assert.same({ name = LIST, opener = "split", mods = "botright" }, host.opened[1])
    assert.same({ "M a.txt", "A b.txt", "D c.txt", HINT }, host.rendered[bufnr].lines)
  end)

  it("names in the hint the key mapped to open, or none when nothing is", function()
    local host, jin = setup()
    host.settings.diffedit_disable_default_mappings = "1"
    local bufnr = asked(host, jin)
    assert.equal(":w apply - :q cancel", host.rendered[bufnr].lines[4])
    host.maps = { { lhs = "go", rhs = "<Plug>(jin-action-open)", mode = "n" } }
    view.read(jin, host, bufnr, LIST)
    assert.equal("go open - :w apply - :q cancel", host.rendered[bufnr].lines[4])
  end)

  it(
    "opens a file in three panes: the change's parent, the result to edit and the change",
    function()
      local host, jin = setup()
      local bufnr = asked(host, jin)
      action.run(jin, host, bufnr, "open", 1, 1)
      assert.same({
        {
          left = {
            path = LEFT .. "/a.txt",
            title = "BEFORE",
            about = "read-only: the change's parent",
          },
          output = {
            path = result("a.txt"),
            title = "RESULT",
            about = "Edit this and :w to keep it as the first change",
          },
          right = {
            path = RIGHT .. "/a.txt",
            title = "AFTER",
            about = "read-only: the change as it is",
          },
        },
      }, host.panes)
    end
  )

  it("tells in the result pane what :w makes of it, as the operation does", function()
    for _, case in ipairs({
      { { "split", "-i", "-r", "kkk" }, "Edit this and :w to keep it as the first change" },
      { { "diffedit", "-r", "kkk" }, "Edit this and :w to make it the change" },
      { { "squash", "-r", "kkk", "-i" }, "Edit this and :w to squash it" },
    }) do
      local host, jin = setup()
      local bufnr = asked(host, jin, case[1])
      action.run(jin, host, bufnr, "open", 2, 2)
      assert.equal(case[2], host.panes[1].output.about)
    end
  end)

  it("restores a file to the left side, taking none of its change, and marks it edited", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    action.run(jin, host, bufnr, "take:left", 1, 3)
    assert.equal("a\n", host.fs[OUTPUT .. "/a.txt"])
    assert.is_nil(host.fs[OUTPUT .. "/b.txt"])
    assert.equal("c\n", host.fs[OUTPUT .. "/c.txt"])
    assert.equal("A\n", host.fs[RIGHT .. "/a.txt"])
    assert.same(
      { "M a.txt  edited", "A b.txt  edited", "D c.txt  edited", HINT },
      host.rendered[bufnr].lines
    )
  end)

  it("is modified once a file is edited, so that leaving it asks first", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    assert.is_falsy(host.rendered[bufnr].modified)
    assert.is_true(host.rendered[bufnr].writable)
    host.fs[OUTPUT .. "/a.txt"] = "edited\n"
    view.read(jin, host, bufnr, LIST)
    assert.is_true(host.rendered[bufnr].modified)
  end)

  it("lists a file whose only change is its executable bit, and restores the bit", function()
    local host, jin = setup()
    host.executables = { [RIGHT .. "/run.sh"] = true, [OUTPUT .. "/run.sh"] = true }
    local bufnr = ask(host, jin, { [LEFT .. "/run.sh"] = "x\n", [RIGHT .. "/run.sh"] = "x\n" })
    assert.same({ "M run.sh", HINT }, host.rendered[bufnr].lines)
    action.run(jin, host, bufnr, "take:left", 1, 1)
    assert.is_nil(host.executables[OUTPUT .. "/run.sh"])
    assert.same({ "M run.sh  edited", HINT }, host.rendered[bufnr].lines)
  end)

  it("lists a symbolic link pointed elsewhere, or turned into a file, and restores it", function()
    local host, jin = setup()
    host.links = {
      [LEFT .. "/moved"] = "a",
      [RIGHT .. "/moved"] = "b",
      [LEFT .. "/same"] = "t",
      [RIGHT .. "/file"] = "x",
      [LEFT .. "/kept"] = "k",
      [RIGHT .. "/kept"] = "k",
    }
    local bufnr = ask(host, jin, { [LEFT .. "/file"] = "x\n", [RIGHT .. "/same"] = "t\n" })
    assert.same({ "M file", "M moved", "M same", HINT }, host.rendered[bufnr].lines)
    action.run(jin, host, bufnr, "take:left", 1, 3)
    assert.equal("x\n", host.fs[OUTPUT .. "/file"])
    assert.is_nil(host.links[OUTPUT .. "/file"])
    assert.equal("a", host.links[OUTPUT .. "/moved"])
    assert.equal("t", host.links[OUTPUT .. "/same"])
    assert.is_nil(host.fs[OUTPUT .. "/same"])
  end)

  it("touches no file under a directory that is a symbolic link on one side", function()
    local host, jin = setup()
    host.links = { [RIGHT .. "/d"] = "/outside" }
    local bufnr = ask(host, jin, { [LEFT .. "/d/file"] = "x\n", ["/outside/file"] = "kept\n" })
    assert.same({ "A d", "D d/file", HINT }, host.rendered[bufnr].lines)
    for _, name in ipairs({ "take:left", "open" }) do
      assert.has_error(function()
        action.run(jin, host, bufnr, name, 2, 2)
      end, "jin: d/file lies under d, a symbolic link on one side; take the left side of d first")
    end
    assert.equal("kept\n", host.fs["/outside/file"])
    action.run(jin, host, bufnr, "take:left", 1, 1)
    assert.is_nil(host.links[OUTPUT .. "/d"])
    action.run(jin, host, bufnr, "take:left", 2, 2)
    assert.equal("x\n", host.fs[OUTPUT .. "/d/file"])
  end)

  it("acts on the file it listed, whatever control characters its name holds", function()
    local host, jin = setup()
    local name = "\27[31m..\27[0m/\27[31m..\27[0m/victim"
    local bufnr = ask(host, jin, { [RIGHT .. "/" .. name] = "x\n", ["/tmp/victim"] = "kept\n" })
    assert.same({ "A ?[31m..?[0m/?[31m..?[0m/victim", HINT }, host.rendered[bufnr].lines)
    action.run(jin, host, bufnr, "take:left", 1, 1)
    assert.is_nil(host.fs[OUTPUT .. "/" .. name])
    assert.equal("kept\n", host.fs["/tmp/victim"])
  end)

  it("opens no symbolic link, which editing would write through", function()
    local host, jin = setup()
    host.links = { [RIGHT .. "/l"] = "/etc/passwd" }
    local bufnr = ask(host, jin, { [LEFT .. "/l"] = "x\n" })
    assert.has_error(
      function()
        action.run(jin, host, bufnr, "open", 1, 1)
      end,
      "jin: l is a symbolic link on one side, taken or left as a whole: take:left takes the left one"
    )
    assert.same({}, host.panes)
  end)

  it("restores no file whose result is edited but not written", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    load_result(host, "a.txt", true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "take:left", 1, 1)
    end, "jin: a.txt is edited but not written; write it, or undo the edit, first")
    assert.equal("A\n", host.fs[OUTPUT .. "/a.txt"])
  end)

  it("restores no directory holding a file whose result is edited but not written", function()
    local host, jin = setup()
    local bufnr = ask(host, jin, { [LEFT .. "/d"] = "file\n", [RIGHT .. "/d/file"] = "x\n" })
    load_result(host, "d/file", true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "take:left", 1, 1)
    end, "jin: d/file is edited but not written; write it, or undo the edit, first")
    assert.equal("x\n", host.fs[OUTPUT .. "/d/file"])
  end)

  it("hands jj the result on :w, and closes the list and the panes of the session", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    local pane = load_result(host, "a.txt", false)
    view.write(jin, host, bufnr)
    assert.equal("done\n", host.answered["/tmp/jin1.fifo"])
    assert.is_true(host.saved[bufnr])
    host.fire_timers()
    assert.same({ { bufnr = pane } }, host.closed_tabs)
    assert.same({ { bufnr = bufnr } }, host.left)
  end)

  it("hands jj nothing on :w while a result is edited but not written", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    load_result(host, "a.txt", true)
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: write what is edited first (:wall), or jj takes the files as they are: a.txt")
    assert.is_nil(host.answered["/tmp/jin1.fifo"])
  end)

  it("answers abort when the list goes away unanswered, closing the panes", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    local pane = load_result(host, "a.txt", false)
    view.forget(host, bufnr)
    assert.equal("abort\n", host.answered["/tmp/jin1.fifo"])
    host.fire_timers()
    assert.same({ { bufnr = pane } }, host.closed_tabs)
  end)

  it("answers abort when the editor exits", function()
    local host, jin = setup()
    asked(host, jin)
    diffedit.abort_all(host)
    assert.equal("abort\n", host.answered["/tmp/jin1.fifo"])
  end)

  it(
    "says nothing when jj fails because the edit was aborted, and tells any other failure",
    function()
      local host, jin = setup()
      local bufnr = asked(host, jin)
      view.forget(host, bufnr)
      host.finish({ code = 1, stdout = "", stderr = "Error: Failed to edit diff\n" })
      assert.same({}, host.messages)
      host, jin = setup()
      asked(host, jin)
      host.finish({ code = 1, stdout = "", stderr = "Error: something else\n" })
      assert.same({ { text = "Error: something else", hl = "ErrorMsg" } }, host.messages)
    end
  )

  it("leaves the tool's requests out of the failure it tells", function()
    local host, jin = setup()
    asked(host, jin)
    host.finish({ code = 1, stdout = "", stderr = ASK .. "\nError: something else\n" })
    assert.same({ { text = "Error: something else", hl = "ErrorMsg" } }, host.messages)
  end)

  it("says nothing more when jj failed with no message of its own", function()
    local host, jin = setup()
    asked(host, jin)
    host.finish({ code = 1, stdout = "", stderr = ASK .. "\n" })
    assert.same({}, host.messages)
  end)

  it("hands jj's result to the caller once jj has exited", function()
    local host, jin = setup()
    local results = {}
    diffedit.run(jin, host, { "split", "-i", "-r", "kkk" }, {
      cwd = "/repo",
      on_exit = function(exited)
        results[#results + 1] = exited.code
      end,
    })
    host.finish({ code = 0, stdout = "", stderr = "" })
    assert.same({ 0 }, results)
  end)

  it("forgets the sessions jj no longer waits on once it has exited", function()
    local host, jin = setup()
    local bufnr = asked(host, jin)
    host.finish({ code = 1, stdout = "", stderr = "Error: killed\n" })
    assert.is_nil(diffedit.get(host, 1))
    diffedit.abort_all(host)
    assert.is_nil(host.answered["/tmp/jin1.fifo"])
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: this edit has been answered already")
  end)

  it("maps <CR> to open and dol to take:left, and leaves ZZ and ZQ to Vim", function()
    local keys = {}
    for _, key in ipairs(action.keys(view.get("diffedit"), false)) do
      keys[key[1]] = key[2]
    end
    assert.same({ "open", "take:left" }, { keys["<CR>"], keys["dol"] })
    assert.is_nil(keys.ZZ)
    assert.is_nil(keys.ZQ)
  end)
end)

describe("the result pane", function()
  ---Open the result pane of a.txt from the list of `asked`.
  local function opened(host, jin, argv)
    local list = asked(host, jin, argv)
    action.run(jin, host, list, "open", 1, 1)
    local bufnr = host.load(result("a.txt"))
    view.read(jin, host, bufnr, result("a.txt"))
    host.contents[result("a.txt")] = host.rendered[bufnr].lines
    return bufnr, list
  end

  it("holds the file of the output to edit, the change as it is to begin with", function()
    local host, jin = setup()
    local bufnr = opened(host, jin)
    assert.same({ "A" }, host.rendered[bufnr].lines)
    assert.is_true(host.rendered[bufnr].editable)
    assert.equal("a.txt", host.rendered[bufnr].detect)
  end)

  it("writes the output on :w, then shows the list again with the file edited", function()
    local host, jin = setup()
    local bufnr, list = opened(host, jin)
    host.contents[result("a.txt")] = { "a", "A" }
    view.write(jin, host, bufnr)
    assert.equal("a\nA\n", host.fs[OUTPUT .. "/a.txt"])
    assert.is_true(host.saved[bufnr])
    host.fire_timers()
    assert.same({ { bufnr = bufnr, back = list } }, host.closed_tabs)
    assert.equal("M a.txt  edited", host.rendered[list].lines[1])
  end)

  it("leaves a removed file removed when emptied, and keeps what is written of it", function()
    local host, jin = setup()
    local list = asked(host, jin)
    action.run(jin, host, list, "open", 3, 3)
    local name = result("c.txt")
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    assert.same({}, host.rendered[bufnr].lines)
    host.contents[name] = {}
    view.write(jin, host, bufnr)
    assert.is_nil(host.fs[OUTPUT .. "/c.txt"])
    host.contents[name] = { "c" }
    view.write(jin, host, bufnr)
    assert.equal("c\n", host.fs[OUTPUT .. "/c.txt"])
  end)

  it("refuses a path that leads out of the output", function()
    local host, jin = setup()
    asked(host, jin)
    local name = result("../right/a.txt")
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    assert.same({}, host.rendered[bufnr].lines)
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: ../right/a.txt is no path inside the diff")
  end)

  it("gets the hunk of the line from BEFORE with dol and from AFTER with dor", function()
    local host, jin = setup()
    local bufnr = opened(host, jin)
    action.run(jin, host, bufnr, "diffget-l", 1, 1)
    assert.same({ "a" }, host.contents[result("a.txt")])
    action.run(jin, host, bufnr, "diffget-r", 1, 1)
    assert.same({ "A" }, host.contents[result("a.txt")])
    assert.has_error(function()
      action.run(jin, host, bufnr, "diffget-r", 1, 1)
    end, "jin: no hunk on this line")
  end)

  it("takes the hunk dp puts from the line of a side", function()
    local host, jin = setup()
    local bufnr = opened(host, jin)
    require("jin.view.middle").put(host, bufnr, "left", 1)
    assert.same({ "a" }, host.contents[result("a.txt")])
    require("jin.view.middle").put(host, bufnr, "right", 1)
    assert.same({ "A" }, host.contents[result("a.txt")])
  end)

  it(
    "takes both sides of the hunk of the line, BEFORE first with do and doa, AFTER first with doA",
    function()
      for _, case in ipairs({
        { "diffget", { "a", "A" } },
        { "diffget-all", { "a", "A" } },
        { "diffget-all-reversed", { "A", "a" } },
      }) do
        local host, jin = setup()
        local bufnr = opened(host, jin)
        action.run(jin, host, bufnr, case[1], 1, 1)
        assert.same(case[2], host.contents[result("a.txt")])
      end
    end
  )

  it("says so where the result agrees with both sides", function()
    local host, jin = setup()
    local name = "jin:///repo;view=result#1 x.txt"
    local list = ask(host, jin, {
      [LEFT .. "/x.txt"] = "same\nold\n",
      [RIGHT .. "/x.txt"] = "same\nnew\n",
    })
    action.run(jin, host, list, "open", 1, 1)
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.contents[name] = host.rendered[bufnr].lines
    assert.has_error(function()
      action.run(jin, host, bufnr, "diffget-all", 1, 1)
    end, "jin: no hunk on this line")
  end)

  it("maps the do keys that get a hunk, and has no base to get", function()
    local host, jin = setup()
    local bufnr = opened(host, jin)
    assert.same({
      { "do", "diffget" },
      { "dol", "diffget-l" },
      { "dor", "diffget-r" },
      { "doa", "diffget-all" },
      { "doA", "diffget-all-reversed" },
    }, host.keys[bufnr].keys)
  end)
end)

describe("split and diffedit", function()
  local function m(...)
    local fields = {}
    for i, value in ipairs({ ... }) do
      fields[i] = '"' .. value:gsub('[\\"]', "\\%0") .. '"'
    end
    return "\30" .. table.concat(fields, " ") .. "\31"
  end

  local function log(host, jin)
    local name = "jin:///repo;view=log#"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-") .. "x\n"))
    return bufnr
  end

  it("split the change of the line in the diff editor, keeping its description first", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { ok("kkk c1\n"), ok("feat: x\n") }
    action.run(jin, host, bufnr, "split", 1, 1)
    local argv = words(host.runs[#host.runs])
    assert.same({ "split", "-i", "-r", "kkk", "-m", "feat: x\n", "--tool", "jin" }, {
      argv[1],
      argv[2],
      argv[3],
      argv[4],
      argv[5],
      argv[6],
      argv[7],
      argv[8],
    })
  end)

  it("edit the diff of the change of the line", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { ok("kkk c1\n") }
    action.run(jin, host, bufnr, "diffedit", 1, 1)
    local argv = words(host.runs[#host.runs])
    assert.same({ "diffedit", "-r", "kkk", "--tool", "jin" }, {
      argv[1],
      argv[2],
      argv[3],
      argv[4],
      argv[5],
    })
  end)

  it("squash:interactive chooses in the diff editor what goes into the parent", function()
    local host, jin = setup()
    local bufnr = log(host, jin)
    host.results = { ok("kkk c1\n"), ok("feat: x\n"), ok("") }
    action.run(jin, host, bufnr, "squash:interactive", 1, 1)
    local argv = words(host.runs[#host.runs])
    assert.same({ "squash", "-r", "kkk", "-m", "feat: x\n", "-i", "--tool", "jin" }, {
      argv[1],
      argv[2],
      argv[3],
      argv[4],
      argv[5],
      argv[6],
      argv[7],
      argv[8],
    })
  end)

  it("split is mapped to gS, and diffedit to no key", function()
    local keys = {}
    for _, key in ipairs(action.keys(view.get("log"), false)) do
      keys[key[1]] = key[2]
    end
    assert.same({ "split" }, { keys.gS, keys.E })
  end)
end)
