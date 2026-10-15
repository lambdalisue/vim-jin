-- What plugin/jin.vim calls: hand the running editor's host to the core, and
-- show a failure as an error message rather than a traceback.

local host = require("jin.host")

local M = {}

---@param fn function
local function report(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    host.echo(tostring(err), "ErrorMsg")
  end
end

---@param line string the arguments of :Jin as typed
function M.jin(line)
  report(require("jin.command.bare").command, host, line)
end

---A failure offers nothing rather than interrupting the command line.
function M.complete(arglead, cmdline, cursorpos)
  local ok, candidates =
    pcall(require("jin.command.bare").complete, host, arglead, cmdline, cursorpos)
  return host.to_list(ok and candidates or {})
end

return M
