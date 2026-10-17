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

local COMMIT = "jin:///repo;view=commit#-r kkk"
local WORKING_COPY = { "log", "--no-graph", "-r", "@", "-T", "change_id" }
-- What jj answers for the description of kkk when nobody changed it.
local UNCHANGED = table.concat({ "kkk", "c1", "wip\n" }, "\31") .. "\30"

local function read(host, jin)
  local bufnr = host.load(COMMIT)
  view.read(jin, host, bufnr, COMMIT)
  host.finish(ok("builtin_draft_commit_description\n"))
  host.finish(ok(m("kkk", "c1", "-", "wip\n") .. "wip\n\nJJ: Change ID: kkk\n"))
  return bufnr
end

describe("the commit action", function()
  it("opens the description buffer of the working copy, whatever the line", function()
    for _, name in ipairs({ "jin:///repo;view=log#", "jin:///repo;view=status#" }) do
      local host, jin = setup()
      local bufnr = host.load(name)
      view.read(jin, host, bufnr, name)
      host.finish(ok("tpl\n"))
      host.finish(ok(m("zzz", "c2", "-") .. "x\n"))
      host.results = { ok("kkk\n") }
      action.run(jin, host, bufnr, "commit", 1, 1)
      assert.same(WORKING_COPY, words(host.runs[3]))
      assert.equal(COMMIT, host.opened[1].name)
    end
  end)
end)

describe("the commit buffer", function()
  it("holds jj's draft of the working copy, to be edited", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    assert.same({ "wip", "", "JJ: Change ID: kkk" }, host.rendered[bufnr].lines)
    assert.is_true(host.rendered[bufnr].editable)
    assert.equal("jj commit -r kkk", host.rendered[bufnr].title)
  end)

  it("commits the working copy with the text on :w, as long as it is still that change", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[COMMIT] = { "feat: x", "", "JJ: Change ID: kkk", "body" }
    host.results = { ok("kkk\n"), ok(UNCHANGED) }
    view.write(jin, host, bufnr)
    assert.same(WORKING_COPY, words(host.runs[3]))
    assert.same({ "commit", "-m", "feat: x\n\nbody\n" }, words(host.runs[5]))
    host.finish(ok("", "Working copy now at: yyy\n"))
    assert.is_true(host.saved[bufnr])
    assert.same({}, host.messages)
  end)

  it("goes back to the view it was opened over once committed", function()
    local host, jin = setup()
    local log = "jin:///repo;view=log#"
    local from = host.load(log)
    view.read(jin, host, from, log)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("zzz", "c2", "-") .. "x\n"))
    host.results = { ok("kkk\n") }
    action.run(jin, host, from, "commit", 1, 1)
    local bufnr = assert(host.buffer_bufnr(COMMIT))
    view.read(jin, host, bufnr, COMMIT)
    host.finish(ok("builtin_draft_commit_description\n"))
    host.finish(ok(m("kkk", "c1", "-", "wip\n") .. "wip\n\nJJ: Change ID: kkk\n"))
    host.contents[COMMIT] = { "feat: x" }
    host.results = { ok("kkk\n"), ok(UNCHANGED) }
    view.write(jin, host, bufnr)
    host.finish(ok(""))
    assert.same({ { bufnr = bufnr, previous = log } }, host.left)
  end)

  it("closes the window or tab page it was opened in once committed", function()
    for _, name in ipairs({ "commit:split", "commit:vsplit", "commit:tab" }) do
      local host, jin = setup()
      local log = "jin:///repo;view=log#"
      local from = host.load(log)
      view.read(jin, host, from, log)
      host.finish(ok("tpl\n"))
      host.finish(ok(m("zzz", "c2", "-") .. "x\n"))
      host.results = { ok("kkk\n") }
      action.run(jin, host, from, name, 1, 1)
      local bufnr = assert(host.buffer_bufnr(COMMIT))
      view.read(jin, host, bufnr, COMMIT)
      host.finish(ok("builtin_draft_commit_description\n"))
      host.finish(ok(m("kkk", "c1", "-", "wip\n") .. "wip\n\nJJ: Change ID: kkk\n"))
      host.contents[COMMIT] = { "feat: x" }
      host.results = { ok("kkk\n"), ok(UNCHANGED) }
      view.write(jin, host, bufnr)
      host.finish(ok(""))
      assert.same({ { bufnr = bufnr } }, host.left)
    end
  end)

  it("stays open when jj refuses to commit, keeping the text", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[COMMIT] = { "feat: x" }
    host.results = { ok("kkk\n"), ok(UNCHANGED) }
    view.write(jin, host, bufnr)
    host.finish({ code = 1, stdout = "", stderr = "Error: nope\n" })
    assert.same({}, host.left)
    assert.is_nil(host.saved[bufnr])
  end)

  it("stays unwritten when the buffer was edited while jj committed it", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[COMMIT] = { "B" }
    host.results = { ok("kkk\n"), ok(UNCHANGED) }
    view.write(jin, host, bufnr)
    host.contents[COMMIT] = { "C" }
    host.finish(ok(""))
    assert.is_nil(host.saved[bufnr])
    assert.same({}, host.left)
  end)

  it("refuses to commit over a description someone changed since it was read", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[COMMIT] = { "feat: x" }
    host.results =
      { ok("kkk\n"), ok(table.concat({ "kkk", "c1", "rewritten by an agent\n" }, "\31") .. "\30") }
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: the description of kkk changed since it was read; :edit! reads it again")
    assert.equal(4, #host.runs)
    assert.is_nil(host.saved[bufnr])
  end)

  it("refuses to commit once the working copy moved to another change", function()
    local host, jin = setup()
    local bufnr = read(host, jin)
    host.contents[COMMIT] = { "feat: x" }
    host.results = { ok("zzz\n") }
    assert.has_error(function()
      view.write(jin, host, bufnr)
    end, "jin: the working copy is no longer kkk; commit it again from a view")
    assert.equal(3, #host.runs)
    assert.is_nil(host.saved[bufnr])
  end)
end)
