local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function write(path, lines)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
end

---A workspace whose @ adds f.lua and was described twice.
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  write(dir .. "/f.lua", { "a", "b" })
  jin.jj({ "describe", "-m", "draft" })
  jin.jj({ "describe", "-m", "final" })
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

local function find(pattern)
  for lnum, line in ipairs(h.lines()) do
    if line:find(pattern) then
      return lnum
    end
  end
  error("no line matches " .. pattern .. " in:\n" .. table.concat(h.lines(), "\n"))
end

return {
  {
    "JinOpLog leads from an operation to the log as it was after it",
    function()
      local dir = workspace()
      h.ex("JinOpLog")
      local meta = settle()
      local op = meta.entries[1][1]
      h.truthy(op and op:match("^%x+$"), "no operation ID on the first line")
      act("log", 1)
      h.eq("jin://" .. dir .. ";view=log#--at-op " .. op, vim.fn.bufname())
      settle()
      find("final")
    end,
  },
  {
    "JinEvolog compares a version of a change with the one before it",
    function()
      local dir = workspace()
      h.ex("JinEvolog")
      local meta = settle()
      local first = meta.entries[1]
      h.truthy(first and #first[2] == 40, "no commit ID on the first line")
      act("interdiff", 1)
      h.truthy(vim.fn.bufname():find("jin://" .. dir, 1, true), vim.fn.bufname())
      h.truthy(vim.fn.bufname():find(";view=interdiff#--from ", 1, true), vim.fn.bufname())
      settle()
    end,
  },
  {
    "JinStatus opens the file of a changed path",
    function()
      local dir = workspace()
      h.ex("JinStatus")
      settle()
      act("edit", find("^A f%.lua"))
      h.eq(dir .. "/f.lua", vim.fn.expand("%:p"))
    end,
  },
  {
    "JinAnnotate leads from a line to the change that wrote it",
    function()
      local dir = workspace()
      h.ex("JinAnnotate f.lua")
      local meta = settle()
      local change = meta.entries[1][1]
      h.truthy(change and #change == 32, "no change ID on the first line")
      act("show", 1)
      h.eq("jin://" .. dir .. ";view=show#" .. change, vim.fn.bufname())
      settle()
      find("final")
    end,
  },
}
