local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

---A workspace whose @ is "second" on top of "first".
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  h.eq(0, jin.jj({ "describe", "-m", "first" }).code)
  h.eq(0, jin.jj({ "new", "-m", "second" }).code)
  return dir
end

local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  return view.meta(host, bufnr)
end

---The line of the log showing `text`.
local function line_of(text)
  for lnum, line in ipairs(h.lines()) do
    if line:find(text, 1, true) then
      return lnum
    end
  end
  error("no line shows " .. text)
end

---Answer the next question or prompt with `reply`: true or false for a
---confirmation, text for an input. The prompts themselves are the editor's.
local function answer(reply)
  local confirm, input = host.confirm, host.input
  host.confirm = function()
    host.confirm = confirm
    return reply == true
  end
  host.input = function()
    host.input = input
    return type(reply) == "string" and reply or nil
  end
end

local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
end

local function at(rev)
  return jin.jj({ "log", "--no-graph", "-r", rev, "-T", "description" }).stdout
end

return {
  {
    "new and edit move the working copy as jj does",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("new", line_of("first"))
      h.eventually(function()
        return at("@-") == "first\n"
      end, "no new change on top of first")
      act("edit", line_of("second"))
      h.eventually(function()
        return at("@") == "second\n"
      end, "second is not the working copy")
    end,
  },
  {
    "abandon asks before it changes anything, and undo and redo do not",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      answer(true)
      act("abandon", line_of("second"))
      h.eventually(function()
        return at("@-") == "first\n"
      end, "second was not abandoned")
      act("undo", 1)
      h.eventually(function()
        return at("@") == "second\n"
      end, "the abandon was not undone")
      act("redo", 1)
      h.eventually(function()
        return at("@") == ""
      end, "the abandon was not redone")
    end,
  },
  {
    "commit opens the draft of the working copy, and :w commits it with the text",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("commit", 1)
      h.truthy(vim.fn.bufname():find(";view=commit#-r ", 1, true), vim.fn.bufname())
      settle()
      h.eq("second", vim.fn.getline(1))
      vim.fn.setline(1, "second, committed")
      local commit = vim.fn.bufnr()
      h.ex("write")
      h.eventually(function()
        return at("@-") == "second, committed\n" and at("@") == ""
      end, function()
        return "@- is " .. at("@-")
      end)
      h.eventually(function()
        return vim.fn.bufexists(commit) == 0
      end, "the commit buffer is still there")
      h.truthy(vim.fn.bufname():find(";view=log#", 1, true), vim.fn.bufname())
      h.eq(1, vim.fn.winnr("$"))
    end,
  },
  {
    "a commit buffer opened in a window or tab page of its own closes it once committed",
    function()
      for _, name in ipairs({ "commit:split", "commit:tab" }) do
        workspace()
        h.ex("JinLog")
        settle()
        local log_win = vim.fn.win_getid()
        local tabs = vim.fn.tabpagenr("$")
        act(name, 1)
        settle()
        local commit = vim.fn.bufnr()
        vim.fn.setline(1, "committed by " .. name)
        h.ex("write")
        h.eventually(function()
          return vim.fn.bufexists(commit) == 0
        end, name .. ": the commit buffer is still there")
        h.eq(tabs, vim.fn.tabpagenr("$"))
        h.eq(1, vim.fn.winnr("$"))
        h.eq(log_win, vim.fn.win_getid())
      end
    end,
  },
  {
    "a commit refused as the working copy moved keeps the commit buffer and its text",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("commit", 1)
      settle()
      local commit = vim.fn.bufnr()
      vim.fn.setline(1, "kept")
      h.eq(0, jin.jj({ "new" }).code)
      h.ex("silent! write")
      h.ex("let v:errmsg = ''")
      h.eq(commit, vim.fn.bufnr())
      h.eq("kept", vim.fn.getline(1))
      h.ex("bwipeout!")
    end,
  },
  {
    "x selects the change of the line in every view of the workspace",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      local log = vim.fn.bufnr()
      h.ex("vsplit")
      h.ex("JinLog -r @-")
      settle()
      act("select", line_of("first"))
      local function selected(bufnr)
        if vim.api then
          local ns = vim.api.nvim_create_namespace("jin-selected")
          return #vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
        end
        return #vim.fn.sign_getplaced(bufnr, vim.dict({ group = "JinSelected" }))[0].signs
      end
      h.eq(2, selected(vim.fn.bufnr()))
      h.eq(2, selected(log))
      h.eq("Visual", vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("JinSelected")), "name"))
      h.ex("only")
    end,
  },
  {
    "a selection shows over the cursor entry",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      local bufnr = vim.fn.bufnr()
      local lnum = line_of("first")
      act("select", lnum)
      local priority, entry_priority
      if vim.api then
        local function top(name)
          local ns = vim.api.nvim_create_namespace(name)
          local found = 0
          for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
            found = math.max(found, mark[4].priority or 4096)
          end
          return found
        end
        priority, entry_priority = top("jin-selected"), math.max(top("jin-cursor-entry"), 4096)
      else
        local function top(group)
          local found = 0
          for _, sign in
            ipairs(host.list(vim.fn.sign_getplaced(bufnr, vim.dict({ group = group }))[0].signs))
          do
            found = math.max(found, sign.priority)
          end
          return found
        end
        priority, entry_priority = top("JinSelected"), math.max(top("JinCursorEntry"), 10)
      end
      h.truthy(
        priority > entry_priority,
        ("selection %d, cursor entry %d"):format(priority, entry_priority)
      )
    end,
  },
  {
    "squash into the selected change joins both descriptions, with no editor to wait for",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      act("select", line_of("first"))
      act("squash", line_of("second"))
      h.eventually(function()
        return at("@-") == "first\n\nsecond\n"
      end, function()
        return "@- is " .. at("@-")
      end)
    end,
  },
  {
    "bookmark asks for a name and sets it, and restore takes the repository back",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      answer("topic")
      act("bookmark", line_of("first"))
      h.eventually(function()
        return jin.jj({ "log", "--no-graph", "-r", "topic", "-T", "description" }).stdout
          == "first\n"
      end, "no bookmark topic on first")
      local before =
        jin.jj({ "op", "log", "--no-graph", "--limit", "2", "-T", 'id ++ "\\n"' }).stdout
      local op = before:match("\n(%x+)")
      h.truthy(op, before)
      h.ex("JinOpLog")
      settle()
      answer(true)
      act("restore", line_of(op:sub(1, 12)))
      h.eventually(function()
        return jin.jj({ "bookmark", "list" }).stdout == ""
      end, function()
        return table.concat({
          "bookmarks: " .. jin.jj({ "bookmark", "list" }).stdout,
          "ops: " .. jin.jj({
            "op",
            "log",
            "--no-graph",
            "--limit",
            "4",
            "-T",
            'id.short() ++ " " ++ description ++ "\\n"',
          }).stdout,
          "wanted: " .. op,
          "messages: " .. vim.fn.execute("messages"),
        }, "\n")
      end)
    end,
  },
  {
    "the bookmark view moves a bookmark to the selected change and deletes it, by exact name",
    function()
      workspace()
      h.eq(0, jin.jj({ "bookmark", "create", "to*pic", "topic", "-r", "@" }).code)
      local function bookmarks()
        return jin.jj({ "bookmark", "list", "-T", 'name ++ " " ++ normal_target.description()' }).stdout
      end
      h.ex("JinLog")
      settle()
      act("select", line_of("first"))
      h.ex("JinBookmark")
      settle()
      act("move", line_of("to*pic"))
      h.eventually(function()
        return bookmarks() == "to*pic first\ntopic second\n"
      end, function()
        return "bookmarks: " .. bookmarks()
      end)
      settle()
      answer(true)
      act("delete", line_of("to*pic"))
      h.eventually(function()
        return bookmarks() == "topic second\n"
      end, function()
        return "bookmarks: " .. bookmarks()
      end)
    end,
  },
  {
    ":JinArrange rebases a line of changes into the order the lines are written in",
    function()
      workspace()
      h.eq(0, jin.jj({ "new", "-m", "third" }).code)
      h.ex("JinArrange")
      settle()
      h.eq(3, #h.lines())
      local by = {}
      for _, line in ipairs(h.lines()) do
        by[line:match("%S+$")] = line
      end
      vim.fn.setline(1, host.to_list({ by.second, by.third, by.first }))
      h.ex("write")
      local function order()
        return jin.jj({
          "log",
          "--no-graph",
          "-r",
          "mutable()",
          "-T",
          'description.first_line() ++ " "',
        }).stdout
      end
      h.eventually(function()
        return order() == "second third first "
      end, function()
        return "order: " .. order()
      end)
      h.eq("third\n", at("@"))
      h.eq(0, vim.fn.getbufvar(vim.fn.bufnr(), "&modified"))
    end,
  },
}
