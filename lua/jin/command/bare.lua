local args = require("jin.args")
local jj = require("jin.jj")

local M = {}

local OPTIONS = { wait = true }

local POST_DELAY = 100

---One debounced JinCommandPost per host, so commands that finish close
---together refresh listeners once.
local posters = setmetatable({}, { __mode = "k" })

---@param host jin.Host
local function post(host)
  local poster = posters[host]
  if not poster then
    poster = {}
    posters[host] = poster
  end
  if poster.timer then
    host.cancel(poster.timer)
  end
  poster.timer = host.defer(POST_DELAY, function()
    poster.timer = nil
    host.doautocmd("JinCommandPost")
  end)
end

---@param result jin.RunResult
---@return string
local function output(result)
  local text = (result.stdout .. result.stderr):gsub("\n$", "")
  return text
end

---Per host, jj's recent completion answers keyed by workspace and preceding
---words. A finished command may have changed them, so it drops them all.
---@type table<jin.Host, table<string, { word: string, values: string[], time: number }>>
local caches = setmetatable({}, { __mode = "k" })

---@class jin.CommandOptions
---@field cwd? string a directory in the workspace to run in; by default the current buffer's or directory's
---@field wait? boolean return only after jj has finished

---Run jj with `argv` the way :Jin does: echo what it prints, then fire
---User JinCommandPost. `on_exit` receives the result after the echo.
---@param host jin.Host
---@param argv string[]
---@param opts jin.CommandOptions
---@param on_exit? fun(result: jin.RunResult)
function M.run(host, argv, opts, on_exit)
  local done = false
  jj.run(host, argv, { cwd = opts.cwd }, function(result)
    done = true
    caches[host] = nil
    local text = output(result)
    if text ~= "" then
      host.echo(text, result.code ~= 0 and "ErrorMsg" or nil)
    end
    post(host)
    if on_exit then
      on_exit(result)
    end
  end)

  if opts.wait then
    host.wait(jj.WAIT_FOREVER, function()
      return done
    end)
  end
end

---Run the arguments of `:Jin` as typed: split with shell-like quoting, then
---take the leading ++ options for vim-jin and the rest for jj.
---@param host jin.Host
---@param line string
function M.command(host, line)
  local opts, rest = args.parse(args.split(line, require("jin.expand").expander(host)))
  args.validate(opts, OPTIONS)
  M.run(host, rest, { wait = opts.wait == true })
end

-- Completion blocks the command line, so a jj that hangs must not.
local COMPLETE_TIMEOUT = 3000

---@param prefix string
---@return string[]
local function complete_options(prefix)
  local names = {}
  for name in pairs(OPTIONS) do
    local option = "++" .. name
    if option:sub(1, #prefix) == prefix then
      names[#names + 1] = option
    end
  end
  table.sort(names)
  return names
end

---Write the part of `value` that follows `from` as text that continues a
---word whose quote `open` is still open there, or that stands unquoted.
---@param value string
---@param from string
---@param open string?
---@return string?
local function continuation(value, from, open)
  if value:sub(1, #from) ~= from then
    return nil
  end
  local tail = value:sub(#from + 1)
  if not open then
    return args.escape(tail)
  end
  -- A directory stays open so that completion can go on inside it.
  local close = tail:sub(-1) == "/" and "" or open
  if open == '"' then
    return (tail:gsub('(["\\])', "\\%1")) .. close
  end
  return (tail:gsub("'", "'\\''")) .. close
end

-- Long enough to cover the Tabs of one command line, short enough that a
-- change made outside vim-jin shows up soon.
local CACHE_TTL = 5000

---jj filters candidates by prefix, so an answer stays valid while the word
---only grows by these. Anything else (`/`, `..`, `|`, `@`, ...) makes jj
---complete a different level or part, and needs a new answer.
local NARROWING = "^[%w_%-]*$"

---@param host jin.Host
---@param cwd string
---@param words string[] the words for jj, the last one being completed
---@return string[]?
local function query(host, cwd, words)
  local cmd = { "jj", "--", "jj" }
  for _, word in ipairs(words) do
    cmd[#cmd + 1] = word
  end
  local result
  host.run(cmd, { cwd = cwd, env = { COMPLETE = "fish" } }, function(r)
    result = r
  end)
  local answered = host.wait(COMPLETE_TIMEOUT, function()
    return result ~= nil
  end)
  if not answered or result.code ~= 0 then
    return nil
  end
  local values = {}
  for entry in result.stdout:gmatch("[^\n]+") do
    local value = entry:match("^[^\t]*")
    if value ~= "" then
      values[#values + 1] = value
    end
  end
  return values
end

---jj's candidates for the last of `words`, from the cache when it still
---holds them.
---@param host jin.Host
---@param cwd string
---@param words string[]
---@return string[]?
local function ask(host, cwd, words)
  local word = words[#words]
  local key = cwd .. "\0" .. table.concat(words, "\0", 1, #words - 1)
  local cache = caches[host] or {}
  caches[host] = cache
  local now = host.now()

  local hit = cache[key]
  if
    hit
    and now - hit.time < CACHE_TTL
    and word:sub(1, #hit.word) == hit.word
    and word:sub(#hit.word + 1):match(NARROWING)
  then
    local values = {}
    for _, value in ipairs(hit.values) do
      if value:sub(1, #word) == word then
        values[#values + 1] = value
      end
    end
    return values
  end

  local values = query(host, cwd, words)
  for k, entry in pairs(cache) do
    if now - entry.time >= CACHE_TTL then
      cache[k] = nil
    end
  end
  if values then
    cache[key] = { word = word, values = values, time = now }
  end
  return values
end

---Offer what jj's own completion offers for the word under the cursor.
---@param host jin.Host
---@param arglead string
---@param cmdline string
---@param cursorpos integer
---@return string[]
function M.complete(host, arglead, cmdline, cursorpos)
  local line = cmdline:sub(1, cursorpos)
  local words = args.split_partial(line)
  local typed = {}
  for i, word in ipairs(words) do
    if word == "Jin" or word == "Ji" then
      for j = i + 1, #words do
        typed[#typed + 1] = words[j]
      end
      break
    end
  end
  if #typed == 0 then
    return {}
  end

  -- The editor replaces only `arglead`, which ends the line but may start
  -- inside a quoted word. What the word holds before it stays as typed.
  local before, open = args.split_partial(line:sub(1, #line - #arglead))
  local kept = before[#before]

  local first = 1
  while first < #typed and typed[first]:match("^%+%+") do
    first = first + 1
  end
  if first == #typed and typed[first]:match("^%+") then
    return complete_options(typed[first])
  end

  local jj_words = {}
  for i = first, #typed do
    jj_words[#jj_words + 1] = typed[i]
  end
  local values = ask(host, jj.cwd(host), jj_words)
  if not values then
    return {}
  end

  local candidates = {}
  for _, value in ipairs(values) do
    local text = continuation(value, kept, open)
    if text then
      candidates[#candidates + 1] = text
    end
  end
  return candidates
end

return M
