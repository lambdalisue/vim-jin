local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local glyphs = require("jin.glyph").PRESETS[require("jin.glyph").DEFAULT_PRESET]
local HINT = ("<CR> open %s :w apply %s :q cancel"):format(glyphs.dot, glyphs.dot)
local EDITED = "  " .. glyphs.edit .. " edited"

---A workspace whose @, "both", adds a.txt and b.txt.
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  for _, name in ipairs({ "a.txt", "b.txt" }) do
    local f = assert(io.open(dir .. "/" .. name, "w"))
    f:write(name .. "\n")
    f:close()
  end
  h.eq(0, jin.jj({ "describe", "-m", "both" }).code)
  return dir
end

local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  return view.meta(host, bufnr)
end

local function line_of(text)
  for lnum, line in ipairs(h.lines()) do
    if line:find(text, 1, true) then
      return lnum
    end
  end
  error("no line shows " .. text .. " in:\n" .. table.concat(h.lines(), "\n"))
end

local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
end

local function files(rev)
  return jin.jj({ "diff", "-r", rev, "--name-only" }).stdout
end

local function current()
  return jin.jj({ "log", "--no-graph", "-r", "@", "-T", "change_id" }).stdout
end

local function description()
  return jin.jj({ "log", "--no-graph", "-r", "@", "-T", "description" }).stdout
end

---Wait for the list of the diff editor, and for it to be read.
local function listed()
  h.eventually(function()
    return vim.fn.bufname():find(";view=diffedit#", 1, true) ~= nil
  end, function()
    return "no list of files: " .. vim.fn.bufname()
  end)
  settle()
end

---Split the change "both" and wait for the list of its files.
local function split()
  h.ex("JinLog")
  settle()
  act("split", line_of("both"))
  listed()
  h.eq({ "A a.txt", "A b.txt", HINT }, h.lines())
end

---The statusline a pane draws, in the window `winid`.
local function statusline_of(winid)
  h.ex("let g:statusline_winid = " .. winid)
  local drawn = vim.fn.eval("jin#statusline#pane()")
  h.ex("unlet g:statusline_winid")
  return tostring(drawn)
end

---Open the file of line `lnum` of the list, and wait for its middle pane.
---@return integer[] windows of the tab page, left to right
local function open(lnum, view_name)
  act("open", lnum)
  h.eventually(function()
    return vim.fn.bufname():find(";view=" .. view_name .. "#", 1, true) ~= nil
  end, function()
    return "no middle pane: " .. vim.fn.bufname()
  end)
  settle()
  local wins = {}
  for nr = 1, vim.fn.winnr("$") do
    wins[nr] = vim.fn.win_getid(nr)
  end
  return wins
end

---Resolve a conflict of f.txt between "left" and "right", and wait for
---the list of the conflicted files.
---@return string dir
local function resolving()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  local function write(text)
    local f = assert(io.open(dir .. "/f.txt", "w"))
    f:write(text)
    f:close()
  end
  write("base\n")
  h.eq(0, jin.jj({ "new", "-m", "left" }).code)
  write("left\n")
  local left = current()
  h.eq(0, jin.jj({ "new", "-m", "right", "@--" }).code)
  write("right\n")
  local right = current()
  h.eq(0, jin.jj({ "new", "-m", "merge", left, right }).code)
  h.ex("JinConflicts")
  settle()
  act("resolve", line_of("merge"))
  listed()
  h.eq({ "C f.txt", HINT }, h.lines())
  return dir
end

