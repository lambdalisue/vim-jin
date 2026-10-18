-- The short title of a view: the jj command it shows, with the full change
-- and commit IDs of its buffer name told by the shortest prefixes jj accepts.
-- The name keeps them in full, as a prefix unique today may not be once the
-- repository grows, and the name is read again.

local M = {}

local TEMPLATE = 'change_id ++ " " ++ change_id.shortest() ++ " "'
  .. ' ++ commit_id ++ " " ++ commit_id.shortest() ++ "\\n"'

---Whether `token` is a change or a commit ID in full, as jj prints them.
---@param token string
---@return boolean
local function is_id(token)
  return (#token == 32 and token:match("^[k-z]+$") ~= nil)
    or (#token == 40 and token:match("^[0-9a-f]+$") ~= nil)
end

---The full change and commit IDs in `argv`, each once, standing alone or
---within a revset. The paths after `--` are no IDs.
---@param argv string[]
---@return string[]
function M.ids(argv)
  local ids, seen = {}, {}
  for _, word in ipairs(argv) do
    if word == "--" then
      break
    end
    for token in word:gmatch("%w+") do
      if is_id(token) and not seen[token] then
        seen[token] = true
        ids[#ids + 1] = token
      end
    end
  end
  return ids
end

---The jj arguments that print the shortest prefixes of `ids`, at the
---operation `op` when given. An ID jj does not find is left out.
---@param ids string[]
---@param op? string
---@return string[]
function M.query(ids, op)
  local revsets = {}
  for i, id in ipairs(ids) do
    revsets[i] = "present(" .. id .. ")"
  end
  local argv = {}
  if op then
    argv = { "--at-op", op }
  end
  for _, word in ipairs({
    "--ignore-working-copy",
    "log",
    "--no-graph",
    "-r",
    table.concat(revsets, " | "),
    "-T",
    TEMPLATE,
  }) do
    argv[#argv + 1] = word
  end
  return argv
end

---The shortest prefix of each ID, from what the arguments of `query` print.
---@param stdout string
---@return table<string, string>
function M.parse(stdout)
  local short = {}
  for change, change_short, commit, commit_short in stdout:gmatch("(%w+) (%w+) (%w+) (%w+)\n") do
    short[change] = change_short
    short[commit] = commit_short
  end
  return short
end

---The title of a buffer showing `argv` after the jj words `command`, with
---the IDs `short` tells shortened to its prefixes. Other long IDs, such as
---those of operations, are cut to 12 characters, and words with spaces are
---quoted.
---@param command string[]
---@param argv string[]
---@param short? table<string, string>
---@return string
function M.format(command, argv, short)
  local words = { "jj" }
  local paths = false
  for _, list in ipairs({ command, argv }) do
    for _, word in ipairs(list) do
      if word == "--" and list == argv then
        paths = true
      elseif short and not paths then
        word = word:gsub("%w+", short)
      end
      if (word:match("^%x+$") or is_id(word)) and #word > 12 then
        word = word:sub(1, 12)
      elseif word:find("[%s'\"]") then
        word = "'" .. word:gsub("'", "'\\''") .. "'"
      end
      words[#words + 1] = word
    end
  end
  return table.concat(words, " ")
end

return M
