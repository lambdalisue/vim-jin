-- The description of a change, or of several, in a buffer to edit: jj's own
-- draft, written back with jj describe --stdin.

local support = require("jin.view.support")

-- What jj heads the draft of each change with when it describes several.
local HEAD = "^JJ: describe (%S+) %-+$"

local text_of = require("jin.description").text

---The revisions `argv` names with -r, in order.
---@param argv string[]
---@return string[]
local function revisions(argv)
  local revs = {}
  for i, a in ipairs(argv) do
    if (a == "-r" or a == "--revisions") and argv[i + 1] then
      revs[#revs + 1] = argv[i + 1]
    end
  end
  return revs
end

---The descriptions to hand jj, each as { revisions, text }: one per head the
---buffer holds, or, without heads, its whole text for every revision.
---@param lines string[]
---@param argv string[]
---@return { [1]: string[], [2]: string }[]
local function sections(lines, argv)
  local found, current = {}, nil
  for _, line in ipairs(lines) do
    local rev = line:match(HEAD)
    if rev then
      current = { { rev }, {} }
      found[#found + 1] = current
    elseif current then
      table.insert(current[2], line)
    end
  end
  if #found == 0 then
    return { { revisions(argv), text_of(lines) } }
  end
  for _, section in ipairs(found) do
    section[2] = text_of(section[2])
  end
  return found
end

---@type jin.View
return {
  command = { "log" },
  flags = { "--no-graph" },
  title = { "describe" },
  filetype = "jjdescription",
  template = {
    key = "draft_commit_description",
    default = "builtin_draft_commit_description",
    -- The description itself as well, which the draft may add to.
    fields = support.DESCRIBED_FIELDS,
    short = support.DESCRIBED_SHORT,
  },
  editable = true,
  decorate = function(meta)
    -- What each change had when read, to tell on :w whether someone, such
    -- as an agent, changed it meanwhile.
    meta.data.originals = support.originals(meta)
    local firsts, count = {}, 0
    for lnum, entry in ipairs(meta.entries) do
      if entry and entry ~= meta.entries[lnum - 1] then
        firsts[lnum] = entry
        count = count + 1
      end
    end
    if count < 2 then
      return
    end
    local lines = {}
    for lnum, line in ipairs(meta.lines) do
      if firsts[lnum] then
        lines[#lines + 1] = ("JJ: describe %s -------"):format(support.revision(firsts[lnum]))
      end
      lines[#lines + 1] = line
    end
    meta.lines = lines
    meta.spans = {}
  end,
  ---Describe the changes with what the buffer says, one after another, and
  ---mark it written once every one of them succeeded.
  write = function(jin, host, bufnr, parsed)
    local written = host.lines(bufnr)
    local pending = sections(written, parsed.argv)
    local meta = require("jin.view").meta(host, bufnr)
    local originals = meta and meta.data.originals or {}
    local replaced = meta and meta.data.replaced or {}
    if meta then
      meta.data.replaced = replaced
    end
    local revs = {}
    for _, section in ipairs(pending) do
      for _, rev in ipairs(section[1]) do
        if replaced[rev] then
          error(
            ("jin: the version %s was replaced by the last :w; describe its change again from a view"):format(
              rev
            ),
            0
          )
        end
        revs[#revs + 1] = rev
      end
    end
    support.refuse_changed(jin, parsed.root, originals, revs)
    local function next_one(i)
      local section = pending[i]
      if not section then
        support.mark_saved(host, bufnr, written)
        return
      end
      local argv = { "describe" }
      for _, rev in ipairs(section[1]) do
        argv[#argv + 1] = "-r"
        argv[#argv + 1] = rev
      end
      argv[#argv + 1] = "--stdin"
      -- Quiet: jj tells what it rebased and where the working copy is, which
      -- the views it reads again show, and a :w should not stop at a prompt.
      jin.command(argv, { cwd = parsed.root, stdin = section[2], quiet = true }, function(result)
        if result.code == 0 then
          -- What jj holds now is what was written, not to be taken for
          -- someone else's change on the next :w.
          for _, rev in ipairs(section[1]) do
            originals[rev] = section[2]
            -- A divergent change is named by the commit ID of its version,
            -- which describing replaces; no revset leads to the new one.
            if rev:match("^%x+$") then
              replaced[rev] = true
            end
          end
          next_one(i + 1)
        end
      end)
    end
    next_one(1)
  end,
}
