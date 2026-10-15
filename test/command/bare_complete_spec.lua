local fake_host = require("support.fake_host")
local bare = require("jin.command.bare")

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

---Complete `cmdline` with the cursor at its end, as Vim would call it.
local function complete(host, cmdline)
  local arglead = cmdline:match("(%S*)$")
  return bare.complete(host, arglead, cmdline, #cmdline)
end

---The words handed to jj's completion, after `jj -- jj`.
local function jj_words(host)
  local argv = host.runs[1].argv
  local words = {}
  for i = 4, #argv do
    words[#words + 1] = argv[i]
  end
  return words
end

describe("jin.command.bare.complete", function()
  describe("what it asks jj", function()
    it("asks jj's own completion about the words typed so far", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, "Jin log -r ")
      assert.same({ "jj", "--", "jj", "log", "-r", "" }, host.runs[1].argv)
      assert.same({ COMPLETE = "fish" }, host.runs[1].env)
    end)

    it("hands jj the word under the cursor as the one to complete", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, "Jin lo")
      assert.same({ "lo" }, jj_words(host))
    end)

    it("ignores what follows the cursor", function()
      local host = fake_host.new()
      host.results = { ok("") }
      bare.complete(host, "lo", "Jin lo -r @", 6)
      assert.same({ "lo" }, jj_words(host))
    end)

    it("finds the command after modifiers and when abbreviated", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, "silent Ji st")
      assert.same({ "st" }, jj_words(host))
    end)

    it("leaves the leading ++ options out of what jj sees", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, "Jin ++wait lo")
      assert.same({ "lo" }, jj_words(host))
    end)

    it("hands jj an escaped space as part of the word", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, [[Jin file show my\ fi]])
      assert.same({ "file", "show", "my fi" }, jj_words(host))
    end)

    it("hands jj the value of a word whose quote is still open", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, [[Jin file show "my fi]])
      assert.same({ "file", "show", "my fi" }, jj_words(host))
    end)

    it("asks in the same workspace :Jin would run in", function()
      local host = fake_host.new({
        cwd = "/other",
        bufname = "/repo/a.txt",
        dirs = { "/repo/.jj" },
      })
      host.results = { ok("") }
      complete(host, "Jin lo")
      assert.equal("/repo", host.runs[1].cwd)
    end)
  end)

  describe("what it offers", function()
    it("offers the values jj lists, without their descriptions", function()
      local host = fake_host.new()
      host.results = { ok("log\tShow revision history\nlocal\n") }
      assert.same({ "log", "local" }, complete(host, "Jin lo"))
    end)

    it("escapes candidates so they come back as one argument", function()
      local host = fake_host.new()
      host.results = { ok("my file.txt\n") }
      assert.same({ [[my\ file.txt]] }, complete(host, "Jin file show my"))
    end)

    it("completes inside an open double quote and closes it", function()
      local host = fake_host.new()
      host.results = { ok('my "file".txt\n') }
      -- Vim replaces only what follows the last space, "fi" here.
      assert.same({ [[\"file\".txt"]] }, complete(host, [[Jin file show "my \"fi]]))
    end)

    it("completes inside an open single quote and closes it", function()
      local host = fake_host.new()
      host.results = { ok("my it's.txt\n") }
      assert.same({ [[it'\''s.txt']] }, complete(host, [[Jin file show 'my it]]))
    end)

    it("leaves the quote open after a directory, to go on into it", function()
      local host = fake_host.new()
      host.results = { ok("my dir/\n") }
      assert.same({ "dir/" }, complete(host, [[Jin file show "my d]]))
    end)

    it("offers ++ options in place of jj's candidates while they can be given", function()
      local host = fake_host.new()
      assert.same({ "++wait" }, complete(host, "Jin ++w"))
      assert.same({}, host.runs)
    end)

    it("leaves a ++ word after the first jj argument to jj", function()
      local host = fake_host.new()
      host.results = { ok("") }
      complete(host, "Jin log ++w")
      assert.same({ "log", "++w" }, jj_words(host))
    end)

    it("offers nothing when jj fails", function()
      local host = fake_host.new()
      host.results = { { code = 1, stdout = "", stderr = "error\n" } }
      assert.same({}, complete(host, "Jin lo"))
    end)

    it("offers nothing when jj does not answer in time", function()
      local host = fake_host.new()
      assert.same({}, complete(host, "Jin lo"))
    end)
  end)

  describe("caching", function()
    it("reuses jj's answer when the same words are completed again", function()
      local host = fake_host.new()
      host.results = { ok("log\n") }
      complete(host, "Jin lo")
      assert.same({ "log" }, complete(host, "Jin lo"))
      assert.equal(1, #host.runs)
    end)

    it("narrows a cached answer as the word grows by name characters", function()
      local host = fake_host.new()
      host.results = { ok("log\nlocal-thing\nlock_x\n") }
      complete(host, "Jin lo")
      assert.same({ "local-thing" }, complete(host, "Jin local-"))
      assert.same({ "lock_x" }, complete(host, "Jin lock_"))
      assert.equal(1, #host.runs)
    end)

    it("asks jj again when the word grows past a separator", function()
      for _, grown in ipairs({ "lua/", "main..", "a|", "x@", "f.t" }) do
        local host = fake_host.new()
        host.results = { ok(""), ok("") }
        complete(host, "Jin log " .. grown:sub(1, 1))
        complete(host, "Jin log " .. grown)
        assert.equal(2, #host.runs, grown)
      end
    end)

    it("asks jj again when the word shrinks", function()
      local host = fake_host.new()
      host.results = { ok("log\n"), ok("log\nlocal\n") }
      complete(host, "Jin log")
      assert.same({ "log", "local" }, complete(host, "Jin lo"))
    end)

    it("asks jj again when an earlier word changes", function()
      local host = fake_host.new()
      host.results = { ok(""), ok("") }
      complete(host, "Jin log -r ")
      complete(host, "Jin new -r ")
      assert.equal(2, #host.runs)
    end)

    it("asks jj again in another workspace", function()
      local host = fake_host.new({ dirs = { "/a/.jj", "/b/.jj" }, cwd = "/a" })
      host.results = { ok(""), ok("") }
      complete(host, "Jin lo")
      host.state.cwd = "/b"
      complete(host, "Jin lo")
      assert.equal(2, #host.runs)
    end)

    it("asks jj again once the answer is a few seconds old", function()
      local host = fake_host.new()
      host.results = { ok("log\n"), ok("log\n") }
      complete(host, "Jin lo")
      host.clock = host.clock + 10000
      complete(host, "Jin lo")
      assert.equal(2, #host.runs)
    end)

    it("asks jj again after a :Jin command finishes", function()
      local host = fake_host.new()
      host.results = { ok("log\n"), ok("main\n"), ok("log\n") }
      complete(host, "Jin lo")
      bare.run(host, { "new" }, { wait = true })
      complete(host, "Jin lo")
      assert.equal(3, #host.runs)
    end)

    it("does not keep an answer jj failed to give", function()
      local host = fake_host.new()
      host.results = { { code = 1, stdout = "", stderr = "" }, ok("log\n") }
      complete(host, "Jin lo")
      assert.same({ "log" }, complete(host, "Jin lo"))
    end)

    it("keeps candidates unescaped, so each use writes them for its place", function()
      local host = fake_host.new()
      host.results = { ok("my file.txt\n") }
      assert.same({ "file.txt" }, complete(host, [[Jin file show my\ f]]))
      assert.same({ [[file.txt"]] }, complete(host, [[Jin file show "my f]]))
      assert.equal(1, #host.runs)
    end)
  end)
end)
