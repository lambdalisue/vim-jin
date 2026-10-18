local h = dofile("test/host/helper.lua")
local host = require("jin.host")
local jin = require("jin")
local view = require("jin.view")

h.ex("source plugin/jin.vim")

local config = h.tempdir() .. "/config.toml"
assert(io.open(config, "w")):close()
vim.fn.setenv("JJ_CONFIG", config)

local SOURCE = { "local answer = 42", "print(answer)", "return answer" }

local function write(path, lines)
  local f = assert(io.open(path, "w"))
  f:write(table.concat(lines, "\n") .. "\n")
  f:close()
end

---A workspace whose @ adds f.lua.
local function workspace()
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  write(dir .. "/f.lua", SOURCE)
  jin.jj({ "describe", "-m", "add f" })
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

local NOT_ANNOTATIONS = { JinSelectedColumn = true, JinSelectedSign = true }

---Per line of the current buffer, the virtual texts shown before it, each
---as { text, group }: extmarks in Neovim, text properties in Vim.
local function annotations()
  local bufnr = vim.fn.bufnr()
  local count = vim.fn.line("$")
  local found = {}
  for lnum = 1, count do
    found[lnum] = {}
  end
  if vim.api then
    local ns = vim.api.nvim_create_namespace("jin")
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      for _, chunk in ipairs(mark[4].virt_text or {}) do
        table.insert(found[mark[2] + 1], { chunk[1], chunk[2] or "" })
      end
    end
  else
    for lnum = 1, count do
      local props = {}
      for prop in vim.fn.prop_list(lnum, vim.dict({ bufnr = bufnr }))() do
        -- The selection column is no annotation.
        if prop.text and not NOT_ANNOTATIONS[prop.type] then
          props[#props + 1] = { prop.text, prop.type == "JinAnnotation" and "" or prop.type }
        end
      end
      -- prop_list lists the virtual texts of a column newest first.
      for i = #props, 1, -1 do
        table.insert(found[lnum], props[i])
      end
    end
  end
  return found
end

---The width of the selection column before every line of a view that can select.
local function column_width()
  return vim.fn.strdisplaywidth(require("jin.glyph").resolve(host).selected) + 1
end

---The annotation of each line of the current buffer as one string.
local function annotation_texts()
  local texts = {}
  for lnum, chunks in ipairs(annotations()) do
    local parts = {}
    for i, chunk in ipairs(chunks) do
      parts[i] = chunk[1]
    end
    texts[lnum] = table.concat(parts)
  end
  return texts
end

---The lines of the current buffer highlighted as `group`, in order, each as
---{ lnum, priority }: extmarks in Neovim, signs in Vim.
local function highlighted(group)
  local bufnr = vim.fn.bufnr()
  local found = {}
  if vim.api then
    local ns = vim.api.nvim_create_namespace(
      group == "JinSelected" and "jin-selected" or "jin-cursor-change"
    )
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      h.eq(group, mark[4].line_hl_group)
      found[#found + 1] = { mark[2] + 1, mark[4].priority }
    end
  else
    local placed = vim.fn.sign_getplaced(bufnr, vim.dict({ group = group }))
    for sign in placed[0].signs() do
      found[#found + 1] = { sign.lnum, sign.priority }
    end
    table.sort(found, function(a, b)
      return a[1] < b[1]
    end)
  end
  return found
end

---The line numbers of `found`, as `highlighted` returns them.
local function lnums(found)
  local out = {}
  for i, item in ipairs(found) do
    out[i] = item[1]
  end
  return out
end

---Open :JinAnnotate f.lua and wait until it is read.
local function annotate()
  h.ex("filetype plugin on")
  h.ex("JinAnnotate f.lua")
  local meta = settle()
  h.ex("filetype plugin off")
  return meta
end

return {
  {
    "JinAnnotate wraps a line after the annotation, in the windows showing it alone",
    function()
      workspace()
      h.ex("set nobreakindent breakindentopt=min:30,sbr")
      annotate()
      local shift = vim.fn.strdisplaywidth(annotation_texts()[1]) + column_width()
      local function options()
        return { vim.fn.eval("&l:breakindent"), vim.fn.eval("&l:breakindentopt") }
      end
      h.eq({ 1, "min:30,sbr,shift:" .. shift }, options())
      local bufnr = vim.fn.bufnr()
      h.ex("enew")
      h.eq({ 0, "min:30,sbr" }, options())
      h.ex("buffer " .. bufnr)
      settle()
      h.eq({ 1, "min:30,sbr,shift:" .. shift }, options())
      h.ex("split")
      h.eq({ 1, "min:30,sbr,shift:" .. shift }, options())
      h.ex("enew")
      h.eq({ 0, "min:30,sbr" }, options())
      h.ex("only")
      h.ex("set nobreakindent breakindentopt&")
    end,
  },
  {
    "JinAnnotate wraps a line beside the annotation however narrow the window, unless min is set",
    function()
      workspace()
      h.ex("set breakindentopt=sbr")
      annotate()
      local shift = vim.fn.strdisplaywidth(annotation_texts()[1]) + column_width()
      h.eq("sbr,min:1,shift:" .. shift, vim.fn.eval("&l:breakindentopt"))
      h.ex("set breakindentopt&")
    end,
  },
  {
    "JinAnnotate goes on with a wrapped line after the annotation",
    function()
      if not vim.api then
        -- Vim in Ex mode draws no screen to wrap lines on.
        return
      end
      local dir = workspace()
      write(dir .. "/f.lua", { SOURCE[1], SOURCE[2], SOURCE[3], "-- " .. ("long "):rep(60) })
      annotate()
      h.ex("setlocal wrap")
      local info = host.list(vim.fn.getwininfo(vim.fn.win_getid()))[1]
      local shift = vim.fn.strdisplaywidth(annotation_texts()[1]) + column_width()
      local first = vim.fn.screenpos(0, 4, 1).row
      local col = 1
      while vim.fn.screenpos(0, 4, col).row == first do
        col = col + 1
      end
      h.eq(info.wincol + info.textoff + shift, vim.fn.screenpos(0, 4, col).col)
    end,
  },
  {
    "JinAnnotate shows the annotation after the selection column",
    function()
      workspace()
      h.ex("let g:jin_glyph_preset = 'ascii'")
      annotate()
      h.ex("unlet g:jin_glyph_preset")
      local bufnr = vim.fn.bufnr()
      require("jin.host.entry").action(bufnr, "select", 1, 1)
      local info = host.list(vim.fn.getwininfo(vim.fn.win_getid()))[1]
      local before = vim.fn.strdisplaywidth(annotation_texts()[1]) + column_width()
      h.eq(info.wincol + info.textoff + before, vim.fn.screenpos(info.winid, 1, 1).curscol)
      -- Virtual texts at one column show the one of the lower priority first
      -- in Neovim, of the higher in Vim.
      if vim.api then
        local function priorities(name)
          local found = {}
          local ns = vim.api.nvim_create_namespace(name)
          for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { 0, 0 }, { details = true }))
          do
            found[#found + 1] = mark[4].priority
          end
          return found
        end
        local column, annotation = priorities("jin-selected-column"), priorities("jin")
        h.eq(1, #column)
        for _, priority in ipairs(annotation) do
          h.truthy(column[1] < priority, ("column %d, annotation %d"):format(column[1], priority))
        end
      else
        local function priority(name)
          return vim.fn.prop_type_get(name).priority or 0
        end
        for prop in vim.fn.prop_list(1, vim.dict({ bufnr = bufnr }))() do
          if prop.text and not NOT_ANNOTATIONS[prop.type] then
            h.truthy(priority("JinSelectedSign") > priority(prop.type), prop.type)
            h.truthy(priority("JinSelectedColumn") > priority(prop.type), prop.type)
          end
        end
      end
    end,
  },
  {
    "JinAnnotate highlights every line the change under the cursor wrote",
    function()
      local dir = workspace()
      jin.jj({ "new" })
      write(dir .. "/f.lua", { SOURCE[1], "print(answer + 1)", SOURCE[3] })
      annotate()
      h.ex("call cursor(1, 1) | doautocmd CursorMoved")
      h.eq({ 1, 3 }, lnums(highlighted("JinCursorChange")))
      h.ex("call cursor(2, 1) | doautocmd CursorMoved")
      h.eq({ 2 }, lnums(highlighted("JinCursorChange")))
      h.eq(
        "CursorLine",
        vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID("JinCursorChange")), "name")
      )
    end,
  },
  {
    "JinAnnotate shows a selected line as selected under the highlight of the change",
    function()
      workspace()
      annotate()
      require("jin.host.entry").action(vim.fn.bufnr(), "select", 1, 1)
      h.ex("call cursor(1, 1) | doautocmd CursorMoved")
      local change = highlighted("JinCursorChange")[1]
      local selected = highlighted("JinSelected")[1]
      h.eq({ 1, 1 }, { change[1], selected[1] })
      h.truthy(change[2] < selected[2], "the highlight of the change hides the selection")
      require("jin.host.entry").action(vim.fn.bufnr(), "select", 1, 1)
    end,
  },
  {
    "JinAnnotate shows the file in one window, highlighted as the file",
    function()
      local dir = workspace()
      annotate()
      h.eq(1, vim.fn.winnr("$"))
      h.eq("jin://" .. dir .. ";view=annotate#f.lua", vim.fn.bufname())
      h.eq("lua", vim.fn.getbufvar(vim.fn.bufnr(), "&filetype"))
      h.eq(SOURCE, h.lines())
    end,
  },
  {
    "JinAnnotate shows before each line the change that wrote it, lined up",
    function()
      workspace()
      local meta = annotate()
      local change = meta.entries[1][1]
      local texts = annotation_texts()
      h.eq(#SOURCE, #texts)
      for lnum, text in ipairs(texts) do
        h.truthy(
          change:sub(1, 8) == text:sub(1, 8),
          "no change ID before line " .. lnum .. ": " .. text
        )
        h.eq(vim.fn.strdisplaywidth(texts[1]), vim.fn.strdisplaywidth(text))
        h.truthy(text:find(" $"), "nothing parts the annotation from the line: " .. text)
      end
    end,
  },
  {
    "JinAnnotate keeps jj's colors in the annotation",
    function()
      workspace()
      annotate()
      local colored = false
      for _, chunk in ipairs(annotations()[1]) do
        if chunk[2]:find("^JinAnsi") then
          colored = true
        end
      end
      h.truthy(colored, "the annotation has no color of jj's")
    end,
  },
  {
    "<C-o> after JinAnnotate shows the previous buffer in the same window",
    function()
      local dir = workspace()
      h.ex("edit " .. vim.fn.fnameescape(dir .. "/f.lua"))
      local file = vim.fn.bufnr()
      local winid = vim.fn.win_getid()
      annotate()
      h.eq(winid, vim.fn.win_getid())
      h.ex('execute "normal \\<C-o>"')
      h.eq({ 1, winid, file }, { vim.fn.winnr("$"), vim.fn.win_getid(), vim.fn.bufnr() })
    end,
  },
  {
    "<CR> on a line of the annotation shows the change that wrote it",
    function()
      local dir = workspace()
      local meta = annotate()
      local change = meta.entries[2][1]
      h.ex("2")
      h.ex('execute "normal \\<CR>"')
      h.eq("jin://" .. dir .. ";view=show#" .. change, vim.fn.bufname())
    end,
  },
  {
    "JinAnnotate left with <CR> and come back to with <C-o> sets up its filetype again",
    function()
      workspace()
      local bufnr = vim.fn.bufnr()
      annotate()
      bufnr = vim.fn.bufnr()
      -- Syntax and plugins go with the buffer when it is unloaded; FileType
      -- is what sets them up again.
      vim.g.jin_filetype_set = 0
      h.ex("autocmd FileType lua let g:jin_filetype_set += 1")
      h.ex("2")
      h.ex('execute "normal \\<CR>"')
      settle()
      h.ex('execute "normal! \\<C-o>"')
      h.eventually(function()
        return vim.fn.bufnr() == bufnr and view.meta(host, bufnr) ~= nil
      end, "never came back to the annotation")
      h.truthy(vim.g.jin_filetype_set >= 1, "FileType did not run on coming back")
      h.ex("autocmd! FileType lua")
    end,
  },
  {
    "annotate and file turn the annotation of a file view on and off, on the same line",
    function()
      local dir = workspace()
      h.ex("JinFile f.lua")
      settle()
      h.ex([[execute "normal 2G\<Plug>(jin-action-annotate)"]])
      h.eq("jin://" .. dir .. ";view=annotate#-r @ -- f.lua", vim.fn.bufname())
      settle()
      h.eq({ 1, 2 }, { vim.fn.winnr("$"), vim.fn.line(".") })
      h.eq(#SOURCE, #annotation_texts())
      h.ex([[execute "normal 3G\<Plug>(jin-action-file)"]])
      h.eq("jin://" .. dir .. ";view=file#-r @ f.lua", vim.fn.bufname())
      settle()
      h.eq({ 1, 3 }, { vim.fn.winnr("$"), vim.fn.line(".") })
      h.eq({ {}, {}, {} }, annotations())
    end,
  },
  {
    "y in visual mode yanks the changes of the lines selected",
    function()
      workspace()
      annotate()
      h.eq("<Plug>(jin-action-yank:change)", vim.fn.maparg("y", "x"))
      h.eq("", vim.fn.maparg("y", "n"))
    end,
  },
  {
    "the annotation follows the file when jj changes it",
    function()
      local dir = workspace()
      annotate()
      local bufnr = vim.fn.bufnr()
      local first = annotations()[1]
      write(dir .. "/f.lua", { "local answer = 42", "return answer" })
      h.ex("doautocmd User JinCommandPost")
      h.eventually(function()
        return #host.list(vim.fn.getbufline(bufnr, 1, "$")) == 2
      end, "the buffer does not show the file as jj now has it")
      h.eq({ "local answer = 42", "return answer" }, h.lines())
      local found = annotations()
      -- The time of the working copy moves on with its snapshot.
      h.eq({ #first, first[1], first[2] }, { #found[1], found[1][1], found[1][2] })
      h.truthy(#found[2] > 0, "the second line lost its annotation")
    end,
  },
}
