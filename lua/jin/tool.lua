-- The diff editor and merge tool vim-jin passes jj: shell one-liners that
-- tell the editor what to edit by a line on jj's standard error, then wait
-- for the answer on a named pipe and exit as it says
-- (docs/adr/20261018-hand-jjs-tools-to-the-running-editor-as-three-panes-answered-by-writing-the-list.md).

local M = {}

---A one-liner that writes `kind` and its arguments, the pipe first, as one
---line on stderr, then waits on the pipe. It goes in a TOML literal string,
---so it holds no single quote.
---@param kind string
---@param count integer how many arguments, the pipe included
---@return string
local function script(kind, count)
  local formats, args = {}, {}
  for i = 1, count do
    formats[i] = "\\037%s"
    args[i] = ('"$%d"'):format(i)
  end
  return ('printf "\\036%s%s\\n" %s >&2; read answer < "$1"; [ "$answer" = done ]'):format(
    kind,
    table.concat(formats),
    table.concat(args, " ")
  )
end

---The jj arguments that make it run vim-jin's diff editor, answering
---through the named pipe `fifo`; the user's own tools stay as they are.
---Asking for $output has jj hand it an output to fill beside the two sides,
---which jj starts as a copy of the right one and takes in its place.
---@param fifo string
---@return string[]
function M.args(fifo)
  local edit = ("merge-tools.jin.edit-args=['-c', '%s', 'jin', '%s', '$left', '$right', '$output']"):format(
    script("jin", 4),
    fifo
  )
  return { "--tool", "jin", "--config", 'merge-tools.jin.program="sh"', "--config", edit }
end

---The jj arguments that make it run vim-jin's merge tool, which edits the
---output jj fills with its conflict markers.
---@param fifo string
---@return string[]
function M.merge_args(fifo)
  local merge = ("merge-tools.jin.merge-args=['-c', '%s', 'jin', '%s', '$base', '$left', '$right', '$output']"):format(
    script("jin-merge", 5),
    fifo
  )
  return {
    "--tool",
    "jin",
    "--config",
    'merge-tools.jin.program="sh"',
    "--config",
    "merge-tools.jin.merge-tool-edits-conflict-markers=true",
    "--config",
    merge,
  }
end

---What a tool asks for, from a line of jj's standard error, or nil for a
---line of jj's own.
---@param line string
---@return { kind: "diff"|"merge", fifo: string, left: string, right: string, output: string, base?: string }?
function M.parse(line)
  local kind, rest = line:match("^\30(jin[%-%a]*)\31(.*)$")
  local fields = {}
  for field in ((rest or "") .. "\31"):gmatch("([^\31]*)\31") do
    fields[#fields + 1] = field
  end
  if kind == "jin" and #fields == 4 then
    return {
      kind = "diff",
      fifo = fields[1],
      left = fields[2],
      right = fields[3],
      output = fields[4],
    }
  elseif kind == "jin-merge" and #fields == 5 then
    return {
      kind = "merge",
      fifo = fields[1],
      base = fields[2],
      left = fields[3],
      right = fields[4],
      output = fields[5],
    }
  end
  return nil
end

return M
