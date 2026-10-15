local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")

h.ex("source plugin/jin.vim")

-- Keep the tests away from the user's jj configuration.
local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  return dir
end

local lines = h.lines

return {
  {
    "opens jj's output in a read-only buffer named after it",
    function()
      local dir = workspace()
      h.ex("JinBuffer log --no-graph -r @ -T change_id")
      h.eq("jin://" .. dir .. "#log --no-graph -r @ -T change_id", vim.fn.bufname())
      h.eventually(function()
        local first = lines()[1]
        return first:match("^[k-z]+$") and #first == 32
      end, function()
        return "not a change id: " .. lines()[1]
      end)
      h.eq("jin-buffer", vim.eval and vim.eval("&filetype") or vim.bo.filetype)
      h.eq(0, vim.fn.getbufvar(vim.fn.bufnr(), "&modifiable"))
    end,
  },
  {
    "is no file buffer even to the autocommands of its first reading",
    function()
      workspace()
      h.ex("let g:jin_test_buftype = 'never entered'")
      h.ex("autocmd BufEnter jin://* ++once let g:jin_test_buftype = &buftype")
      h.ex("JinBuffer log")
      h.eq("nofile", vim.fn.eval("g:jin_test_buftype"))
    end,
  },
  {
    "shows jj's colors as highlights, and none with ++monochrome",
    function()
      workspace()
      h.ex("JinBuffer log -r @")
      h.eventually(function()
        return #h.highlights(vim.fn.bufnr()) > 0
      end, "no highlights")
      h.truthy(not lines()[1]:find("\27", 1, true), "escape left in the text")
      h.ex("JinBuffer ++monochrome log -r @")
      h.eventually(function()
        return lines()[1] ~= ""
      end, "nothing shown")
      h.eq({}, h.highlights(vim.fn.bufnr()))
    end,
  },
  {
    "reads jj again on :edit",
    function()
      workspace()
      h.ex("JinBuffer log --no-graph -r @ -T description")
      jin.jj({ "describe", "-m", "edited" })
      h.ex("edit")
      h.eventually(function()
        return lines()[1] == "edited"
      end, function()
        return "not read again: " .. lines()[1]
      end)
    end,
  },
  {
    "reads jj again with a bang",
    function()
      workspace()
      h.ex("JinBuffer log --no-graph -r @ -T description")
      jin.jj({ "describe", "-m", "banged" })
      h.ex("JinBuffer! log --no-graph -r @ -T description")
      h.eventually(function()
        return lines()[1] == "banged"
      end, function()
        return "not read again: " .. lines()[1]
      end)
    end,
  },
  {
    "refreshes after :Jin changes the repository",
    function()
      workspace()
      h.ex("JinBuffer log --no-graph -r @ -T description")
      local bufnr = vim.fn.bufnr()
      h.ex([[Jin ++wait describe -m "refreshed by jin"]])
      h.truthy(
        host.wait(3000, function()
          return host.list(vim.fn.getbufline(bufnr, 1))[1] == "refreshed by jin"
        end),
        "not refreshed: " .. tostring(host.list(vim.fn.getbufline(bufnr, 1))[1])
      )
    end,
  },
  {
    "makes :Jin run in the workspace the buffer shows, wherever the current directory is",
    function()
      local shown = workspace()
      h.ex("JinBuffer log")
      workspace()
      h.ex("messages clear")
      h.ex("Jin ++wait root")
      h.truthy(vim.fn.execute("messages"):find(shown, 1, true), vim.fn.execute("messages"))
    end,
  },
  {
    "shows what jj reported when it fails",
    function()
      workspace()
      h.ex("JinBuffer log -r no_such_revision")
      h.eventually(function()
        return table.concat(lines(), "\n"):find("no_such_revision", 1, true) ~= nil
      end, "no error shown")
    end,
  },
  {
    "opens from Lua with jin.buffer",
    function()
      local dir = workspace()
      h.ex("only")
      local bufnr = jin.buffer({ "root" }, { opener = "split" })
      h.eq(2, vim.fn.winnr("$"))
      h.eq(bufnr, vim.fn.bufnr())
      h.eventually(function()
        return lines()[1] == dir
      end, function()
        return "not the root: " .. lines()[1]
      end)
      h.ex("only")
    end,
  },
  {
    "completes its own ++ options and jj's arguments",
    function()
      workspace()
      local candidates = host.list(vim.fn.getcompletion("JinBuffer ++", "cmdline"))
      h.eq({ "++filetype=", "++monochrome", "++opener=" }, candidates)
      local sub = host.list(vim.fn.getcompletion("JinBuffer ++monochrome lo", "cmdline"))
      h.truthy(vim.fn.index(host.to_list(sub), "log") >= 0, "no log in completion")
    end,
  },
}
