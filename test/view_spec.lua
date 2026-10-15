local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")

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
  end)

  it("forgets an unloaded buffer, ignoring a read still running for it", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    host.finish(ok("first\n"))
    view.read(jin, host, bufnr, "jin:///repo#log")
    view.forget(host, bufnr)
    host.finish(ok("late\n"))
    assert.same({ "first" }, host.rendered[bufnr].lines)
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
end)

describe("jin.view.name", function()
  it("leaves the raw view out of the name", function()
    local host, jin = setup()
    assert.equal("jin:///repo#log", view.name(jin, host, "buffer", { "log" }, {}))
  end)

  it("rejects a view it does not know", function()
    local host, jin = setup()
    assert.has_error(function()
      view.name(jin, host, "nope", {}, {})
    end, "jin: unknown view: nope")
  end)
end)

describe("the title of a vim-jin buffer", function()
  local function title(name)
    local host, jin = setup()
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok(""))
    return host.rendered[bufnr].title
  end

  it("names the jj command shown, without the workspace", function()
    assert.equal("jj log --no-graph", title("jin:///repo#log --no-graph"))
  end)

  it("shortens long IDs and quotes words with spaces", function()
    local op = ("0123456789abcdef"):rep(8)
    assert.equal("jj op show 0123456789ab", title("jin:///repo#op show " .. op))
    assert.equal(
      [[jj file show -r @ 'my file.txt']],
      title([[jin:///repo#file show -r @ my\ file.txt]])
    )
  end)
end)
