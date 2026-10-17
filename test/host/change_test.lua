local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

---A workspace whose @ is "second" on top of "first".
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  h.eq(0, jin.jj({ "describe", "-m", "first" }).code)
  h.eq(0, jin.jj({ "new", "-m", "second" }).code)
  return dir
end

local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  return view.meta(host, bufnr)
end

local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
end

local function at(rev)
  return jin.jj({ "log", "--no-graph", "-r", rev, "-T", "description" }).stdout
end

return {
  {
    "commit opens the draft of the working copy, and :w commits it with the text",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("commit", 1)
      h.truthy(vim.fn.bufname():find(";view=commit#-r ", 1, true), vim.fn.bufname())
      settle()
      h.eq("second", vim.fn.getline(1))
      vim.fn.setline(1, "second, committed")
      local commit = vim.fn.bufnr()
      h.ex("write")
      h.eventually(function()
        return at("@-") == "second, committed\n" and at("@") == ""
      end, function()
        return "@- is " .. at("@-")
      end)
      h.eventually(function()
        return vim.fn.bufexists(commit) == 0
      end, "the commit buffer is still there")
      h.truthy(vim.fn.bufname():find(";view=log#", 1, true), vim.fn.bufname())
      h.eq(1, vim.fn.winnr("$"))
    end,
  },
  {
    "a commit buffer opened in a window or tab page of its own closes it once committed",
    function()
      for _, name in ipairs({ "commit:split", "commit:tab" }) do
        workspace()
        h.ex("JinLog")
        settle()
        local log_win = vim.fn.win_getid()
        local tabs = vim.fn.tabpagenr("$")
        act(name, 1)
        settle()
        local commit = vim.fn.bufnr()
        vim.fn.setline(1, "committed by " .. name)
        h.ex("write")
        h.eventually(function()
          return vim.fn.bufexists(commit) == 0
        end, name .. ": the commit buffer is still there")
        h.eq(tabs, vim.fn.tabpagenr("$"))
        h.eq(1, vim.fn.winnr("$"))
        h.eq(log_win, vim.fn.win_getid())
      end
    end,
  },
  {
    "a commit refused as the working copy moved keeps the commit buffer and its text",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("commit", 1)
      settle()
      local commit = vim.fn.bufnr()
      vim.fn.setline(1, "kept")
      h.eq(0, jin.jj({ "new" }).code)
      h.ex("silent! write")
      h.ex("let v:errmsg = ''")
      h.eq(commit, vim.fn.bufnr())
      h.eq("kept", vim.fn.getline(1))
      h.ex("bwipeout!")
    end,
  },
}
