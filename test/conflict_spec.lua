local conflict = require("jin.conflict")

---@param text string
---@return string[]
local function lines(text)
  local out = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    out[#out + 1] = line
  end
  if out[#out] == "" then
    out[#out] = nil
  end
  return out
end

local LEFT = { "left1", "base2" }
local BASE = { "base1", "base2" }
local RIGHT = { "right1", "right2" }

describe("conflict.parse", function()
  it("reads the diff style: a side as its diff from the base, and a side as it is", function()
    local found = conflict.parse(lines([[
a
<<<<<<< conflict 1 of 1
%%%%%%% diff from: mqzlrslx 990429f5 "base"
\\\\\\\        to: zlqstyxs c7baff25 "left"
-base1
+left1
 base2
+++++++ zvyzmltx 68c4eb9d "right"
right1
right2
>>>>>>> conflict 1 of 1 ends
z]]))
    assert.same({ { first = 2, last = 11, sides = { LEFT, RIGHT }, bases = { BASE } } }, found)
  end)

  it("reads the snapshot style", function()
    local found = conflict.parse(lines([[
a
<<<<<<< conflict 1 of 1
+++++++ zlqstyxs c7baff25 "left"
left1
base2
------- mqzlrslx 990429f5 "base"
base1
base2
+++++++ zvyzmltx 68c4eb9d "right"
right1
right2
>>>>>>> conflict 1 of 1 ends
z]]))
    assert.same({ { first = 2, last = 12, sides = { LEFT, RIGHT }, bases = { BASE } } }, found)
  end)

  it("reads the git style", function()
    local found = conflict.parse(lines([[
a
<<<<<<< zlqstyxs c7baff25 "left"
left1
base2
||||||| mqzlrslx 990429f5 "base"
base1
base2
=======
right1
right2
>>>>>>> zvyzmltx 68c4eb9d "right"
z]]))
    assert.same({ { first = 2, last = 11, sides = { LEFT, RIGHT }, bases = { BASE } } }, found)
  end)

  it("reads every conflict of the file, and those of more than two sides", function()
    local found = conflict.parse(lines([[
<<<<<<< conflict 1 of 2
+++++++ side #1
one
------- base
+++++++ side #2
two
>>>>>>> conflict 1 of 2 ends
between
<<<<<<< conflict 2 of 2
+++++++ side #1
x
------- base #1
o
+++++++ side #2
y
------- base #2
o
+++++++ side #3
z
>>>>>>> conflict 2 of 2 ends]]))
    assert.same({
      { first = 1, last = 7, sides = { { "one" }, { "two" } }, bases = { {} } },
      {
        first = 9,
        last = 20,
        sides = { { "x" }, { "y" }, { "z" } },
        bases = { { "o" }, { "o" } },
      },
    }, found)
  end)

  it("reads markers longer than seven, as jj writes around lines that look like markers", function()
    local found = conflict.parse(lines([[
<<<<<<<<< conflict 1 of 1
+++++++++ side #1
<<<<<<< not a marker
--------- base
+++++++++ side #2
=======
>>>>>>>>> conflict 1 of 1 ends]]))
    assert.same({
      {
        first = 1,
        last = 7,
        sides = { { "<<<<<<< not a marker" }, { "=======" } },
        bases = { {} },
      },
    }, found)
  end)

  it("reads markers ending a line with a carriage return, as in a CRLF file", function()
    local found = conflict.parse({ "<<<<<<< l\r", "l\r", "=======\r", "r\r", ">>>>>>> r\r" })
    assert.same({ { first = 1, last = 5, sides = { { "l\r" }, { "r\r" } }, bases = {} } }, found)
  end)

  it("reads the conflicts after a line that only looks like an opening marker", function()
    for _, opening in ipairs({ "<<<<<<< an example", "<<<<<<<<<<< an example" }) do
      local found = conflict.parse({
        opening,
        "<<<<<<<<< conflict 1 of 1",
        "+++++++++ side #1",
        "l",
        "--------- base",
        "+++++++++ side #2",
        "r",
        ">>>>>>>>> conflict 1 of 1 ends",
      })
      assert.same({ { first = 2, last = 8, sides = { { "l" }, { "r" } }, bases = { {} } } }, found)
    end
  end)

  it("starts again at an opening marker of the same length met before the end", function()
    local found = conflict.parse({
      "<<<<<<< conflict 1 of 2",
      "+++++++ side #1",
      "half edited",
      "<<<<<<< conflict 2 of 2",
      "+++++++ side #1",
      "l",
      "+++++++ side #2",
      "r",
      ">>>>>>> conflict 2 of 2 ends",
    })
    assert.same({ { first = 4, last = 9, sides = { { "l" }, { "r" } }, bases = {} } }, found)
  end)

  it("leaves out a conflict that never ends", function()
    assert.same({}, conflict.parse(lines("<<<<<<< conflict 1 of 1\n+++++++ side #1\nx")))
  end)
end)

describe("conflict.at", function()
  it("finds the conflict that holds a line, or none", function()
    local found = conflict.parse(lines("a\n<<<<<<< x\nl\n=======\nr\n>>>>>>> y\nz"))
    assert.equal(found[1], conflict.at(found, 2))
    assert.equal(found[1], conflict.at(found, 6))
    assert.is_nil(conflict.at(found, 1))
    assert.is_nil(conflict.at(found, 7))
  end)
end)
