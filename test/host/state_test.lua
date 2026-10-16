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
  jin.jj({ "bookmark", "create", "topic", "-r", "@" })
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

---The first line of the current buffer matching `pattern`.
local function find(pattern)
  for lnum, line in ipairs(h.lines()) do
    if line:find(pattern) then
      return lnum
    end
  end
  error("no line matches " .. pattern .. " in:\n" .. table.concat(h.lines(), "\n"))
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

---The component `name` once it reads `expected`.
local function component_becomes(name, expected)
  h.eventually(function()
    return vim.fn.eval("jin#component#get('" .. name .. "')") == expected
  end, function()
    return name .. ": " .. vim.fn.eval("jin#component#get('" .. name .. "')")
  end)
end

---Write `text` to the file at `path`.
local function write(path, text)
  local f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

---A remote with commits "c1" and "c2", bookmark main on "c2", cloned into a
---fresh workspace that becomes the current directory.
local function clone()
  local origin = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = origin }).code)
  write(origin .. "/f", "1")
  h.eq(0, jin.jj({ "commit", "-m", "c1" }, { cwd = origin }).code)
  write(origin .. "/f", "2")
  h.eq(0, jin.jj({ "commit", "-m", "c2" }, { cwd = origin }).code)
  h.eq(0, jin.jj({ "bookmark", "create", "main", "-r", "@-" }, { cwd = origin }).code)
  local dir = h.tempdir() .. "/clone"
  h.eq(0, jin.jj({ "git", "clone", origin, dir }, { cwd = origin }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  return dir
end

---The change ID of `revset`.
local function change_of(revset)
  return jin.jj({ "log", "-r", revset, "--no-graph", "-T", "change_id" }).stdout
end

---Commit `text` written to f and to "sp ace.txt" of the current directory,
---and return the change ID of the commit.
local function commit(text)
  write(vim.fn.getcwd() .. "/f", text)
  write(vim.fn.getcwd() .. "/sp ace.txt", text)
  h.eq(0, jin.jj({ "commit", "-m", text }).code)
  return change_of("@-")
end

---Make the working copy a change "merge" of "left" and "right", which
---conflict in f and "sp ace.txt", on top of "base"; return the change ID of
---the merge.
local function conflict()
  local base = commit("base")
  local left = commit("left")
  h.eq(0, jin.jj({ "new", base }).code)
  local right = commit("right")
  h.eq(0, jin.jj({ "new", left, right, "-m", "merge" }).code)
  return change_of("@")
end

---Add a workspace named "second" beside the current one, and return its root.
local function second_workspace()
  local other = h.tempdir() .. "/second"
  h.eq(0, jin.jj({ "workspace", "add", "--name", "second", other }).code)
  return other
end

---Run the action `name` of the current buffer on line `lnum`.
local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
end

---Press `keys`, written as in a Vim string ("\\<CR>"), on line `lnum`.
local function press(keys, lnum)
  vim.fn.cursor(lnum, 1)
  h.ex('execute "normal ' .. keys .. '"')
end

---The first line of the current buffer that stands for no entry.
local function line_of_nothing(meta)
  for lnum = 1, #h.lines() do
    if not meta.entries[lnum] then
      return lnum
    end
  end
  error("every line stands for a change in:\n" .. table.concat(h.lines(), "\n"))
end

---The editor's global current directory, whatever window or tab page
---directory is set: Neovim reads it at (-1, -1), Vim at -1.
local function global_cwd()
  if vim.api then
    return vim.fn.getcwd(-1, -1)
  end
  return vim.fn.getcwd(-1)
end

---The current tab page's directory, or the global one when it has none.
local function tab_cwd()
  return vim.fn.getcwd(-1, 0)
end

return {
  {
    "components show the working copy without adding an operation",
    function()
      local dir = workspace()
      local before = operations(dir)
      component_becomes("description", "work in progress")
      h.eq("topic", vim.fn.eval("jin#component#get('bookmarks')"))
      h.truthy(vim.fn.eval("jin#component#get('change')"):match("^[k-z]+$"), "no change ID")
      h.eq(before, operations(dir))
    end,
  },
  {
    "components read the newest operation when operations diverged, without merging them",
    function()
      local dir = workspace()
      component_becomes("description", "work in progress")
      local op = jin.jj({ "op", "log", "-n1", "--no-graph", "-T", "id.short()" }).stdout
      h.eq(0, jin.jj({ "describe", "-m", "two" }).code)
      local three = { "--at-op", op, "--ignore-working-copy", "describe", "-m", "three" }
      h.eq(0, jin.jj(three).code)
      local before = operations(dir)
      h.eq(2, before.heads)
      h.ex("call jin#component#touch(1)")
      component_becomes("description", "three")
      h.eq(before, operations(dir))
    end,
  },
  {
    "components show the state of the working-copy change",
    function()
      workspace()
      component_becomes("state", "empty")
      conflict()
      h.ex("call jin#component#touch(1)")
      component_becomes("state", "empty conflict")
    end,
  },
  {
    "components show a divergent working-copy change",
    function()
      workspace()
      component_becomes("description", "work in progress")
      local op = jin.jj({ "op", "log", "-n1", "--no-graph", "-T", "id.short()" }).stdout
      h.eq(0, jin.jj({ "describe", "-m", "two" }).code)
      h.eq(0, jin.jj({ "--at-op", op, "--ignore-working-copy", "describe", "-m", "three" }).code)
      -- A plain jj command merges the heads, rewriting the change twice.
      h.eq(0, jin.jj({ "status" }).code)
      h.ex("call jin#component#touch(1)")
      component_becomes("state", "empty divergent")
    end,
  },
  {
    "components show how far a bookmark is ahead of its remote",
    function()
      clone()
      h.eq(0, jin.jj({ "new", "main", "-m", "local" }).code)
      h.eq(0, jin.jj({ "bookmark", "set", "main", "-r", "@" }).code)
      component_becomes("traffic", "main@origin↑1")
      h.eq("main", vim.fn.eval("jin#component#get('bookmarks')"))
    end,
  },
  {
    "components show how far a bookmark is behind its remote",
    function()
      clone()
      h.eq(0, jin.jj({ "bookmark", "set", "main", "-r", "main-", "--allow-backwards" }).code)
      h.eq(0, jin.jj({ "new", "main" }).code)
      component_becomes("traffic", "main@origin↓1")
    end,
  },
  {
    "components name the workspaces at the working copy once there are several",
    function()
      workspace()
      component_becomes("description", "work in progress")
      h.eq("", vim.fn.eval("jin#component#get('workspace')"))
      h.eq(0, jin.jj({ "workspace", "add", h.tempdir() .. "/other" }).code)
      h.ex("call jin#component#touch(1)")
      component_becomes("workspace", "default@")
    end,
  },
  {
    "a forced refresh of an unchanged repository does not fire JinComponentPost",
    function()
      workspace()
      h.ex("let g:jin_component_post = 0")
      h.ex("autocmd User JinComponentPost let g:jin_component_post += 1")
      component_becomes("description", "work in progress")
      h.eq(1, vim.fn.eval("g:jin_component_post"))
      h.ex("call jin#component#touch(1)")
      -- Refreshes run one after another, so once the next change shows, the
      -- forced refresh before it has finished.
      h.eq(0, jin.jj({ "describe", "-m", "changed" }).code)
      h.ex("call jin#component#touch(1)")
      component_becomes("description", "changed")
      h.ex("autocmd! User JinComponentPost")
      h.eq(2, vim.fn.eval("g:jin_component_post"))
    end,
  },
  {
    "components fire JinComponentPost when they change",
    function()
      workspace()
      h.ex("let g:jin_component_post = 0")
      h.ex("autocmd User JinComponentPost let g:jin_component_post += 1")
      -- Only a workspace whose components were read is refreshed.
      vim.fn.eval("jin#component#get('change')")
      h.ex("call jin#component#touch(1)")
      h.eventually(function()
        return vim.fn.eval("g:jin_component_post") >= 1
      end, "JinComponentPost did not fire")
      h.ex("autocmd! User JinComponentPost")
    end,
  },
  {
    "a statusline reading a component never fails, even outside a workspace",
    function()
      h.ex("cd " .. vim.fn.fnameescape(h.tempdir()))
      h.eq("", vim.fn.eval("jin#component#get('change')"))
      h.eq("", vim.fn.eval("jin#component#get('no-such-component')"))
    end,
  },
  {
    "JinBookmark lists bookmarks and leads to the log up to one",
    function()
      local dir = workspace()
      h.ex("JinBookmark")
      local bufnr = vim.fn.bufnr()
      h.eventually(function()
        return view.meta(host, bufnr) ~= nil
      end, "never read")
      h.eq("topic", view.meta(host, bufnr).entries[1][1])
      require("jin.host.entry").action(bufnr, "log", 1, 1)
      h.eq([[jin://]] .. dir .. [[;view=log#-r ::bookmarks(exact:\"topic\")]], vim.fn.bufname())
    end,
  },
  {
    "JinBookmark keeps a name with a space and a quote whole and leads to its log",
    function()
      workspace()
      local name = [[my book"mark]]
      h.eq(0, jin.jj({ "bookmark", "create", [["my book\"mark"]], "-r", "@" }).code)
      h.ex("JinBookmark")
      local meta = settle()
      local lnum = entry_line(meta, name)
      h.eq(name, meta.entries[lnum][1])
      require("jin.host.entry").action(vim.fn.bufnr(), "log", lnum, lnum)
      settle()
      find("work in progress")
    end,
  },
  {
    "JinWorkspace keeps a name with a space and a quote whole and changes to it",
    function()
      workspace()
      local name = [[my qu'ote"d]]
      local other = h.tempdir() .. "/other"
      h.eq(0, jin.jj({ "workspace", "add", "--name", name, other }).code)
      h.ex("JinWorkspace")
      local meta = settle()
      local lnum = entry_line(meta, name)
      h.eq(name, meta.entries[lnum][1])
      local bufnr = vim.fn.bufnr()
      require("jin.host.entry").action(bufnr, "cd", lnum, lnum)
      h.eq(other, vim.fn.getcwd())
      require("jin.host.entry").action(bufnr, "log", lnum, lnum)
      settle()
      -- The new workspace's working copy is a fresh change on the root.
      find("my qu'ote")
    end,
  },
  {
    "JinTcd goes to the root of the workspace",
    function()
      local dir = workspace()
      vim.fn.mkdir(dir .. "/sub", "p")
      h.ex("cd sub")
      h.ex("JinTcd")
      h.eq(dir, vim.fn.getcwd())
    end,
  },
  {
    "JinConflicts lists only the conflicted changes and its keys lead to their files and diff",
    function()
      local dir = workspace()
      local merge = conflict()
      h.ex("filetype plugin on")
      h.ex("JinConflicts")
      local meta = settle()
      local lnum = find("merge")
      h.eq(merge, meta.entries[lnum][1])
      for _, line in ipairs(h.lines()) do
        h.truthy(not line:find("left") and not line:find("right"), "a resolved change is listed")
      end
      local conflicts = vim.fn.bufnr()
      press("yy", lnum)
      h.eq(merge, vim.fn.getreg('"'))
      press("\\<CR>", lnum)
      h.eq("jin://" .. dir .. ";view=resolve#-r " .. merge, vim.fn.bufname())
      settle()
      find("^f%s+2%-sided conflict")
      h.ex("buffer " .. conflicts)
      settle()
      press("gd", lnum)
      h.eq("jin://" .. dir .. ";view=diff#-r " .. merge, vim.fn.bufname())
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinConflicts does nothing on a line shared by two changes, and says why by name",
    function()
      workspace()
      conflict()
      h.eq(0, jin.jj({ "new", "-m", "child" }).code)
      -- Without a newline in the template, both conflicted changes share the line.
      h.ex("filetype plugin on")
      h.ex("JinConflicts --no-graph -T change_id.short()")
      local lnum = line_of_nothing(settle())
      local name = vim.fn.bufname()
      h.ex("messages clear")
      press("gd", lnum)
      h.ex("filetype plugin off")
      h.eq(name, vim.fn.bufname())
      local shown = vim.fn.execute("messages")
      h.truthy(not shown:find("nothing to act on", 1, true), shown)
      local ok, err =
        pcall(require("jin.action").run, jin, host, vim.fn.bufnr(), "show", lnum, lnum)
      h.eq({ false, "jin: nothing to act on in this line" }, { ok, err })
    end,
  },
  {
    "JinBookmark keys show the change of a local bookmark and yank its name",
    function()
      local dir = workspace()
      h.ex("filetype plugin on")
      h.ex("JinBookmark")
      local lnum = entry_line(settle(), "topic")
      press("yy", lnum)
      h.eq("topic", vim.fn.getreg('"'))
      press("\\<Plug>(jin-action-show)", lnum)
      h.eq([[jin://]] .. dir .. [[;view=show#bookmarks(exact:\"topic\")]], vim.fn.bufname())
      settle()
      find("work in progress")
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinBookmark leads from a remote-tracking line to the log of the remote bookmark",
    function()
      local dir = clone()
      h.eq(0, jin.jj({ "bookmark", "set", "main", "-r", "main-", "--allow-backwards" }).code)
      h.ex("filetype plugin on")
      h.ex("JinBookmark")
      local meta = settle()
      local lnum = find("@origin")
      h.eq({ "main", "origin" }, { meta.entries[lnum][1], meta.entries[lnum][2] })
      press("\\<CR>", lnum)
      h.eq(
        [[jin://]] .. dir .. [[;view=log#-r ::remote_bookmarks(exact:\"main\",\ exact:\"origin\")]],
        vim.fn.bufname()
      )
      settle()
      -- Only the remote bookmark has reached c2.
      find("c2")
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinBookmark maps every line of a conflicted bookmark to that bookmark",
    function()
      workspace()
      h.eq(0, jin.jj({ "new", "root()", "-m", "left" }).code)
      local left = change_of("@")
      h.eq(0, jin.jj({ "new", "root()", "-m", "right" }).code)
      local right = change_of("@")
      local op = jin.jj({ "op", "log", "-n1", "--no-graph", "-T", "id.short()" }).stdout
      h.eq(0, jin.jj({ "bookmark", "set", "topic", "-r", left, "--allow-backwards" }).code)
      local other = { "--at-op", op, "--ignore-working-copy" }
      for _, a in ipairs({ "bookmark", "set", "topic", "-r", right, "--allow-backwards" }) do
        other[#other + 1] = a
      end
      h.eq(0, jin.jj(other).code)
      -- A plain jj command merges the heads, leaving topic in conflict.
      h.eq(0, jin.jj({ "status" }).code)
      h.ex("JinBookmark")
      local meta = settle()
      find("topic %(conflicted%)")
      local sides = 0
      for lnum, line in ipairs(h.lines()) do
        if line:find("^%s+[-+] ") then
          sides = sides + 1
          h.eq({ "topic" }, meta.entries[lnum])
        end
      end
      h.eq(3, sides)
      act("log", find("^%s+%+ .*right"))
      settle()
      find("left")
      find("right")
    end,
  },
  {
    "JinWorkspace leads from another workspace to its log and its working-copy change",
    function()
      local dir = workspace()
      second_workspace()
      local change = change_of("second@")
      h.ex("filetype plugin on")
      h.ex("JinWorkspace")
      local lnum = entry_line(settle(), "second")
      local workspaces = vim.fn.bufnr()
      press("\\<Plug>(jin-action-log)", lnum)
      h.eq([[jin://]] .. dir .. [[;view=log#-r ::\"second\"@]], vim.fn.bufname())
      settle()
      find("second@")
      h.ex("buffer " .. workspaces)
      settle()
      act("show", lnum)
      h.eq([[jin://]] .. dir .. [[;view=show#\"second\"@]], vim.fn.bufname())
      settle()
      find(change)
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinWorkspace changes only the window's directory with lcd and only the tab's with tcd",
    function()
      local dir = workspace()
      local other = second_workspace()
      h.ex("JinWorkspace")
      local lnum = entry_line(settle(), "second")
      act("lcd", lnum)
      h.eq({ other, dir, dir }, { vim.fn.getcwd(), tab_cwd(), global_cwd() })
      h.ex("cd " .. vim.fn.fnameescape(dir))
      act("tcd", lnum)
      h.eq({ other, other, dir }, { vim.fn.getcwd(), tab_cwd(), global_cwd() })
    end,
  },
  {
    "JinCd and JinLcd go from a file of another workspace to its root, whatever the cwd",
    function()
      workspace()
      local other = second_workspace()
      vim.fn.mkdir(other .. "/sub", "p")
      write(other .. "/sub/g", "x")
      local outside = h.tempdir()
      h.ex("cd " .. vim.fn.fnameescape(outside))
      h.ex("edit " .. vim.fn.fnameescape(other .. "/sub/g"))
      h.ex("JinCd")
      h.eq({ other, other }, { vim.fn.getcwd(), global_cwd() })
      h.ex("cd " .. vim.fn.fnameescape(outside))
      h.ex("JinLcd")
      h.eq({ other, outside }, { vim.fn.getcwd(), global_cwd() })
    end,
  },
  {
    "JinCd and JinLcd go from a jin:// buffer to the root of its workspace",
    function()
      local dir = workspace()
      h.ex("JinLog")
      settle()
      local outside = h.tempdir()
      h.ex("cd " .. vim.fn.fnameescape(outside))
      h.ex("JinCd")
      h.eq(dir, global_cwd())
      h.ex("cd " .. vim.fn.fnameescape(outside))
      h.ex("JinLcd")
      h.eq({ dir, outside }, { vim.fn.getcwd(), global_cwd() })
    end,
  },
  {
    "JinCd and JinLcd outside any workspace say so and stay where they are",
    function()
      local outside = h.tempdir()
      h.ex("cd " .. vim.fn.fnameescape(outside))
      for _, command in ipairs({ "JinCd", "JinLcd" }) do
        h.ex("messages clear")
        h.ex(command)
        local shown = vim.fn.execute("messages")
        h.truthy(shown:find("jin: not in a jj workspace", 1, true), command .. ": " .. shown)
        h.eq({ outside, outside }, { vim.fn.getcwd(), global_cwd() })
      end
    end,
  },
  {
    "the conflict, bookmark and workspace views and their read actions add no operation",
    function()
      local dir = workspace()
      second_workspace()
      conflict()
      h.eq(0, jin.jj({ "status" }).code)
      local before = operations(dir)
      local function each(command, name, actions)
        for _, a in ipairs(actions) do
          h.ex(command)
          act(a, entry_line(settle(), name))
          settle()
        end
      end
      each("JinConflicts", change_of("@"), { "files", "show", "diff" })
      each("JinBookmark", "topic", { "log", "show" })
      each("JinWorkspace", "second", { "log", "show" })
      h.eq(before, operations(dir))
    end,
  },
  {
    "JinConflicts leads to each conflicted file of the working copy, a path with a space too",
    function()
      local dir = workspace()
      local merge = conflict()
      h.ex("filetype plugin on")
      h.ex("JinConflicts")
      press("\\<CR>", entry_line(settle(), merge))
      settle()
      local listing = vim.fn.bufnr()
      press("\\<CR>", find("^sp ace%.txt"))
      h.eq(dir .. "/sp ace.txt", vim.fn.expand("%:p"))
      h.truthy(h.lines()[1]:find("^<<<<<<<"), "the conflict is not shown")
      h.ex("buffer " .. listing)
      settle()
      press("gd", find("^sp ace%.txt"))
      h.eq(
        [[jin://]] .. dir .. [[;view=diff#-r ]] .. merge .. [[ -- file:\"sp\ ace.txt\"]],
        vim.fn.bufname()
      )
      settle()
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinConflicts opens a conflicted file of another change as that change holds it",
    function()
      local dir = workspace()
      local merge = conflict()
      h.eq(0, jin.jj({ "new", "-m", "child" }).code)
      h.ex("JinConflicts")
      act("files", entry_line(settle(), merge))
      settle()
      act("edit", find("^sp ace%.txt"))
      h.eq(
        [[jin://]] .. dir .. [[;view=file#-r ]] .. merge .. [[ file:\"sp\ ace.txt\"]],
        vim.fn.bufname()
      )
      h.eventually(function()
        return (h.lines()[1] or ""):find("^<<<<<<<") ~= nil
      end, "the conflict is not shown")
    end,
  },
  {
    "JinBookmark says a remote bookmark not pushed yet points to no change",
    function()
      clone()
      h.eq(0, jin.jj({ "bookmark", "create", "feat", "-r", "@" }).code)
      h.eq(0, jin.jj({ "bookmark", "track", "feat", "--remote", "origin" }).code)
      h.ex("filetype plugin on")
      h.ex("JinBookmark")
      settle()
      local lnum = find("not created yet")
      local name = vim.fn.bufname()
      for _, keys in ipairs({ "\\<CR>", "\\<C-w>\\<CR>" }) do
        h.ex("messages clear")
        press(keys, lnum)
        h.eq(name, vim.fn.bufname())
        local shown = vim.fn.execute("messages")
        h.truthy(shown:find("feat@origin points to no change", 1, true), shown)
      end
      h.ex("filetype plugin off")
    end,
  },
  {
    "the actions leading to evologs, relatives, annotations and conflicted files add no operation",
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
      local function spaced()
        return find("^sp ace%.txt")
      end
      each("JinLog -r " .. merge, of_merge, { "evolog" })
      each("JinShow " .. merge, first, { "parent", "child" })
      each("JinFile -r " .. merge .. " f", first, { "annotate", "log" })
      each("JinAnnotate -r fork_point(" .. merge .. "-) f", first, { "log" })
      each("JinConflicts", of_merge, { "files" })
      for _, a in ipairs({ "edit", "diff" }) do
        h.ex("JinConflicts")
        act("files", of_merge(settle()))
        settle()
        act(a, spaced())
        settle()
      end
      h.ex("JinConflicts")
      act("files", entry_line(settle(), change_of("@")))
      settle()
      act("edit", spaced())
      h.eq(dir .. "/sp ace.txt", vim.fn.expand("%:p"))
      h.eq(before, operations(dir))
    end,
  },
}
