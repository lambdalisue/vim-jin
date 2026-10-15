local M = {}

---@param path string
---@return string
local function strip_trailing_slash(path)
  local stripped = path:gsub("/+$", "")
  if stripped == "" and path ~= "" then
    return "/"
  end
  return stripped
end

---@param segments string[]
---@return string
local function join(segments)
  return "/" .. table.concat(segments, "/")
end

---Return `path` as an absolute path without `.` or `..` segments, taking a
---relative one from the absolute directory `base`. `..` leaves the directory
---the path has reached after `resolve`, which resolves symlinks, so a `..`
---after a symlink goes to the parent of where the link points, as the
---filesystem does.
---@param path string
---@param base string
---@param resolve? fun(path: string): string
---@return string
function M.absolute(path, base, resolve)
  if path:sub(1, 1) ~= "/" then
    path = base .. "/" .. path
  end
  local segments = {}
  for segment in path:gmatch("[^/]+") do
    if segment == ".." then
      if resolve and #segments > 0 then
        local resolved = resolve(join(segments))
        segments = {}
        for s in resolved:gmatch("[^/]+") do
          segments[#segments + 1] = s
        end
      end
      segments[#segments] = nil
    elseif segment ~= "." then
      segments[#segments + 1] = segment
    end
  end
  return join(segments)
end

---Return the parent directory of `path`, or "" for an empty path.
---@param path string
---@return string
function M.dirname(path)
  if path == "" then
    return ""
  end
  local parent = strip_trailing_slash(path):match("^(.*)/[^/]*$")
  if parent == nil or parent == "" then
    return "/"
  end
  return parent
end

---Return the nearest directory, `start` or above, that holds `.jj`.
---@param start string an absolute directory
---@param is_dir fun(path: string): boolean
---@return string?
function M.find_root(start, is_dir)
  local dir = strip_trailing_slash(start)
  while true do
    local marker = dir == "/" and "/.jj" or dir .. "/.jj"
    if is_dir(marker) then
      return dir
    end
    if dir == "/" then
      return nil
    end
    dir = M.dirname(dir)
  end
end

---Return the workspace root of the first candidate directory inside one.
---@param candidates string[] absolute directories; empty strings are skipped
---@param is_dir fun(path: string): boolean
---@return string?
function M.find(candidates, is_dir)
  for _, dir in ipairs(candidates) do
    if dir ~= "" then
      local root = M.find_root(dir, is_dir)
      if root then
        return root
      end
    end
  end
  return nil
end

return M
