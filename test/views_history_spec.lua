local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local support = require("jin.view.support")

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

local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

describe("the operation log view", function()
  local NAME = "jin:///repo;view=oplog#"

  it("marks each operation with its ID", function()
    local host, jin = setup()
    read(host, jin, NAME, "", true)
    assert.same({
      "op",
      "log",
      "--config",
      "ui.log-word-wrap=false",
      "-T",
      [["\x1e" ++ json(stringify(self.id())) ++ "\x1f" ++ (tpl)]],
    }, words(host.runs[2]))
  end)

  it("shows what an operation changed, and the log as it was after it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, "@  " .. m("op1") .. "snapshot\n│  args\n", true)
    action.run(jin, host, bufnr, "show", 2, 2)
    action.run(jin, host, bufnr, "log:tab", 1, 1)
    assert.equal("jin:///repo;view=opshow#op1", host.opened[1].name)
    assert.same(
      { name = "jin:///repo;view=log#--at-op op1", opener = "tabedit" },
      { name = host.opened[2].name, opener = host.opened[2].opener }
    )
  end)

  it("yanks operation IDs", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, m("op1") .. "a\n" .. m("op2") .. "b\n", true)
    action.run(jin, host, bufnr, "yank:operation", 1, 2)
    assert.same({ "op1\nop2" }, host.yanked)
  end)
end)

describe("the operation show view", function()
  local NAME = "jin:///repo;view=opshow#op1"
  local OUTPUT = table.concat({
    "op1 alice default@ 1 minute ago",
    "snapshot working copy",
    "",
    "Changed commits:",
    "○  + " .. m("kkk", "c1aaaaaa", "-") .. "feat",
    "   - " .. m("kkk", "c2bbbbbb", "-") .. "feat, a version rewritten away",
    "",
    "Changed working copy default@:",
    "+ " .. m("zzz", "c3cccccc", "-") .. "other",
    "",
  }, "\n")

  it("asks jj what the operation changed, in color-words, with marked summaries", function()
    local host, jin = setup()
    read(host, jin, NAME, OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "op", "show", "--color-words" }, { argv[1], argv[2], argv[5] })
    assert.same({ "op1", "--config" }, { argv[6], argv[7] })
    assert.truthy(argv[8]:find("^templates%.commit_summary="))
  end)

  it("keeps jj from wrapping the graph lines, which would split the markers", function()
    local host, jin = setup()
    read(host, jin, NAME, OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "--config", "ui.log-word-wrap=false" }, { argv[3], argv[4] })
  end)

  it("leaves a -T of the user to the operation", function()
    local host, jin = setup()
    read(host, jin, "jin:///repo;view=opshow#-T description op1", OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same({ "-T", "description", "op1" }, { argv[6], argv[7], argv[8] })
  end)

  it("offers nothing on a line after a summary that names no change itself", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "show", 7, 7)
    end)
  end)

  it("shows a version of a change it touched, or its diff, by commit ID", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "show", 5, 5)
    action.run(jin, host, bufnr, "diff", 6, 6)
    action.run(jin, host, bufnr, "show", 9, 9)
    assert.equal("jin:///repo;view=show#c1aaaaaa", host.opened[1].name)
    assert.equal("jin:///repo;view=diff#-r c2bbbbbb", host.opened[2].name)
    assert.equal("jin:///repo;view=show#c3cccccc", host.opened[3].name)
  end)

  it("yanks the change or commit IDs of the lines", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "yank:change", 5, 6)
    action.run(jin, host, bufnr, "yank:commit", 5, 6)
    assert.same({ "kkk\nkkk", "c1aaaaaa\nc2bbbbbb" }, host.yanked)
  end)

  it("offers nothing on a line that names no change", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "show", 4, 4)
    end)
  end)

  -- The summaries carry the markers of the template vim-jin wraps, whatever
  -- the user's templates.commit_summary prints.
  it("wraps the user's commit summary template with markers", function()
    local host, jin = setup()
    read(host, jin, NAME, OUTPUT, true)
    assert.same({ "config", "get", "templates.commit_summary" }, words(host.runs[1]))
    -- A TOML string, as --config reads its value as TOML.
    local value = words(host.runs[2])[8]:match('^templates%.commit_summary="(.*)"$')
    assert.truthy(value)
    assert.truthy(value:find("json(stringify(change_id))", 1, true))
    assert.truthy(value:find("++ (tpl)", 1, true))
  end)

  it("puts its template after the user's settings, which would override it", function()
    local host, jin = setup()
    local name = "jin:///repo;view=opshow#--config templates.commit_summary=x op1"
    read(host, jin, name, OUTPUT, true)
    local argv = words(host.runs[2])
    assert.same(
      { "--config", "templates.commit_summary=x", "op1", "--config" },
      { argv[6], argv[7], argv[8], argv[9] }
    )
    assert.truthy(argv[10]:find('^templates%.commit_summary="'))
  end)

  it("writes a template of several lines as a TOML string jj can read", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("change_id\n\t++ commit_id\r\n"))
    host.finish(ok(""))
    local value = words(host.runs[2])[8]
    assert.is_nil(value:find("[\r\n\t]"))
    assert.truthy(value:find("change_id\\n\\t++ commit_id", 1, true))
  end)
end)

describe("the evolog view", function()
  local NAME = "jin:///repo;view=evolog#-r kkk"
  local OUTPUT = m("kkk", "c3")
    .. "now\n"
    .. m("kkk", "c2")
    .. "before\n"
    .. m("kkk", "c1")
    .. "first\n"

  it("shows a version of the change by its commit ID", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "show", 2, 2)
    assert.equal("jin:///repo;view=show#c2", host.opened[1].name)
  end)

  it("compares a version's diff with the version before it", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    action.run(jin, host, bufnr, "interdiff", 1, 1)
    assert.equal("jin:///repo;view=interdiff#--from c2 --to c3", host.opened[1].name)
  end)

  it("tells why the first version has nothing to compare with", function()
    local host, jin = setup()
    local bufnr = read(host, jin, NAME, OUTPUT, true)
    assert.has_error(function()
      action.run(jin, host, bufnr, "interdiff", 3, 3)
    end, "jin: this is the first version of the change")
  end)
end)

describe("the marker of a change in a template of its own", function()
  -- An older version is a hidden commit, which its change ID would name the
  -- latest version for, so this view marks it as the log does.
  for _, name in ipairs({ "evolog" }) do
    it(("marks a hidden commit in the %s, to be named by its commit ID"):format(name), function()
      local marker = view.get(name).template.fields[3]
      assert.truthy(marker:find("hidden()", 1, true))
      assert.truthy(marker:find('"hidden"', 1, true))
    end)
  end
end)

describe("jin.view.support.fileset", function()
  it("keeps a plain path, and quotes one jj would read as an expression", function()
    assert.equal("src/a-b_c.lua", support.fileset("src/a-b_c.lua"))
    assert.equal([[file:"my file.txt"]], support.fileset("my file.txt"))
    assert.equal([[file:"a\"b\\c"]], support.fileset([[a"b\c]]))
    assert.equal([[file:"-n"]], support.fileset("-n"))
  end)
end)
