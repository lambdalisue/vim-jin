local workspace = require("jin.workspace")

local function dirs(...)
  local set = {}
  for _, d in ipairs({ ... }) do
    set[d] = true
  end
  return function(path)
    return set[path] == true
  end
end

describe("jin.workspace.find_root", function()
  it("returns the directory itself when it holds .jj", function()
    assert.equal("/repo", workspace.find_root("/repo", dirs("/repo/.jj")))
  end)

  it("walks up to the nearest directory holding .jj", function()
    local is_dir = dirs("/repo/.jj", "/repo/sub/nested/.jj")
    assert.equal("/repo", workspace.find_root("/repo/a/b", is_dir))
    assert.equal("/repo/sub/nested", workspace.find_root("/repo/sub/nested/c", is_dir))
  end)

  it("finds a workspace at the filesystem root", function()
    assert.equal("/", workspace.find_root("/a/b", dirs("/.jj")))
  end)

  it("ignores a trailing slash", function()
    assert.equal("/repo", workspace.find_root("/repo/a/", dirs("/repo/.jj")))
  end)

  it("returns nil outside any workspace", function()
    assert.is_nil(workspace.find_root("/tmp/x", dirs("/repo/.jj")))
  end)
end)

describe("jin.workspace.find", function()
  it("takes the first candidate that is inside a workspace", function()
    local is_dir = dirs("/a/.jj", "/b/.jj")
    assert.equal("/b", workspace.find({ "/elsewhere", "/b/x", "/a" }, is_dir))
  end)

  it("skips empty candidates", function()
    assert.equal("/a", workspace.find({ "", "/a/x" }, dirs("/a/.jj")))
  end)

  it("returns nil when no candidate is inside a workspace", function()
    assert.is_nil(workspace.find({ "/x", "/y" }, dirs("/a/.jj")))
  end)
end)

describe("jin.workspace.absolute", function()
  it("leaves an absolute path as it is, apart from . and ..", function()
    assert.equal("/a/b", workspace.absolute("/a/b", "/base"))
    assert.equal("/a/c", workspace.absolute("/a/./b/../c", "/base"))
  end)

  it("resolves a relative path against the base directory", function()
    assert.equal("/repo/sub", workspace.absolute(".", "/repo/sub"))
    assert.equal("/repo", workspace.absolute("..", "/repo/sub"))
    assert.equal("/repo/sub/x/y", workspace.absolute("x/y/", "/repo/sub"))
  end)

  it("stops .. at the root", function()
    assert.equal("/", workspace.absolute("../../..", "/a"))
  end)

  it("takes .. after a symlink to the parent of where the link points", function()
    local function resolve(path)
      return path == "/outside/link" and "/repo/sub" or path
    end
    assert.equal("/repo", workspace.absolute("/outside/link/..", "/", resolve))
    assert.equal("/repo/x", workspace.absolute("link/../x", "/outside", resolve))
  end)
end)

describe("jin.workspace.dirname", function()
  it("returns the parent directory of a path", function()
    assert.equal("/a/b", workspace.dirname("/a/b/c.txt"))
  end)

  it("returns / for a path directly under the root", function()
    assert.equal("/", workspace.dirname("/c.txt"))
  end)

  it("returns an empty string for an empty path", function()
    assert.equal("", workspace.dirname(""))
  end)
end)
