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

---A workspace whose @- adds f.lua and whose @ adds `more` lines to it, or
---one.
local function two_changes(more)
  local dir = h.tempdir()
  h.eq(0, jin.jj({ "git", "init" }, { cwd = dir }).code)
  h.ex("cd " .. vim.fn.fnameescape(dir))
  write(dir .. "/f.lua", SOURCE)
  jin.jj({ "describe", "-m", "add f" })
  jin.jj({ "new" })
  local lines = { SOURCE[1], SOURCE[2], SOURCE[3] }
  for i = 1, more or 1 do
    lines[#lines + 1] = "-- the end " .. i
  end
  write(dir .. "/f.lua", lines)
  jin.jj({ "describe", "-m", "end f\n\nWith a comment saying so." })
  -- A case before may have left the window smaller.
  h.ex("silent! only | resize")
  return dir
end

---Open :JinAnnotate f.lua and wait until it is read.
local function annotate()
  h.ex("JinAnnotate f.lua")
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
end

---The detail panel shown, as its box on the screen, its border included,
---counted from 1, and its lines; nil when none shows.
local function panel()
  if vim.api then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local float = vim.api.nvim_win_get_config(win)
      if float.relative ~= "" then
        local pos = vim.api.nvim_win_get_position(win)
        return {
          top = pos[1] + 1,
          left = pos[2] + 1,
          width = float.width + 2,
          height = float.height + 2,
          focusable = float.focusable,
          corner = type(float.border[1]) == "table" and float.border[1][1] or float.border[1],
          footer = float.footer,
          footer_pos = float.footer_pos,
          lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false),
        }
      end
    end
    return nil
  end
  for id in vim.fn.popup_list()() do
    local pos = vim.fn.popup_getpos(id)
    return {
      top = pos.line,
      left = pos.col,
      width = pos.width,
      height = pos.height,
      focusable = false,
      corner = host.list(vim.fn.popup_getoptions(id).borderchars)[5],
      lines = host.list(vim.fn.getbufline(vim.fn.winbufnr(id), 1, "$")),
    }
  end
  return nil
end

---Wait until the panel shows `first` as its first line, and return it.
local function showing(first)
  h.eventually(function()
    local shown = panel()
    return shown ~= nil and shown.lines[1] == first
  end, function()
    local shown = panel()
    return "the panel shows " .. (shown and ("'" .. tostring(shown.lines[1]) .. "'") or "nothing")
  end)
  return assert(panel())
end

---The room made around the lines of the current buffer: how many virtual
---lines before the first and after the last, and on how many lines virtual
---columns after the text, and how wide.
local function room()
  local bufnr = vim.fn.bufnr()
  local found = { above = 0, below = 0, right = 0, width = 0 }
  if vim.api then
    local ns = vim.api.nvim_create_namespace("jin-detail-room")
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })) do
      local d = mark[4]
      if d.virt_lines then
        local side = d.virt_lines_above and "above" or "below"
        found[side] = found[side] + #d.virt_lines
      elseif d.virt_text then
        found.right = found.right + 1
        found.width = vim.fn.strdisplaywidth(d.virt_text[1][1])
      end
    end
    return found
  end
  for lnum = 1, vim.fn.line("$") do
    for prop in
      vim.fn.prop_list(lnum, vim.dict({ bufnr = bufnr, types = vim.list({ "JinDetailRoom" }) }))()
    do
      if prop.text_align == "above" or prop.text_align == "below" then
        found[prop.text_align] = found[prop.text_align] + 1
      else
        found.right = found.right + 1
        found.width = vim.fn.strdisplaywidth(prop.text)
      end
    end
  end
  return found
end

---Where the current window lies on the screen.
local function area()
  local info = host.list(vim.fn.getwininfo(vim.fn.win_getid()))[1]
  return { top = info.winrow, left = info.wincol, height = info.height, width = info.width }
end

