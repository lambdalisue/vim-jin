local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  h.eq(0, jin.jj({ "describe", "-m", "before" }).code)
  return dir
end

local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  return view.meta(host, bufnr)
end

local function option(name)
  return vim.fn.getbufvar(vim.fn.bufnr(), "&" .. name)
end

local function description()
  return jin.jj({ "log", "--no-graph", "-r", "@", "-T", "description" }).stdout
end

return {
  {
    "describe opens jj's draft of the change to edit, and :w hands it to jj",
    function()
      local dir = workspace()
      h.ex("JinLog -r @")
      settle()
      require("jin.host.entry").action(vim.fn.bufnr(), "describe", 1, 1)
      h.truthy(vim.fn.bufname():find(";view=describe#-r ", 1, true), vim.fn.bufname())
      settle()
      h.eq("before", vim.fn.getline(1))
      h.truthy(vim.fn.search("^JJ: ", "nw") > 0, "no JJ: line in the draft")
      h.eq({ "acwrite", 1, 0, "jjdescription" }, {
        option("buftype"),
        option("modifiable"),
        option("modified"),
        option("filetype"),
      })
      vim.fn.setline(1, "after")
      h.eq(1, option("modified"))
      h.ex("write")
      h.eventually(function()
        return description() == "after\n"
      end, function()
        return "jj has: " .. description()
      end)
      h.eventually(function()
        return option("modified") == 0
      end, "the buffer stays modified")
      h.eq(dir, jin.root())
    end,
  },
}
