local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local block = require("jin.view.block")

local calls = {}

package.preload["jin.view.acting"] = function()
  local actions = {
    record = {
      desc = "record what was acted on",
      fn = function(ctx)
        calls[#calls + 1] = { entries = ctx.entries, first = ctx.first, last = ctx.last }
      end,
    },
  }
  action.openers(actions, "open", "open the entry", function(ctx, opener)
    calls[#calls + 1] = { opener = opener, entry = action.entry(ctx) }
  end)
  return {
    command = { "log" },
    filetype = "jin-acting",
    template = { key = "log", default = "builtin_log_compact", fields = { "change_id" } },
    actions = actions,
  }
end
view.register("acting")

local NAME = "jin:///repo;view=acting#"

---A loaded buffer of the acting view showing entries a (2 lines), b, and a
---line that belongs to none.
local function setup()
  calls = {}
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  local jin = api.new(function()
    return host
  end)
  local bufnr = host.load(NAME)
  view.read(jin, host, bufnr, NAME)
  host.finish({ code = 0, stdout = "t\n", stderr = "" })
  host.finish({
    code = 0,
    stdout = "\30"
      .. '"a"\31'
      .. "a1\na2\n\30"
      .. '"b"\31'
      .. "b1\n\30"
      .. '"x"\31\30'
      .. '"y"\31'
      .. "xy\n",
    stderr = "",
  })
  return host, jin, bufnr
end

describe("jin.action.run", function()
  it("hands the action the entries of the lines, once each, in order", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "record", 1, 3)
    assert.same({ { entries = { { "a" }, { "b" } }, first = 1, last = 3 } }, calls)
  end)

  it("accepts a range given bottom up", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "record", 3, 2)
    assert.same({ first = 2, last = 3 }, { first = calls[1].first, last = calls[1].last })
  end)

  it("leaves out lines that belong to no entry", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "record", 4, 4)
    assert.same({}, calls[1].entries)
  end)

  it("makes edit, split, vsplit and tab variants of an action that opens", function()
    local host, jin, bufnr = setup()
    for _, name in ipairs({ "open", "open:split", "open:vsplit", "open:tab" }) do
      action.run(jin, host, bufnr, name, 3, 3)
    end
    local openers = {}
    for i, call in ipairs(calls) do
      openers[i] = call.opener
      assert.same({ "b" }, call.entry)
    end
    assert.same({ "edit", "split", "vsplit", "tabedit" }, openers)
  end)

  it("tells why when a single entry is needed but the line has none", function()
    local host, jin, bufnr = setup()
    assert.has_error(function()
      action.run(jin, host, bufnr, "open", 4, 4)
    end, "jin: nothing to act on in this line")
  end)

  it("does nothing, quietly, when a key asks it of a line that names nothing", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "open", 4, 4, { key = true })
    assert.same({}, calls)
  end)

  it("still tells other mistakes when a key asks", function()
    local host, jin, bufnr = setup()
    assert.has_error(function()
      action.run(jin, host, bufnr, "nope", 1, 1, { key = true })
    end, "jin: no action named nope here")
  end)

  it("tells why when an action chosen by name has nothing to act on", function()
    local host, jin, bufnr = setup()
    host.answers = { "open" }
    assert.has_error(function()
      action.run(jin, host, bufnr, "choice", 4, 4, { key = true })
    end, "jin: nothing to act on in this line")
  end)

  it("rejects an action the view does not have", function()
    local host, jin, bufnr = setup()
    assert.has_error(function()
      action.run(jin, host, bufnr, "nope", 1, 1)
    end, "jin: no action named nope here")
  end)

  it("refuses to act before the buffer has been read", function()
    local host = fake_host.new()
    local jin = api.new(function()
      return host
    end)
    local bufnr = host.load(NAME)
    assert.has_error(function()
      action.run(jin, host, bufnr, "record", 1, 1)
    end, "jin: the buffer is still being read")
  end)
end)

