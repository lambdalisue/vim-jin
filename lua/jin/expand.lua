-- What a bare % stands for in the arguments of vim-jin's commands: the file
-- of the current buffer, as jj (running at the workspace root) names it.

local args = require("jin.args")
local bufname = require("jin.bufname")
local jj = require("jin.jj")

local M = {}

---The options of `jj file show` that take a value.
local VALUED = { ["-T"] = "template", ["--template"] = "template" }
for spelling, name in pairs(args.REVISIONS) do
  VALUED[spelling] = name
end

---The path a `jj file show` argument list names: its last argument that is
---neither an option nor an option's value, or the last one after `--`.
---@param argv string[]
---@return string?
function M.file_path(argv)
  local items, rest = args.options(argv, VALUED)
  local path = rest[2] and rest[#rest]
  if not path then
    for _, item in ipairs(items) do
      local a = item.words[1]
      if not item.name and not a:match("^%-") then
        path = a
      end
    end
  end
  -- A path written as a fileset string, file:"...", names the path inside.
  local quoted = path and path:match('^file:"(.*)"$')
  if quoted then
    path = quoted:gsub("\\(.)", "%1")
  end
  return path
end

---The file of the current buffer, relative to its workspace root. A file
---view (jin://...;view=file) stands for the file it shows.
---@param host jin.Host
---@return string
function M.path(host)
  local name = host.bufname()
  if name:find("^jin://") then
    local parsed = bufname.parse(name)
    local path = parsed and parsed.params.view == "file" and M.file_path(parsed.argv)
    if not path then
      error("jin: % stands for no file in this buffer", 0)
    end
    return path
  end
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
