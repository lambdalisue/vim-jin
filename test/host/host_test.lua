local h = dofile("test/host/helper.lua")
local host = require("jin.host")

local function run(argv, opts)
  local result
  host.run(argv, opts or {}, function(r)
    result = r
  end)
  h.truthy(
    host.wait(5000, function()
      return result ~= nil
    end),
    "the process did not finish"
  )
  return result
end

return {
  {
    "selects the implementation for the running editor",
    function()
      h.eq(vim.api and "nvim" or "vim", host.name)
    end,
  },
  {
    "run reports stdout, stderr and the exit code separately",
    function()
      local r = run({ "sh", "-c", "printf out; printf err >&2; exit 3" })
      h.eq({ code = 3, stdout = "out", stderr = "err" }, r)
    end,
  },
  {
    "run keeps output that spans several lines and chunks",
    function()
      local r = run({ "sh", "-c", "seq 1 20000" })
      h.eq(0, r.code)
      local lines = 0
      for _ in r.stdout:gmatch("[^\n]+\n") do
        lines = lines + 1
      end
      h.eq(20000, lines)
    end,
  },
  {
    "run starts the process in the given directory",
    function()
      local dir = h.tempdir()
      local r = run({ "pwd", "-P" }, { cwd = dir })
      h.eq(dir .. "\n", r.stdout)
    end,
  },
  {
    "run adds env to the environment the process inherits",
    function()
      vim.fn.setenv("JIN_INHERITED", "kept")
      local r = run({ "sh", "-c", 'printf \'%s %s\' "$JIN_ADDED" "$JIN_INHERITED"' }, {
        env = { JIN_ADDED = "added" },
      })
      h.eq("added kept", r.stdout)
    end,
  },
  {
    "run gives a process no stdin, so that reading it ends at once",
    function()
      h.eq({ code = 0, stdout = "", stderr = "" }, run({ "cat" }))
    end,
  },
  {
    "run reports a command that cannot start as a failure",
    function()
      local r = run({ "jin-no-such-command" })
      h.truthy(r.code ~= 0, "expected a non-zero code, got " .. tostring(r.code))
      h.truthy(r.stderr ~= "", "expected an error message")
    end,
  },
  {
    "run reports a directory that does not exist as a failure",
    function()
      local r = run({ "pwd" }, { cwd = h.tempdir() .. "/missing" })
      h.truthy(r.code ~= 0, "expected a non-zero code, got " .. tostring(r.code))
      h.truthy(r.stderr ~= "", "expected an error message")
    end,
  },
  {
    "run calls back where the editor can be used",
    function()
      local cwd
      run({ "true" })
      host.run({ "true" }, {}, function()
        cwd = vim.fn.getcwd()
      end)
      host.wait(5000, function()
        return cwd ~= nil
      end)
      h.eq(vim.fn.getcwd(), cwd)
    end,
  },
  {
    "wait gives up after the timeout",
    function()
      h.eq(
        false,
        host.wait(50, function()
          return false
        end)
      )
      h.eq(
        true,
        host.wait(50, function()
          return true
        end)
      )
    end,
  },
  {
    "is_dir tells directories from files",
    function()
      local dir = h.tempdir()
      local file = dir .. "/file"
      local f = assert(io.open(file, "w"))
      f:close()
      h.eq(true, host.is_dir(dir))
      h.eq(false, host.is_dir(file))
      h.eq(false, host.is_dir(dir .. "/missing"))
    end,
  },
  {
    "bufname and cwd report absolute paths",
    function()
      local dir = h.tempdir()
      h.ex("cd " .. vim.fn.fnameescape(dir))
      h.ex("edit file.txt")
      h.eq(dir, host.realpath(host.cwd()))
      h.eq(dir .. "/file.txt", host.realpath(host.bufname()))
      h.ex("enew!")
      h.eq("", host.bufname())
    end,
  },
  {
    "echo records every line in the message history",
    function()
      host.echo("jin-echo-first\njin-echo-second", "ErrorMsg")
      local messages = vim.fn.execute("messages")
      h.truthy(messages:find("jin-echo-first", 1, true), messages)
      h.truthy(messages:find("jin-echo-second", 1, true), messages)
    end,
  },
  {
    "doautocmd fires a defined User event and ignores an undefined one",
    function()
      h.ex("let g:jin_probe = 0")
      h.ex("autocmd User JinProbe let g:jin_probe += 1")
      host.doautocmd("JinProbe")
      host.doautocmd("JinUndefinedProbe")
      h.eq(1, vim.fn.eval("g:jin_probe"))
    end,
  },
  {
    "now measures the time that passes in milliseconds",
    function()
      local start = host.now()
      host.wait(100, function()
        return false
      end)
      local elapsed = host.now() - start
      h.truthy(elapsed >= 90 and elapsed < 2000, "elapsed " .. tostring(elapsed))
    end,
  },
  {
    "defer runs the function later unless cancelled",
    function()
      local fired, cancelled = false, false
      host.defer(10, function()
        fired = true
      end)
      local timer = host.defer(10, function()
        cancelled = true
      end)
      host.cancel(timer)
      host.wait(500, function()
        return fired
      end)
      host.wait(50, function()
        return false
      end)
      h.eq(true, fired)
      h.eq(false, cancelled)
    end,
  },
  {
    "keymaps leaves out a mapping to a Lua function, which has no right-hand side",
    function()
      h.ex("enew!")
      h.ex("nnoremap <buffer> zq <Plug>(jin-action-help)")
      if vim.api then
        vim.keymap.set("n", "zw", function() end, { buffer = true })
      end
      local found = {}
      for _, map in ipairs(host.keymaps()) do
        h.truthy(map.rhs, "a mapping without a right-hand side: " .. tostring(map.lhs))
        found[map.lhs] = map.rhs
      end
      h.eq("<Plug>(jin-action-help)", found.zq)
    end,
  },
  {
    "list turns an editor list into a Lua table",
    function()
      h.eq({ "a", "b" }, host.list(vim.fn.split("a b")))
    end,
  },
  {
    "to_list hands a Lua table back as an editor list",
    function()
      h.eq(2, vim.fn.len(host.to_list({ "a", "b" })))
      h.eq({ "a", "b" }, host.list(host.to_list({ "a", "b" })))
    end,
  },
}