describe("the actions every view has", function()
  it("are mapped on the buffer once it has been read", function()
    local host, _, bufnr = setup()
    assert.same({
      "choice",
      "help",
      "open",
      "open:split",
      "open:tab",
      "open:vsplit",
      "record",
      "repeat",
    }, host.defined[bufnr])
  end)

  it("choice runs the action named, and repeat runs it again", function()
    local host, jin, bufnr = setup()
    host.answers = { "record" }
    action.run(jin, host, bufnr, "choice", 1, 1)
    action.run(jin, host, bufnr, "repeat", 3, 3)
    assert.same({ { "a" } }, calls[1].entries)
    assert.same({ { "b" } }, calls[2].entries)
  end)

  it("choice of repeat repeats what was chosen before, and is not remembered itself", function()
    local host, jin, bufnr = setup()
    host.answers = { "record", "repeat" }
    action.run(jin, host, bufnr, "choice", 1, 1)
    action.run(jin, host, bufnr, "choice", 3, 3)
    action.run(jin, host, bufnr, "repeat", 1, 1)
    assert.equal(3, #calls)
    assert.same({ { "b" } }, calls[2].entries)
  end)

  it("choice does nothing when no name is given", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "choice", 1, 1)
    assert.same({}, calls)
  end)

  it("repeat says so when nothing was chosen yet", function()
    local host, jin, bufnr = setup()
    action.run(jin, host, bufnr, "repeat", 1, 1)
    assert.same({ { text = "jin: no action to repeat", hl = "WarningMsg" } }, host.messages)
  end)

  it("help lists the actions with the keys mapped to them", function()
    local host, jin, bufnr = setup()
    host.maps = {
      { lhs = "<CR>", rhs = "<Plug>(jin-action-open)", mode = "n" },
      { lhs = "<Plug>(jin-action-open)", rhs = "<Cmd>...", mode = "n" },
      { lhs = "?", rhs = "<Plug>(jin-action-help)", mode = "n" },
    }
    action.run(jin, host, bufnr, "help", 1, 1)
    local text = host.messages[1].text
    assert(text:find("<CR>  open    open the entry (also :split, :vsplit, :tab)\n", 1, true), text)
    assert(text:find("?     help ", 1, true), text)
    assert(text:find("      record ", 1, true), text)
  end)

  it("help lists the variants of an action on its line, with their keys", function()
    local host, jin, bufnr = setup()
    host.maps = {
      { lhs = "<CR>", rhs = "<Plug>(jin-action-open)", mode = "n" },
      { lhs = "<C-w><CR>", rhs = "<Plug>(jin-action-open:split)", mode = "n" },
    }
    action.run(jin, host, bufnr, "help", 1, 1)
    local text = host.messages[1].text
    assert(text:find("<CR> <C-w><CR>  open  ", 1, true), text)
    assert(not text:find("open:split", 1, true), text)
  end)
end)

