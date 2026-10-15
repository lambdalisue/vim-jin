local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")

-- A view for these tests: a log-like command with a marked template.
package.preload["jin.view.probe"] = function()
  return {
    command = { "log" },
    config = { "ui.log-word-wrap=false" },
    flags = { "--no-pager" },
    filetype = "jin-probe",
    template = { key = "log", default = "builtin_log_compact", fields = { "change_id" } },
    decorate = function(meta)
      meta.data.count = #meta.lines
    end,
  }
end
view.register("probe")

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

local NAME = "jin:///repo;view=probe#-r @"

---The jj words after the global flags vim-jin always adds.
local function words(run)
  local w = {}
  for i = 5, #run.argv do
    w[#w + 1] = run.argv[i]
  end
  return w
end

describe("jin.view.read of a view with a template", function()
  it("wraps the configured template with markers", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    assert.same({ "config", "get", "templates.log" }, words(host.runs[1]))
    host.finish(ok("my_template\n"))
    assert.same({
      "log",
      "--config",
      "ui.log-word-wrap=false",
      "--no-pager",
      "-T",
      [["\x1e" ++ json(stringify(change_id)) ++ "\x1f" ++ (my_template)]],
      "-r",
      "@",
    }, words(host.runs[2]))
  end)

  it("falls back to the view's default when nothing is configured", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish({ code = 1, stdout = "", stderr = "Error: not found\n" })
    assert.truthy(words(host.runs[2])[6]:find("(builtin_log_compact)", 1, true))
  end)

  it("wraps the user's own template instead, in any of its spellings", function()
    for _, given in ipairs({
      { "-T", "mine" },
      { "--template", "mine" },
      { "--template=mine" },
      { "-Tmine" },
    }) do
      local host, jin = setup()
      local name = "jin:///repo;view=probe#" .. table.concat(given, " ")
      local bufnr = host.load(name)
      view.read(jin, host, bufnr, name)
      assert.same({
        "log",
        "--config",
        "ui.log-word-wrap=false",
        "--no-pager",
        "-T",
        [["\x1e" ++ json(stringify(change_id)) ++ "\x1f" ++ (mine)]],
      }, words(host.runs[1]))
    end
  end)

  it("leaves a -T after -- to jj as a path", function()
    local host, jin = setup()
    local name = "jin:///repo;view=probe#-T mine -- -T"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    local w = words(host.runs[1])
    assert.same({ "--", "-T" }, { w[#w - 1], w[#w] })
  end)

  it("shows the text without markers and keeps what each line stands for", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("t\n"))
    host.finish(ok("@  " .. "\30" .. [["kkk"]] .. "\31" .. "first\n│  more\n"))
    assert.same({ "@  first", "│  more" }, host.rendered[bufnr].lines)
    assert.equal("jin-probe", host.rendered[bufnr].filetype)
    local meta = assert(view.meta(host, bufnr))
    assert.same({ { "kkk" }, { "kkk" } }, meta.entries)
    assert.equal(2, meta.data.count)
    assert.equal("probe", meta.view)
  end)
end)

describe("jin.view.read of the configured template", function()
  local function configured_runs(host)
    local n = 0
    for _, run in ipairs(host.runs) do
      if run.argv[5] == "config" then
        n = n + 1
      end
    end
    return n
  end

  it("asks jj for it once per workspace, and again after jj changed the repository", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("my_template\n"))
    host.finish(ok(""))
    view.read(jin, host, bufnr, NAME)
    assert.equal(1, configured_runs(host))
    assert.truthy(words(host.runs[3])[6]:find("(my_template)", 1, true))
    host.finish(ok(""))
    view.reload(jin, host)
    assert.equal(2, configured_runs(host))
  end)

  it("asks again when the user reads a view again with !", function()
    local host, jin = setup()
    local bufnr = view.open(jin, host, "probe", { "-r", "@" }, {})
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("my_template\n"))
    host.finish(ok(""))
    view.open(jin, host, "probe", { "-r", "@" }, { reload = true })
    assert.equal(2, configured_runs(host))
  end)

  it("asks again for a workspace elsewhere", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("my_template\n"))
    host.finish(ok(""))
    local other = "jin:///other;view=probe#"
    view.read(jin, host, host.load(other), other)
    assert.equal(2, configured_runs(host))
  end)
end)

