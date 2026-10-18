local hunk = require("jin.hunk")

describe("jin.hunk.diff", function()
  it("finds no hunk between equal lines", function()
    assert.same({}, hunk.diff({ "a", "b" }, { "a", "b" }))
  end)

  it("tells each hunk as where it starts and how many lines it has on either side", function()
    assert.same({
      { 2, 1, 2, 2 },
      { 4, 1, 5, 0 },
    }, hunk.diff({ "a", "b", "c", "d", "e" }, { "a", "B", "B2", "c", "e" }))
  end)

  it("tells lines added at the end, and every line of an empty side", function()
    assert.same({ { 2, 0, 2, 1 } }, hunk.diff({ "a" }, { "a", "b" }))
    assert.same({ { 1, 0, 1, 2 } }, hunk.diff({}, { "a", "b" }))
    assert.same({ { 1, 2, 1, 0 } }, hunk.diff({ "a", "b" }, {}))
  end)
  it("tells hunks that, taken in place of their lines of a, make b", function()
    local function apply(a, b, hunks)
      local out, at = {}, 1
      for _, h in ipairs(hunks) do
        for i = at, h[1] - 1 do
          out[#out + 1] = a[i]
        end
        for i = h[3], h[3] + h[4] - 1 do
          out[#out + 1] = b[i]
        end
        at = h[1] + h[2]
      end
      for i = at, #a do
        out[#out + 1] = a[i]
      end
      return out
    end
    local function chars(s)
      local out = {}
      for c in s:gmatch(".") do
        out[#out + 1] = c
      end
      return out
    end
    for _, case in ipairs({
      { "abcabba", "cbabac" },
      { "xaxbxc", "abc" },
      { "abc", "xaxbxc" },
      { "abcdef", "fedcba" },
      { "aaaa", "aa" },
      { "", "abc" },
    }) do
      local a, b = chars(case[1]), chars(case[2])
      assert.same(b, apply(a, b, hunk.diff(a, b)))
    end
  end)
end)

describe("jin.hunk.at", function()
  local LEFT = { "a", "b", "c", "d" }
  local RIGHT = { "a", "B", "c", "D" }

  it("finds the hunk under the cursor with what either side has there", function()
    local result = { "a", "B", "c", "D" }
    assert.same(
      { result = { 2, 2 }, left = { "b" }, right = { "B" } },
      hunk.at(LEFT, result, RIGHT, 2)
    )
    assert.same(
      { result = { 4, 4 }, left = { "d" }, right = { "D" } },
      hunk.at(LEFT, result, RIGHT, 4)
    )
  end)

  it("finds no hunk where the result agrees with both sides", function()
    assert.is_nil(hunk.at(LEFT, { "a", "B", "c", "D" }, RIGHT, 1))
  end)

  it("joins what differs from either side into one hunk where the two overlap", function()
    local left = { "a", "b", "c", "d" }
    local right = { "a", "x", "y", "d" }
    local result = { "a", "x", "c", "d" }
    assert.same(
      { result = { 2, 3 }, left = { "b", "c" }, right = { "x", "y" } },
      hunk.at(left, result, right, 3)
    )
  end)

  it("finds lines one side added, which the result lacks, beside the cursor", function()
    local left = { "a", "z" }
    local right = { "a", "new", "z" }
    local result = { "a", "z" }
    assert.same(
      { result = { 2, 1 }, left = {}, right = { "new" } },
      hunk.at(left, result, right, 2)
    )
  end)
end)

describe("jin.hunk.select", function()
  local SIDE = { "a", "b", "c", "d" }
  local RESULT = { "a", "B", "c", "D", "e" }

  it("finds the hunks between the result and a side at the lines of the result", function()
    assert.same({ { result = { 2, 2 }, lines = { "b" } } }, hunk.select(RESULT, SIDE, 2, 2))
    assert.same({
      { result = { 2, 2 }, lines = { "b" } },
      { result = { 4, 5 }, lines = { "d" } },
    }, hunk.select(RESULT, SIDE, 1, 4))
    assert.same({}, hunk.select(RESULT, SIDE, 3, 3))
  end)

  it("finds them at the lines of the side instead, as a put from it does", function()
    assert.same({ { result = { 4, 5 }, lines = { "d" } } }, hunk.select(RESULT, SIDE, 4, 4, true))
  end)

  it("finds lines the result lacks just above the line, or below the last one", function()
    assert.same(
      { { result = { 2, 1 }, lines = { "b" } } },
      hunk.select({ "a", "c" }, { "a", "b", "c" }, 2, 2)
    )
    assert.same(
      { { result = { 2, 1 }, lines = { "b" } } },
      hunk.select({ "a" }, { "a", "b" }, 1, 1)
    )
    assert.same({ { result = { 1, 0 }, lines = { "a" } } }, hunk.select({}, { "a" }, 1, 1))
  end)
end)
