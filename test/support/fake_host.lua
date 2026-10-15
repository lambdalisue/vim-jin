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

  ---Pretend the editor has `name` loaded as a buffer, and return its number.
  function host.load(name)
    local bufnr = #host.loaded + 1
    host.loaded[#host.loaded + 1] = { bufnr = bufnr, name = name }
    return bufnr
  end

  return host
end

return M