describe("jin.view.read ordering", function()
  it("keeps only the result of the latest read", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    -- The newer read finishes first; the older one must not overwrite it.
    host.runs[2].on_exit(ok("new\n"))
    host.runs[1].on_exit(ok("old\n"))
    assert.same({ "new" }, host.rendered[bufnr].lines)
  end)

  it("writes nothing to a buffer that was closed meanwhile", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    host.loaded = {}
    host.finish(ok("late\n"))
    assert.is_nil(host.rendered[bufnr])
    assert.is_nil(view.meta(host, bufnr))
  end)

  it("forgets an unloaded buffer, ignoring a read still running for it", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    host.finish(ok("first\n"))
    view.read(jin, host, bufnr, "jin:///repo#log")
    view.forget(host, bufnr)
    assert.is_nil(view.meta(host, bufnr))
    host.finish(ok("late\n"))
    assert.same({ "first" }, host.rendered[bufnr].lines)
    assert.is_nil(view.meta(host, bufnr))
  end)

  it("writes nothing to a buffer that now holds another name", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    host.loaded[1].name = "/repo/other.txt"
    host.finish(ok("late\n"))
    assert.is_nil(host.rendered[bufnr])
  end)
end)

describe("jin.view.read again", function()
  local DIFF_A = "Modified regular file a.txt:\n   1    1: x\n   2    2: y\n"
  local DIFF_B = DIFF_A .. "Modified regular file b.txt:\n   1    1: z\n   2    2: w\n"

  local function reread(host, jin, bufnr, stdout)
    view.read(jin, host, bufnr, "jin:///repo;view=diff#")
    host.finish(ok(stdout))
    return host.rendered[bufnr]
  end

  it("folds the sections found by each read", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;view=diff#")
    assert.same({ { 1, 3 } }, reread(host, jin, bufnr, DIFF_A).folds)
    assert.same({ { 1, 3 }, { 4, 6 } }, reread(host, jin, bufnr, DIFF_B).folds)
  end)

  it(
    "tells the host the first read since the buffer was loaded, to set its filetype up anew",
    function()
      local host, jin = setup()
      local bufnr = host.load("jin:///repo#log")
      view.read(jin, host, bufnr, "jin:///repo#log")
      host.finish(ok("a\n"))
      assert.is_true(host.rendered[bufnr].fresh)
      view.read(jin, host, bufnr, "jin:///repo#log")
      host.finish(ok("a\n"))
      assert.is_false(host.rendered[bufnr].fresh)
      view.forget(host, bufnr)
      view.read(jin, host, bufnr, "jin:///repo#log")
      host.finish(ok("a\n"))
      assert.is_true(host.rendered[bufnr].fresh)
    end
  )

  it("maps the actions once, and again after the buffer was unloaded", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;view=diff#")
    reread(host, jin, bufnr, DIFF_A)
    host.defined = {}
    reread(host, jin, bufnr, DIFF_A)
    assert.is_nil(host.defined[bufnr])
    view.forget(host, bufnr)
    reread(host, jin, bufnr, DIFF_A)
    assert.truthy(host.defined[bufnr])
  end)

  it(
    "maps the default keys and motions of the view, split the way the user splits diffs",
    function()
      local host, jin = setup()
      host.vertical_split = true
      local bufnr = host.load("jin:///repo;view=diff#")
      reread(host, jin, bufnr, DIFF_A)
      assert.same({
        view = "diff",
        keys = action.keys(view.get("diff"), true),
        motions = require("jin.view.block").keys(view.get("diff")),
      }, host.keys[bufnr])
    end
  )
end)

describe("jin.view.name", function()
  it("records the view in the name, but not for the raw view", function()
    local host, jin = setup()
    assert.equal("jin:///repo;view=probe#-r @", view.name(jin, host, "probe", { "-r", "@" }, {}))
    assert.equal("jin:///repo#log", view.name(jin, host, "buffer", { "log" }, {}))
  end)

  it("rejects a view it does not know", function()
    local host, jin = setup()
    assert.has_error(function()
      view.name(jin, host, "nope", {}, {})
    end, "jin: unknown view: nope")
  end)
end)

