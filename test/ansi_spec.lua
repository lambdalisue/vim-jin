local ansi = require("jin.ansi")

local ESC = "\27"

local function sgr(codes)
  return ESC .. "[" .. codes .. "m"
end

describe("jin.ansi.parse", function()
  it("passes text without escapes through untouched", function()
    local lines, spans = ansi.parse({ "plain", "" })
    assert.same({ "plain", "" }, lines)
    assert.same({}, spans)
  end)

  it("removes escapes and records the styled byte range", function()
    local lines, spans = ansi.parse({ "a" .. sgr("31") .. "red" .. sgr("0") .. "b" })
    assert.same({ "aredb" }, lines)
    assert.same({ { line = 1, col = 2, end_col = 5, style = { fg = 1 } } }, spans)
  end)

  it("counts columns in bytes", function()
    local _, spans = ansi.parse({ "あ" .. sgr("1") .. "い" .. sgr("") })
    assert.same({ { line = 1, col = 4, end_col = 7, style = { bold = true } } }, spans)
  end)

  it("reads the basic, bright, 256 and true colors for both grounds", function()
    local _, spans = ansi.parse({
      sgr("32") .. "a" .. sgr("0"),
      sgr("95") .. "b" .. sgr("0"),
      sgr("38;5;208") .. "c" .. sgr("0"),
      sgr("38;2;255;0;16") .. "d" .. sgr("0"),
      sgr("44") .. "e" .. sgr("0"),
      sgr("103") .. "f" .. sgr("0"),
      sgr("48;5;17;48;2;1;2;3") .. "g" .. sgr("0"),
    })
    local styles = {}
    for _, span in ipairs(spans) do
      styles[#styles + 1] = span.style
    end
    assert.same({
      { fg = 2 },
      { fg = 13 },
      { fg = 208 },
      { fg = "#ff0010" },
      { bg = 4 },
      { bg = 11 },
      { bg = "#010203" },
    }, styles)
  end)

  it("combines attributes and resets them one by one", function()
    local _, spans = ansi.parse({
      sgr("1;3;4;7;9;31;42") .. "a" .. sgr("22;23") .. "b" .. sgr("24;27;29;39;49") .. "c",
    })
    assert.same({
      {
        line = 1,
        col = 1,
        end_col = 2,
        style = {
          bold = true,
          italic = true,
          underline = true,
          reverse = true,
          strikethrough = true,
          fg = 1,
          bg = 2,
        },
      },
      {
        line = 1,
        col = 2,
        end_col = 3,
        style = { underline = true, reverse = true, strikethrough = true, fg = 1, bg = 2 },
      },
    }, spans)
  end)

  it("ignores codes it does not show, such as faint and blink", function()
    local _, spans = ansi.parse({ sgr("2;5;31") .. "a" .. sgr("0") })
    assert.same({ { line = 1, col = 1, end_col = 2, style = { fg = 1 } } }, spans)
  end)

  it("carries a style across lines until it is reset", function()
    local _, spans = ansi.parse({ sgr("31") .. "a", "b" .. sgr("0") .. "c" })
    assert.same({
      { line = 1, col = 1, end_col = 2, style = { fg = 1 } },
      { line = 2, col = 1, end_col = 2, style = { fg = 1 } },
    }, spans)
  end)

  it("merges neighbouring runs that end up with the same style", function()
    local _, spans = ansi.parse({ sgr("31") .. "a" .. sgr("31") .. "b" .. sgr("0") })
    assert.same({ { line = 1, col = 1, end_col = 3, style = { fg = 1 } } }, spans)
  end)

  it("drops escapes that are not colors", function()
    local lines, spans = ansi.parse({
      "a" .. ESC .. "[K" .. "b" .. ESC .. "]8;;https://x" .. ESC .. "\\" .. "c" .. ESC .. "]8;;\7",
    })
    assert.same({ "abc" }, lines)
    assert.same({}, spans)
  end)
end)

describe("jin.ansi.group", function()
  it("names one highlight group per style", function()
    assert.equal("JinAnsiF1", ansi.group({ fg = 1 }))
    assert.equal(
      "JinAnsiFff0010B4bu",
      ansi.group({ fg = "#ff0010", bg = 4, bold = true, underline = true })
    )
    assert.equal(ansi.group({ bold = true, fg = 1 }), ansi.group({ fg = 1, bold = true }))
  end)
end)

describe("jin.ansi.hex", function()
  it("gives the xterm color of a 256-color index", function()
    assert.equal("#000000", ansi.hex(0))
    assert.equal("#ff0000", ansi.hex(9))
    assert.equal("#ff8700", ansi.hex(208))
    assert.equal("#eeeeee", ansi.hex(255))
  end)

  it("passes a true color through", function()
    assert.equal("#ff0010", ansi.hex("#ff0010"))
  end)
end)
