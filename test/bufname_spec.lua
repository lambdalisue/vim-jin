local bufname = require("jin.bufname")

describe("jin.bufname.format", function()
  it("writes the scheme, the workspace and the arguments", function()
    assert.equal(
      "jin:///repo#log -r @",
      bufname.format({ scheme = "jin", root = "/repo", argv = { "log", "-r", "@" } })
    )
  end)

  it("writes parameters sorted, a flag without a value", function()
    assert.equal(
      "jin:///repo;filetype=x;monochrome#log",
      bufname.format({
        scheme = "jin",
        root = "/repo",
        params = { monochrome = true, filetype = "x" },
        argv = { "log" },
      })
    )
  end)

  it("quotes arguments the way :Jin reads them", function()
    assert.equal(
      [[jin:///repo#describe -m feat:\ add\ \"x\"]],
      bufname.format({
        scheme = "jin",
        root = "/repo",
        argv = { "describe", "-m", 'feat: add "x"' },
      })
    )
  end)

  it("escapes the characters that separate the parts", function()
    assert.equal(
      "jin:///a%3Bb%23c%25d;k%3D=v%3B#log",
      bufname.format({
        scheme = "jin",
        root = "/a;b#c%d",
        params = { ["k="] = "v;" },
        argv = { "log" },
      })
    )
  end)
end)

describe("jin.bufname.parse", function()
  local cases = {
    { scheme = "jin", root = "/repo", params = {}, argv = {} },
    { scheme = "jin", root = "/repo", params = {}, argv = { "log", "-r", "root()|@" } },
    { scheme = "jin", root = "/repo", params = {}, argv = { "log", "-T", "", "-r", "@" } },
    {
      scheme = "jin",
      root = "/a;b#c%d e",
      params = { monochrome = true, filetype = "jin-buffer", ["k=;#"] = "v=;#%" },
      argv = { "describe", "-m", [[it's "x" \ #y]] },
    },
  }

  for i, case in ipairs(cases) do
    it(("gives back what format took, case %d"):format(i), function()
      assert.same(case, bufname.parse(bufname.format(case)))
    end)
  end

  it("returns nil for a name that is not a vim-jin buffer", function()
    assert.is_nil(bufname.parse("/repo/file.lua"))
    assert.is_nil(bufname.parse("term://~//123:/bin/sh"))
  end)
end)
