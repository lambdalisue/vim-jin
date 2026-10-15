local args = require("jin.args")

describe("jin.args.parse", function()
  it("passes arguments without ++ options through unchanged", function()
    local opts, rest = args.parse({ "log", "-r", "@" })
    assert.same({}, opts)
    assert.same({ "log", "-r", "@" }, rest)
  end)

  it("takes a bare ++name as true", function()
    local opts, rest = args.parse({ "++wait", "status" })
    assert.same({ wait = true }, opts)
    assert.same({ "status" }, rest)
  end)

  it("takes ++name=value as a string, keeping later = signs", function()
    local opts, rest = args.parse({ "++opener=split", "++expr=a=b", "log" })
    assert.same({ opener = "split", expr = "a=b" }, opts)
    assert.same({ "log" }, rest)
  end)

  it("takes an empty value after = as an empty string", function()
    local opts = args.parse({ "++opener=" })
    assert.same({ opener = "" }, opts)
  end)

  it("stops at the first argument that is not a ++ option", function()
    local opts, rest = args.parse({ "++wait", "file", "list", "++wait" })
    assert.same({ wait = true }, opts)
    assert.same({ "file", "list", "++wait" }, rest)
  end)

  it("passes a bare ++ through to jj", function()
    local opts, rest = args.parse({ "++", "status" })
    assert.same({}, opts)
    assert.same({ "++", "status" }, rest)
  end)

  it("does not modify the given list", function()
    local given = { "++wait", "status" }
    args.parse(given)
    assert.same({ "++wait", "status" }, given)
  end)
end)

describe("jin.args.validate", function()
  it("accepts options that are all known", function()
    args.validate({ wait = true }, { wait = true })
  end)

  it("rejects an unknown option, naming it", function()
    assert.has_error(function()
      args.validate({ wiat = true }, { wait = true })
    end, "jin: unknown option ++wiat")
  end)
end)

describe("jin.args.split", function()
  it("splits on white space", function()
    assert.same({ "log", "-r", "@" }, args.split("  log  -r\t@ "))
  end)

  it("keeps everything inside single quotes literally", function()
    assert.same({ "-m", [[a "b" \c]] }, args.split([[-m 'a "b" \c']]))
  end)

  it('keeps everything inside double quotes, where a backslash escapes " and \\', function()
    assert.same({ "-m", [[a 'b' "c" \d \e]] }, args.split([[-m "a 'b' \"c\" \\d \e"]]))
  end)

  it("lets a backslash outside quotes escape the next character", function()
    assert.same({ "a b", [['c']], [[\]] }, args.split([[a\ b \'c\' \\]]))
  end)

  it("joins quoted and unquoted pieces that touch into one argument", function()
    assert.same({ "-mfeat: x", "a'b" }, args.split([[-m"feat: x" a"'"b]]))
  end)

  it("keeps an empty quoted argument", function()
    assert.same({ "-m", "" }, args.split([[-m '']]))
  end)

  it("returns nothing for a blank line", function()
    assert.same({}, args.split("  "))
  end)

  it("rejects an unterminated quote", function()
    assert.has_error(function()
      args.split([[describe -m "wip]])
    end, "jin: unterminated quote")
  end)
end)

describe("jin.args.split with expand", function()
  local function expand()
    return "a b.txt"
  end

  it("replaces a bare % with what expand returns", function()
    assert.same({ "file", "show", "a b.txt" }, args.split("file show %", expand))
    assert.same({ "a b.txt", "-r" }, args.split("% -r", expand))
  end)

  it("leaves a quoted or escaped %, and % inside a word, as it is", function()
    assert.same({ "%", "%", "%", "a%b" }, args.split([['%' "%" \% a%b]], expand))
  end)

  it("leaves % as it is without expand", function()
    assert.same({ "%" }, args.split("%"))
  end)
end)

describe("jin.args.split_partial", function()
  it("splits like split when every quote is closed", function()
    local words, open = args.split_partial([[-m "a b" c]])
    assert.same({ "-m", "a b", "c" }, words)
    assert.is_nil(open)
  end)

  it("keeps the last word of an unterminated quote and names the quote", function()
    local words, open = args.split_partial([[file show "my fi]])
    assert.same({ "file", "show", "my fi" }, words)
    assert.equal('"', open)
  end)

  it("ends with an empty word after trailing white space", function()
    assert.same({ "log", "" }, args.split_partial("log "))
  end)

  it("ends with an empty word inside a quote just opened", function()
    local words, open = args.split_partial([[log -r ']])
    assert.same({ "log", "-r", "" }, words)
    assert.equal("'", open)
  end)
end)

describe("jin.args.escape", function()
  it("leaves a plain argument alone", function()
    assert.equal("root()|@", args.escape("root()|@"))
  end)

  it("escapes what split would otherwise take apart", function()
    for _, arg in ipairs({ "a b", [[a\b]], [[it's]], [["q"]], "tab\there", "" }) do
      assert.same({ arg }, args.split(args.escape(arg)))
    end
  end)
end)

describe("jin.args.options", function()
  local REVS = { ["-r"] = "revisions", ["--revisions"] = "revisions" }

  it("reads an option's value in each of its spellings", function()
    local items = args.options({ "-r", "a", "-rb", "--revisions", "c", "--revisions=d" }, REVS)
    local values = {}
    for _, item in ipairs(items) do
      assert.equal("revisions", item.name)
      values[#values + 1] = item.value
    end
    assert.same({ "a", "b", "c", "d" }, values)
  end)

  it("keeps the words each item was written with", function()
    local items = args.options({ "-r", "a", "--no-graph", "-rb" }, REVS)
    assert.same({ "-r", "a" }, items[1].words)
    assert.same({ name = nil, value = nil, words = { "--no-graph" } }, items[2])
    assert.same({ "-rb" }, items[3].words)
  end)

  it("knows the values of jj's global options without being told", function()
    local items = args.options({ "--at-op", "-r", "-R", "-rx", "--config=-r", "y" }, REVS)
    assert.same({ "at-op", "-r" }, { items[1].name, items[1].value })
    assert.same({ "repository", "-rx" }, { items[2].name, items[2].value })
    assert.same({ "config", "-r" }, { items[3].name, items[3].value })
    assert.same({ words = { "y" } }, items[4])
  end)

  it("stops at --, handing it back with what follows", function()
    local items, rest = args.options({ "a", "--", "-r", "b" }, REVS)
    assert.same({ { words = { "a" } } }, items)
    assert.same({ "--", "-r", "b" }, rest)
  end)

  it("takes an option missing its value as a plain argument", function()
    assert.same({ { words = { "-r" } } }, args.options({ "-r" }, REVS))
  end)
end)
