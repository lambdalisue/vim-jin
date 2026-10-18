local fake_host = require("support.fake_host")
local api = require("jin.api")
local view = require("jin.view")
local action = require("jin.action")
local detail = require("jin.view.detail")
local glyph = require("jin.glyph")

local function ok(stdout)
  return { code = 0, stdout = stdout, stderr = "" }
end

local function setup()
  local host = fake_host.new({ cwd = "/repo", dirs = { "/repo", "/repo/.jj" } })
  -- The layout is pinned in the ascii preset, whose labels are the words
  -- alone; the glyphs of the others are pinned on their own below.
  host.settings.glyph_preset = "ascii"
  local jin = api.new(function()
    return host
  end)
  return host, jin
end

local function m(...)
  local fields = {}
  for i, value in ipairs({ ... }) do
    fields[i] = '"' .. value:gsub('[\\"]', "\\%0"):gsub("\n", "\\n") .. '"'
  end
  return "\30" .. table.concat(fields, " ") .. "\31"
end

local NAME = "jin:///repo;view=annotate#a.lua"

---jj's annotation of a file whose lines the changes `changes` wrote, in
---order, in a template like jj's own, each entry telling the subject
---"about <change>", its author and how long ago.
---@param changes string[]
local function annotation(changes)
  local out = {}
  for i, change in ipairs(changes) do
    local content = "line " .. i
    out[#out + 1] = m(
      change,
      "c" .. change,
      "-",
      content .. "\n",
      "about " .. change,
      "alice",
      "3 days ago",
      change:sub(1, 1),
      "c"
    ) .. ("%s alice 2026-01-01 09:00:00 %4d: %s\n"):format(change, i, content)
  end
  return table.concat(out)
end

---Read `NAME` (or `name`) annotated by `changes`, and return its buffer.
local function read(host, jin, changes, name)
  name = name or NAME
  local bufnr = host.load(name)
  view.read(jin, host, bufnr, name)
  host.finish(ok("tpl\n"))
  host.finish(ok(annotation(changes)))
  return bufnr
end

---What jj tells of a change, as the panel asks for it.
local function details(fields)
  fields = fields or {}
  return m(
    fields.change or "kk",
    fields.change_rest or "mmmmmm",
    fields.commit or "c1",
    fields.commit_rest or "234567",
    fields.description or "add the answer\n\nIt is 42.\n",
    fields.author or "Alice",
    fields.email or "alice@example.com",
    "2026-01-01 09:00:00",
    "2 days ago"
  )
end

---The texts of the lines of `shown`.
local function texts(shown)
  local out = {}
  for i, line in ipairs(shown.lines) do
    local parts = {}
    for j, chunk in ipairs(line) do
      parts[j] = chunk.text
    end
    out[i] = table.concat(parts)
  end
  return out
end

