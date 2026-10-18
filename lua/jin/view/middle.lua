-- The pane in the middle of the three a diff editor or a merge tool session
-- opens for a file: what jj takes of it, in a buffer to edit between its two
-- sides. :w writes it back for jj to take once the list is written, and
-- shows the list again. Its do keys get a hunk from a side, or both sides,
-- as Vim's do gets one from the other buffer of a diff, and dp in a side
-- puts one into it. Hunks are found here rather than taken from Vim's diff,
-- which with three buffers, and 'diffopt' matching lines across them, can
-- leave a hunk with nothing on one side.

local action = require("jin.action")
local conflict = require("jin.conflict")
local diffedit = require("jin.diffedit")
local hunk = require("jin.hunk")

---@param host jin.Host
---@param parsed jin.Bufname
---@return jin.DiffEdit
local function session_of(host, parsed)
  local session = diffedit.get(host, tonumber(parsed.argv[1]))
  if not session then
    error("jin: this edit has been answered already", 0)
  end
  return session
end

---The file of the pane `parsed` names: the result of a merge, or the file
---of the output its path names, as long as it lies inside.
---@param session jin.DiffEdit
---@param parsed jin.Bufname
---@return string? output
---@return string? left
---@return string? right
local function files_of(session, parsed)
  if session.kind == "merge" then
    return session.output, session.left, session.right
  end
  local path = parsed.argv[2] or ""
  if not diffedit.inside(path) then
    return nil
  end
  return session.output .. "/" .. path, session.left .. "/" .. path, session.right .. "/" .. path
end

