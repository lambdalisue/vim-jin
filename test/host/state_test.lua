local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  jin.jj({ "describe", "-m", "work in progress" })
  return dir
end

---Wait until the current buffer has been read, and return its metadata.
local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  return view.meta(host, bufnr)
end

---The first line whose entry starts with `name`.
local function entry_line(meta, name)
  for lnum, entry in ipairs(meta.entries) do
    if entry and entry[1] == name then
      return lnum
    end
  end
  error("no line stands for " .. name .. " in:\n" .. table.concat(h.lines(), "\n"))
end

---How many operations and operation heads the repository at `dir` holds,
---read from its files: asking jj would merge diverged heads, which adds an
---operation.
local function operations(dir)
  local function count(path)
    return #host.list(vim.fn.readdir(dir .. "/.jj/repo/" .. path))
  end
  return { operations = count("op_store/operations"), heads = count("op_heads/heads") }
end

---Write `text` to the file at `path`.
local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

---The change ID of `revset`.
local function change_of(revset)
  return jin.jj({ "log", "-r", revset, "--no-graph", "-T", "change_id" }).stdout
end

---Commit `text` written to f of the current directory, and return the
---change ID of the commit.
local function commit(text)
  write(vim.fn.getcwd() .. "/f", text)
  h.eq(0, jin.jj({ "commit", "-m", text }).code)
  return change_of("@-")
end

---Make the working copy a change "merge" of "left" and "right", which
---conflict in f, on top of "base"; return the change ID of the merge.
local function conflict()
  local base = commit("base")
  local left = commit("left")
  h.eq(0, jin.jj({ "new", base }).code)
  local right = commit("right")
  h.eq(0, jin.jj({ "new", left, right, "-m", "merge" }).code)
  return change_of("@")
end

---Run the action `name` of the current buffer on line `lnum`.
local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
end

return {
  {
    "the actions leading to evologs, relatives and annotations add no operation",
    function()
      local dir = workspace()
      local merge = conflict()
      h.eq(0, jin.jj({ "new", "-m", "child" }).code)
      h.eq(0, jin.jj({ "status" }).code)
      local before = operations(dir)
      local function each(command, lnum_of, actions)
        for _, a in ipairs(actions) do
          h.ex(command)
          act(a, lnum_of(settle()))
          settle()
        end
      end
      local function first()
        return 1
      end
      local function of_merge(meta)
        return entry_line(meta, merge)
      end
      each("JinLog -r " .. merge, of_merge, { "evolog" })
      each("JinShow " .. merge, first, { "parent", "child" })
      each("JinFile -r " .. merge .. " f", first, { "annotate", "log" })
      each("JinAnnotate -r fork_point(" .. merge .. "-) f", first, { "log" })
      h.eq(before, operations(dir))
    end,
  },
}
