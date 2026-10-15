-- :JinCd, :JinLcd and :JinTcd: go to the root of the current workspace.

local M = {}

---@param jin jin.Api
---@param host jin.Host
---@param scope "cd"|"lcd"|"tcd"
function M.run(jin, host, scope)
  local root = jin.root()
  if not root then
    error("jin: not in a jj workspace", 0)
  end
  host.cd(scope, root)
end

return M
