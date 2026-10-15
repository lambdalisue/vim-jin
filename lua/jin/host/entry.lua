-- What plugin/jin.vim calls: hand the running editor's host and the public
-- API to the core, and show a failure as an error message rather than a
-- traceback.

local host = require("jin.host")
local jin = require("jin")

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

---@param line string the arguments of :JinBuffer as typed
---@param bang integer
---@param mods string
function M.jin_buffer(line, bang, mods)
  report(require("jin.command.buffer").command, jin, host, line, { bang = bang == 1, mods = mods })
end

---Fill a jin:// buffer the editor is reading (BufReadCmd).
---@param bufnr integer
---@param name string
function M.read_buffer(bufnr, name)
  report(require("jin.view").read, jin, host, bufnr, name)
end

---Free what is kept for a jin:// buffer being unloaded (BufUnload).
---@param bufnr integer
function M.forget_buffer(bufnr)
  require("jin.view").forget(host, bufnr)
end

---Refresh every loaded jin:// buffer (User JinCommandPost).
function M.reload_buffers()
  report(require("jin.view").reload, jin, host)
end

---A failure offers nothing rather than interrupting the command line.
---@param command? jin.CompletedCommand
local function complete(arglead, cmdline, cursorpos, command)
  local ok, candidates =
    pcall(require("jin.command.bare").complete, host, arglead, cmdline, cursorpos, command)
  return host.to_list(ok and candidates or {})
end

function M.complete(arglead, cmdline, cursorpos)
  return complete(arglead, cmdline, cursorpos)
end

function M.complete_buffer(arglead, cmdline, cursorpos)
  return complete(arglead, cmdline, cursorpos, require("jin.command.buffer").COMMAND)
end

return M
