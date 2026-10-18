-- The change and commit of the one revision a view shows the content of, as
-- its statusline tells them in place of the entry under the cursor.

local M = {}

local TEMPLATE = 'change_id ++ " " ++ change_id.shortest() ++ " "'
  .. ' ++ commit_id ++ " " ++ commit_id.shortest() ++ " "'
  .. ' ++ if(divergent, "divergent", "-") ++ "\\n"'

---@class jin.ShownRevision
---@field change string
---@field change_short string
---@field commit string
---@field commit_short string
---@field divergent boolean

---The jj arguments that print the change and commit of `rev`, at the
---operation `op`, or at the latest one, without a snapshot: a query run in
---the background must not race the read for the working copy. Two at most
---are printed, enough to tell a revset naming several.
---@param rev string
---@param op? string
---@return string[]
function M.query(rev, op)
  return {
    "--at-op",
    op or "@",
    "--ignore-working-copy",
    "log",
    "--no-graph",
    "--limit",
    "2",
    "-r",
    rev,
    "-T",
    TEMPLATE,
  }
end

---The revision the arguments of `query` print, or nil when they print none
---or several.
---@param stdout string
---@return jin.ShownRevision?
function M.parse(stdout)
  local found
  for line in stdout:gmatch("[^\n]+") do
    if found then
      return nil
    end
    local change, change_short, commit, commit_short, state =
      line:match("^(%w+) (%w+) (%w+) (%w+) (%S+)$")
    if not change then
      return nil
    end
    found = {
      change = change,
      change_short = change_short,
      commit = commit,
      commit_short = commit_short,
      divergent = state == "divergent",
    }
  end
  return found
end

return M
