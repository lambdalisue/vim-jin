local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local selection = require("jin.selection")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

local function setup()
  local host = fake_host.new({
    cwd = "/repo",
    dirs = { "/repo", "/repo/.jj", "/lib", "/lib/.jj" },
  })
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

-- kkk on lines 1 and 2, zzz on line 3.
local OUTPUT = "@  " .. m("kkk", "c1", "-") .. "x\n│  a\n○  " .. m("zzz", "c2", "-") .. "y\n"

local function log(host, jin, name, first)
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  if first then
    host.finish(ok("tpl\n"))
  end
  host.finish(ok(OUTPUT))
  return bufnr
end

describe("the selection", function()
  it("select the change of the line in every view of the workspace", function()
    local host, jin = setup()
    local a = log(host, jin, "jin:///repo;view=log#", true)
    local b = log(host, jin, "jin:///repo;view=log#-r ::@")
    local elsewhere = log(host, jin, "jin:///lib;view=log#", true)
    action.run(jin, host, a, "select", 1, 1)
    assert.same({ "kkk" }, selection.list(host, "/repo"))
    assert.same({ 1, 2 }, host.selected[a])
    assert.same({ 1, 2 }, host.selected[b])
    assert.is_nil(host.selected[elsewhere])
  end)

  it("leave out a selected change, and select the changes of every line selected", function()
    local host, jin = setup()
    local bufnr = log(host, jin, "jin:///repo;view=log#", true)
    action.run(jin, host, bufnr, "select", 1, 3)
    assert.same({ "kkk", "zzz" }, selection.list(host, "/repo"))
    assert.same({ 1, 2, 3 }, host.selected[bufnr])
    action.run(jin, host, bufnr, "select", 2, 2)
    assert.same({ "zzz" }, selection.list(host, "/repo"))
    assert.same({ 3 }, host.selected[bufnr])
  end)

  it("select a change once when several lines selected name it, as annotate's do", function()
    local host, jin = setup()
    local name = "jin:///repo;view=log#"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-") .. "x\n" .. m("kkk", "c1", "-") .. "y\n"))
    action.run(jin, host, bufnr, "select", 1, 2)
    assert.same({ "kkk" }, selection.list(host, "/repo"))
  end)

  it("stay shown when a view is read again", function()
    local host, jin = setup()
    local bufnr = log(host, jin, "jin:///repo;view=log#", true)
    action.run(jin, host, bufnr, "select", 3, 3)
    host.selected[bufnr] = nil
    view.read(jin, host, bufnr, "jin:///repo;view=log#")
    host.finish(ok(OUTPUT))
    assert.same({ 3 }, host.selected[bufnr])
  end)

  it("are all cleared with select:clear", function()
    local host, jin = setup()
    local bufnr = log(host, jin, "jin:///repo;view=log#", true)
    action.run(jin, host, bufnr, "select", 1, 3)
    action.run(jin, host, bufnr, "select:clear", 1, 1)
    assert.same({}, selection.list(host, "/repo"))
    assert.same({}, host.selected[bufnr])
  end)

  it("are toggled with x and cleared with X", function()
    local keys = {}
    for _, key in ipairs(action.keys(view.get("log"), false)) do
      keys[(key[3] or "n") .. key[1]] = key[2]
    end
    assert.same({ "select", "select", "select:clear" }, { keys.nx, keys.xx, keys.nX })
  end)
end)
