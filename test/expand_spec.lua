local fake_host = require("support.fake_host")
local expand = require("jin.expand")

describe("jin.expand.path", function()
  it("names the file of the buffer relative to its workspace root", function()
    local host = fake_host.new({ bufname = "/repo/src/a.lua", dirs = { "/repo/.jj" } })
    assert.equal("src/a.lua", expand.path(host))
  end)

  it("follows a symlinked buffer into its workspace", function()
    local host = fake_host.new({
      bufname = "/home/a.lua",
      links = { ["/home/a.lua"] = "/repo/a.lua" },
      dirs = { "/repo/.jj" },
    })
    assert.equal("a.lua", expand.path(host))
  end)

  it("keeps the path as it is outside any workspace", function()
    local host = fake_host.new({ bufname = "/tmp/a.txt" })
    assert.equal("/tmp/a.txt", expand.path(host))
  end)

  it("refuses in a buffer without a name", function()
    local host = fake_host.new()
    assert.has_error(function()
      expand.path(host)
    end, "jin: % stands for no file, as the buffer has no name")
  end)
end)
