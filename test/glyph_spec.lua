local fake_host = require("support.fake_host")
local glyph = require("jin.glyph")

local function setup()
  return fake_host.new({ cwd = "/repo" })
end

---Whether `text` holds a code point of the Private Use Area, U+E000..U+F8FF,
---or of the supplementary ones, U+F0000 on, where Nerd Fonts put glyphs.
local function private(text)
  for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    local b1, b2 = char:byte(1, 2)
    if b1 == 0xEE or (b1 == 0xEF and b2 <= 0xA3) or b1 == 0xF3 or b1 == 0xF4 then
      return true
    end
  end
  return false
end

describe("the glyphs vim-jin draws with", function()
  it("come from the nerdfont preset when none is chosen", function()
    local host = setup()
    assert.equal("nerdfont", glyph.DEFAULT_PRESET)
    assert.same(glyph.PRESETS.nerdfont, glyph.resolve(host))
  end)

  it("come from the preset g:jin_glyph_preset names", function()
    local host = setup()
    for _, name in ipairs({ "nerdfont", "unicode", "ascii" }) do
      host.settings.glyph_preset = name
      assert.same(glyph.PRESETS[name], glyph.resolve(host))
    end
  end)

  it("come from the default preset when g:jin_glyph_preset names none there is", function()
    local host = setup()
    host.settings.glyph_preset = "emoji"
    assert.same(glyph.PRESETS[glyph.DEFAULT_PRESET], glyph.resolve(host))
    assert.same({}, host.messages)
  end)

  it("take each glyph g:jin_glyphs sets over the preset's, the rest from the preset", function()
    local host = setup()
    host.settings.glyph_preset = "ascii"
    host.dict_settings.glyphs = { change = "~", separator = "" }
    local glyphs = glyph.resolve(host)
    assert.equal("~", glyphs.change)
    assert.equal("", glyphs.separator)
    assert.equal(glyph.PRESETS.ascii.commit, glyphs.commit)
  end)

  it("ignore what g:jin_glyphs sets that is no glyph or no string", function()
    local host = setup()
    host.settings.glyph_preset = "ascii"
    host.dict_settings.glyphs = { unknown = "?", change = 1 }
    assert.same(glyph.PRESETS.ascii, glyph.resolve(host))
  end)

  it("follow g:jin_glyph_preset and g:jin_glyphs as they change, without a restart", function()
    local host = setup()
    host.settings.glyph_preset = "ascii"
    assert.equal("|", glyph.resolve(host).separator)
    host.settings.glyph_preset = "unicode"
    assert.equal("│", glyph.resolve(host).separator)
    host.dict_settings.glyphs = { separator = "/" }
    assert.equal("/", glyph.resolve(host).separator)
  end)

  it("are named the same in every preset", function()
    for preset, glyphs in pairs(glyph.PRESETS) do
      local names = {}
      for name in pairs(glyphs) do
        names[#names + 1] = name
      end
      table.sort(names)
      local expected = {}
      for i, name in ipairs(glyph.NAMES) do
        expected[i] = name
      end
      table.sort(expected)
      assert.same(expected, names, preset)
    end
  end)

  it("are plain Unicode in the unicode preset, with no Private Use Area code point", function()
    for name, value in pairs(glyph.PRESETS.unicode) do
      assert.equal(false, private(value), name)
    end
  end)

  it("are ASCII alone in the ascii preset", function()
    for name, value in pairs(glyph.PRESETS.ascii) do
      assert.equal(nil, value:find("[\128-\255]"), name)
    end
  end)

  it("encode a code point as UTF-8", function()
    assert.equal("A", glyph.utf8(0x41))
    assert.equal("·", glyph.utf8(0xB7))
    assert.equal("╭", glyph.utf8(0x256D))
    assert.equal("\239\144\151", glyph.utf8(0xF417))
    assert.equal("\243\176\156\152", glyph.utf8(0xF0718))
  end)
end)