describe("jin.view.refresh", function()
  local DIFF = "jin:///repo;view=diff#"
  local OP = { "op", "log", "--limit", "1", "--no-graph", "-T", 'id ++ "\\n"' }

  local function opened(host, jin, name)
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok(""))
    return bufnr
  end

  ---Look at the repository once, answering with `op`, and return how many
  ---processes ran.
  local function look(host, jin, op, bufnr)
    view.refresh(jin, host, bufnr)
    host.finish(ok(op .. "\n"))
    while host.runs[#host.runs] and not host.runs[#host.runs].finished do
      host.finish(ok(""))
    end
    return #host.runs
  end

  it("reads the views again once the repository moved on, and not before", function()
    local host, jin = setup()
    opened(host, jin, DIFF)
    assert.equal(3, look(host, jin, "op1"))
    assert.same(OP, words(host.runs[2]))
    assert.equal(4, look(host, jin, "op1"))
    assert.equal(6, look(host, jin, "op2"))
    assert.same({ "diff", "--color-words" }, words(host.runs[6]))
  end)

  it("reads them again at the first look, which has nothing to compare with", function()
    local host, jin = setup()
    opened(host, jin, DIFF)
    look(host, jin, "op1")
    assert.same({ "diff", "--color-words" }, words(host.runs[3]))
  end)

  it("asks only about the workspace of the buffer given", function()
    local host, jin = setup()
    host.dirs["/lib"] = true
    host.dirs["/lib/.jj"] = true
    local bufnr = opened(host, jin, DIFF)
    opened(host, jin, "jin:///lib;view=diff#")
    look(host, jin, "op1", bufnr)
    assert.equal("/repo", host.runs[3].cwd)
    assert.equal(4, #host.runs)
  end)

  it("leaves a view at a given operation as it is, but follows one relative to @", function()
    local host, jin = setup()
    opened(host, jin, "jin:///repo;view=diff#--at-op op0")
    view.refresh(jin, host)
    assert.equal(1, #host.runs)
    opened(host, jin, "jin:///repo;view=diff#--at-op @-")
    look(host, jin, "op1")
    assert.same({ "diff", "--color-words", "--at-op", "@-" }, words(host.runs[#host.runs]))
  end)

  it("never runs a jj command of :JinBuffer again by itself", function()
    local host, jin = setup()
    opened(host, jin, "jin:///repo#new")
    view.refresh(jin, host)
    assert.equal(1, #host.runs)
  end)

  it("looks without a snapshot when every view of the workspace asks for none", function()
    local host, jin = setup()
    opened(host, jin, DIFF .. "--ignore-working-copy")
    look(host, jin, "op1")
    assert.equal("--ignore-working-copy", words(host.runs[2])[#OP + 1])
    opened(host, jin, DIFF)
    look(host, jin, "op1")
    assert.is_nil(words(host.runs[5])[#OP + 1])
  end)

  it("takes a view relative to an operation for one that asks for no snapshot", function()
    local host, jin = setup()
    opened(host, jin, DIFF .. "--at-op @-")
    look(host, jin, "op1")
    assert.equal("--ignore-working-copy", words(host.runs[2])[#OP + 1])
  end)

  it("reads no flag in the paths after --", function()
    local host, jin = setup()
    opened(host, jin, DIFF .. "-- --ignore-working-copy")
    look(host, jin, "op1")
    assert.is_nil(words(host.runs[2])[#OP + 1])
  end)
end)

describe("the title of a vim-jin buffer", function()
  local function title(name)
    local host, jin = setup()
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    for _ = 1, 2 do
      if host.runs[#host.runs] and not host.runs[#host.runs].finished then
        host.finish(ok(""))
      end
    end
    return host.rendered[bufnr].title
  end

  it("names the jj command shown, without the workspace", function()
    assert.equal("jj log -r @", title(NAME))
    assert.equal("jj diff", title("jin:///repo;view=diff#"))
    assert.equal("jj log --no-graph", title("jin:///repo#log --no-graph"))
  end)

  it("shortens long IDs and quotes words with spaces", function()
    local op = ("0123456789abcdef"):rep(8)
    assert.equal("jj show 0123456789ab", title("jin:///repo;view=show#" .. op))
    assert.equal(
      [[jj file show -r @ 'my file.txt']],
      title([[jin:///repo;view=file#-r @ my\ file.txt]])
    )
  end)
end)
