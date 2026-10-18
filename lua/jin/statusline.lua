-- What the statusline of a vim-jin view shows, as parts the host lays out:
-- the view, the operation it stays at, how many changes are selected, what
-- the line under the cursor stands for and what that is about, or the file
-- a file view shows and its revision, and the state of the workspace.

local view = require("jin.view")
local selection = require("jin.selection")
local support = require("jin.view.support")

local M = {}

---What the entry `entry` of a view whose markers carry `fields` stands for,
---in a few characters: a change and its commit, an operation, a bookmark or
---a workspace, and which of them it is.
---@param fields string[]
---@param entry string[]
---@return string?
---@return jin.StatuslineKind?
local function name_of(fields, entry)
  local first = fields[1]
  if first == "change_id" or first == "commit.change_id()" then
    return entry[1]:sub(1, 8) .. " " .. entry[2]:sub(1, 8), "change"
  elseif first == "self.id()" then
    return entry[1]:sub(1, 12), "operation"
  elseif first == "name" then
    -- A bookmark names its remote second; a workspace has no remote.
    if fields[2] ~= "if(remote, remote)" then
      return entry[1], "workspace"
    end
    local remote = entry[2]
    return remote and remote ~= "" and (entry[1] .. "@" .. remote) or entry[1], "bookmark"
  end
  return nil
end

---How many characters of the change and the commit `name_of` shows jj
---highlights, from the shortest prefixes the markers carry from `short` on.
---@param short? integer
---@param entry string[]
---@return integer[]?
local function prefixes_of(short, entry)
  local change, commit = short and entry[short], short and entry[short + 1]
  if not (change and commit) then
    return nil
  end
  return { math.min(#change, 8), math.min(#commit, 8) }
end

---Whether the change of `entry` is divergent, as the third of the markers
---says when the view prints the change, its commit and that.
---@param fields string[]
---@param entry string[]
---@return true?
local function divergent_of(fields, entry)
  if not (fields[3] and fields[3]:find('"divergent"', 1, true)) then
    return nil
  end
  return entry[3] == "divergent" or nil
end

---@class jin.StatuslineAbout
---@field what? string the first line of the description
---@field who? string the author, or the user of an operation without its host
---@field when? string how long ago, as "2 days ago"

---@class jin.StatuslineHere
---@field root string the name of the workspace's directory
---@field change string the working-copy change, as jin.component tells
---@field state string
---@field bookmarks string
---@field traffic string

---@alias jin.StatuslineKind "change"|"operation"|"bookmark"|"workspace"

---@class jin.StatuslineParts
---@field view string
---@field editable boolean a buffer to edit and hand back to jj
---@field at_op? string the operation the view stays at, cut to 12 characters
---@field selected integer the changes selected in its workspace
---@field file? string the path of the file the view shows at its one revision
---@field entry? string what the line under the cursor stands for, or the change and commit of that revision
---@field kind? jin.StatuslineKind what `entry` names
---@field prefixes? integer[] for a change and its commit, how many leading characters of each word of `entry` jj highlights
---@field divergent? boolean the change of `entry` is divergent, its prefix shown in red by jj
---@field about? jin.StatuslineAbout what that is about
---@field here? jin.StatuslineHere the workspace, when asked for with `jin`

---@param def jin.View
---@param entry string[]
---@return jin.StatuslineAbout?
local function about_of(def, entry)
  local first = def.template and def.template.about
  if not first then
    return nil
  end
  local what, who, when = entry[first], entry[first + 1], entry[first + 2]
  if not (what or who or when) then
    return nil
  end
  return { what = what, who = who and who:match("^[^@]*"), when = when }
end

---The parts of the statusline of `bufnr`, or nil when it is no view, or one
---not read yet. With `jin`, the state of the workspace of the current
---buffer, which a statusline reads without running jj, is told as well.
---`lnum` is the cursor's line in the window drawn, which may not be the one
---the host takes for the buffer when several show it.
---@param host jin.Host
---@param bufnr integer
---@param jin? jin.Api
---@param lnum? integer
---@return jin.StatuslineParts?
function M.parts(host, bufnr, jin, lnum)
  local meta = view.meta(host, bufnr)
  if not meta then
    return nil
  end
  local def = view.get(meta.view)
  local at_op = support.at_op(meta.parsed.argv)
  lnum = lnum or host.line(bufnr)
  local entry = lnum and meta.entries[lnum] or nil
  local divergent, entry_name, kind, prefixes
  if entry and def.template then
    divergent = divergent_of(def.template.fields, entry)
    entry_name, kind = name_of(def.template.fields, entry)
    prefixes = prefixes_of(def.template.short, entry)
  end
  local file
  if def.revision then
    file = support.file_path(meta.parsed.argv)
    local shown = meta.revision
    if shown and not entry_name then
      entry_name, kind = shown.change:sub(1, 8) .. " " .. shown.commit:sub(1, 8), "change"
      prefixes = { math.min(#shown.change_short, 8), math.min(#shown.commit_short, 8) }
      divergent = shown.divergent or nil
    end
  end
  local here
  if jin then
    local component = require("jin.component")
    here = { root = meta.parsed.root:match("([^/]+)/*$") or meta.parsed.root }
    for _, name in ipairs({ "change", "state", "bookmarks", "traffic" }) do
      here[name] = component.get(jin, host, name)
    end
  end
  return {
    view = meta.view,
    editable = def.editable == true,
    at_op = at_op and at_op:sub(1, 12) or nil,
    selected = #selection.list(host, meta.parsed.root),
    file = file,
    entry = entry_name,
    kind = kind,
    prefixes = prefixes,
    divergent = divergent,
    about = entry and about_of(def, entry) or nil,
    here = here,
  }
end

return M
