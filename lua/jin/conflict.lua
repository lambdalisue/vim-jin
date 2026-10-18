-- The conflicts jj writes into a file with its markers, read back into the
-- sides and the bases they stand for. jj writes them in one of three styles
-- (ui.conflict-marker-style): "diff", a side as its diff from a base;
-- "snapshot", every side and base as it is; and "git", two sides and their
-- base as Git writes them.

local M = {}

---@class jin.Conflict
---@field first integer the line of the opening marker
---@field last integer the line of the closing marker
---@field sides string[][] what each side holds, in jj's order
---@field bases string[][] what each base holds, in jj's order

---The marker character and its run length when `line` is a marker line.
---jj lengthens its markers past seven when a line of the file looks like
---one, so a marker is a run of at least seven, and the opening one sets the
---length the rest of the conflict uses.
---@param line string
---@return string? char
---@return integer? length
local function marker(line)
  -- A CRLF file ends its marker lines with a carriage return as well.
  line = line:gsub("\r$", "")
  local char = line:sub(1, 1)
  if not char:match("[<>%%\\+%-|=]") then
    return nil
  end
  local run = line:match("^" .. (char:match("%W") and "%" or "") .. char .. "+")
  if #run < 7 then
    return nil
  end
  local rest = line:sub(#run + 1)
  if rest ~= "" and not rest:match("^ ") then
    return nil
  end
  return char, #run
end

---The conflicts of `lines` from line `from` on, appended to `found`, up to
---the end or to an opening marker that never ends, whose line it returns.
---@param lines string[]
---@param from integer
---@param found jin.Conflict[]
---@return integer? unclosed
local function scan(lines, from, found)
  local open, length, section
  local function start(kind, diff)
    section = { kind = kind, diff = diff, lines = {} }
    open.sections[#open.sections + 1] = section
  end
  for lnum = from, #lines do
    local line = lines[lnum]
    local char, run = marker(line)
    -- jj writes no line of a conflict that looks like its own markers, so an
    -- opening one of the same length starts another: the one open lost its
    -- end, as an edit may take it away.
    if not open or (char == "<" and run == length) then
      if char == "<" then
        open, length = { first = lnum, sections = {} }, run
        -- Git's style starts the first side right after the opening line;
        -- jj's own styles open a section of their own first.
        start("side")
      end
    elseif char and run == length and char ~= "<" then
      if char == ">" then
        local conflict = { first = open.first, last = lnum, sides = {}, bases = {} }
        for _, s in ipairs(open.sections) do
          if s.diff then
            local base, side = {}, {}
            for _, l in ipairs(s.lines) do
              local sign, text = l:sub(1, 1), l:sub(2)
              if sign ~= "+" then
                base[#base + 1] = text
              end
              if sign ~= "-" then
                side[#side + 1] = text
              end
            end
            conflict.bases[#conflict.bases + 1] = base
            conflict.sides[#conflict.sides + 1] = side
          elseif s.kind == "base" then
            conflict.bases[#conflict.bases + 1] = s.lines
          elseif s.kind == "side" and not s.opening then
            conflict.sides[#conflict.sides + 1] = s.lines
          end
        end
        found[#found + 1] = conflict
        open, section = nil, nil
      -- A "\" line is the second line of a "diff" section's heading.
      elseif char ~= "\\" then
        -- An empty side right after the opening line is no side: jj's own
        -- styles open their first section at once.
        local first = open.sections[1]
        if #open.sections == 1 and #first.lines == 0 and char ~= "|" and char ~= "=" then
          first.opening = true
        end
        if char == "%" then
          start("side", true)
        elseif char == "+" or char == "=" then
          start("side")
        elseif char == "-" or char == "|" then
          start("base")
        end
      end
    else
      table.insert(section.lines, line)
    end
  end
  return open and open.first
end

---Every conflict of `lines`, in order, the lines around them left out. A
---line that only looks like an opening marker, never ending, is read past:
---the conflicts after it are read from the line that follows it.
---@param lines string[]
---@return jin.Conflict[]
function M.parse(lines)
  local found = {}
  local from = 1 ---@type integer?
  while from do
    local unclosed = scan(lines, from, found)
    from = unclosed and unclosed + 1
  end
  return found
end

---The conflict of `conflicts` that holds line `lnum`, markers included.
---@param conflicts jin.Conflict[]
---@param lnum integer
---@return jin.Conflict?
function M.at(conflicts, lnum)
  for _, c in ipairs(conflicts) do
    if c.first <= lnum and lnum <= c.last then
      return c
    end
  end
  return nil
end

return M
