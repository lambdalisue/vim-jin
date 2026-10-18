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

---Open the view of a view command such as :JinLog.
---@param name string the Ex command
---@param line string its arguments as typed
---@param bang integer
---@param mods string
function M.view(name, line, bang, mods)
  report(require("jin.command.views").run, jin, host, name, line, { bang = bang == 1, mods = mods })
end

---Fill a jin:// buffer the editor is reading (BufReadCmd).
---@param bufnr integer
---@param name string
function M.read_buffer(bufnr, name)
  report(require("jin.view").read, jin, host, bufnr, name)
end

---Run the action `name` of `bufnr` on its lines `first`..`last`, as a key
---mapped to it asks.
---@param bufnr integer
---@param name string
---@param first integer
---@param last integer
function M.action(bufnr, name, first, last)
  report(require("jin.action").run, jin, host, bufnr, name, first, last, { key = true })
end

---Jump `count` blocks forward or back from the cursor of `bufnr`, as ]] and
---[[ do.
---@param bufnr integer
---@param forward integer 1 for forward, 0 for back
---@param count integer
function M.block(bufnr, forward, count)
  report(require("jin.view").move_block, host, bufnr, forward == 1, count)
end

---:JinCd, :JinLcd and :JinTcd.
---@param scope "cd"|"lcd"|"tcd"
function M.cd(scope)
  report(require("jin.command.cd").run, jin, host, scope)
end

---A statusline component. It never fails: any error gives "".
---@param name string
---@return string
function M.component(name)
  local ok, value = pcall(require("jin.component").get, jin, host, name)
  return ok and value or ""
end

---Refresh the components of the current workspace; with `force`, even when
---they were just refreshed.
---@param force integer
function M.touch_components(force)
  pcall(require("jin.component").touch, jin, host, force == 1)
end

---Free what is kept for a jin:// buffer being unloaded (BufUnload).
---@param bufnr integer
function M.forget_buffer(bufnr)
  require("jin.view").forget(host, bufnr)
end

---The statusline of the view in the window `winid` as a 'statusline' format, highlighted
---and told the workspace of when `active`, the window of the current
---buffer. It never fails: anything wrong gives the plain one.
---@param winid integer the window drawn
---@param active boolean
---@return string
function M.statusline(winid, active)
  local bufnr = vim.fn.winbufnr(winid)
  local ok, parts = pcall(
    require("jin.statusline").parts,
    host,
    bufnr,
    active and jin or nil,
    vim.fn.line(".", winid)
  )
  local glyph = require("jin.glyph")
  local glyphs_ok, glyphs = pcall(glyph.resolve, host)
  return require("jin.host.common").statusline(
    ok and parts or nil,
    active,
    glyphs_ok and glyphs or glyph.PRESETS[glyph.DEFAULT_PRESET]
  )
end

---Follow the cursor of a jin:// buffer (CursorMoved).
---@param bufnr integer
function M.cursor_moved(bufnr)
  report(require("jin.view").cursor_moved, host, bufnr)
  report(require("jin.view.detail").cursor_moved, jin, host, bufnr)
end

---Make the lines of a jin:// buffer shown in a window wrap after its
---annotation there, as wide as it was last read (BufWinEnter).
---@param bufnr integer
function M.buffer_shown(bufnr)
  report(require("jin.host.common").wrap_after_annotation, bufnr, host.list)
end

---Show the detail panel again in a jin:// buffer's window entered
---(BufEnter, WinEnter).
---@param bufnr integer
function M.detail_entered(bufnr)
  report(require("jin.view.detail").entered, jin, host, bufnr)
end

---Close the detail panel of a jin:// buffer whose window or buffer is left
---(WinLeave, BufLeave).
---@param bufnr integer
function M.detail_left(bufnr)
  report(require("jin.view.detail").close, host, bufnr)
end

---Forget whether the detail panel shows in the window `winid`, closed
---(WinClosed).
---@param winid integer
function M.window_closed(winid)
  report(require("jin.view.detail").window_closed, host, winid)
end

---Put the detail panels shown back in place (WinScrolled, VimResized).
function M.windows_scrolled()
  report(require("jin.view.detail").scrolled, jin, host)
end

---Read views again when jj changed the repository outside the editor: those
---of `bufnr`'s workspace (BufEnter of a jin:// buffer), or every one when
---`bufnr` is 0 (FocusGained). It runs unasked, so it never reports a failure.
---@param bufnr integer
function M.refresh_buffers(bufnr)
  pcall(require("jin.view").refresh, jin, host, bufnr ~= 0 and bufnr or nil)
end

---Hand what a jin:// buffer to edit holds back to jj (BufWriteCmd).
---@param bufnr integer
function M.write_buffer(bufnr)
  report(require("jin.view").write, jin, host, bufnr)
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

function M.complete_view(arglead, cmdline, cursorpos)
  local command = require("jin.command.views").find(cmdline)
  if not command then
    return host.to_list({})
  end
  return complete(arglead, cmdline, cursorpos, command)
end

return M
