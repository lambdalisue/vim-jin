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

  it("names the file a file view shows", function()
    local host = fake_host.new({ bufname = "jin:///repo;view=file#-r @- src/a.lua" })
    assert.equal("src/a.lua", expand.path(host))
  end)

  it("refuses in a vim-jin buffer that shows no file", function()
    local host = fake_host.new({ bufname = "jin:///repo;view=log#" })
    assert.has_error(function()
      expand.path(host)
    end, "jin: % stands for no file in this buffer")
  end)

  it("refuses in a buffer without a name", function()
    local host = fake_host.new()
    assert.has_error(function()
      expand.path(host)
    end, "jin: % stands for no file, as the buffer has no name")
  end)
end)

describe("jin.expand.file_path", function()
  it("takes the last argument that is not an option or a revision", function()
    assert.equal("a.lua", expand.file_path({ "-r", "@-", "a.lua" }))
    assert.equal("b c.lua", expand.file_path({ "--revision", "x", "--", "b c.lua" }))
    assert.is_nil(expand.file_path({ "-r", "x" }))
  end)

  it("takes no option's value for the path, a global one's included", function()
    assert.equal("f.lua", expand.file_path({ "-r", "@", "f.lua", "--at-op", "op1" }))
    assert.equal("f.lua", expand.file_path({ "f.lua", "-R", "/repo", "--config", "a=b" }))
    assert.equal("f.lua", expand.file_path({ "-r@-", "--revisions", "x", "f.lua" }))
  end)

  it("takes no template for the path", function()
    assert.equal("f.lua", expand.file_path({ "f.lua", "-T", "content" }))
    assert.equal("f.lua", expand.file_path({ "f.lua", "--template", "content" }))
    assert.equal("f.lua", expand.file_path({ "f.lua", "--template=content" }))
  end)

  it("takes a path after -- even when it looks like an option", function()
    assert.equal("-f.lua", expand.file_path({ "-r", "x", "--", "-f.lua" }))
  end)
end)
