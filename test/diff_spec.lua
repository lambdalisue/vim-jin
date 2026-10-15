local diff = require("jin.diff")

local SAMPLE = {
  "Commit ID: abc", -- 1
  "", -- 2
  "Modified regular file bin.dat:", -- 3
  "    (binary)", -- 4
  "Removed regular file gone.txt:", -- 5
  "   1     : old", -- 6
  "Modified regular file keep.txt:", -- 7
  "   1    1: a", -- 8
  "   2     : b", -- 9
  "        2: B", -- 10
  "    ...", -- 11
  "  10   11: c", -- 12
  "Added executable file new.sh:", -- 13
  "        1: x", -- 14
  "Modified regular file to.txt (from.txt => to.txt):", -- 15
}

describe("jin.diff.parse", function()
  local parsed = diff.parse(SAMPLE)

  it("finds each file section with its status and path", function()
    local sections = {}
    for _, s in ipairs(parsed.files) do
      sections[#sections + 1] = { s.status, s.path, s.from, s.first, s.last }
    end
    assert.same({
      { "modified", "bin.dat", nil, 3, 4 },
      { "removed", "gone.txt", nil, 5, 6 },
      { "modified", "keep.txt", nil, 7, 12 },
      { "added", "new.sh", nil, 13, 14 },
      { "modified", "to.txt", "from.txt", 15, 15 },
    }, sections)
  end)

  it("maps a line shown on both sides to both line numbers", function()
    assert.same({ path = "keep.txt", old = 1, new = 1 }, parsed.lines[8])
    assert.same({ path = "keep.txt", old = 10, new = 11 }, parsed.lines[12])
  end)

  it("maps a removed line to the old side only, and an added line to the new side only", function()
    assert.same({ path = "keep.txt", old = 2 }, parsed.lines[9])
    assert.same({ path = "keep.txt", new = 2 }, parsed.lines[10])
    assert.same({ path = "gone.txt", old = 1 }, parsed.lines[6])
  end)

  it("maps a header to the start of its file", function()
    assert.same({ path = "keep.txt" }, parsed.lines[7])
    assert.same({ path = "to.txt", from = "from.txt" }, parsed.lines[15])
  end)

  it("maps other lines of a section to its file without a position", function()
    assert.same({ path = "bin.dat" }, parsed.lines[4])
    assert.same({ path = "keep.txt" }, parsed.lines[11])
  end)

  it("maps nothing before the first file", function()
    assert.is_nil(parsed.lines[1])
    assert.is_nil(parsed.lines[2])
  end)

  it("reads paths with spaces and colons", function()
    local p = diff.parse({ "Added regular file my dir/a: b.txt:", "        1: x" })
    assert.equal("my dir/a: b.txt", p.files[1].path)
    assert.same({ path = "my dir/a: b.txt", new = 1 }, p.lines[2])
  end)
end)

describe("jin.diff.sides", function()
  it("compares a revision with its parents for -r, and for show", function()
    assert.same({ old = "x-", new = "x" }, diff.sides({ "-r", "x" }))
    assert.same({ old = "x-", new = "x" }, diff.sides({ "--revision=x" }))
    assert.same({ old = "x-", new = "x" }, diff.sides({ "--revisions", "x" }))
    assert.same({ old = "x-", new = "x" }, diff.sides({ "--revisions=x" }))
    assert.same({ old = "x-", new = "x" }, diff.sides({ "x" }, true))
  end)

  it("compares --from and --to, each defaulting to @", function()
    assert.same({ old = "a", new = "b" }, diff.sides({ "--from", "a", "--to", "b" }))
    assert.same({ old = "a", new = "@" }, diff.sides({ "--from=a" }))
    assert.same({ old = "@", new = "b" }, diff.sides({ "--to", "b" }))
  end)

  it("compares the working copy with its parent by default", function()
    assert.same({ old = "@-", new = "@" }, diff.sides({ "--", "a.txt" }))
    assert.same({ old = "@-", new = "@" }, diff.sides({}, true))
  end)
end)

describe("jin.diff.sides of a revset", function()
  it("takes the parents of the whole revset, not of its last term", function()
    assert.same({ old = "(a::b)-", new = "a::b" }, diff.sides({ "-r", "a::b" }))
    assert.same({ old = "(x | y)-", new = "x | y" }, diff.sides({ "-r", "x | y" }))
  end)

  it("skips the values of jj's global options", function()
    assert.same({ old = "@-", new = "@" }, diff.sides({ "--config", "x=-ry" }))
    assert.same({ old = "x-", new = "x" }, diff.sides({ "-R", "repo", "x" }, true))
  end)
end)
