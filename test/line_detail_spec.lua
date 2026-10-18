local line_detail = require("jin.view.line_detail")

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

describe("the side a line of a diff is blamed on", function()
  local SIDES = { old = "c9-", new = "c9" }

  it("is the old side for a removed line, at its old number", function()
    assert.same(
      { rev = "c9-", path = "a.lua", number = 3, removed = true },
      line_detail.side({ path = "a.lua", old = 3 }, SIDES)
    )
  end)

  it("is the old path of a renamed file for a removed line", function()
    assert.same(
      { rev = "c9-", path = "old.lua", number = 3, removed = true },
      line_detail.side({ path = "new.lua", from = "old.lua", old = 3 }, SIDES)
    )
  end)

  it("is the new side for an added line, at its new number and path", function()
    assert.same(
      { rev = "c9", path = "new.lua", number = 4, removed = false },
      line_detail.side({ path = "new.lua", from = "old.lua", new = 4 }, SIDES)
    )
  end)

  it("is the change shown for an added line, where the view shows one change", function()
    local known = { change = "kk" }
    assert.same(
      { shown = "c9", known = known, path = "a.lua", number = 4, removed = false },
      line_detail.side(
        { path = "a.lua", new = 4 },
        { old = "c9-", new = "c9", shown = "c9", known = known }
      )
    )
  end)

  it("is the new side for a line on both sides, at its new number and path", function()
    local sides = { old = "c9-", new = "c9", shown = "c9" }
    assert.same(
      { rev = "c9", path = "new.lua", number = 5, removed = false },
      line_detail.side({ path = "new.lua", from = "old.lua", old = 2, new = 5 }, sides)
    )
  end)

  it("is none for a removed line where no revision holds the old side", function()
    assert.is_nil(line_detail.side({ path = "a.lua", old = 3 }, { new = "b" }))
  end)

  it("is none for a line without line numbers", function()
    assert.is_nil(line_detail.side({ path = "a.png" }, SIDES))
  end)
end)

describe("what jj file annotate tells of each line", function()
  it("asks the details of a change on the first line of each of its hunks alone", function()
    assert.truthy(line_detail.TEMPLATE:find("if(first_line_in_hunk, ", 1, true))
    assert.truthy(line_detail.TEMPLATE:find("commit.description()", 1, true))
  end)

  it("gives every line the change its hunk names", function()
    local full = function(commit, change, subject)
      return m(
        commit,
        change,
        "mmmmmm",
        commit:sub(1, 2),
        "345678",
        subject .. "\n",
        "Alice",
        "alice@example.com",
        "2026-01-01 09:00:00",
        "2 days ago",
        "",
        "immutable"
      )
    end
    local stdout = table.concat({
      full("p1aaaa", "pp", "add keep"),
      m("p1aaaa"),
      full("q2bbbb", "qq", "add tail"),
      full("p1aaaa", "pp", "add keep"),
    }, "\n") .. "\n"
    local lines = line_detail.parse(stdout)
    assert.equal("pp", lines[1].change)
    assert.equal("p1", lines[1].commit)
    assert.equal("add keep\n", lines[1].description)
    assert.equal(lines[1], lines[2])
    assert.equal("qq", lines[3].change)
    assert.same({ "immutable" }, lines[3].states)
    assert.equal("pp", lines[4].change)
    assert.is_nil(lines[5])
  end)
end)
