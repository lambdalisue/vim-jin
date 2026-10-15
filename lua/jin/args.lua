local M = {}

---Split the leading `++name` / `++name=value` options from the arguments
---that follow them.
---@param argv string[]
---@return table<string, string|true> opts
---@return string[] rest
function M.parse(argv)
  local opts = {}
  local i = 1
  while i <= #argv do
    local name, value = argv[i]:match("^%+%+([^=]+)=(.*)$")
    if name then
      opts[name] = value
    else
      name = argv[i]:match("^%+%+([^=]+)$")
      if not name then
        break
      end
      opts[name] = true
    end
    i = i + 1
  end
  local rest = {}
  for j = i, #argv do
    rest[#rest + 1] = argv[j]
  end
  return opts, rest
end

---@param line string
---@return string[] words
---@return string? word the word still being read when the line ended
---@return string? open the quote left open, if any
---@return table<integer, true> plain the indices of `words` written without quotes or backslashes
---@return boolean word_plain whether `word` was written without them
local function tokenize(line)
  local words, plain = {}, {}
  local word = nil
  local literal = false
  local quote = nil
  local i = 1
  while i <= #line do
    local c = line:sub(i, i)
    local next_c = line:sub(i + 1, i + 1)
    if quote == "'" then
      if c == "'" then
        quote = nil
      else
        word = word .. c
      end
    elseif quote == '"' then
      if c == '"' then
        quote = nil
      elseif c == "\\" and (next_c == '"' or next_c == "\\") then
        word = word .. next_c
        i = i + 1
      else
        word = word .. c
      end
    elseif c == "'" or c == '"' then
      quote = c
      word = word or ""
      literal = true
    elseif c == "\\" and next_c ~= "" then
      word = (word or "") .. next_c
      literal = true
      i = i + 1
    elseif c:match("^%s$") then
      if word then
        words[#words + 1] = word
        if not literal then
          plain[#words] = true
        end
        word = nil
        literal = false
      end
    else
      word = (word or "") .. c
    end
    i = i + 1
  end
  return words, word, quote, plain, not literal
end

---Split a command line into arguments the way a POSIX shell does: white
---space separates them, single quotes keep everything literally, double
---quotes keep everything but a backslash-escaped `"` or `\`, and outside
---quotes a backslash escapes the next character.
---
---A bare `%`, written without quotes or a backslash, is replaced by what
---`expand` returns, when given.
---@param line string
---@param expand? fun(): string
---@return string[]
function M.split(line, expand)
  local words, word, open, plain, word_plain = tokenize(line)
  if open then
    error("jin: unterminated quote", 0)
  end
  if word then
    words[#words + 1] = word
    if word_plain then
      plain[#words] = true
    end
  end
  if expand then
    for i, w in ipairs(words) do
      if w == "%" and plain[i] then
        words[i] = expand()
      end
    end
  end
  return words
end

---Split a line that is still being typed. The last word is the one under
---the cursor: empty after trailing white space, and possibly inside a quote
---that is still open.
---@param line string
---@return string[] words
---@return string? open the quote left open, if any
function M.split_partial(line)
  local words, word, open = tokenize(line)
  words[#words + 1] = word or ""
  return words, open
end

---Escape `arg` so that `split` turns it back into one argument.
---@param arg string
---@return string
function M.escape(arg)
  if arg == "" then
    return "''"
  end
  local escaped = arg:gsub("([%s\\'\"])", "\\%1")
  return escaped
end

---Raise an error for the first option not in `known`.
---@param opts table<string, string|true>
---@param known table<string, true>
function M.validate(opts, known)
  local names = {}
  for name in pairs(opts) do
    names[#names + 1] = name
  end
  table.sort(names)
  for _, name in ipairs(names) do
    if not known[name] then
      error("jin: unknown option ++" .. name, 0)
    end
  end
end

return M