---The lines of `text`, a final newline ending the last rather than
---starting another.
---@param text string
---@return string[]
local function split(text)
  local lines = {}
  for line in text:gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  local rest = text:match("[^\n]*$")
  if rest ~= "" then
    lines[#lines + 1] = rest
  end
  return lines
end

---Put `lines` in place of the hunk or the conflict `first`..`last`.
---@param ctx jin.ActionContext
---@param first integer
---@param last integer
---@param ... string[]
local function put(ctx, first, last, ...)
  local lines = {}
  for _, list in ipairs({ ... }) do
    for _, line in ipairs(list) do
      lines[#lines + 1] = line
    end
  end
  ctx.host.replace_lines(ctx.bufnr, first, last, lines)
end

---Take `which` of the conflict of the line, when the pane holds one there:
---"left", "right", "base", or "all" or "all-reversed" for both sides.
---@param ctx jin.ActionContext
---@param which string
---@return boolean taken
local function take_conflict(ctx, which)
  if session_of(ctx.host, ctx.meta.parsed).kind ~= "merge" then
    return false
  end
  local found = conflict.at(conflict.parse(ctx.host.lines(ctx.bufnr)), ctx.first)
  if not found then
    return false
  end
  local left, right = found.sides[1] or {}, found.sides[2] or {}
  if which == "left" then
    put(ctx, found.first, found.last, left)
  elseif which == "right" then
    put(ctx, found.first, found.last, right)
  elseif which == "base" then
    put(ctx, found.first, found.last, found.bases[1] or {})
  elseif which == "all" then
    put(ctx, found.first, found.last, left, right)
  else
    put(ctx, found.first, found.last, right, left)
  end
  return true
end

---Take both sides of the hunk of the line, `reversed` the right first.
---@param ctx jin.ActionContext
---@param reversed boolean
local function take_both(ctx, reversed)
  local session = session_of(ctx.host, ctx.meta.parsed)
  local _, left_path, right_path = files_of(session, ctx.meta.parsed)
  local left = split(left_path and ctx.host.read_file(left_path) or "")
  local right = split(right_path and ctx.host.read_file(right_path) or "")
  local found = hunk.at(left, ctx.host.lines(ctx.bufnr), right, ctx.first)
  if not found then
    action.nothing(ctx, "jin: no hunk on this line")
    return
  end
  local first, last = found.result[1], found.result[2]
  if reversed then
    put(ctx, first, last, found.right, found.left)
  else
    put(ctx, first, last, found.left, found.right)
  end
end

---The lines of the file of `side` of the pane `parsed` names.
---@param host jin.Host
---@param parsed jin.Bufname
---@param side "left"|"right"
---@return string[]
local function side_lines(host, parsed, side)
  local _, left_path, right_path = files_of(session_of(host, parsed), parsed)
  local path = side == "left" and left_path or right_path
  return split(path and host.read_file(path) or "")
end

---Put in the pane `bufnr` what `side` has in place of each of `hunks`, the
---lower first so that the lines of the upper stay where they are; in a
---merge, a hunk within a conflict takes that side of the whole conflict.
---@param host jin.Host
---@param bufnr integer
---@param parsed jin.Bufname
---@param side "left"|"right"
---@param hunks { result: { [1]: integer, [2]: integer }, lines: string[] }[]
local function put_hunks(host, bufnr, parsed, side, hunks)
  local conflicts = session_of(host, parsed).kind == "merge" and conflict.parse(host.lines(bufnr))
    or {}
  local done = {}
  for i = #hunks, 1, -1 do
    local h = hunks[i]
    local within
    for _, c in ipairs(conflicts) do
      if c.first <= math.max(h.result[1], h.result[2]) and h.result[1] <= c.last then
        within = c
      end
    end
    if within and not done[within] then
      done[within] = true
      host.replace_lines(
        bufnr,
        within.first,
        within.last,
        within.sides[side == "left" and 1 or 2] or {}
      )
    elseif not within then
      host.replace_lines(bufnr, h.result[1], h.result[2], h.lines)
    end
  end
end

---Get the hunks of the lines acted on from the pane of one side, as
---:diffget does.
---@param ctx jin.ActionContext
---@param side "left"|"right"
local function get_side(ctx, side)
  local lines = side_lines(ctx.host, ctx.meta.parsed, side)
  local hunks = hunk.select(ctx.host.lines(ctx.bufnr), lines, ctx.first, ctx.last)
  if #hunks == 0 then
    action.nothing(ctx, "jin: no hunk on this line")
  end
  put_hunks(ctx.host, ctx.bufnr, ctx.meta.parsed, side, hunks)
end

local M = {}

---Put the hunk at line `lnum` of the pane of `side` into the middle pane
---`bufnr`, as :diffput does from there; nothing where there is none.
---@param host jin.Host
---@param bufnr integer
---@param side "left"|"right"
---@param lnum integer
function M.put(host, bufnr, side, lnum)
  local meta = require("jin.view").meta(host, bufnr)
  if not meta then
    error("jin: the pane to put into is gone", 0)
  end
  local lines = side_lines(host, meta.parsed, side)
  put_hunks(host, bufnr, meta.parsed, side, hunk.select(host.lines(bufnr), lines, lnum, lnum, true))
end

---@param kind "merge"|"result" the pane of the merge tool, or of the diff editor
---@return jin.View
function M.new(kind)
  local merge = kind == "merge"
  local actions = {
    ["diffget-l"] = {
      desc = merge and "take the left side of the conflict or the hunk of the line"
        or "take BEFORE's side of the hunk of the line",
      fn = function(ctx)
        if not take_conflict(ctx, "left") then
          get_side(ctx, "left")
        end
      end,
    },
    ["diffget-r"] = {
      desc = merge and "take the right side of the conflict or the hunk of the line"
        or "take AFTER's side of the hunk of the line",
      fn = function(ctx)
        if not take_conflict(ctx, "right") then
          get_side(ctx, "right")
        end
      end,
    },
  }
  for name, reversed in pairs({ ["diffget-all"] = false, ["diffget-all-reversed"] = true }) do
    local order = merge and (reversed and "the right side first" or "the left side first")
      or (reversed and "AFTER first" or "BEFORE first")
    actions[name] = {
      desc = ("take both sides of the %s of the line, %s"):format(
        merge and "conflict or the hunk" or "hunk",
        order
      ),
      fn = function(ctx)
        if not take_conflict(ctx, reversed and "all-reversed" or "all") then
          take_both(ctx, reversed)
        end
      end,
    }
  end
  actions.diffget = { desc = actions["diffget-all"].desc, fn = actions["diffget-all"].fn }
  local keys = {
    { "do", "diffget" },
    { "dol", "diffget-l" },
    { "dor", "diffget-r" },
  }
  if merge then
    actions["diffget-base"] = {
      desc = "take the base the sides of the conflict of the line started from",
      fn = function(ctx)
        if not take_conflict(ctx, "base") then
          action.nothing(ctx, "jin: no conflict on this line")
        end
      end,
    }
    keys[#keys + 1] = { "dob", "diffget-base" }
  end
  keys[#keys + 1] = { "doa", "diffget-all" }
  keys[#keys + 1] = { "doA", "diffget-all-reversed" }

  ---@type jin.View
  return {
    title = { kind },
    filetype = "jin-" .. kind,
    editable = true,
    source = function(host, parsed)
      local output = files_of(session_of(host, parsed), parsed)
      return output and host.read_file(output) or ""
    end,
    ---The file the pane stands for, as the list names it.
    detect = function(meta)
      return meta.parsed.argv[2]
    end,
    ---Write the buffer to the file jj takes, ending it with a newline only
    ---when the file had one, and an emptied buffer as an empty file, or as
    ---none when the change has none there either; then show the list again,
    ---the file edited.
    write = function(jin, host, bufnr, parsed)
      local session = session_of(host, parsed)
      local output, _, right = files_of(session, parsed)
      if not output then
        error(("jin: %s is no path inside the diff"):format(parsed.argv[2] or ""), 0)
      end
      local lines = host.lines(bufnr)
      local before = host.read_file(output)
      right = right or output
      if #lines == 0 and not merge and not host.read_file(right) and not host.link(right) then
        host.delete_file(output)
      else
        local text = ""
        if #lines > 0 then
          before = before or ""
          if before == "" or before:sub(-1) == "\n" then
            text = table.concat(lines, "\n") .. "\n"
          else
            -- jj ends every side with a newline to set the markers apart; in
            -- a CRLF file without a final newline, the carriage return
            -- before it is jj's as well.
            lines[#lines] = lines[#lines]:gsub("\r$", "")
            text = table.concat(lines, "\n")
          end
        end
        host.write_file(output, text)
      end
      host.mark_saved(bufnr)
      local view = require("jin.view")
      local name = view.name(
        jin,
        host,
        "diffedit",
        { tostring(session.id) },
        { cwd = session.root }
      )
      local list
      for _, buf in ipairs(host.buffers()) do
        if buf.name == name then
          list = buf.bufnr
          view.read(jin, host, list, name)
        end
      end
      -- Not from within :w, which the window is still writing for.
      host.defer(0, function()
        if host.buffer_name(bufnr) then
          host.close_tab(bufnr, list)
        end
      end)
    end,
    actions = actions,
    -- The keys of Vim's diff mode, telling which side do gets from, as a
    -- third buffer leaves Vim's own do without one.
    keys = keys,
  }
end

return M
