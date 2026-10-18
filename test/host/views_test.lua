local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local function write(path, lines)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
end

---A workspace whose @- holds f.lua as a, b, c and whose @ removes b and adds d.
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  write(dir .. "/f.lua", { "a", "b", "c" })
  jin.jj({ "describe", "-m", "first change" })
  jin.jj({ "new" })
  write(dir .. "/f.lua", { "a", "c", "d" })
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

local function act(name, lnum)
  require("jin.host.entry").action(vim.fn.bufnr(), name, lnum, lnum)
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

return {
  {
    "the views that pass jj settings of their own keep jj's colors",
    function()
      workspace()
      for _, command in ipairs({ "JinLog", "JinOpLog", "JinEvolog" }) do
        h.ex(command)
        settle()
        h.truthy(#h.highlights(vim.fn.bufnr()) > 0, command .. " shows no colors")
      end
    end,
  },
  {
    "a view keeps a short title for a statusline in b:jin_title",
    function()
      workspace()
      h.ex("JinLog -r @-")
      settle()
      h.eq("jj log -r @-", vim.fn.getbufvar(vim.fn.bufnr(), "jin_title"))
    end,
  },
  {
    "JinLog shows the graph and leads from a change to its show view",
    function()
      local dir = workspace()
      h.ex("JinLog -r @-")
      local meta = settle()
      local lnum = find("first change")
      local change = meta.entries[lnum][1]
      h.truthy(change and #change == 32, "no change ID on the line")
      act("show", lnum)
      h.eq("jin://" .. dir .. ";view=show#" .. change, vim.fn.bufname())
      settle()
      find("first change")
    end,
  },
  {
    "JinDiff jumps from a line of the working copy to that line of the file",
    function()
      local dir = workspace()
      h.ex("JinDiff")
      settle()
      act("jump", find("^%s+3: d"))
      h.eq(dir .. "/f.lua", vim.fn.expand("%:p"))
      h.eq(3, vim.fn.line("."))
    end,
  },
  {
    "JinDiff jumps from a removed line to the file as it was in the parent",
    function()
      local dir = workspace()
      h.ex("JinDiff")
      settle()
      act("jump", find("^%s+2%s+: b"))
      h.eq("jin://" .. dir .. ";view=file#-r @- f.lua", vim.fn.bufname())
      h.eventually(function()
        return vim.fn.line(".") == 2 and h.lines()[2] == "b"
      end, "not on line 2 of the old file")
    end,
  },
  {
    "JinDiff of a merge says why a removed line has no single old file",
    function()
      local dir = workspace()
      jin.jj({ "new", "@-" })
      write(dir .. "/g.lua", { "x" })
      h.eq(0, jin.jj({ "new", "heads(all())" }).code)
      write(dir .. "/f.lua", { "a", "d" })
      h.ex("JinDiff")
      settle()
      local name = vim.fn.bufname()
      act("jump", find("^%s+2%s+: c"))
      h.eq(name, vim.fn.bufname())
      local messages = vim.fn.execute("messages")
      h.truthy(messages:find("parents of a merge", 1, true), messages)
    end,
  },
  {
    "JinDiff keeps the files the user folded closed across a reload",
    function()
      local dir = workspace()
      write(dir .. "/g.lua", { "x" })
      h.ex("JinDiff")
      local before = settle()
      h.ex("normal! gg")
      h.ex("normal! zc")
      h.truthy(vim.fn.foldclosed(1) == 1, "the first file did not fold")
      h.ex("JinDiff!")
      h.eventually(function()
        return view.meta(host, vim.fn.bufnr()) ~= before
      end, "never read again")
      h.eq(1, vim.fn.foldclosed(1))
      local second = find("g%.lua")
      h.eq(-1, vim.fn.foldclosed(second))
    end,
  },
  {
    "JinFile shows a file of a revision with the filetype of its path",
    function()
      workspace()
      h.ex("filetype on")
      h.ex("edit f.lua")
      h.ex("JinFile -r @- %")
      h.eventually(function()
        return h.lines()[2] == "b"
      end, "the old file is not shown")
      h.eq("lua", vim.fn.getbufvar(vim.fn.bufnr(), "&filetype"))
      h.eq(0, vim.fn.getbufvar(vim.fn.bufnr(), "&modifiable"))
    end,
  },
  {
    "JinLog leads from a change to its evolog",
    function()
      local dir = workspace()
      h.ex("JinLog -r @-")
      local meta = settle()
      local lnum = find("first change")
      act("evolog", lnum)
      h.eq("jin://" .. dir .. ";view=evolog#-r " .. meta.entries[lnum][1], vim.fn.bufname())
      settle()
      find("first change")
    end,
  },
  {
    "JinShow leads to the show view of the parent and back to its child",
    function()
      local dir = workspace()
      h.ex("JinShow")
      local change = settle().entries[1][1]
      act("parent", 1)
      h.truthy(vim.fn.bufname():find("^jin://.*;view=show#%l+$"), vim.fn.bufname())
      settle()
      find("first change")
      act("child", 1)
      h.eq("jin://" .. dir .. ";view=show#" .. change, vim.fn.bufname())
      settle()
    end,
  },
  {
    "JinFile leads to the annotation of the file, its parent version and its log",
    function()
      local dir = workspace()
      h.ex("JinFile -r @ f.lua")
      settle()
      local file = vim.fn.bufnr()
      act("annotate", 2)
      h.eq("jin://" .. dir .. ";view=annotate#-r @ -- f.lua", vim.fn.bufname())
      h.eventually(function()
        return view.meta(host, vim.fn.bufnr()) ~= nil and vim.fn.line(".") == 2
      end, "the annotation is not on line 2")
      h.ex("buffer " .. file)
      settle()
      act("parent", 1)
      h.truthy(vim.fn.bufname():find(";view=file#%-r %l+ f%.lua$"), vim.fn.bufname())
      h.eventually(function()
        return h.lines()[2] == "b"
      end, "the parent version is not shown")
      act("log", 1)
      settle()
      find("first change")
    end,
  },
  {
    "views map the default keys to actions",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      h.eq("<Plug>(jin-action-show)", vim.fn.maparg("<CR>", "n"))
      h.eq("<Plug>(jin-action-choice)", vim.fn.maparg("a", "n"))
      h.eq("<Plug>(jin-action-new:before)", vim.fn.maparg("o", "n"))
      h.eq("<Plug>(jin-action-undo)", vim.fn.maparg("u", "n"))
      h.eq("<Plug>(jin-action-diff)", vim.fn.maparg("<S-CR>", "n"))
      h.eq("<Plug>(jin-action-diff)", vim.fn.maparg("<C-CR>", "n"))
      h.eq("<Plug>(jin-action-yank:change)", vim.fn.maparg("y", "x"))
    end,
  },
  {
    "views leave a key the user mapped on the buffer as it is",
    function()
      workspace()
      h.ex("autocmd FileType jin-log ++once nnoremap <buffer> cw <Cmd>let g:jin_test_cw = 1<CR>")
      h.ex("JinLog")
      settle()
      h.eq("<Cmd>let g:jin_test_cw = 1<CR>", vim.fn.maparg("cw", "n"))
      h.eq("<Plug>(jin-action-commit)", vim.fn.maparg("cc", "n"))
    end,
  },
  {
    "<C-w><CR> opens in a window split the way 'diffopt' splits diffs",
    function()
      workspace()
      local diffopt = vim.fn.eval("&diffopt")
      for _, case in ipairs({
        { "internal,filler", "split" },
        { "internal,filler,vertical", "vsplit" },
      }) do
        vim.fn.execute("set diffopt=" .. case[1])
        h.ex("JinLog")
        settle()
        h.eq("<Plug>(jin-action-show:" .. case[2] .. ")", vim.fn.maparg("<C-w><CR>", "n"))
        h.ex("bwipeout")
      end
      vim.fn.execute("set diffopt=" .. diffopt)
    end,
  },
  {
    "JinShow maps gp and gc to the parent and the child",
    function()
      local dir = workspace()
      h.ex("JinShow")
      local change = settle().entries[1][1]
      h.ex("normal gp")
      h.truthy(vim.fn.bufname():find("^jin://.*;view=show#%l+$"), vim.fn.bufname())
      settle()
      h.ex("normal gc")
      h.eq("jin://" .. dir .. ";view=show#" .. change, vim.fn.bufname())
    end,
  },
  {
    "JinFile maps its default keys on its own buffer, not on other buffers of the filetype",
    function()
      workspace()
      h.ex("filetype plugin on")
      h.ex("JinFile -r @- f.lua")
      settle()
      h.eq("lua", vim.fn.getbufvar(vim.fn.bufnr(), "&filetype"))
      local keys = { a = "choice", ["."] = "repeat", ["?"] = "help" }
      keys.gp, keys.gc, keys["<CR>"] = "parent", "child", "annotate"
      for lhs, name in pairs(keys) do
        h.eq("<Plug>(jin-action-" .. name .. ")", vim.fn.maparg(lhs, "n"))
        h.eq(1, vim.fn.eval(("maparg('%s', 'n', 0, 1).buffer"):format(lhs)))
      end
      h.ex("edit f.lua")
      h.eq("lua", vim.fn.getbufvar(vim.fn.bufnr(), "&filetype"))
      -- Neovim maps gc itself, globally.
      for lhs in pairs(keys) do
        h.eq(0, vim.fn.eval(("get(maparg('%s', 'n', 0, 1), 'buffer', 0)"):format(lhs)))
      end
      h.ex("filetype plugin off")
    end,
  },
  {
    "JinFile's default keys lead to the parent version",
    function()
      workspace()
      h.ex("JinFile -r @ f.lua")
      settle()
      h.ex("normal gp")
      h.truthy(vim.fn.bufname():find(";view=file#%-r %l+ f%.lua$"), vim.fn.bufname())
      h.eventually(function()
        return h.lines()[2] == "b"
      end, "the parent version is not shown")
    end,
  },
  {
    "g:jin_file_disable_default_mappings keeps JinFile's keys unmapped",
    function()
      workspace()
      vim.fn.execute("let g:jin_file_disable_default_mappings = 1")
      h.ex("JinFile -r @- f.lua")
      settle()
      vim.fn.execute("unlet g:jin_file_disable_default_mappings")
      h.eq("", vim.fn.maparg("gp", "n"))
      h.eq("", vim.fn.maparg("?", "n"))
      h.truthy(vim.fn.maparg("<Plug>(jin-action-annotate)", "n") ~= "", "annotate is not mapped")
    end,
  },
  {
    "a view follows what jj did outside the editor once the editor regains focus",
    function()
      workspace()
      h.ex("JinLog -r @")
      settle()
      h.ex("doautocmd FocusGained")
      -- As another terminal, or an agent, would: jj itself, not :Jin.
      vim.fn.system("jj describe -m 'described outside'")
      h.eq(0, vim.fn.eval("v:shell_error"))
      h.ex("doautocmd FocusGained")
      h.eventually(function()
        return vim.fn.search("described outside", "nw") > 0
      end, function()
        return table.concat(h.lines(), "\n")
      end)
    end,
  },
  {
    "JinLog highlights the lines of the change under the cursor",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      local lnum = find("first change")
      h.ex(("call cursor(%d, 1) | doautocmd CursorMoved"):format(lnum))
      local bufnr = vim.fn.bufnr()
      local lines = {}
      if vim.api then
        local ns = vim.api.nvim_create_namespace("jin-cursor-entry")
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
          h.eq("JinCursorEntry", mark[4].line_hl_group)
          lines[#lines + 1] = mark[2] + 1
        end
      else
        local placed = vim.fn.sign_getplaced(bufnr, vim.dict({ group = "JinCursorEntry" }))
        for sign in placed[0].signs() do
          lines[#lines + 1] = sign.lnum
        end
        table.sort(lines)
        h.eq("no", vim.eval("&signcolumn"))
      end
      h.eq({ lnum - 1, lnum }, lines)
      h.eq("CursorLine", vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("JinCursorEntry")), "name"))
    end,
  },
  {
    "JinStatus highlights the line under the cursor, each line being one thing",
    function()
      workspace()
      h.ex("JinStatus")
      settle()
      h.truthy(#h.lines() >= 2, "the status has a line to move to")
      h.ex("call cursor(2, 1) | doautocmd CursorMoved")
      local bufnr = vim.fn.bufnr()
      local lines = {}
      if vim.api then
        local ns = vim.api.nvim_create_namespace("jin-cursor-entry")
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})) do
          lines[#lines + 1] = mark[2] + 1
        end
      else
        local placed = vim.fn.sign_getplaced(bufnr, vim.dict({ group = "JinCursorEntry" }))
        for sign in placed[0].signs() do
          lines[#lines + 1] = sign.lnum
        end
      end
      h.eq({ 2 }, lines)
    end,
  },
  {
    "the highlight of the change under the cursor leaves 'signcolumn' of other buffers alone",
    function()
      workspace()
      h.ex("set signcolumn=yes")
      h.ex("JinLog")
      settle()
      local log = vim.fn.bufnr()
      h.ex("doautocmd CursorMoved")
      h.ex("enew")
      h.eq("yes", vim.fn.eval("&signcolumn"))
      h.ex("buffer " .. log)
      h.ex("doautocmd CursorMoved")
      if not vim.api then
        h.eq("no", vim.fn.eval("&signcolumn"))
      end
      h.ex("enew")
      h.eq("yes", vim.fn.eval("&signcolumn"))
      h.ex("set signcolumn&")
    end,
  },
  {
    "a view left and come back to with CTRL-O keeps the cursor where it was",
    function()
      workspace()
      h.ex("JinLog")
      settle()
      local lnum = find("first change")
      h.truthy(lnum > 1, "the change is on the first line")
      vim.fn.cursor(lnum, 1)
      h.ex("JinOpLog")
      settle()
      vim.v.errmsg = ""
      h.ex('execute "normal! \\<C-o>"')
      -- The jump lands before jj answers, in the buffer read again.
      h.eq("", vim.v.errmsg)
      settle()
      h.eq(lnum, vim.fn.line("."))
    end,
  },
  {
    "JinEvolog left with <CR> and come back to with <C-o> raises no error",
    function()
      workspace()
      for i = 1, 4 do
        h.eq(0, jin.jj({ "describe", "-m", "version " .. i }).code)
      end
      h.ex("JinEvolog")
      settle()
      local lnum = find("version 2")
      h.truthy(lnum > 1, "version 2 is on the first line")
      vim.fn.cursor(lnum, 1)
      h.ex('execute "normal \\<CR>"')
      settle()
      h.truthy(
        vim.fn.bufname():find("view=interdiff", 1, true),
        "no interdiff: " .. vim.fn.bufname()
      )
      vim.v.errmsg = ""
      h.ex('execute "normal! \\<C-o>"')
      h.eq("", vim.v.errmsg)
      -- Before jj answers, the buffer read again already reaches the line a
      -- jump back, or a plugin restoring the view, lands on.
      h.truthy(vim.fn.line("$") >= lnum, "the buffer read again ends above line " .. lnum)
      settle()
      h.eq(lnum, vim.fn.line("."))
    end,
  },
  {
    "a view read while no window shows it maps its actions once one does",
    function()
      workspace()
      h.ex("JinLog")
      local bufnr = vim.fn.bufnr()
      h.ex("setlocal bufhidden=hide")
      h.ex("enew")
      h.eventually(function()
        return view.meta(host, bufnr) ~= nil
      end, "the buffer was never read")
      h.ex("buffer " .. bufnr)
      h.truthy(vim.fn.maparg("<Plug>(jin-action-show)", "n") ~= "", "show is not mapped")
      h.truthy(vim.fn.maparg("<Plug>(jin-action-show)", "x") ~= "", "show is not mapped")
    end,
  },
  {
    "a file view read while no window shows it maps its default keys once one does",
    function()
      workspace()
      h.ex("JinFile -r @- f.lua")
      local bufnr = vim.fn.bufnr()
      h.ex("setlocal bufhidden=hide")
      h.ex("enew")
      h.eventually(function()
        return view.meta(host, bufnr) ~= nil
      end, "the buffer was never read")
      h.ex("buffer " .. bufnr)
      h.eq("<Plug>(jin-action-parent)", vim.fn.maparg("gp", "n"))
    end,
  },
  {
    "completes view commands with jj's arguments of the subcommand",
    function()
      workspace()
      local flags = host.list(vim.fn.getcompletion("JinLog --no-g", "cmdline"))
      h.eq({ "--no-graph" }, flags)
      local options = host.list(vim.fn.getcompletion("JinDiff ++o", "cmdline"))
      h.eq({ "++opener=" }, options)
    end,
  },
}
