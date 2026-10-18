-- A jin.Host for core tests. Processes and timers do nothing until the test
-- finishes or fires them, so every interleaving is under the test's control.

local M = {}

---@param opts? { cwd?: string, bufname?: string, dirs?: string[], links?: table<string, string> }
function M.new(opts)
  opts = opts or {}
  local dirs = {}
  for _, d in ipairs(opts.dirs or {}) do
    dirs[d] = true
  end

  local host = {
    name = "fake",
    runs = {},
    messages = {},
    events = {},
    timers = {},
    -- What `wait` makes each pending process return, in order.
    results = {},
    -- What `now` returns, in milliseconds; tests move it forward.
    clock = 0,
    -- The editor state given to `new`; tests may change it in between.
    state = opts,
  }

  function host.now()
    return host.clock
  end

  function host.run(argv, run_opts, on_exit)
    host.runs[#host.runs + 1] = {
      argv = argv,
      cwd = run_opts.cwd,
      env = run_opts.env,
      stdin = run_opts.stdin,
      on_exit = on_exit,
    }
  end

  ---Finish the oldest unfinished process with `result`.
  function host.finish(result)
    for _, run in ipairs(host.runs) do
      if not run.finished then
        run.finished = true
        run.on_exit(result)
        return
      end
    end
    error("no process is running")
  end

  function host.wait(_, cond)
    while not cond() do
      local result = table.remove(host.results, 1)
      if not result then
        return false
      end
      host.finish(result)
    end
    return true
  end

  function host.echo(text, hl)
    host.messages[#host.messages + 1] = { text = text, hl = hl }
  end

  function host.cwd()
    return opts.cwd or "/"
  end

  function host.bufname()
    return opts.bufname or ""
  end

  function host.realpath(path)
    return (opts.links or {})[path] or path
  end

  -- How often the filesystem was asked about a directory.
  host.dir_lookups = 0
  -- The directories that exist, to make or remove one during a test.
  host.dirs = dirs

  -- Like the filesystem, `.` and `..` in the path are followed.
  function host.is_dir(path)
    host.dir_lookups = host.dir_lookups + 1
    return dirs[require("jin.workspace").absolute(path, "/")] == true
  end

  function host.doautocmd(event)
    host.events[#host.events + 1] = event
  end

  function host.defer(ms, fn)
    local timer = { ms = ms, fn = fn }
    host.timers[#host.timers + 1] = timer
    return timer
  end

  function host.cancel(timer)
    timer.cancelled = true
  end

  ---Fire every timer that is due and not cancelled.
  function host.fire_timers()
    local timers = host.timers
    host.timers = {}
    for _, timer in ipairs(timers) do
      if not timer.cancelled then
        timer.fn()
      end
    end
  end

  function host.list(value)
    return value
  end

  -- Buffers: what `open` was asked to open, and what each was rendered with.
  host.opened = {}
  host.rendered = {}
  host.loaded = {}

  function host.open(name, open_opts)
    host.opened[#host.opened + 1] =
      { name = name, opener = open_opts.opener, mods = open_opts.mods }
    for _, buf in ipairs(host.loaded) do
      if buf.name == name then
        return buf.bufnr
      end
    end
    local bufnr = #host.loaded + 1
    host.loaded[#host.loaded + 1] = { bufnr = bufnr, name = name }
    return bufnr
  end

  function host.render(bufnr, content)
    host.rendered[bufnr] = content
  end

  function host.buffers()
    return host.loaded
  end

  function host.buffer_name(bufnr)
    for _, buf in ipairs(host.loaded) do
      if buf.bufnr == bufnr then
        return buf.name
      end
    end
    return nil
  end

  -- Actions: what was mapped per buffer, the buffer's own key mappings, the
  -- answers `input` gives in order, and what was yanked.
  host.defined = {}
  host.maps = {}
  host.answers = {}
  host.yanked = {}

  host.keys = {}

  function host.define_actions(bufnr, names, keys)
    host.defined[bufnr] = names
    host.keys[bufnr] = keys
  end

  function host.keymaps()
    return host.maps
  end

  function host.input(_, _)
    return table.remove(host.answers, 1)
  end

  -- What `confirm` answers in order, and what it was asked; no answer is no.
  host.confirms = {}
  host.asked = {}

  function host.confirm(prompt)
    host.asked[#host.asked + 1] = prompt
    return table.remove(host.confirms, 1) == true
  end

  function host.yank(text)
    host.yanked[#host.yanked + 1] = text
  end

  host.cds = {}

  function host.cd(scope, path)
    host.cds[#host.cds + 1] = { scope = scope, path = path }
  end

  host.cursors = {}

  function host.cursor(bufnr, lnum)
    host.cursors[bufnr] = lnum
  end

  -- The jumps asked for, in order, each moving the cursor as well.
  host.jumps = {}

  function host.jump(bufnr, lnum)
    host.jumps[#host.jumps + 1] = { bufnr = bufnr, lnum = lnum }
    host.cursors[bufnr] = lnum
  end

  function host.line(bufnr)
    return host.cursors[bufnr] or 1
  end

  -- Whether the user splits diffs vertically.
  host.vertical_split = false

  function host.vertical()
    return host.vertical_split
  end

  -- Per buffer, the lines shown as selected.
  host.selected = {}

  -- Per buffer, the selection column: the lines that show the selected glyph, and
  -- the glyph.
  host.selected_columns = {}

  function host.highlight_selected(bufnr, lnums, column)
    host.selected[bufnr] = lnums
    host.selected_columns[bufnr] = column
  end

  -- Per buffer, the lines highlighted as { first, last }, or false once
  -- cleared.
  host.highlighted = {}

  function host.highlight_lines(bufnr, first, last)
    host.highlighted[bufnr] = first and { first, last } or false
  end

  -- Per buffer, the lines highlighted as written by the change under the
  -- cursor.
  host.change_highlighted = {}

  function host.highlight_change(bufnr, lnums)
    host.change_highlighted[bufnr] = lnums
  end

  -- Per buffer, the window showing it, as `window` tells it, or false for
  -- none; by default the current one, of 24 rows and 80 columns with
  -- nothing before the text, the cursor on the row of its line, wrapping
  -- lines.
  host.windows = {}

  function host.window(bufnr)
    local win = host.windows[bufnr]
    if win == false then
      return nil
    end
    win = win or {}
    return {
      id = win.id or (1000 + bufnr),
      height = win.height or 24,
      width = win.width or 80,
      textoff = win.textoff or 0,
      row = win.row or host.line(bufnr),
      wrap = win.wrap ~= false,
      current = win.current ~= false,
    }
  end

  -- A character takes a cell, but a CJK ideograph two.
  function host.width(text)
    local cells = 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
      local byte = char:byte()
      cells = cells + ((byte >= 0xE4 and byte <= 0xE9) and 2 or 1)
    end
    return cells
  end

  -- The g:jin_* variables set, by name without the prefix.
  host.settings = {}

  function host.setting(name)
    return host.settings[name]
  end

  -- The g:jin_* dictionaries set, by name without the prefix.
  host.dict_settings = {}

  function host.setting_dict(name)
    return host.dict_settings[name]
  end

  -- Per buffer, the detail panel shown, and how many times one was drawn
  -- or closed.
  host.details = {}
  host.detail_draws = 0
  host.detail_closes = 0

  function host.open_detail(bufnr, panel)
    host.details[bufnr] = panel
    host.detail_draws = host.detail_draws + 1
  end

  function host.close_detail(bufnr)
    host.details[bufnr] = nil
    host.detail_closes = host.detail_closes + 1
  end

  -- Per buffer, the room made around its lines for the detail panel, and
  -- how many times it was made.
  host.rooms = {}
  host.room_makes = 0

  function host.detail_padding(bufnr, room)
    host.rooms[bufnr] = room
    host.room_makes = host.room_makes + 1
  end

  -- Each time the cursor was kept out from under the panel: the window
  -- and the room.
  host.kept = {}

  function host.detail_keep(winid, room)
    host.kept[#host.kept + 1] = { window = winid, room = room }
  end

  ---The number of the loaded buffer named `name`.
  function host.buffer_bufnr(name)
    for _, buf in ipairs(host.loaded) do
      if buf.name == name then
        return buf.bufnr
      end
    end
    return nil
  end

  -- The buffers marked as written, as after a :w that succeeded.
  host.saved = {}

  function host.mark_saved(bufnr)
    host.saved[bufnr] = true
  end

  -- Per buffer name, the lines a file opened with `open` holds.
  host.contents = {}

  function host.lines(bufnr)
    return host.contents[host.buffer_name(bufnr) or ""] or {}
  end

  -- The buffers left, each with the buffer shown in its place, if any.
  host.left = {}

  function host.leave(bufnr, previous)
    host.left[#host.left + 1] = { bufnr = bufnr, previous = previous }
  end

  ---Pretend the editor has `name` loaded as a buffer, and return its number.
  function host.load(name)
    local bufnr = #host.loaded + 1
    host.loaded[#host.loaded + 1] = { bufnr = bufnr, name = name }
    return bufnr
  end

  return host
end

return M
