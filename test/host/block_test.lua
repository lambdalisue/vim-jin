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

---A workspace whose @- holds f.lua as a, b, c and whose @ removes b, adds d
---and adds g.lua.
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  write(dir .. "/f.lua", { "a", "b", "c" })
  jin.jj({ "describe", "-m", "first change" })
  jin.jj({ "new" })
  write(dir .. "/f.lua", { "a", "c", "d" })
  write(dir .. "/g.lua", { "g" })
  return dir
end

---Wait until the current buffer has been read.
local function settle()
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
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

---The line of the cursor after typing `keys` on line `from`.
local function after(from, keys)
  vim.fn.cursor(from, 1)
  h.ex('execute "normal ' .. keys .. '"')
  return vim.fn.line(".")
end

---The log of @, @- and the root, its changes starting on lines 1, 3 and 5.
local function log()
  workspace()
  h.ex("JinLog")
  settle()
  h.eq(3, find("first change") - 1)
  h.eq(5, find("root%(%)"))
end

return {
  {
    "]] and [[ go to the first line of the next and previous change of the log",
    function()
      log()
      h.eq(3, after(1, "]]"))
      h.eq(3, after(4, "[["))
      h.eq(1, after(3, "[["))
    end,
  },
  {
    "a count goes as many changes, and stops at the last one there is",
    function()
      log()
      h.eq(5, after(1, "2]]"))
      h.eq(5, after(1, "9]]"))
      h.eq(1, after(5, "9[["))
    end,
  },
  {
    "the cursor stays where no change lies that way",
    function()
      log()
      h.eq(5, after(5, "]]"))
      h.eq(1, after(1, "[["))
    end,
  },
  {
    "]] leaves where it came from in the jumplist",
    function()
      log()
      after(1, "2]]")
      h.ex('execute "normal! \\<C-o>"')
      h.eq(1, vim.fn.line("."))
    end,
  },
  {
    "]] extends the selection in visual mode",
    function()
      log()
      vim.fn.cursor(1, 1)
      h.ex("normal V]]y")
      h.eq({ 1, 3 }, { vim.fn.line("'<"), vim.fn.line("'>") })
    end,
  },
  {
    "an operator takes the lines up to the next change, as with Vim's own ]]",
    function()
      log()
      vim.fn.cursor(1, 1)
      h.ex("normal y]]")
      h.eq({ 1, 2 }, { vim.fn.line("'["), vim.fn.line("']") })
    end,
  },
  {
    "]] goes from file to file in a diff",
    function()
      workspace()
      h.ex("JinDiff")
      settle()
      local f, g = find("^Modified regular file f%.lua:"), find("^Added regular file g%.lua:")
      h.eq(math.max(f, g), after(math.min(f, g), "]]"))
    end,
  },
  {
    "]] goes from the header of a change to its files, and on, in a show",
    function()
      workspace()
      h.ex("JinShow")
      settle()
      local f, g = find("^Modified regular file f%.lua:"), find("^Added regular file g%.lua:")
      h.eq(math.min(f, g), after(1, "]]"))
      h.eq(math.max(f, g), after(1, "2]]"))
    end,
  },
  {
    "]] goes to the next run of lines another change wrote in an annotation",
    function()
      workspace()
      h.ex("JinAnnotate f.lua")
      settle()
      h.eq(3, after(1, "]]"))
      h.eq(1, after(3, "[["))
    end,
  },
  {
    "]] and [[ keep Vim's meaning in a view of no blocks",
    function()
      workspace()
      h.ex("JinStatus")
      settle()
      h.eq("", vim.fn.maparg("]]", "n"))
      h.eq("", vim.fn.maparg("<Plug>(jin-next-block)", "n"))
    end,
  },
  {
    "a mapping of ]] the buffer has of its own is left alone",
    function()
      workspace()
      h.ex("autocmd FileType jin-log ++once nnoremap <buffer> ]] <Cmd>let g:jin_test_own = 1<CR>")
      h.ex("JinLog")
      settle()
      h.eq("<Cmd>let g:jin_test_own = 1<CR>", vim.fn.maparg("]]", "n"))
      h.eq("<Plug>(jin-next-block)", vim.fn.maparg("]]", "x"))
    end,
  },
  {
    "g:jin_log_disable_default_mappings keeps ]] unmapped, its <Plug> still there",
    function()
      workspace()
      vim.fn.execute("let g:jin_log_disable_default_mappings = 1")
      h.ex("JinLog")
      settle()
      vim.fn.execute("unlet g:jin_log_disable_default_mappings")
      h.eq("", vim.fn.maparg("]]", "n"))
      for _, mode in ipairs({ "n", "x", "o" }) do
        h.truthy(vim.fn.maparg("<Plug>(jin-prev-block)", mode) ~= "", "not mapped in " .. mode)
      end
      vim.fn.cursor(1, 1)
      h.ex([[execute "normal \<Plug>(jin-next-block)"]])
      h.eq(3, vim.fn.line("."))
    end,
  },
}
