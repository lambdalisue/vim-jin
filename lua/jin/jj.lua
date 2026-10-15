local workspace = require("jin.workspace")

local M = {}

-- Effectively forever: the caller asked to block until jj finishes.
M.WAIT_FOREVER = 2 ^ 31 - 1

---@class jin.JjOptions
---@field cwd? string a directory in the workspace to run in; by default the current buffer's or directory's
---@field env? table<string, string> added to the environment jj inherits
---@field color? boolean ask jj for ANSI colors instead of plain text

---The directory `path` stands for: itself when it is a directory (such as a
---directory buffer), else the one it is in. Relative paths are taken from
---the current directory.
---@param host jin.Host
---@param path string
---@return string
local function directory_of(host, path)
  local absolute = workspace.absolute(path, host.cwd(), host.realpath)
  return host.is_dir(absolute) and absolute or workspace.dirname(absolute)
end

---The directories a workspace is looked for from, nearest first.
---@param host jin.Host
---@return string[]
local function candidates(host)
  local dirs = {}
  local bufname = host.bufname()
  -- A vim-jin buffer is no file; its name records the workspace it shows.
  local shown = bufname:find("^jin://") and require("jin.bufname").parse(bufname)
  if shown then
    dirs[#dirs + 1] = shown.root
  elseif bufname ~= "" then
    dirs[#dirs + 1] = directory_of(host, host.realpath(bufname))
    dirs[#dirs + 1] = directory_of(host, bufname)
  end
  dirs[#dirs + 1] = host.cwd()
  return dirs
end

---Return the root of the workspace that holds `path`, or of the current
---buffer or directory when `path` is nil.
---@param host jin.Host
---@param path? string
---@return string?
function M.root(host, path)
  if path == nil then
    return workspace.find(candidates(host), host.is_dir)
  end
  return workspace.find({ directory_of(host, path) }, host.is_dir)
end

---Return the directory jj should run in: the workspace root, or the given or
---current directory when it is in no workspace.
---@param host jin.Host
---@param cwd? string
---@return string
function M.cwd(host, cwd)
  if cwd then
    local given = cwd:sub(1, 1) == "/" and cwd or host.cwd() .. "/" .. cwd
    -- Not normalized: a directory that does not exist must make jj fail,
    -- not turn into an existing parent through a `..`.
    if not host.is_dir(given) then
      return given
    end
    return M.root(host, cwd) or given
  end
  return M.root(host) or host.cwd()
end

---Run jj with `argv`, without echoing or firing events. With `on_exit` it
---returns at once and calls it with the result; without, it waits and
---returns the result.
---@param host jin.Host
---@param argv string[]
---@param opts jin.JjOptions
---@param on_exit? fun(result: jin.RunResult)
---@return jin.RunResult?
function M.run(host, argv, opts, on_exit)
  -- Flags rather than --config: jj drops every --config before the
  -- subcommand once one follows it, as a view's own settings do.
  local cmd = { "jj", "--color", opts.color and "always" or "never", "--no-pager" }
  for _, a in ipairs(argv) do
    cmd[#cmd + 1] = a
  end

  local result
  host.run(cmd, { cwd = M.cwd(host, opts.cwd), env = opts.env }, function(r)
    result = r
    if on_exit then
      on_exit(r)
    end
  end)
  if on_exit then
    return nil
  end
  host.wait(M.WAIT_FOREVER, function()
    return result ~= nil
  end)
  return result
end

return M