local function reset()
  for _, name in ipairs({
    "detail",
    "detail_position",
    "detail_height",
    "detail_width",
    "annotate_detail_height",
    "glyph_preset",
  }) do
    if vim.fn.exists("g:jin_" .. name) == 1 then
      h.ex("unlet g:jin_" .. name)
    end
  end
  -- A window of its own, as the panel is shown or hidden per window.
  h.ex("new | only")
end

---Open the view of `command` with a panel tall enough for all it tells, in
---plain ASCII, put the cursor on the line holding `pattern`, and wait until
---the panel holds `wanted`; the lines it shows then.
local function telling(command, pattern, wanted)
  reset()
  h.ex("let g:jin_detail_height = 14 | let g:jin_glyph_preset = 'ascii'")
  h.ex(command)
  local bufnr = vim.fn.bufnr()
  h.eventually(function()
    return view.meta(host, bufnr) ~= nil
  end, "the buffer was never read")
  h.ex(("call cursor(search('%s', 'w'), 1) | doautocmd CursorMoved"):format(pattern))
  local shown
  h.eventually(function()
    shown = panel()
    for _, line in ipairs(shown and shown.lines or {}) do
      if line == wanted then
        return true
      end
    end
    return false
  end, function()
    return "the panel shows " .. table.concat(shown and shown.lines or {}, " | ")
  end)
  h.ex("unlet g:jin_glyph_preset")
  return shown.lines
end

