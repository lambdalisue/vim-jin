local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")

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

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
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

---The question that asks jj for the descriptions of `revset`.
local function DESCRIPTIONS(revset)
  return {
    "log",
    "--no-graph",
    "-r",
    revset,
    "-T",
    'change_id ++ "\\x1f" ++ commit_id ++ "\\x1f" ++ description ++ "\\x1e"',
  }
end

---What jj answers DESCRIPTIONS with for one commit.
local function record(change, commit, text)
  return change .. "\31" .. commit .. "\31" .. text .. "\30"
end

local ONE = "jin:///repo;view=describe#-r kkk"
local TWO = "jin:///repo;view=describe#-r kkk -r zzz"

---Read the description buffer `name`, answering the template lookup and then
---jj log with `stdout`.
local function read(host, jin, name, stdout)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok("builtin_draft_commit_description\n"))
  host.finish(ok(stdout))
  return bufnr
end

describe("the description buffer", function()
  it("holds jj's own draft of the description, JJ: lines and all", function()
    local host, jin = setup()
    local bufnr =
      read(host, jin, ONE, m("kkk", "c1", "-", "feat: x\n") .. "feat: x\n\nJJ: Change ID: kkk\n")
    assert.same({ "config", "get", "templates.draft_commit_description" }, words(host.runs[1]))
    local argv = words(host.runs[2])
    assert.same({ "log", "--no-graph", "-T" }, { argv[1], argv[2], argv[3] })
    assert.same({ "-r", "kkk" }, { argv[5], argv[6] })
    assert.same({ "feat: x", "", "JJ: Change ID: kkk" }, host.rendered[bufnr].lines)
    assert.is_true(host.rendered[bufnr].editable)
    assert.equal("jjdescription", host.rendered[bufnr].filetype)
  end)

  it("heads the draft of each of several changes with its change ID, as jj does", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      TWO,
      m("kkk", "c1", "-", "A\n") .. "A\n" .. m("zzz", "c2", "-", "B\n") .. "B\n"
    )
    assert.same({
      "JJ: describe kkk -------",
      "A",
      "JJ: describe zzz -------",
      "B",
    }, host.rendered[bufnr].lines)
  end)

  it("maps no key, as its text is there to be edited", function()
    local host, jin = setup()
    local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
    assert.same({}, host.keys[bufnr].keys)
  end)

  it("is never read again by itself, which would lose what is being written", function()
    local host, jin = setup()
    read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
    local runs = #host.runs
    view.reload(jin, host)
    view.refresh(jin, host)
    assert.equal(runs, #host.runs)
  end)
end)

