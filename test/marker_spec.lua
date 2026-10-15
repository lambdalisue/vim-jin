local marker = require("jin.marker")

-- A marker as jj prints it from marker.wrap: each field a JSON string.
local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

describe("jin.marker.wrap", function()
  it("puts the fields in a marker before the template, each as a JSON string", function()
    assert.equal(
      [["\x1e" ++ json(stringify(change_id)) ++ " " ++ json(stringify(commit_id)) ++ "\x1f" ++ (builtin_log_compact)]],
      marker.wrap({ "change_id", "commit_id" }, "builtin_log_compact")
    )
  end)
end)

describe("jin.marker.parse", function()
  it("strips the markers and keeps the fields of each entry", function()
    local lines, entries = marker.parse({
      "@  " .. m("kkk", "c1") .. "kkk first",
      "│  description",
      "○  " .. m("zzz", "c2") .. "zzz root",
    })
    assert.same({ "@  kkk first", "│  description", "○  zzz root" }, lines)
    assert.same({ { "kkk", "c1" }, { "kkk", "c1" }, { "zzz", "c2" } }, entries)
  end)

  it("gives the same table to every line of an entry", function()
    local _, entries = marker.parse({ m("a") .. "x", "y" })
    assert.equal(entries[1], entries[2])
  end)

  it("maps lines before the first marker to nothing", function()
    local lines, entries = marker.parse({ "header", m("a") .. "x" })
    assert.same({ "header", "x" }, lines)
    assert.is_false(entries[1])
    assert.same({ "a" }, entries[2])
  end)

  it("maps a line with several markers, and the lines after it, to nothing", function()
    local lines, entries = marker.parse({ m("a") .. "x" .. m("b") .. "y", "z", m("c") .. "w" })
    assert.same({ "xy", "z", "w" }, lines)
    assert.is_false(entries[1])
    assert.is_false(entries[2])
    assert.same({ "c" }, entries[3])
  end)

  it("keeps an entry whose template printed nothing after the marker", function()
    local lines, entries = marker.parse({ "@  " .. m("a"), m("b") .. "x" })
    assert.same({ "@  ", "x" }, lines)
    assert.same({ "a" }, entries[1])
  end)

  it("keeps names with spaces, quotes and backslashes whole", function()
    -- What jj 0.46 prints for json(stringify(name)) of such bookmarks.
    local _, entries = marker.parse({
      "\30" .. [["we ird" ""]] .. "\31" .. "x",
      "\30" .. [["qu'ote\"d" "my origin"]] .. "\31" .. "x",
      "\30" .. [["back\\slash" ""]] .. "\31" .. "x",
    })
    assert.same({ { "we ird" }, { "qu'ote\"d", "my origin" }, { "back\\slash" } }, entries)
  end)

  it("takes an empty field as absent", function()
    local _, entries = marker.parse({ "\30" .. [["main" ""]] .. "\31" .. "x" })
    assert.same({ "main" }, entries[1])
    assert.is_nil(entries[1][2])
  end)

  it("decodes the escapes JSON allows, control characters and non-ASCII included", function()
    local _, entries = marker.parse({
      "\30" .. [["a\nb\tc\/d\b\f\r" "\u001e\u001f" "éあ" "😀" "é"]] .. "\31" .. "x",
    })
    assert.same({ { "a\nb\tc/d\b\f\r", "\30\31", "é" .. "あ", "😀", "é" } }, entries)
  end)

  it("maps a marker that holds no JSON strings, and the lines after it, to nothing", function()
    local _, entries = marker.parse({ m("a") .. "x", "\30not json\31" .. "y", "z" })
    assert.same({ "a" }, entries[1])
    assert.is_false(entries[2])
    assert.is_false(entries[3])
  end)

  it("drops the colors jj puts on the fields themselves", function()
    local _, entries = marker.parse({
      '\30\27[38;5;5m"kkk"\27[39m \27[1m"c1"\27[0m\31' .. "x",
    })
    assert.same({ { "kkk", "c1" } }, entries)
  end)

  it("leaves ANSI escapes around a marker in place", function()
    local lines = marker.parse({ "\27[1m@\27[0m  " .. m("a") .. "\27[31mx\27[0m" })
    assert.same({ "\27[1m@\27[0m  \27[31mx\27[0m" }, lines)
  end)
end)