describe("jin.action.keys", function()
  local VIEWS = {
    "buffer",
    "log",
    "show",
    "diff",
    "interdiff",
    "file",
    "oplog",
    "opshow",
    "evolog",
    "status",
    "annotate",
    "bookmark",
    "workspace",
    "conflicts",
    "resolve",
  }

  ---The action `lhs` is mapped to in `mode` ("n" unless given), or nil.
  local function lookup(keys, lhs, mode)
    for _, key in ipairs(keys) do
      if key[1] == lhs and (key[3] or "n") == (mode or "n") then
        return key[2]
      end
    end
    return nil
  end

  it("maps choice, repeat and help in every view", function()
    for _, name in ipairs(VIEWS) do
      local keys = action.keys(view.get(name), false)
      assert.same(
        { "choice", "repeat", "help" },
        { lookup(keys, "a"), lookup(keys, "."), lookup(keys, "?") },
        name
      )
    end
  end)

  it("maps <CR> to what the line is most likely there for", function()
    local primary = {
      log = "show",
      file = "annotate",
      show = "jump",
      diff = "jump",
      interdiff = "jump",
      oplog = "show",
      opshow = "show",
      evolog = "interdiff",
      status = "inspect",
      annotate = "show",
      bookmark = "log",
      workspace = "tcd",
      conflicts = "files",
      resolve = "edit",
    }
    for _, name in ipairs(VIEWS) do
      assert.equal(primary[name], lookup(action.keys(view.get(name), false), "<CR>"), name)
    end
  end)

  it("maps <S-CR> and <C-CR> to the second thing the line is there for", function()
    local secondary = {
      log = "diff",
      file = "log",
      oplog = "log",
      opshow = "diff",
      evolog = "show",
      status = "open",
      bookmark = "show",
      workspace = "log",
    }
    for _, name in ipairs(VIEWS) do
      local keys = action.keys(view.get(name), false)
      assert.same(
        { secondary[name], secondary[name] },
        { lookup(keys, "<S-CR>"), lookup(keys, "<C-CR>") },
        name
      )
    end
  end)

  it(
    "goes to the file with gf, the diff with gd, and the parent and the child with gp and gc",
    function()
      local keys = action.keys(view.get("annotate"), false)
      assert.same({ "file", "diff" }, { lookup(keys, "gf"), lookup(keys, "gd") })
      local show = action.keys(view.get("show"), false)
      assert.same({ "parent", "child" }, { lookup(show, "gp"), lookup(show, "gc") })
      assert.equal("interdiff", lookup(action.keys(view.get("evolog"), false), "gd"))
      assert.equal("edit", lookup(action.keys(view.get("status"), false), "gf"))
      assert.is_nil(lookup(action.keys(view.get("log"), false), "gf"))
    end
  )

  it(
    "opens what <CR> opens in a new window with <C-w><CR>, split the way the user splits diffs",
    function()
      assert.equal("show:split", lookup(action.keys(view.get("log"), false), "<C-w><CR>"))
      assert.equal("show:vsplit", lookup(action.keys(view.get("log"), true), "<C-w><CR>"))
      -- What is no view opens in no new window.
      assert.is_nil(lookup(action.keys(view.get("workspace"), false), "<C-w><CR>"))
    end
  )

  it("leaves the other openers to a, and = to Vim", function()
    local wrong = {}
    for _, name in ipairs(VIEWS) do
      for _, key in ipairs(action.keys(view.get(name), false)) do
        -- Reached by name, or as what <CR> and <S-CR> serve.
        local unmapped = {
          show = true,
          log = true,
          evolog = true,
          annotate = true,
          files = true,
          resolve = true,
        }
        if unmapped[key[2]] and key[1] ~= "<CR>" and key[1] ~= "<S-CR>" and key[1] ~= "<C-CR>" then
          wrong[#wrong + 1] = name .. ": " .. key[1] .. " " .. key[2]
        end
        if key[1]:match("^=") then
          wrong[#wrong + 1] = name .. ": " .. key[1]
        end
      end
    end
    assert.same({}, wrong)
  end)

  it("yanks with yy, and the lines selected with y in visual mode", function()
    local keys = action.keys(view.get("oplog"), false)
    assert.same(
      { "yank:operation", "yank:operation" },
      { lookup(keys, "yy"), lookup(keys, "y", "x") }
    )
    assert.is_nil(lookup(action.keys(view.get("diff"), false), "yy"))
  end)

  it("yanks commit IDs with YY, and those of the lines selected with Y in visual mode", function()
    for _, name in ipairs({ "log", "show", "evolog", "annotate", "conflicts" }) do
      local keys = action.keys(view.get(name), false)
      assert.same(
        { "yank:commit", "yank:commit" },
        { lookup(keys, "YY"), lookup(keys, "Y", "x") },
        name
      )
    end
    assert.is_nil(lookup(action.keys(view.get("oplog"), false), "YY"))
    assert.equal("yank:change", lookup(action.keys(view.get("evolog"), false), "yy"))
  end)

  -- What each default key means in Vim, which the view must leave as it is.
  -- A key whose Vim meaning a read-only buffer has no use for, as it edits
  -- text, is free to take, for the change closest to what it does to text.
  local UNUSED = {
    ["^gp$"] = "gp puts text",
    ["^gc$"] = "gc comments lines out, in Neovim; Vim gives it nothing",
  }
  -- A key may keep its meaning, the view telling what it applies to.
  local KEPT = {
    ["^<CR>$"] = "goes to what the line names, as in the quickfix window",
    ["^<S%-CR>$"] = "is <CR> as a terminal may send it",
    ["^<C%-CR>$"] = "is <CR> as a terminal may send it",
    ["^<C%-w><CR>$"] = "goes to what the line names in a new window, as in the quickfix window",
    ["^gf$"] = "goes to the file",
    ["^gd$"] = "goes to what defines what is under the cursor",
    ["^yy$"] = "yanks",
    ["^y$"] = "yanks",
    ["^YY$"] = "yanks",
    ["^Y$"] = "yanks",
    ["^K$"] = "looks up what is under the cursor",
    ["^ZZ$"] = "writes and quits",
    ["^ZQ$"] = "quits",
    ["^%]%]$"] = "goes to the next section",
    ["^%[%[$"] = "goes to the previous section",
  }
  -- The keys the author's plugins have taken since gita, kept on purpose.
  local EXCEPTIONS = { ["a"] = true, ["."] = true, ["?"] = true }

  ---Why `lhs` may be mapped, or nil when mapping it would change what it
  ---means in Vim.
  local function allowed(lhs)
    if EXCEPTIONS[lhs] then
      return "a deliberate exception"
    end
    for _, table_ in ipairs({ UNUSED, KEPT }) do
      for pattern, why in pairs(table_) do
        if lhs:match(pattern) then
          return why
        end
      end
    end
    return nil
  end

  it("maps only actions the view has, each key once, none whose Vim meaning it changes", function()
    local wrong = {}
    for _, name in ipairs(VIEWS) do
      local def = view.get(name)
      local actions, seen = {}, {}
      for _, n in ipairs(action.names(def)) do
        actions[n] = true
      end
      local keys = {}
      for _, key in ipairs(action.keys(def, false)) do
        keys[#keys + 1] = key
        if not actions[key[2]] then
          wrong[#wrong + 1] = name .. ": " .. key[1] .. " to no action " .. key[2]
        end
      end
      for _, key in ipairs(block.keys(def)) do
        keys[#keys + 1] = key
      end
      for _, key in ipairs(keys) do
        local id = name .. ": " .. (key[3] or "n") .. " " .. key[1]
        if seen[id] then
          wrong[#wrong + 1] = id .. " twice"
        end
        seen[id] = true
        if not allowed(key[1]) then
          wrong[#wrong + 1] = id .. " changes what the key means in Vim"
        end
      end
    end
    assert.same({}, wrong)
  end)

  it("moves between blocks with ]] and [[ in the views that have them", function()
    local with = {}
    for _, name in ipairs(VIEWS) do
      if lookup(block.keys(view.get(name)), "]]") then
        with[#with + 1] = name
      end
    end
    assert.same({
      "log",
      "show",
      "diff",
      "interdiff",
      "oplog",
      "evolog",
      "annotate",
      "conflicts",
    }, with)
  end)
end)
