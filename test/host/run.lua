-- Runs every test/host/*_test.lua inside the editor that loaded this file,
-- then quits that editor, with a non-zero status when any case failed.
--
-- busted cannot run here: Vim offers no way to load it as a test runner. A
-- test file returns a list of `{ name, fn }` cases; a case fails by raising
-- an error, or by leaving an editor error message behind.

local ex = vim.cmd or vim.command

local function out(line)
  io.write(line, "\n")
end

-- Each case starts from one empty buffer, so what a case left open (such as
-- a jin:// buffer, which decides the workspace) does not leak into the next.
local function run_case(fn)
  ex("silent! %bwipeout!")
  ex("let v:errmsg = ''")
  local cwd = vim.fn.getcwd()
  local passed, err = xpcall(fn, debug.traceback)
  ex("cd " .. vim.fn.fnameescape(cwd))
  if not passed then
    return false, err
  end
  local errmsg = vim.fn.eval("v:errmsg")
  if errmsg ~= "" then
    return false, "the editor reported: " .. errmsg
  end
  return true
end

local files = {}
for path in tostring(vim.fn.glob("test/host/*_test.lua")):gmatch("[^\n]+") do
  files[#files + 1] = path
end
table.sort(files)

local failures = 0
local total = 0
for _, path in ipairs(files) do
  local ok, cases = pcall(dofile, path)
  if not ok then
    failures = failures + 1
    out(("ERROR %s\n  %s"):format(path, tostring(cases)))
  else
    for _, case in ipairs(cases) do
      total = total + 1
      local passed, err = run_case(case[2])
      if passed then
        out(("ok    %s: %s"):format(path, case[1]))
      else
        failures = failures + 1
        out(("FAIL  %s: %s\n  %s"):format(path, case[1], tostring(err)))
      end
    end
  end
end

out(("%d cases, %d failures"):format(total, failures))
-- `cquit 0` rather than `qall!`: Vim in Ex mode exits non-zero after any
-- error message, including ones a case expected and checked.
ex(failures == 0 and "cquit 0" or "cquit 1")