return {
  {
    "split keeps what :w on the list leaves in the result as the first change",
    function()
      workspace()
      split()
      act("take:left", line_of("b.txt"))
      settle()
      h.eq({ "A a.txt", "A b.txt" .. EDITED, HINT }, h.lines())
      h.ex("write")
      h.eventually(function()
        return files("@-") == "a.txt\n" and files("@") == "b.txt\n"
      end, function()
        return "@- has " .. files("@-") .. "@ has " .. files("@")
      end)
    end,
  },
  {
    "a file opens in three panes in diff mode, named, the sides read-only",
    function()
      workspace()
      split()
      local wins = open(line_of("a.txt"), "result")
      h.eq(3, #wins)
      local expected = {
        { "BEFORE", "read-only: the change's parent", 0 },
        { "RESULT", "Edit this and :w to keep it as the first change", 1 },
        { "AFTER", "read-only: the change as it is", 0 },
      }
      for i, winid in ipairs(wins) do
        local bufnr = vim.fn.winbufnr(winid)
        h.eq(1, vim.fn.getwinvar(winid, "&diff"))
        h.eq(expected[i][3], vim.fn.getbufvar(bufnr, "&modifiable"))
        local drawn = statusline_of(winid)
        h.truthy(drawn:find(expected[i][1], 1, true), drawn)
        h.truthy(drawn:find(expected[i][2], 1, true), drawn)
      end
      h.eq(wins[2], vim.fn.win_getid())
      h.eq({ "a.txt" }, h.lines())
      h.ex("silent! tabonly!")
    end,
  },
  {
    "the middle pane gets hunks with the do keys, and the sides put them with dp",
    function()
      local dir = workspace()
      h.eq(0, jin.jj({ "new", "-m", "edit" }).code)
      local f = assert(io.open(dir .. "/a.txt", "w"))
      f:write("A\n")
      f:close()
      h.ex("JinLog")
      settle()
      act("diffedit", line_of("edit"))
      listed()
      local wins = open(1, "result")
      h.eq({ "A" }, h.lines())
      for key, plug in pairs({
        ["do"] = "diffget",
        dol = "diffget-l",
        dor = "diffget-r",
        doa = "diffget-all",
        doA = "diffget-all-reversed",
      }) do
        h.eq("<Plug>(jin-action-" .. plug .. ")", vim.fn.maparg(key, "n"))
      end
      h.eq("", vim.fn.maparg("dob", "n"))
      -- do waits for a letter that may follow.
      h.eq(0, vim.fn.maparg("do", "n", 0, 1).nowait)
      h.ex("normal doa")
      h.eq({ "a.txt", "A" }, h.lines())
      h.ex("normal doA")
      h.eq({ "A", "a.txt" }, h.lines())
      vim.fn.setline(1, "A")
      vim.fn.deletebufline(vim.fn.bufnr(), 2, "$")
      h.ex("diffupdate")
      h.ex("normal dol")
      h.eq({ "a.txt" }, h.lines())
      h.ex("diffupdate")
      vim.fn.win_gotoid(wins[3])
      h.eq("<Plug>(jin-diffput)", vim.fn.maparg("dp", "n"))
      h.ex("normal dp")
      vim.fn.win_gotoid(wins[2])
      h.eq({ "A" }, h.lines())
      h.ex("silent! tabonly!")
      h.ex("silent! %bwipeout!")
    end,
  },
  {
    ":w in the middle pane writes it and goes back to the list, the file edited",
    function()
      workspace()
      split()
      local list = vim.fn.bufnr()
      open(line_of("a.txt"), "result")
      vim.fn.setline(1, "edited")
      h.ex("write")
      h.eventually(function()
        return vim.fn.tabpagenr("$") == 1 and vim.fn.bufnr() == list
      end, function()
        return ("%d tab pages, in %s"):format(vim.fn.tabpagenr("$"), vim.fn.bufname())
      end)
      h.eventually(function()
        return h.lines()[1] == "A a.txt" .. EDITED
      end, function()
        return table.concat(h.lines(), "\n")
      end)
      h.eq(1, vim.fn.getbufvar(list, "&modified"))
      h.ex("write")
      h.eventually(function()
        return jin.jj({ "file", "show", "-r", "@-", "a.txt" }).stdout == "edited\n"
      end, function()
        return "a.txt is " .. jin.jj({ "file", "show", "-r", "@-", "a.txt" }).stdout
      end)
    end,
  },
  {
    "leaving the list cancels, refused first while a file is edited",
    function()
      workspace()
      split()
      local list = vim.fn.bufnr()
      local id = tonumber(vim.fn.bufname():match("#(%d+)$"))
      act("take:left", line_of("b.txt"))
      settle()
      -- Refused as for any buffer holding an edit, which :q! forces.
      h.ex("silent! quit")
      h.ex("let v:errmsg = ''")
      h.eq(list, vim.fn.bufnr())
      h.truthy(require("jin.diffedit").get(host, id), "the edit was cancelled unasked")
      h.ex("quit!")
      h.eventually(function()
        return require("jin.diffedit").get(host, id) == nil
      end, "the edit was never cancelled")
      h.eventually(function()
        return files("@") == "a.txt\nb.txt\n"
      end, function()
        return "@ has " .. files("@")
      end)
      h.eq("both\n", description())
    end,
  },
  {
    "leaving the list with nothing edited cancels without a question",
    function()
      workspace()
      split()
      -- In a window of its own, left for the log it was opened from.
      h.eq(2, vim.fn.winnr("$"))
      h.ex("quit")
      h.truthy(vim.fn.bufname():find(";view=log#", 1, true), vim.fn.bufname())
      h.eventually(function()
        return files("@") == "a.txt\nb.txt\n"
      end, function()
        return "@ has " .. files("@")
      end)
      h.eq("both\n", description())
    end,
  },
  {
    "squash:interactive moves what the result holds into the parent",
    function()
      workspace()
      local both = current()
      h.eq(0, jin.jj({ "new", "--insert-before", "@", "-m", "base" }).code)
      local base = current()
      h.ex("JinLog")
      settle()
      act("squash:interactive", line_of("both"))
      listed()
      act("take:left", line_of("b.txt"))
      settle()
      h.ex("write")
      h.eventually(function()
        return files(base) == "a.txt\n"
      end, function()
        return "base has " .. files(base)
      end)
      h.eq("b.txt\n", files(both))
    end,
  },
  {
    "the merge tool takes a side of the conflict in its output and hands it to jj",
    function()
      local dir = resolving()
      local wins = open(1, "merge")
      local expected = { "LEFT", "OUTPUT", "RIGHT" }
      for i, winid in ipairs(wins) do
        local drawn = statusline_of(winid)
        h.truthy(drawn:find(expected[i], 1, true), drawn)
      end
      h.eq("<Plug>(jin-action-diffget-base)", vim.fn.maparg("dob", "n"))
      vim.fn.cursor(line_of("<<<<<<<"), 1)
      h.ex("normal dol")
      h.eq({ "left" }, h.lines())
      h.ex("write")
      h.eventually(function()
        return vim.fn.bufname():find(";view=diffedit#", 1, true) ~= nil
          and h.lines()[1] == "C f.txt" .. EDITED
      end, function()
        return vim.fn.bufname() .. ": " .. table.concat(h.lines(), "\n")
      end)
      h.ex("write")
      h.eventually(function()
        return jin.jj({ "file", "show", "-r", "@", "f.txt" }).stdout == "left\n"
      end, function()
        return "f.txt is " .. jin.jj({ "file", "show", "-r", "@", "f.txt" }).stdout
      end)
      h.eq("left\n", assert(io.open(dir .. "/f.txt")):read("*a"))
    end,
  },
  {
    "the panes open without a message",
    function()
      local shortmess = vim.o and vim.o.shortmess or vim.eval("&shortmess")
      h.ex("set shortmess-=F")
      local dir = h.tempdir()
      for _, name in ipairs({ "left", "output", "right" }) do
        local f = assert(io.open(dir .. "/" .. name .. ".txt", "w"))
        f:write(name .. "\n")
        f:close()
      end
      h.ex("messages clear")
      host.open_panes(
        { path = dir .. "/left.txt", title = "L", about = "l" },
        { path = dir .. "/output.txt", title = "O", about = "o" },
        { path = dir .. "/right.txt", title = "R", about = "r" }
      )
      -- What a file read says of it: its lines and bytes.
      local said = {}
      for line in tostring(vim.fn.execute("messages")):gmatch("[^\n]+") do
        if line:find("%dL, %d+B") then
          said[#said + 1] = line
        end
      end
      h.ex("silent! tabonly!")
      h.ex("let &shortmess = " .. vim.fn.string(shortmess))
      h.eq({}, said)
    end,
  },
}
