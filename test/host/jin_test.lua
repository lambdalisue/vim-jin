local h = dofile("test/host/helper.lua")
local host = require("jin.host")

h.ex("source plugin/jin.vim")

-- Keep the tests away from the user's jj configuration.
local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function messages()
  return vim.fn.execute("messages")
end

local function workspace()
  local dir = h.tempdir()
  h.ex("cd " .. vim.fn.fnameescape(dir))
  h.ex("Jin ++wait git init")
  h.truthy(host.is_dir(dir .. "/.jj"), "jj git init did not create a workspace: " .. messages())
  return dir
end

return {
  {
    "runs jj in the workspace of the current buffer and echoes its output",
    function()
      local a = workspace()
      workspace()
      h.ex("edit " .. vim.fn.fnameescape(a .. "/file.txt"))
      h.ex("messages clear")
      h.ex("Jin ++wait root")
      h.truthy(messages():find(a, 1, true), "expected " .. a .. " in: " .. messages())
      h.ex("enew!")
    end,
  },
  {
    "passes | through to jj as part of a revset",
    function()
      workspace()
      h.ex("messages clear")
      h.ex("Jin ++wait log --no-graph -r root()|@ -T change_id")
      -- Vim prefixes :messages with a "Messages maintainer" line.
      local last = messages():match("([^\n]*)%s*$")
      h.truthy(last:match("^[k-z]+$") and #last == 64, "expected two change ids, got: " .. last)
    end,
  },
  {
    "passes a quoted argument with spaces to jj as one argument",
    function()
      workspace()
      h.ex([[Jin ++wait describe -m "feat: add 'parser'"]])
      h.ex("messages clear")
      h.ex("Jin ++wait log --no-graph -r @ -T description")
      h.truthy(messages():find("feat: add 'parser'", 1, true), messages())
    end,
  },
  {
    "completes a path inside an open quote and closes the quote",
    function()
      local dir = workspace()
      assert(io.open(dir .. "/my file.txt", "w")):close()
      h.ex("Jin ++wait status")
      h.eq({ 'file.txt"' }, host.list(vim.fn.getcompletion('Jin file show "my f', "cmdline")))
    end,
  },
  {
    "fires User JinCommandPost after jj finishes",
    function()
      h.ex("let g:jin_post = 0")
      h.ex("autocmd User JinCommandPost let g:jin_post += 1")
      h.ex("Jin version")
      h.truthy(
        host.wait(5000, function()
          return vim.fn.eval("g:jin_post") == 1
        end),
        "JinCommandPost did not fire"
      )
      h.ex("autocmd! User JinCommandPost")
    end,
  },
  {
    "completes subcommands, flags and revisions from jj",
    function()
      workspace()
      local function candidates(cmdline)
        return host.list(vim.fn.getcompletion(cmdline, "cmdline"))
      end
      local function has(list, item)
        for _, v in ipairs(list) do
          if v == item then
            return true
          end
        end
        return false
      end
      local sub = candidates("Jin lo")
      h.truthy(has(sub, "log"), "no log in: " .. table.concat(sub, " "))
      local flags = candidates("Jin log --no-g")
      h.eq({ "--no-graph" }, flags)
      local revs = candidates("Jin log -r ")
      -- The root change's ID is all z; its shortest unique prefix is a run of
      -- z as long as other change IDs make it.
      local root = false
      for _, rev in ipairs(revs) do
        root = root or rev:match("^z+$") ~= nil
      end
      h.truthy(root, "no root change in: " .. table.concat(revs, " "))
      h.eq({ "++wait" }, candidates("Jin ++w"))
    end,
  },
  {
    "shows an unknown ++ option as an error instead of running jj",
    function()
      h.ex("messages clear")
      h.ex("Jin ++nope version")
      h.truthy(messages():find("jin: unknown option ++nope", 1, true), messages())
    end,
  },
}