return {
  {
    "the detail panel docks at the bottom of the window by default, room made after the last line",
    function()
      reset()
      two_changes()
      annotate()
      h.ex("call cursor(1, 1) | doautocmd CursorMoved")
      local shown = showing("add f")
      local win = area()
      local third = math.floor(win.height / 3)
      h.eq({ win.top + win.height - third, win.left, win.width, third }, {
        shown.top,
        shown.left,
        shown.width,
        shown.height,
      })
      h.eq(false, shown.focusable)
      h.eq({ above = 0, below = third, right = 0, width = 0 }, room())
      h.eq(SOURCE[1], vim.fn.getline(1))
      h.eq(4, vim.fn.line("$"))
      h.truthy(vim.fn.bufname():match("^jin://") ~= nil, "the panel took the focus")
    end,
  },
  {
    "the detail panel takes the fraction of the window g:jin_{view}_detail_height gives its view",
    function()
      reset()
      h.ex("let g:jin_detail_height = 5 | let g:jin_annotate_detail_height = 0.5")
      two_changes()
      annotate()
      local shown = showing("add f")
      h.eq(math.floor(area().height / 2), shown.height)
      reset()
    end,
  },
  {
    "the detail panel swaps its content as the cursor moves, at its size",
    function()
      reset()
      -- Room for the body and the files after it, and in Vim for the key
      -- hiding it.
      h.ex("let g:jin_detail_height = 14")
      two_changes()
      annotate()
      h.ex("call cursor(1, 1) | doautocmd CursorMoved")
      local before = showing("add f")
      h.ex("call cursor(4, 1) | doautocmd CursorMoved")
      local after = showing("end f")
      h.eq(
        { before.top, before.left, before.width, before.height },
        { after.top, after.left, after.width, after.height }
      )
      h.eq(#before.lines, #after.lines)
      h.eventually(function()
        for _, line in ipairs(panel().lines) do
          if line == "With a comment saying so." then
            return true
          end
        end
        return false
      end, "jj never told the description")
      reset()
    end,
  },
  {
    "the detail panel docks at the top with g:jin_detail_position = 'top', room made before the first line",
    function()
      reset()
      h.ex("let g:jin_detail_position = 'top'")
      two_changes()
      annotate()
      local shown = showing("add f")
      local win = area()
      local third = math.floor(win.height / 3)
      h.eq({ win.top, win.width, third }, { shown.top, shown.width, shown.height })
      h.eq({ above = third, below = 0, right = 0, width = 0 }, room())
      if vim.api then
        h.truthy(vim.fn.winline() > third, "line 1 is under the panel")
      end
      reset()
    end,
  },
  {
    "the detail panel moves away from the half of the window the cursor is in with 'auto'",
    function()
      reset()
      h.ex("let g:jin_detail_position = 'auto'")
      h.ex("let g:jin_detail_height = 5")
      two_changes(20)
      annotate()
      h.ex("resize 10")
      h.ex("call cursor(1, 1) | doautocmd CursorMoved")
      local win = area()
      h.eq(win.top + win.height - 5, showing("add f").top)
      h.ex("call cursor(9, 1) | doautocmd CursorMoved")
      h.eq(win.top, showing("end f").top)
      h.eq({ above = 0, below = 0, right = 0, width = 0 }, room())
      reset()
    end,
  },
  {
    "the detail panel docks at the right with 'right', room made after every line of a window not wrapping",
    function()
      reset()
      h.ex("let g:jin_detail_position = 'right'")
      h.ex("let g:jin_detail_width = 30")
      two_changes()
      annotate()
      h.ex("setlocal nowrap | doautocmd CursorMoved")
      local shown = showing("add f")
      local win = area()
      h.eq({ win.top, win.left + win.width - 30, 30, win.height }, {
        shown.top,
        shown.left,
        shown.width,
        shown.height,
      })
      h.eq({ above = 0, below = 0, right = 4, width = 30 }, room())
      reset()
    end,
  },
  {
    "the detail panel keeps the cursor out from under it",
    function()
      reset()
      two_changes(40)
      annotate()
      h.ex("resize 20")
      h.ex("normal! G")
      h.ex("doautocmd CursorMoved")
      showing("end f")
      local above = 20 - math.floor(20 / 3)
      h.truthy(
        vim.fn.winline() <= above,
        "the cursor is under the panel on row " .. vim.fn.winline()
      )
      h.eq(vim.fn.line("$"), vim.fn.line("."))
    end,
  },
  {
    "the detail panel at the right keeps the cursor out from under it, the selection column counted",
    function()
      reset()
      h.ex("let g:jin_detail_position = 'right'")
      h.ex("let g:jin_detail_width = 30")
      local dir = two_changes()
      write(dir .. "/f.lua", { SOURCE[1], "-- " .. ("long "):rep(60), SOURCE[3] })
      annotate()
      h.ex("setlocal nowrap")
      h.ex("call cursor(2, 1) | normal! $")
      h.ex("doautocmd CursorMoved")
      showing("end f")
      local info = host.list(vim.fn.getwininfo(vim.fn.win_getid()))[1]
      local at = vim.fn.screenpos(info.winid, 2, vim.fn.col(".")).curscol - info.wincol + 1
      h.truthy(at > 0 and at <= info.width - 30, "the cursor is in column " .. at)
      reset()
    end,
  },
  {
    "K hides the detail panel in its window alone, and shows it again",
    function()
      reset()
      -- Rows enough for the title in the split of the annotation.
      h.ex("let g:jin_detail_height = 8")
      two_changes()
      annotate()
      showing("add f")
      h.ex("normal K")
      h.eq(nil, panel())
      h.eq({ above = 0, below = 0, right = 0, width = 0 }, room())
      h.ex("call cursor(4, 1) | doautocmd CursorMoved")
      h.eq(nil, panel())
      h.ex("split")
      h.ex("doautocmd WinEnter")
      showing("end f")
      h.ex("wincmd j")
      h.eq(nil, panel())
      h.ex("normal K")
      showing("end f")
      h.ex("silent! only")
    end,
  },
  {
    "the detail panel tells dimmed at its bottom right the key that hides it",
    function()
      reset()
      two_changes()
      annotate()
      local shown = showing("add f")
      if vim.api then
        h.eq({
          { " ", "JinDetailBorder" },
          { "Press K to hide", "JinDetailDim" },
          { " ", "JinDetailBorder" },
        }, shown.footer)
        h.eq("right", shown.footer_pos)
      else
        local last = shown.lines[#shown.lines]
        h.eq("Press K to hide", last:sub(-15))
        h.eq(shown.width - 2, vim.fn.strdisplaywidth(last))
      end
      h.ex("nunmap <buffer> K")
      h.ex("nmap <buffer> gK <Plug>(jin-action-detail)")
      h.ex("doautocmd WinEnter")
      h.eventually(function()
        local now = panel()
        if not now then
          return false
        end
        if vim.api then
          return now.footer ~= nil
            and now.footer[2] ~= nil
            and now.footer[2][1] == "Press gK to hide"
        end
        return now.lines[#now.lines]:sub(-16) == "Press gK to hide"
      end, "the panel never named gK")
      h.ex("nunmap <buffer> gK")
      h.ex("doautocmd WinEnter")
      h.eventually(function()
        local now = panel()
        if not now then
          return false
        end
        if vim.api then
          return now.footer == nil or #now.footer == 0
        end
        return now.lines[#now.lines] == ""
      end, "the panel still names a key")
      reset()
    end,
  },
  {
    "the detail panel starts hidden in every window with g:jin_detail = v:false",
    function()
      reset()
      h.ex("let g:jin_detail = v:false")
      two_changes()
      annotate()
      h.ex("sleep 50m")
      h.eq(nil, panel())
      h.ex("normal K")
      showing("add f")
      reset()
    end,
  },
  {
    "the detail panel closes when its window is left, and shows again when it is entered",
    function()
      reset()
      -- Rows enough for the title in the split of the annotation.
      h.ex("let g:jin_detail_height = 8")
      two_changes()
      annotate()
      showing("add f")
      h.ex("new")
      h.eq(nil, panel())
      h.ex("wincmd j")
      showing("add f")
      h.ex("silent! only")
    end,
  },
  {
    "the detail panel draws with the glyphs of g:jin_glyph_preset and g:jin_glyphs",
    function()
      reset()
      h.ex("let g:jin_glyph_preset = 'ascii'")
      h.ex("let g:jin_glyphs = {'change': '~'}")
      two_changes()
      annotate()
      local shown = showing("add f")
      h.ex("unlet g:jin_glyph_preset g:jin_glyphs")
      h.eq("+", shown.corner)
      h.eq("~ Change  ", shown.lines[2]:sub(1, 10))
    end,
  },
  {
    "the detail panel of the log tells of a change the files it changes",
    function()
      two_changes()
      -- The change without a body, whose files come right after its date
      -- even in the small window of Vim.
      local lines = telling("JinLog", "add f", "Files   1 file  +3 -0")
      h.eq("add f", lines[1])
      local found = false
      for _, line in ipairs(lines) do
        found = found or line == "        A +3 -0 f.lua"
      end
      h.truthy(found, table.concat(lines, " | "))
      reset()
    end,
  },
  {
    "the detail panel draws on the background of Normal",
    function()
      h.ex("highlight clear")
      h.ex("highlight Normal guifg=#e0e0e0 guibg=#102030 ctermfg=252 ctermbg=17")
      h.ex("highlight FloatBorder guifg=#a0b0c0 guibg=#ffffff ctermfg=7 ctermbg=15")
      h.ex("doautocmd ColorScheme")
      local function attr(group, what, mode)
        return vim.fn.synIDattr(vim.fn.synIDtrans(vim.fn.hlID(group)), what, mode)
      end
      h.eq(vim.fn.hlID("Normal"), vim.fn.synIDtrans(vim.fn.hlID("JinDetailBody")))
      h.eq({ "#a0b0c0", "#102030", "7", "17" }, {
        attr("JinDetailBorder", "fg#", "gui"),
        attr("JinDetailBorder", "bg#", "gui"),
        attr("JinDetailBorder", "fg", "cterm"),
        attr("JinDetailBorder", "bg", "cterm"),
      })
      h.ex("highlight clear FloatBorder")
      h.ex("highlight clear")
      h.ex("doautocmd ColorScheme")
    end,
  },
}
