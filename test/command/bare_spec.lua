local fake_host = require("support.fake_host")
local bare = require("jin.command.bare")

local PLAIN = { "jj", "--color", "never", "--no-pager" }

local function plain(...)
  local argv = {}
  for _, a in ipairs(PLAIN) do
    argv[#argv + 1] = a
  end
  for _, a in ipairs({ ... }) do
    argv[#argv + 1] = a
  end
  return argv
end

local function ok(stdout, stderr)
  return { code = 0, stdout = stdout or "", stderr = stderr or "" }
end

describe("jin.command.bare.run", function()
  describe("what it runs", function()
    it("runs jj with the arguments unchanged, after flags that keep output plain", function()
      local host = fake_host.new()
      bare.run(host, { "log", "-r", "@", "--color=always" }, {})
      assert.same(plain("log", "-r", "@", "--color=always"), host.runs[1].argv)
    end)

    it("passes ++-looking arguments to jj, as options come in opts", function()
      local host = fake_host.new()
      bare.run(host, { "++wait" }, {})
      assert.same(plain("++wait"), host.runs[1].argv)
    end)

    it("runs where jin.jj would run", function()
      local host =
        fake_host.new({ bufname = "/repo/a.txt", dirs = { "/repo/.jj", "/lib/.jj", "/lib/src" } })
      bare.run(host, { "status" }, {})
      bare.run(host, { "status" }, { cwd = "/lib/src" })
      assert.equal("/repo", host.runs[1].cwd)
      assert.equal("/lib", host.runs[2].cwd)
    end)
  end)

  describe("what it shows", function()
    it("echoes stdout, then stderr, without the final newline", function()
      local host = fake_host.new()
      bare.run(host, { "new" }, {})
      host.finish(ok("out\n", "Working copy now at: abc\n"))
      assert.same({ { text = "out\nWorking copy now at: abc" } }, host.messages)
    end)

    it("echoes in the error highlight when jj fails", function()
      local host = fake_host.new()
      bare.run(host, { "nonsense" }, {})
      host.finish({ code = 2, stdout = "", stderr = "error: unrecognized subcommand\n" })
      assert.same({ { text = "error: unrecognized subcommand", hl = "ErrorMsg" } }, host.messages)
    end)

    it("echoes nothing when jj prints nothing", function()
      local host = fake_host.new()
      bare.run(host, { "describe", "-m", "x", "--quiet" }, {})
      host.finish(ok())
      assert.same({}, host.messages)
    end)
  end)

  describe("when it returns", function()
    it("returns before jj finishes", function()
      local host = fake_host.new()
      bare.run(host, { "status" }, {})
      assert.is_nil(host.runs[1].finished)
      assert.same({}, host.messages)
    end)

    it("returns after jj finishes with wait", function()
      local host = fake_host.new()
      host.results = { ok("done\n") }
      bare.run(host, { "status" }, { wait = true })
      assert.is_true(host.runs[1].finished)
      assert.same({ { text = "done" } }, host.messages)
    end)

    it("hands the result to on_exit after echoing", function()
      local host = fake_host.new()
      local seen
      bare.run(host, { "new" }, {}, function(result)
        seen = { result = result, messages = #host.messages }
      end)
      host.finish(ok("out\n"))
      assert.same({ result = ok("out\n"), messages = 1 }, seen)
    end)
  end)

  describe("JinCommandPost", function()
    it("fires once jj finishes", function()
      local host = fake_host.new()
      bare.run(host, { "new" }, {})
      host.fire_timers()
      assert.same({}, host.events)
      host.finish(ok())
      host.fire_timers()
      assert.same({ "JinCommandPost" }, host.events)
    end)

    it("fires after a failed command too, as jj may have changed the repository", function()
      local host = fake_host.new()
      bare.run(host, { "rebase" }, {})
      host.finish({ code = 1, stdout = "", stderr = "error\n" })
      host.fire_timers()
      assert.same({ "JinCommandPost" }, host.events)
    end)

    it("fires once for commands that finish close together", function()
      local host = fake_host.new()
      bare.run(host, { "new" }, {})
      bare.run(host, { "describe", "-m", "x" }, {})
      host.finish(ok())
      host.finish(ok())
      host.fire_timers()
      assert.same({ "JinCommandPost" }, host.events)
    end)
  end)
end)
