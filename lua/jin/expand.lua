-- What a bare % stands for in the arguments of vim-jin's commands: the file
-- of the current buffer, as jj (running at the workspace root) names it.

local jj = require("jin.jj")

local M = {}

---The file of the current buffer, relative to its workspace root.
---@param host jin.Host
---@return string
function M.path(host)
  local name = host.bufname()
  if name == "" then
    error("jin: % stands for no file, as the buffer has no name", 0)
  end
  local root = jj.root(host)
  if root then
    for _, path in ipairs({ name, host.realpath(name) }) do
      if path:sub(1, #root + 1) == root .. "/" then
        return path:sub(#root + 2)
      end
    end
  end
  return name
end

---A function that expands % for `host`, for args.split.
---@param host jin.Host
---@return fun(): string
function M.expander(host)
  return function()
    return M.path(host)
  end
end

return M
