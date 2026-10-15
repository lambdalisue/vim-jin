local fake_host = require("support.fake_host")
local api = require("jin.api")
local buffer = require("jin.command.buffer")
local view = require("jin.view")

local ESC = "\27"

local function setup(opts)
  local host = fake_host.new(opts or { cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function ok(stdout, stderr)
  return { code = 0, stdout = stdout or "", stderr = stderr or "" }
end

describe("jin.command.buffer.open", function()
  it("names the buffer after the workspace, the options and the arguments", function()
    local host, jin = setup()
    buffer.open(jin, host, { "log", "-r", "@" }, { monochrome = true, filetype = "x" })
    assert.equal("jin:///repo;filetype=x;monochrome#log -r @", host.opened[1].name)
  end)

  it("opens it with the opener and modifiers given", function()
    local host, jin = setup()
    buffer.open(jin, host, { "log" }, { opener = "vsplit", mods = "botright" })
    assert.same({ name = "jin:///repo#log", opener = "vsplit", mods = "botright" }, host.opened[1])
  end)

  it("names the buffer after the workspace of the given directory", function()
    local host, jin = setup({ cwd = "/", dirs = { "/repo", "/repo/sub", "/repo/.jj" } })
    buffer.open(jin, host, { "log" }, { cwd = "/repo/sub" })
    assert.equal("jin:///repo#log", host.opened[1].name)
  end)

  it("names the buffer after the current directory outside any workspace", function()
    local host, jin = setup({ cwd = "/tmp", dirs = { "/tmp" } })
    buffer.open(jin, host, { "version" }, {})
    assert.equal("jin:///tmp#version", host.opened[1].name)
  end)

  it("leaves reading a buffer it has just created to the editor", function()
    local host, jin = setup()
    buffer.open(jin, host, { "log" }, { reload = true })
    assert.same({}, host.runs)
  end)

  it("reads an open buffer again when told to reload", function()
    local host, jin = setup()
    buffer.open(jin, host, { "log" }, {})
    buffer.open(jin, host, { "log" }, { reload = true })
    host.finish(ok("fresh\n"))
    assert.same({ "fresh" }, host.rendered[1].lines)
  end)
end)

describe("jin.view.read of the raw view", function()
  it("shows what jj prints, with its colors as highlights", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log")
    view.read(jin, host, bufnr, "jin:///repo#log")
    host.finish(ok(ESC .. "[1;31mabc" .. ESC .. "[0m def\nsecond\n"))
    local argv = host.runs[1].argv
    assert.equal("always", argv[3])
    assert.equal("log", argv[#argv])
    assert.equal("/repo", host.runs[1].cwd)
    assert.same({
      lines = { "abc def", "second" },
      highlights = { { line = 1, col = 1, end_col = 4, group = "JinAnsiF1b" } },
      groups = { JinAnsiF1b = { fg = 1, bold = true } },
      filetype = "jin-buffer",
      title = "jj log",
      fresh = true,
    }, host.rendered[bufnr])
  end)

  it("asks jj for no colors with monochrome", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;monochrome#log")
    view.read(jin, host, bufnr, "jin:///repo;monochrome#log")
    host.finish(ok("plain\n"))
    assert.equal("never", host.runs[1].argv[3])
    assert.same({}, host.rendered[bufnr].highlights)
  end)

  it("sets the filetype given", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo;filetype=diff#diff")
    view.read(jin, host, bufnr, "jin:///repo;filetype=diff#diff")
    host.finish(ok(""))
    assert.equal("diff", host.rendered[bufnr].filetype)
  end)

  it("shows nothing for empty output, and leaves stderr out when jj succeeds", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#new")
    view.read(jin, host, bufnr, "jin:///repo#new")
    host.finish(ok("", "Warning: something\n"))
    assert.same({}, host.rendered[bufnr].lines)
  end)

  it("shows what jj printed on stderr as well when it fails", function()
    local host, jin = setup()
    local bufnr = host.load("jin:///repo#log -r nope")
    view.read(jin, host, bufnr, "jin:///repo#log -r nope")
    host.finish({ code = 1, stdout = "partial\n", stderr = "Error: bad revset\n" })
    assert.same({ "partial", "Error: bad revset" }, host.rendered[bufnr].lines)
  end)

  it("rejects a name that is not a vim-jin buffer", function()
    local host, jin = setup()
    assert.has_error(function()
      view.read(jin, host, 1, "/repo/file.lua")
    end, "jin: not a vim-jin buffer: /repo/file.lua")
  end)
end)

describe("jin.view.reload", function()
  it("reads every loaded vim-jin buffer again, and nothing else", function()
    local host, jin = setup()
    host.load("jin:///repo#log")
    host.load("/repo/file.lua")
    host.load("jin:///repo#status")
    view.reload(jin, host)
    host.finish(ok("one\n"))
    host.finish(ok("two\n"))
    assert.same({ "one" }, host.rendered[1].lines)
    assert.is_nil(host.rendered[2])
    assert.same({ "two" }, host.rendered[3].lines)
  end)
end)

describe("jin.command.buffer.command", function()
  it("takes the leading ++ options and runs the rest", function()
    local host, jin = setup()
    buffer.command(jin, host, [[++opener=botright\ split ++monochrome log -r 'a | b']], {})
    assert.same({
      name = [[jin:///repo;monochrome#log -r a\ |\ b]],
      opener = "botright split",
    }, host.opened[1])
  end)

  it("reloads with a bang and passes the modifiers on", function()
    local host, jin = setup()
    buffer.command(jin, host, "log", { mods = "tab" })
    buffer.command(jin, host, "log", { bang = true, mods = "tab" })
    host.finish(ok("again\n"))
    assert.equal("tab", host.opened[2].mods)
    assert.same({ "again" }, host.rendered[1].lines)
  end)

  it("rejects an unknown ++ option without opening anything", function()
    local host, jin = setup()
    assert.has_error(function()
      buffer.command(jin, host, "++wait log", {})
    end, "jin: unknown option ++wait")
    assert.same({}, host.opened)
  end)
end)