describe("writing the description buffer", function()
  it(
    "describes the change with the text, its JJ: lines and what follows ignore-rest left out",
    function()
      local host, jin = setup()
      local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
      host.contents[ONE] = {
        "feat: x",
        "",
        "JJ: Change ID: kkk",
        "body",
        "",
        "JJ: ignore-rest",
        "diff --git a b",
      }
      host.results = { ok(record("kkk", "c1", "feat\n")) }
      view.write(jin, host, bufnr)
      local run = host.runs[#host.runs]
      assert.same(DESCRIPTIONS("kkk"), words(host.runs[#host.runs - 1]))
      assert.same({ "describe", "-r", "kkk", "--stdin" }, words(run))
      assert.equal("feat: x\n\nbody\n", run.stdin)
      assert.is_nil(host.saved[bufnr])
      host.finish({ code = 0, stdout = "", stderr = "Rebased 1 descendant commits\n" })
      assert.is_true(host.saved[bufnr])
      assert.same({}, host.messages)
    end
  )

  it("describes each of several changes with the text under its head, one after another", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      TWO,
      m("kkk", "c1", "-", "A\n") .. "A\n" .. m("zzz", "c2", "-", "B\n") .. "B\n"
    )
    host.contents[TWO] = { "JJ: describe kkk -------", "A2", "JJ: describe zzz -------", "B2" }
    host.results = { ok(record("kkk", "c1", "A\n") .. record("zzz", "c2", "B\n")) }
    local before = #host.runs + 1
    view.write(jin, host, bufnr)
    assert.equal(before + 1, #host.runs)
    assert.same({ "describe", "-r", "kkk", "--stdin" }, words(host.runs[before + 1]))
    assert.equal("A2\n", host.runs[before + 1].stdin)
    host.finish(ok(""))
    assert.same({ "describe", "-r", "zzz", "--stdin" }, words(host.runs[before + 2]))
    assert.equal("B2\n", host.runs[before + 2].stdin)
    assert.is_nil(host.saved[bufnr])
    host.finish(ok(""))
    assert.is_true(host.saved[bufnr])
  end)

  it("stays unwritten when the buffer was edited while jj described it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
    host.contents[ONE] = { "B" }
    host.results = { ok(record("kkk", "c1", "feat\n")) }
    view.write(jin, host, bufnr)
    host.contents[ONE] = { "C" }
    host.finish(ok(""))
    assert.is_nil(host.saved[bufnr])
  end)

  it("stays unwritten when jj fails, and stops there", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      TWO,
      m("kkk", "c1", "-", "A\n") .. "A\n" .. m("zzz", "c2", "-", "B\n") .. "B\n"
    )
    host.contents[TWO] = { "JJ: describe kkk -------", "A2", "JJ: describe zzz -------", "B2" }
    host.results = { ok(record("kkk", "c1", "A\n") .. record("zzz", "c2", "B\n")) }
    local before = #host.runs + 1
    view.write(jin, host, bufnr)
    host.finish({ code = 1, stdout = "", stderr = "Error: no such change\n" })
    assert.equal(before + 1, #host.runs)
    assert.is_nil(host.saved[bufnr])
  end)

  it("refuses to overwrite a description someone changed since it was read", function()
    local host, jin = setup()
    local bufnr =
      read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n\nJJ: Change ID: kkk\n")
    host.contents[ONE] = { "mine" }
    host.results = { ok(record("kkk", "c1", "rewritten by an agent\n")) }
    local before = #host.runs
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: the description of kkk changed since it was read; :edit! reads it again")
    assert.equal(before + 1, #host.runs)
    assert.is_nil(host.saved[bufnr])
  end)

  it("writes again over the description it wrote itself", function()
    local host, jin = setup()
    local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
    host.contents[ONE] = { "B" }
    host.results = { ok(record("kkk", "c1", "feat\n")) }
    view.write(jin, host, bufnr)
    host.finish(ok(""))
    host.contents[ONE] = { "C" }
    host.results = { ok(record("kkk", "c1", "B\n")) }
    view.write(jin, host, bufnr)
    local run = host.runs[#host.runs]
    assert.same({ "describe", "-r", "kkk", "--stdin" }, words(run))
    assert.equal("C\n", run.stdin)
  end)

  it("refuses to write again a version named by commit ID, which the last :w replaced", function()
    local host, jin = setup()
    local name = "jin:///repo;view=describe#-r 0a1b2c3d4e5f"
    local bufnr = read(host, jin, name, m("kkk", "0a1b2c3d4e5f", "-", "feat\n") .. "feat\n")
    host.contents[name] = { "B" }
    host.results = { ok(record("kkk", "c1", "feat\n")) }
    view.write(jin, host, bufnr)
    host.finish(ok(""))
    host.contents[name] = { "C" }
    local before = #host.runs
    assert.has_error(
      function()
        view.write(jin, host, bufnr)
      end,
      "jin: the version 0a1b2c3d4e5f was replaced by the last :w; describe its change again from a view"
    )
    assert.equal(before, #host.runs)
  end)

  it("compares with the description itself, not with the draft jj made of it", function()
    local host, jin = setup()
    -- A draft template, or ui.default-description, adds text the
    -- description does not hold.
    local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "") .. "TODO\n")
    host.contents[ONE] = { "feat" }
    host.results = { ok(record("kkk", "c1", "")) }
    view.write(jin, host, bufnr)
    local run = host.runs[#host.runs]
    assert.same({ "describe", "-r", "kkk", "--stdin" }, words(run))
  end)

  it("asks jj once for the descriptions of every change it writes", function()
    local host, jin = setup()
    local bufnr = read(
      host,
      jin,
      TWO,
      m("kkk", "c1", "-", "A\n") .. "A\n" .. m("zzz", "c2", "-", "B\n") .. "B\n"
    )
    host.contents[TWO] = { "JJ: describe kkk -------", "A2", "JJ: describe zzz -------", "B2" }
    host.results = { ok(record("kkk", "c1", "A\n") .. record("zzz", "c2", "changed\n")) }
    local before = #host.runs
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: the description of zzz changed since it was read; :edit! reads it again")
    assert.equal(before + 1, #host.runs)
    assert.same(DESCRIPTIONS("kkk|zzz"), words(host.runs[before + 1]))
  end)

  it("refuses a change that has split into several versions since it was read", function()
    local host, jin = setup()
    local bufnr = read(host, jin, ONE, m("kkk", "c1", "-", "feat\n") .. "feat\n")
    host.contents[ONE] = { "mine" }
    host.results = { ok(record("kkk", "c8", "feat\n") .. record("kkk", "c9", "feat\n")) }
    local before = #host.runs
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: kkk has split into several versions since it was read; describe one from a view")
    assert.equal(before + 1, #host.runs)
  end)

  it("refuses a buffer that is not to be written", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;view=log#")
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: this buffer is not to be written")
  end)
end)

describe("the describe action", function()
  local LOG = "jin:///repo;view=log#"

  it("opens the description buffer of the change of the line, or of every line selected", function()
    local host, jin = setup()
    local bufnr = host.load(LOG)
    view.read(jin, host, bufnr, LOG)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-") .. "x\n" .. m("zzz", "c2", "-") .. "y\n"))
    action.run(jin, host, bufnr, "describe", 1, 1)
    action.run(jin, host, bufnr, "describe:split", 1, 2)
    assert.equal(ONE, host.opened[1].name)
    assert.same({ name = TWO, opener = "split" }, {
      name = host.opened[2].name,
      opener = host.opened[2].opener,
    })
  end)
end)
