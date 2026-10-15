local fake_host = require("support.fake_host")
local jj = require("jin.jj")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

describe("jin.jj.run", function()
  it("runs jj with the arguments after settings that keep output plain", function()
    local host = fake_host.new()
    jj.run(host, { "log", "-r", "@" }, {}, function() end)
    assert.same({ "jj", "--color", "never", "--no-pager", "log", "-r", "@" }, host.runs[1].argv)
  end)

  it("asks jj for color when told to", function()
    local host = fake_host.new()
    jj.run(host, { "log" }, { color = true }, function() end)
    assert.equal("always", host.runs[1].argv[3])
  end)

  it("runs in the workspace of the current buffer", function()
    local host = fake_host.new({ cwd = "/other", bufname = "/repo/a.txt", dirs = { "/repo/.jj" } })
    jj.run(host, { "status" }, {}, function() end)
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("follows a symlinked buffer to the workspace it points into", function()
    local host = fake_host.new({
      cwd = "/other",
      bufname = "/home/notes.md",
      links = { ["/home/notes.md"] = "/repo/notes.md" },
      dirs = { "/repo/.jj", "/other/.jj" },
    })
    jj.run(host, { "status" }, {}, function() end)
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("looks from a directory buffer itself, not from its parent", function()
    local host = fake_host.new({
      cwd = "/other",
      bufname = "/repo/",
      dirs = { "/repo", "/repo/.jj", "/other/.jj" },
    })
    jj.run(host, { "status" }, {}, function() end)
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("falls back to the workspace of the current directory", function()
    local host =
      fake_host.new({ cwd = "/repo/sub", bufname = "/tmp/x.txt", dirs = { "/repo/.jj" } })
    jj.run(host, { "status" }, {}, function() end)
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("runs in the current directory outside any workspace", function()
    local host = fake_host.new({ cwd = "/new-project" })
    jj.run(host, { "git", "init" }, {}, function() end)
    assert.equal("/new-project", host.runs[1].cwd)
  end)

  it("runs in the workspace that holds the given directory", function()
    local host =
      fake_host.new({ bufname = "/repo/a.txt", dirs = { "/repo/.jj", "/lib/.jj", "/lib/src" } })
    jj.run(host, { "status" }, { cwd = "/lib/src" }, function() end)
    assert.equal("/lib", host.runs[1].cwd)
  end)

  it("takes a relative directory from the current directory", function()
    local host = fake_host.new({ cwd = "/repo/sub", dirs = { "/repo/sub", "/repo/.jj" } })
    jj.run(host, { "status" }, { cwd = "." }, function() end)
    assert.equal("/repo", host.runs[1].cwd)
  end)

  it("hands a directory that does not exist to jj as given, to fail there", function()
    local host = fake_host.new({ cwd = "/", dirs = { "/tmp/.jj" } })
    jj.run(host, { "git", "init" }, { cwd = "/tmp/missing/.." }, function() end)
    assert.equal("/tmp/missing/..", host.runs[1].cwd)
  end)

  it("runs in the given directory when it is in no workspace", function()
    local host = fake_host.new({ dirs = { "/repo/.jj" } })
    jj.run(host, { "git", "init" }, { cwd = "/new" }, function() end)
    assert.equal("/new", host.runs[1].cwd)
  end)

  it("passes env on to the process", function()
    local host = fake_host.new()
    jj.run(host, { "status" }, { env = { JJ_USER = "x" } }, function() end)
    assert.same({ JJ_USER = "x" }, host.runs[1].env)
  end)

  it("hands the result to on_exit without echoing or firing events", function()
    local host = fake_host.new()
    local got
    jj.run(host, { "log" }, {}, function(result)
      got = result
    end)
    host.finish(ok("out\n"))
    host.fire_timers()
    assert.same(ok("out\n"), got)
    assert.same({}, host.messages)
    assert.same({}, host.events)
  end)

  it("returns the result when no on_exit is given", function()
    local host = fake_host.new()
    host.results = { ok("out\n") }
    assert.same(ok("out\n"), jj.run(host, { "log" }, {}))
  end)
end)

describe("jin.jj.root", function()
  it("returns the workspace of the current buffer or directory", function()
    local host = fake_host.new({ cwd = "/repo/sub", dirs = { "/repo/.jj" } })
    assert.equal("/repo", jj.root(host))
  end)

  it("returns the workspace that holds the given path", function()
    local host = fake_host.new({ dirs = { "/repo/.jj", "/repo/src" } })
    assert.equal("/repo", jj.root(host, "/repo/src"))
    assert.equal("/repo", jj.root(host, "/repo/src/main.lua"))
  end)

  it("takes a relative path from the current directory", function()
    local host = fake_host.new({ cwd = "/repo/sub", dirs = { "/repo/sub", "/repo/.jj" } })
    assert.equal("/repo", jj.root(host, "."))
    assert.equal("/repo", jj.root(host, "../a.txt"))
  end)

  it("takes .. after a symlink from where the link points", function()
    local host = fake_host.new({
      links = { ["/outside/link"] = "/repo/sub" },
      dirs = { "/repo", "/repo/.jj", "/outside/.jj" },
    })
    assert.equal("/repo", jj.root(host, "/outside/link/.."))
  end)

  it("returns nil outside any workspace", function()
    local host = fake_host.new({ cwd = "/tmp" })
    assert.is_nil(jj.root(host))
    assert.is_nil(jj.root(host, "/tmp/x"))
  end)
end)
