local jj = require("jin.jj")

local M = {}

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

---@class jin.CommandOptions
---@field cwd? string a directory in the workspace to run in; by default the current buffer's or directory's
---@field wait? boolean return only after jj has finished

---Run jj with `argv`, echo what it prints, then fire User JinCommandPost.
---`on_exit` receives the result after the echo.
---@param host jin.Host
---@param argv string[]
---@param opts jin.CommandOptions
---@param on_exit? fun(result: jin.RunResult)
function M.run(host, argv, opts, on_exit)
  local done = false
  jj.run(host, argv, { cwd = opts.cwd }, function(result)
    done = true
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

return M
