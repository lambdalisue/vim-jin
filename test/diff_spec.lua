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

  it("ends a file at a section that is no file, such as the description", function()
    local lines = {
      "Modified regular file f.txt:",
      "   1    1: old new",
      "Modified JJ-COMMIT-DESCRIPTION:",
      "   1    1: before after",
    }
    local described = diff.parse(lines)
    assert.equal(2, described.files[1].last)
    assert.is_nil(described.lines[3])
    assert.is_nil(described.lines[4])
  end)

  it("keeps a line numbered 1000 or more that ends with a colon in its file", function()
    local numbered = diff.parse({ "Modified regular file f.yml:", "1000 1000: key:" })
    assert.same({ path = "f.yml", old = 1000, new = 1000 }, numbered.lines[2])
  end)

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

describe("jin.diff.counterpart", function()
  local SHOWN = diff.parse({
    "Commit ID: c", -- 1
    "Modified regular file a.txt:", -- 2
    "   1    1: a", -- 3
    "   2     : b", -- 4
    "        2: B", -- 5
    "   3    3: c", -- 6
    "Added regular file new.txt:", -- 7
    "        1: n", -- 8
    "Modified regular file to.txt (from.txt => to.txt):", -- 9
    "   4    4: r", -- 10
  })

  -- The parent's new side is the old side of the change shown.
  local PARENT = diff.parse({
    "Commit ID: p", -- 1
    "", -- 2
    "Modified regular file a.txt:", -- 3
    "   1     : x", -- 4
    "        1: a", -- 5
    "   2    2: b", -- 6
    "    ...", -- 7
    "   9    9: i", -- 8
    "Modified regular file from.txt:", -- 9
    "   4    4: r", -- 10
  })

  -- The child's old side is the new side of the change shown.
  local CHILD = diff.parse({
    "Commit ID: k", -- 1
    "Modified regular file to.txt:", -- 2
    "   4    5: r", -- 3
    "Modified regular file a.txt:", -- 4
    "   2    2: B", -- 5
    "   3     : c", -- 6
  })

  it("finds the line of the parent whose new side is the old side of the line", function()
    assert.equal(5, diff.counterpart(SHOWN, 3, PARENT, "old"))
    assert.equal(6, diff.counterpart(SHOWN, 4, PARENT, "old"))
  end)

  it("finds the line of the child whose old side is the new side of the line", function()
    assert.equal(5, diff.counterpart(SHOWN, 5, CHILD, "new"))
    assert.equal(6, diff.counterpart(SHOWN, 6, CHILD, "new"))
  end)

  it("takes the nearest line on the side for one not on it, the one above first", function()
    -- Line 5 is added, so it has no old side; lines 4 and 6 are as near.
    assert.equal(6, diff.counterpart(SHOWN, 5, PARENT, "old"))
    -- Line 4 is removed, so it has no new side.
    assert.equal(5, diff.counterpart(SHOWN, 4, CHILD, "new"))
  end)

  it("goes to the nearest numbered line of the file when the other diff skips the line", function()
    -- Old line 3 is in neither hunk of the parent's a.txt: 2 is nearer than 9.
    assert.equal(6, diff.counterpart(SHOWN, 6, PARENT, "old"))
  end)

  it("goes from a file header to the header of the same file", function()
    assert.equal(3, diff.counterpart(SHOWN, 2, PARENT, "old"))
    assert.equal(4, diff.counterpart(SHOWN, 2, CHILD, "new"))
  end)

  it("follows a rename, which the parent names by the old path", function()
    assert.equal(10, diff.counterpart(SHOWN, 10, PARENT, "old"))
    assert.equal(3, diff.counterpart(SHOWN, 10, CHILD, "new"))
    local renaming = diff.parse({ "Modified regular file b.txt (a.txt => b.txt):", "   1    1: a" })
    assert.equal(2, diff.counterpart(SHOWN, 3, renaming, "new"))
  end)

  it("finds nothing when the other diff does not touch the file", function()
    assert.is_nil(diff.counterpart(SHOWN, 8, PARENT, "old"))
  end)

  it("finds nothing off a file, such as on the description", function()
    assert.is_nil(diff.counterpart(SHOWN, 1, PARENT, "old"))
  end)

  it("goes to the header of the file when no line of it is on the side", function()
    -- The parent removed new.txt and the change shown adds it again.
    local removing = diff.parse({ "Removed regular file new.txt:", "   1     : n" })
    assert.equal(1, diff.counterpart(SHOWN, 8, removing, "old"))
  end)
end)