---The timers running, not cancelled.
local function running(host)
  local out = {}
  for _, timer in ipairs(host.timers) do
    if not timer.cancelled then
      out[#out + 1] = timer
    end
  end
  return out
end

---Whether `argv` holds `words` one after another.
local function has(argv, words)
  for i = 1, #argv - #words + 1 do
    local found = true
    for j, word in ipairs(words) do
      found = found and argv[i + j - 1] == word
    end
    if found then
      return true
    end
  end
  return false
end

---Move the cursor of `bufnr` to `lnum`, as the editor tells the core.
local function move(jin, host, bufnr, lnum)
  host.cursors[bufnr] = lnum
  detail.cursor_moved(jin, host, bufnr)
end

local CHANGES = { "kkk", "kkk", "zzz", "kkk" }

---The first `n` of `list`.
local function first(list, n)
  local out = {}
  for i = 1, n do
    out[i] = list[i]
  end
  return out
end

---Read with a panel tall enough for every line the change tells, and
---return the buffer once jj told of the change under the cursor.
local function told(host, jin, fields)
  host.settings.detail_height = "12"
  local bufnr = read(host, jin, CHANGES)
  host.fire_timers()
  host.finish(ok(details(fields)))
  return bufnr
end

describe("the detail panel of the annotate view", function()
  describe("tells of the change of the line under the cursor", function()
    it("its description, its IDs, its author and when it was made", function()
      local host, jin = setup()
      local bufnr = told(host, jin)
      local lines = host.details[bufnr].lines
      assert.same({
        { { text = "add the answer", group = "JinDetailTitle" } },
        {
          { text = "Change  ", group = "JinDetailDim" },
          { text = "kk", group = "JinDetailChange" },
          { text = "mmmmmm", group = "JinDetailDim" },
        },
        {
          { text = "Commit  ", group = "JinDetailDim" },
          { text = "c1", group = "JinDetailCommit" },
          { text = "234567", group = "JinDetailDim" },
        },
        {
          { text = "Author  ", group = "JinDetailDim" },
          { text = "Alice <alice@example.com>", group = "JinDetailBody" },
        },
        {
          { text = "Date    ", group = "JinDetailDim" },
          { text = "2026-01-01 09:00:00 (2 days ago)", group = "JinDetailBody" },
        },
        { { text = "", group = "JinDetailBody" } },
        { { text = "It is 42.", group = "JinDetailBody" } },
      }, { lines[1], lines[2], lines[3], lines[4], lines[5], lines[6], lines[7] })
    end)

    it("asking jj for the IDs eight characters long, the shortest prefix apart", function()
      local host, jin = setup()
      read(host, jin, CHANGES)
      host.fire_timers()
      local template = host.runs[#host.runs].argv[#host.runs[#host.runs].argv]
      assert.truthy(template:find("self.change_id().shortest(8).prefix()", 1, true))
      assert.truthy(template:find("self.change_id().shortest(8).rest()", 1, true))
      assert.truthy(template:find("self.commit_id().shortest(8).prefix()", 1, true))
      assert.truthy(template:find("self.commit_id().shortest(8).rest()", 1, true))
    end)

    it("leaving out an author jj knows neither the name nor the email of", function()
      local host, jin = setup()
      local bufnr = told(host, jin, { author = "", email = "" })
      assert.equal("Date    2026-01-01 09:00:00 (2 days ago)", texts(host.details[bufnr])[4])
    end)

    it("lining a value too long for its line up after its label", function()
      local host, jin = setup()
      host.settings.detail_height = "12"
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { width = 30 }
      host.fire_timers()
      host.finish(ok(details()))
      assert.same(
        { "Author  Alice", "        <alice@example.com>" },
        { texts(host.details[bufnr])[4], texts(host.details[bufnr])[5] }
      )
    end)

    it("wrapping the description to its width", function()
      local host, jin = setup()
      host.settings.detail_height = "12"
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { width = 35 }
      host.fire_timers()
      host.finish(ok(details({
        description = "make the answer forty-two everywhere it is asked\n\n"
          .. "一二三四五六七八九十一二三四五六七八九十\n",
      })))
      local lines = texts(host.details[bufnr])
      assert.same({ "make the answer forty-two", "everywhere it is asked" }, { lines[1], lines[2] })
      assert.same(
        { "一二三四五六七八九十一二三四五六", "七八九十" },
        { lines[9], lines[10] }
      )
      for _, text in ipairs(lines) do
        assert.is_true(host.width(text) <= 33)
      end
    end)

    it("saying so when the change has no description", function()
      local host, jin = setup()
      local bufnr = told(host, jin, { description = "" })
      assert.same(
        { { text = "(no description set)", group = "JinDetailDim" } },
        host.details[bufnr].lines[1]
      )
      assert.equal("", texts(host.details[bufnr])[6])
    end)

    it("asking jj at the operation the view shows, taking no snapshot", function()
      local host, jin = setup()
      local name = "jin:///repo;view=annotate#--at-op op1 -- a.lua"
      local bufnr = read(host, jin, CHANGES, name)
      move(jin, host, bufnr, 3)
      host.fire_timers()
      local argv = host.runs[#host.runs].argv
      assert.is_true(has(argv, { "--at-op", "op1" }))
      assert.is_true(has(argv, { "--ignore-working-copy" }))
      assert.is_true(has(argv, { "-r", "zzz" }))
      assert.equal("/repo", host.runs[#host.runs].cwd)
    end)

    it("pinning the operation even when the view shows the latest one", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      move(jin, host, bufnr, 3)
      host.fire_timers()
      -- Left out, jj would merge a diverged operation log, adding an
      -- operation only because the cursor rested on a line.
      local argv = host.runs[#host.runs].argv
      assert.is_true(has(argv, { "--at-op", "@", "--ignore-working-copy" }))
    end)

    it("asking for the commit of a divergent change", function()
      local host, jin = setup()
      local bufnr = host.load(NAME)
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(m("zzz", "c9", "divergent", "x\n") .. "zzz alice 1: x\n"))
      host.fire_timers()
      assert.is_true(has(host.runs[#host.runs].argv, { "-r", "c9" }))
    end)

    it("as the annotation tells it when jj fails", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      host.fire_timers()
      host.finish({ code = 1, stdout = "", stderr = "Error: no such operation" })
      assert.same(
        { "about kkk", "Change  kkk", "Commit  ckkk", "Author  alice", "Date    3 days ago" },
        first(texts(host.details[bufnr]), 5)
      )
      assert.same({ text = "k", group = "JinDetailChange" }, host.details[bufnr].lines[2][2])
    end)
  end)

  describe("swaps its content as the cursor moves", function()
    it("showing at once what the line tells of its change, before jj is asked", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      assert.equal(2, #host.runs)
      assert.same(
        { "about kkk", "Change  kkk", "Commit  ckkk", "Author  alice", "Date    3 days ago" },
        first(texts(host.details[bufnr]), 5)
      )
      move(jin, host, bufnr, 3)
      assert.equal("about zzz", texts(host.details[bufnr])[1])
      assert.equal(2, #host.runs)
    end)

    it("asking jj once the cursor stayed on the change for a moment", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      assert.same({ detail.DEBOUNCE }, { running(host)[1].ms, running(host)[2] })
      assert.is_true(detail.DEBOUNCE > 0 and detail.DEBOUNCE <= 200)
      host.fire_timers()
      assert.equal(3, #host.runs)
      host.finish(ok(details()))
      assert.equal("add the answer", texts(host.details[bufnr])[1])
    end)

    it("asking jj nothing of a change the cursor only passed over", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      move(jin, host, bufnr, 3)
      move(jin, host, bufnr, 4)
      assert.equal(1, #running(host))
      host.fire_timers()
      assert.equal(3, #host.runs)
      assert.is_true(has(host.runs[3].argv, { "-r", "kkk" }))
    end)

    it("showing what jj told at once when the cursor comes back to a change", function()
      local host, jin = setup()
      local bufnr = told(host, jin)
      move(jin, host, bufnr, 3)
      move(jin, host, bufnr, 1)
      assert.equal("add the answer", texts(host.details[bufnr])[1])
      assert.same({}, running(host))
    end)

    it("running jj once per change and read", function()
      local host, jin = setup()
      local bufnr = told(host, jin)
      move(jin, host, bufnr, 3)
      host.fire_timers()
      host.finish(ok(details({ change = "zz" })))
      move(jin, host, bufnr, 4)
      host.fire_timers()
      assert.equal(4, #host.runs)
      assert.equal("Change  kkmmmmmm", texts(host.details[bufnr])[2])
      view.read(jin, host, bufnr, NAME)
      host.finish(ok(annotation(CHANGES)))
      host.fire_timers()
      assert.equal(6, #host.runs)
    end)

    it("ignoring what jj tells once the cursor moved to another change", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      host.fire_timers()
      move(jin, host, bufnr, 3)
      host.finish(ok(details()))
      assert.equal("about zzz", texts(host.details[bufnr])[1])
    end)

    it("ignoring what jj tells once the panel was hidden", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      host.fire_timers()
      detail.toggle(jin, host, bufnr)
      host.finish(ok(details()))
      assert.is_nil(host.details[bufnr])
    end)

    it("staying open all the while, drawn again only when its content changed", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      local draws = host.detail_draws
      move(jin, host, bufnr, 2)
      assert.equal(draws, host.detail_draws)
      move(jin, host, bufnr, 3)
      assert.equal(draws + 1, host.detail_draws)
      assert.equal(0, host.detail_closes)
    end)

    it("left blank on a line of no change, without asking jj", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      move(jin, host, bufnr, 9)
      host.fire_timers()
      assert.equal(2, #host.runs)
      for _, text in ipairs(texts(host.details[bufnr])) do
        assert.equal("", text)
      end
    end)
  end)

  describe("keeps one size from line to line", function()
    ---The panel of the annotate view with the g:jin_* `settings` set, in a
    ---window `win`.
    local function sized(settings, win)
      local host, jin = setup()
      for name, value in pairs(settings) do
        host.settings[name] = value
      end
      local bufnr = host.load(NAME)
      host.windows[bufnr] = win or {}
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(annotation(CHANGES)))
      return host.details[bufnr]
    end

    it("a third of the window high with its border by default, as wide as the window", function()
      local shown = sized({})
      assert.same({ 8, 80 }, { shown.height, shown.width })
      assert.equal(6, #shown.lines)
      assert.equal(10, sized({}, { height = 30 }).height)
      assert.equal(10, sized({}, { height = 32 }).height)
    end)

    it("as many rows high as g:jin_detail_height says", function()
      assert.equal(5, sized({ detail_height = "5" }).height)
    end)

    it("as high as the fraction of the window g:jin_detail_height says below 1", function()
      assert.equal(10, sized({ detail_height = "0.25" }, { height = 40 }).height)
      assert.equal(6, sized({ detail_height = "0.25" }, { height = 24 }).height)
    end)

    it("as g:jin_{view}_detail_height says for its view before g:jin_detail_height", function()
      local settings = { detail_height = "5", annotate_detail_height = "7" }
      assert.equal(7, sized(settings).height)
      settings.annotate_detail_height = "0.5"
      assert.equal(12, sized(settings).height)
    end)

    it("leaving the height of other views to g:jin_{view}_detail_height of theirs", function()
      assert.equal(5, sized({ detail_height = "5", log_detail_height = "7" }).height)
    end)

    it("passing over a height that is neither rows nor a fraction", function()
      local settings = { detail_height = "5" }
      for _, value in ipairs({ "0", "-2", "2.5", "x" }) do
        settings.annotate_detail_height = value
        assert.equal(5, sized(settings).height)
      end
      assert.equal(8, sized({ detail_height = "0" }).height)
      assert.equal(8, sized({ detail_height = "1.5" }).height)
    end)

    it("no more than half the window high", function()
      local host, jin = setup()
      host.settings.detail_height = "8"
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { height = 11 }
      detail.cursor_moved(jin, host, bufnr)
      assert.equal(5, host.details[bufnr].height)
      assert.equal(12, sized({ detail_height = "20" }).height)
      assert.equal(12, sized({ detail_height = "0.75" }).height)
    end)

    it("no less than 3 rows high, a row of content within its border", function()
      assert.equal(3, sized({ detail_height = "1" }).height)
      assert.equal(3, sized({ detail_height = "0.05" }).height)
      assert.equal(3, sized({}, { height = 7 }).height)
    end)

    it("leaving rows it has no content for blank", function()
      local host, jin = setup()
      host.settings.detail_height = "12"
      local bufnr = told(host, jin)
      local full = host.details[bufnr]
      move(jin, host, bufnr, 3)
      local quick = host.details[bufnr]
      assert.same({ full.row, full.height, full.width }, { quick.row, quick.height, quick.width })
      assert.same({ "about zzz", "", "" }, { texts(quick)[1], texts(quick)[6], texts(quick)[10] })
      assert.equal(10, #quick.lines)
    end)

    it("cutting content longer than it, its last row the ellipsis glyph", function()
      local host, jin = setup()
      host.settings.detail_height = "5"
      local bufnr = read(host, jin, CHANGES)
      assert.same({ "about kkk", "Change  kkk", "..." }, texts(host.details[bufnr]))
      assert.equal("JinDetailDim", host.details[bufnr].lines[3][1].group)
    end)

    it("and shows none in a window too low for a row of content", function()
      local host, jin = setup()
      local bufnr = host.load(NAME)
      host.windows[bufnr] = { height = 5 }
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(annotation(CHANGES)))
      assert.is_nil(host.details[bufnr])
    end)
  end)

  describe("lies where g:jin_detail_position says", function()
    ---The panel and the room made for it with g:jin_detail_position set to
    ---`position`, in a window `win` with the cursor on the row `row`.
    local function placed(position, win)
      local host, jin = setup()
      host.settings.detail_position = position
      local bufnr = host.load(NAME)
      host.windows[bufnr] = win or {}
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(annotation(CHANGES)))
      local shown = host.details[bufnr]
      return { shown.row, shown.col, shown.width, shown.height }, host.rooms[bufnr], host
    end

    it("docked at the bottom, as wide as the window, by default", function()
      local frame, room = placed(nil, { textoff = 4 })
      assert.same({ 16, 0, 80, 8 }, frame)
      assert.same({ below = 8 }, room)
    end)

    it("docked at the bottom with 'bottom', and for a value it does not know", function()
      assert.same({ 16, 0, 80, 8 }, (placed("bottom")))
      assert.same({ 16, 0, 80, 8 }, (placed("left")))
    end)

    it("docked at the top with 'top'", function()
      local frame, room = placed("top")
      assert.same({ 0, 0, 80, 8 }, frame)
      assert.same({ above = 8 }, room)
    end)

    it("with 'auto', at the bottom or the top, away from the half the cursor is in", function()
      local frame, room = placed("auto", { row = 12 })
      assert.same({ 16, 0, 80, 8 }, frame)
      assert.is_nil(room)
      assert.same({ 0, 0, 80, 8 }, (placed("auto", { row = 13 })))
    end)

    it("with 'right', docked at the right edge, as high as the window", function()
      local frame = placed("right", { width = 120 })
      assert.same({ 0, 70, 50, 24 }, frame)
    end)

    it("with 'right', as wide as g:jin_detail_width says, at most half the text", function()
      local host, jin = setup()
      host.settings.detail_position = "right"
      host.settings.detail_width = "30"
      local bufnr = read(host, jin, CHANGES)
      assert.same({ 50, 30 }, { host.details[bufnr].col, host.details[bufnr].width })
      assert.same({ 0, 42, 38, 24 }, (placed("right", { width = 80, textoff = 4 })))
    end)

    it(
      "with 'right', as wide as the fraction of the text g:jin_detail_width says below 1",
      function()
        local host, jin = setup()
        host.settings.detail_position = "right"
        host.settings.detail_width = "0.25"
        local bufnr = host.load(NAME)
        host.windows[bufnr] = { width = 124, textoff = 4 }
        view.read(jin, host, bufnr, NAME)
        host.finish(ok("tpl\n"))
        host.finish(ok(annotation(CHANGES)))
        assert.equal(30, host.details[bufnr].width)
      end
    )

    it("with 'right', as wide as g:jin_{view}_detail_width says for its view first", function()
      local host, jin = setup()
      host.settings.detail_position = "right"
      host.settings.detail_width = "30"
      host.settings.annotate_detail_width = "20"
      host.settings.log_detail_width = "10"
      local bufnr = read(host, jin, CHANGES)
      assert.equal(20, host.details[bufnr].width)
    end)

    it("with 'right', making room after each line only where lines do not wrap", function()
      local _, room = placed("right", { width = 120, wrap = false })
      assert.same({ right = 50 }, room)
      _, room = placed("right", { width = 120 })
      assert.is_nil(room)
    end)
  end)

  describe("keeps every line able to come out from under it", function()
    it("keeping the cursor out from under it on every move", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      move(jin, host, bufnr, 3)
      assert.same({ window = 1000 + bufnr, room = { below = 8 } }, host.kept[#host.kept])
    end)

    it("keeping the cursor nowhere with 'auto', which moves out of its way", function()
      local host, jin = setup()
      host.settings.detail_position = "auto"
      local bufnr = read(host, jin, CHANGES)
      move(jin, host, bufnr, 3)
      assert.same({}, host.kept)
    end)

    it("making the room again after the view was read again", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      local makes = host.room_makes
      move(jin, host, bufnr, 3)
      assert.equal(makes, host.room_makes)
      view.read(jin, host, bufnr, NAME)
      host.finish(ok(annotation(CHANGES)))
      assert.equal(makes + 1, host.room_makes)
      assert.same({ below = 8 }, host.rooms[bufnr])
    end)

    it("closing the panel and its room when the view read again tells nothing", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      assert.truthy(host.details[bufnr])
      view.read(jin, host, bufnr, NAME)
      -- Lines the annotation cannot be split from leave the view nothing to
      -- tell, so the panel shown before must not stay behind.
      host.finish(ok("plain\n"))
      assert.is_nil(host.details[bufnr])
      assert.is_nil(host.rooms[bufnr])
    end)

    it("and takes the room away once it is hidden or closed", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      detail.toggle(jin, host, bufnr)
      assert.is_nil(host.rooms[bufnr])
      detail.toggle(jin, host, bufnr)
      assert.same({ below = 8 }, host.rooms[bufnr])
      detail.close(host, bufnr)
      assert.is_nil(host.rooms[bufnr])
    end)
  end)

  describe("is shown or hidden per window", function()
    it("by K, which the detail action is mapped to", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      local mapped = false
      for _, key in ipairs(host.keys[bufnr].keys) do
        mapped = mapped or (key[1] == "K" and key[2] == "detail" and key[3] == nil)
      end
      assert.is_true(mapped)
    end)

    it("hidden by the action, it shows no more as the cursor moves or the view is read", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      action.run(jin, host, bufnr, "detail", 1, 1, { key = true })
      assert.is_nil(host.details[bufnr])
      move(jin, host, bufnr, 3)
      host.fire_timers()
      view.read(jin, host, bufnr, NAME)
      host.finish(ok(annotation(CHANGES)))
      assert.is_nil(host.details[bufnr])
      action.run(jin, host, bufnr, "detail", 3, 3, { key = true })
      assert.equal("about zzz", texts(host.details[bufnr])[1])
    end)

    it("each window keeping its own state", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { id = 1 }
      detail.toggle(jin, host, bufnr)
      host.windows[bufnr] = { id = 2 }
      detail.entered(jin, host, bufnr)
      assert.is_not_nil(host.details[bufnr])
      host.windows[bufnr] = { id = 1 }
      detail.entered(jin, host, bufnr)
      assert.is_nil(host.details[bufnr])
    end)

    it("a window starting hidden with g:jin_detail = 0", function()
      for _, off in ipairs({ "0", "false", "v:false" }) do
        local host, jin = setup()
        host.settings.detail = off
        local bufnr = read(host, jin, CHANGES)
        assert.is_nil(host.details[bufnr])
        detail.toggle(jin, host, bufnr)
        assert.is_not_nil(host.details[bufnr])
      end
    end)

    it("a window closed forgetting its state", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { id = 1 }
      detail.toggle(jin, host, bufnr)
      detail.window_closed(host, 1)
      detail.entered(jin, host, bufnr)
      assert.is_not_nil(host.details[bufnr])
    end)
  end)

  describe("closes", function()
    it("when the window or the buffer is left, and shows again when it is entered", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      detail.close(host, bufnr)
      assert.is_nil(host.details[bufnr])
      assert.same({}, running(host))
      detail.entered(jin, host, bufnr)
      assert.is_not_nil(host.details[bufnr])
    end)

    it("in a window the cursor is not in", function()
      local host, jin = setup()
      local bufnr = host.load(NAME)
      host.windows[bufnr] = { current = false }
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(annotation(CHANGES)))
      assert.is_nil(host.details[bufnr])
    end)

    it("when the buffer is unloaded", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      view.forget(host, bufnr)
      assert.is_nil(host.details[bufnr])
      assert.is_nil(host.rooms[bufnr])
    end)
  end)

  describe("tells, dimmed at its bottom right, the key that hides it", function()
    local PLUG = "<Plug>(jin-action-detail)"

    ---Read with `maps` as the mappings of the buffer, in a host that draws
    ---a footer in the border when `border` is true.
    local function hinted(maps, border)
      local host, jin = setup()
      host.maps = maps
      host.detail_footer = border
      return host, read(host, jin, CHANGES), jin
    end

    it("in the bottom border, where the editor draws a footer there", function()
      local host, bufnr = hinted({ { lhs = "K", rhs = PLUG, mode = "n" } }, true)
      local shown = host.details[bufnr]
      assert.same({ { text = "Press K to hide", group = "JinDetailDim" } }, shown.footer)
      assert.equal(6, #shown.lines)
      assert.equal("", texts(shown)[6])
    end)

    it("on its last row, right-aligned, where the editor draws none", function()
      local host, bufnr = hinted({ { lhs = "K", rhs = PLUG, mode = "n" } }, false)
      local shown = host.details[bufnr]
      assert.is_nil(shown.footer)
      assert.equal(6, #shown.lines)
      assert.same({
        { text = (" "):rep(78 - 15), group = "JinDetailBody" },
        { text = "Press K to hide", group = "JinDetailDim" },
      }, shown.lines[6])
    end)

    it("cutting the content before its last row to make room for it", function()
      local host, jin = setup()
      host.maps = { { lhs = "K", rhs = PLUG, mode = "n" } }
      host.settings.detail_height = "5"
      local bufnr = read(host, jin, CHANGES)
      local lines = texts(host.details[bufnr])
      assert.same({ "about kkk", "..." }, { lines[1], lines[2] })
      assert.equal("Press K to hide", lines[3]:match("%S.*$"))
    end)

    it("naming the key the user mapped to the action in place of K", function()
      local host, bufnr = hinted({
        { lhs = "<Plug>(jin-action-detail)", rhs = ":call x()<CR>", mode = "n" },
        { lhs = "<Space>d", rhs = PLUG, mode = "n" },
      }, true)
      assert.equal("Press <Space>d to hide", host.details[bufnr].footer[1].text)
    end)

    it("naming K before other keys mapped to it as well", function()
      local host, bufnr = hinted({
        { lhs = "<Space>d", rhs = PLUG, mode = "n" },
        { lhs = "K", rhs = PLUG, mode = " " },
      }, true)
      assert.equal("Press K to hide", host.details[bufnr].footer[1].text)
    end)

    it("and nothing where no key in Normal mode leads to the action", function()
      local host, bufnr = hinted({
        { lhs = "K", rhs = PLUG, mode = "x" },
        { lhs = "K", rhs = "<Plug>(jin-action-help)", mode = "n" },
      }, true)
      assert.is_nil(host.details[bufnr].footer)
      host, bufnr = hinted({}, false)
      assert.equal("", texts(host.details[bufnr])[6])
    end)

    ---The footer of a panel `width` cells wide, `lhs` hiding it.
    local function footer_at(width, lhs)
      local host, jin = setup()
      host.maps = { { lhs = lhs or "K", rhs = PLUG, mode = "n" } }
      host.detail_footer = true
      local bufnr = host.load(NAME)
      host.windows[bufnr] = { width = width }
      view.read(jin, host, bufnr, NAME)
      host.finish(ok("tpl\n"))
      host.finish(ok(annotation(CHANGES)))
      local footer = host.details[bufnr].footer
      return footer and footer[1].text
    end

    it("in full while it fits beside a corner and a space on either side", function()
      assert.equal("Press K to hide", footer_at(19))
    end)

    it("shortened to the key in brackets where the panel is too narrow for that", function()
      assert.equal("[K] hide", footer_at(18))
      assert.equal("[K] hide", footer_at(12))
    end)

    it("nor where even the shortened one does not fit in the width of the panel", function()
      assert.is_nil(footer_at(11))
      assert.is_nil(footer_at(20, "<Space><Space><Space>d"))
    end)

    it("looking the key up again when the window is entered, not on every move", function()
      local host, bufnr, jin = hinted({ { lhs = "K", rhs = PLUG, mode = "n" } }, true)
      host.maps = { { lhs = "gK", rhs = PLUG, mode = "n" } }
      move(jin, host, bufnr, 3)
      assert.equal("Press K to hide", host.details[bufnr].footer[1].text)
      detail.entered(jin, host, bufnr)
      assert.equal("Press gK to hide", host.details[bufnr].footer[1].text)
    end)
  end)

  describe("draws with the glyphs of g:jin_glyph_preset", function()
    local nf = glyph.PRESETS.nerdfont

    it("a glyph before the label of each field, the values lined up after the widest", function()
      local host, jin = setup()
      host.settings.glyph_preset = "nerdfont"
      host.settings.detail_height = "12"
      local bufnr = read(host, jin, CHANGES)
      host.windows[bufnr] = { width = 35 }
      host.fire_timers()
      host.finish(ok(details()))
      local lines = texts(host.details[bufnr])
      assert.same({
        nf.change .. " Change  kkmmmmmm",
        nf.commit .. " Commit  c1234567",
        nf.author .. " Author  Alice",
        "          <alice@example.com>",
        nf.date .. " Date    2026-01-01 09:00:00",
      }, { lines[2], lines[3], lines[4], lines[5], lines[6] })
    end)

    it("the label alone where the preset has no glyph for it", function()
      local host, jin = setup()
      host.settings.glyph_preset = "unicode"
      local bufnr = told(host, jin)
      local lines = texts(host.details[bufnr])
      assert.same(
        { "○ Change  kkmmmmmm", "◉ Commit  c1234567", "Author    Alice <alice@example.com>" },
        { lines[2], lines[3], lines[4] }
      )
    end)

    it("its border, clockwise from the top-left corner", function()
      for _, case in ipairs({
        { "nerdfont", { "╭", "─", "╮", "│", "╯", "─", "╰", "│" } },
        { "unicode", { "╭", "─", "╮", "│", "╯", "─", "╰", "│" } },
        { "ascii", { "+", "-", "+", "|", "+", "-", "+", "|" } },
      }) do
        local host, jin = setup()
        host.settings.glyph_preset = case[1]
        local bufnr = read(host, jin, CHANGES)
        assert.same(case[2], host.details[bufnr].border, case[1])
      end
    end)

    it("each glyph g:jin_glyphs sets in place of the preset's", function()
      local host, jin = setup()
      host.dict_settings.glyphs = { change = "@", border_top_left = "*" }
      local bufnr = read(host, jin, CHANGES)
      assert.equal("@ Change  kkk", texts(host.details[bufnr])[2])
      assert.equal("*", host.details[bufnr].border[1])
    end)

    it("anew once the glyphs changed, as the cursor moves within the same change", function()
      local host, jin = setup()
      local bufnr = read(host, jin, CHANGES)
      local draws = host.detail_draws
      host.settings.glyph_preset = "unicode"
      move(jin, host, bufnr, 2)
      assert.equal(draws + 1, host.detail_draws)
      assert.equal("╭", host.details[bufnr].border[1])
    end)
  end)

  it("shows nothing where the annotation could not be told from the file", function()
    local host, jin = setup()
    local bufnr = host.load(NAME)
    view.read(jin, host, bufnr, NAME)
    host.finish(ok("tpl\n"))
    host.finish(ok(m("kkk", "c1", "-", "x\n") .. "x\nkkk alice\n"))
    host.fire_timers()
    assert.equal(2, #host.runs)
    assert.is_nil(host.details[bufnr])
  end)

  it("shows nothing in a view that tells nothing more", function()
    local host, jin = setup()
    local name = "jin:///repo;view=file#-r kkk a.lua"
    local bufnr = host.load(name)
    view.read(jin, host, bufnr, name)
    host.finish(ok("x\n"))
    host.finish(ok(""))
    detail.cursor_moved(jin, host, bufnr)
    host.fire_timers()
    assert.equal(2, #host.runs)
    assert.is_nil(host.details[bufnr])
  end)
end)
