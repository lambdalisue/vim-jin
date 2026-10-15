local fake_host = require("support.fake_host")
local api = require("jin.api")

local function ok(stdout)
  return { code = 0, stdout = stdout or "", stderr = "" }
end

describe("jin.api.new", function()
  it("runs jj on the host it is given", function()
    local host = fake_host.new()
    host.results = { ok("out\n") }
    local jin = api.new(function()
      return host
    end)
    assert.same(ok("out\n"), jin.jj({ "log" }))
    assert.same("log", host.runs[1].argv[#host.runs[1].argv])
  end)

  it("runs commands that echo and fire JinCommandPost on that host", function()
    local host = fake_host.new()
    host.results = { ok("done\n") }
    local jin = api.new(function()
      return host
    end)
    jin.command({ "new" }, { wait = true })
    host.fire_timers()
    assert.same({ { text = "done" } }, host.messages)
    assert.same({ "JinCommandPost" }, host.events)
  end)

  it("finds workspace roots on that host", function()
    local host = fake_host.new({ cwd = "/repo/sub", dirs = { "/repo/.jj" } })
    local jin = api.new(function()
      return host
    end)
    assert.equal("/repo", jin.root())
  end)

  it("asks for the host only when a function is called", function()
    api.new(function()
      error("asked too early")
    end)
  end)
end)
