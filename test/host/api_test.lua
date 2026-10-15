local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function workspace()
  local dir = h.tempdir()
  local r = jin.jj({ "git", "init" }, { cwd = dir })
  h.eq(0, r.code)
  return dir
end

return {
  {
    "jj returns what jj printed when called without a callback",
    function()
      local dir = workspace()
      local r = jin.jj({ "root" }, { cwd = dir })
      h.eq({ code = 0, stdout = dir .. "\n", stderr = "" }, r)
    end,
  },
  {
    "jj calls back with the result when given a callback",
    function()
      local dir = workspace()
      local got
      h.eq(
        nil,
        jin.jj({ "root" }, { cwd = dir }, function(r)
          got = r
        end)
      )
      host.wait(5000, function()
        return got ~= nil
      end)
      h.eq(dir .. "\n", got.stdout)
    end,
  },
  {
    "jj neither echoes nor fires JinCommandPost",
    function()
      local dir = workspace()
      h.ex("messages clear")
      h.ex("let g:jin_post = 0")
      h.ex("autocmd User JinCommandPost let g:jin_post += 1")
      jin.jj({ "new" }, { cwd = dir })
      host.wait(300, function()
        return false
      end)
      h.ex("autocmd! User JinCommandPost")
      h.eq(0, vim.fn.eval("g:jin_post"))
      h.truthy(not vim.fn.execute("messages"):find("Working copy", 1, true), "jj echoed")
    end,
  },
  {
    "command echoes, fires JinCommandPost and hands back the result",
    function()
      local dir = workspace()
      h.ex("messages clear")
      h.ex("let g:jin_post = 0")
      h.ex("autocmd User JinCommandPost let g:jin_post += 1")
      local got
      jin.command({ "new" }, { cwd = dir, wait = true }, function(r)
        got = r
      end)
      h.eq(0, got.code)
      h.truthy(vim.fn.execute("messages"):find("Working copy", 1, true), "nothing echoed")
      host.wait(2000, function()
        return vim.fn.eval("g:jin_post") == 1
      end)
      h.ex("autocmd! User JinCommandPost")
      h.eq(1, vim.fn.eval("g:jin_post"))
    end,
  },
  {
    "root finds the workspace of a path, and nil outside one",
    function()
      local dir = workspace()
      vim.fn.mkdir(dir .. "/sub", "p")
      h.eq(dir, jin.root(dir .. "/sub"))
      h.eq(nil, jin.root(h.tempdir()))
    end,
  },
}
