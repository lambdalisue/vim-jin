if exists('g:loaded_jin') || !(has('nvim') || has('lua'))
  finish
endif
let g:loaded_jin = 1

function! s:complete(arglead, cmdline, cursorpos) abort
  return luaeval('require("jin.host.entry").complete(_A[1], _A[2], _A[3])',
        \ [a:arglead, a:cmdline, a:cursorpos])
endfunction

function! s:complete_buffer(arglead, cmdline, cursorpos) abort
  return luaeval('require("jin.host.entry").complete_buffer(_A[1], _A[2], _A[3])',
        \ [a:arglead, a:cmdline, a:cursorpos])
endfunction

" No -bar: `|` is a revset operator and must reach jj. The line is handed
" over as typed (<q-args>) so that vim-jin can split it with shell quoting.
command! -nargs=* -complete=customlist,s:complete Jin
      \ call luaeval('require("jin.host.entry").jin(_A)', <q-args>)

command! -bang -nargs=* -complete=customlist,s:complete_buffer JinBuffer
      \ call luaeval('require("jin.host.entry").jin_buffer(_A[1], _A[2], _A[3])',
      \ [<q-args>, <bang>0, <q-mods>])

function! s:complete_view(arglead, cmdline, cursorpos) abort
  return luaeval('require("jin.host.entry").complete_view(_A[1], _A[2], _A[3])',
        \ [a:arglead, a:cmdline, a:cursorpos])
endfunction

for s:name in ['JinLog', 'JinShow', 'JinDiff', 'JinFile', 'JinOpLog', 'JinEvolog', 'JinStatus', 'JinAnnotate', 'JinBookmark', 'JinWorkspace', 'JinConflicts', 'JinArrange']
  execute printf(
        \ 'command! -bang -nargs=* -complete=customlist,%s %s'
        \ . ' call luaeval(''require("jin.host.entry").view(_A[1], _A[2], _A[3], _A[4])'','
        \ . ' [''%s'', <q-args>, <bang>0, <q-mods>])',
        \ expand('<SID>') . 'complete_view', s:name, s:name)
endfor
unlet s:name

command! -bar JinCd call luaeval('require("jin.host.entry").cd(_A)', 'cd')
command! -bar JinLcd call luaeval('require("jin.host.entry").cd(_A)', 'lcd')
command! -bar JinTcd call luaeval('require("jin.host.entry").cd(_A)', 'tcd')

function! s:highlight() abort
  highlight default link JinCursorEntry CursorLine
  highlight default link JinCursorChange CursorLine
  highlight default link JinSelected Visual
  highlight default link JinSelectedSign Special
  highlight default link JinDetailBody Normal
  call s:detail_border()
  highlight default link JinDetailTitle Title
  highlight default link JinDetailChange Identifier
  highlight default link JinDetailCommit Function
  highlight default link JinDetailDim Comment
  highlight default link JinDetailRef Special
  highlight default link JinDetailAlert WarningMsg
  execute 'highlight default link JinDetailAdded' (hlexists('Added') ? 'Added' : 'DiffAdd')
  execute 'highlight default link JinDetailRemoved' (hlexists('Removed') ? 'Removed' : 'DiffDelete')
  highlight default link JinStatusline StatusLine
  highlight default link JinStatuslineView PmenuSel
  highlight default link JinStatuslineEdit Search
  highlight default link JinStatuslineEntry Identifier
  highlight default link JinStatuslineCommit Function
  highlight default link JinStatuslineHere Directory
  highlight default link JinStatuslineDim Comment
  highlight default link JinStatuslineAlert WarningMsg
  highlight default link JinStatuslineSelected Special
  call s:inks()
endfunction

" The border of the detail panel in the color of FloatBorder, which Vim
" lacks, on the background of Normal, as the panel's body is: FloatBorder often has a
" background of its own, which no link can leave out.
function! s:detail_border() abort
  let l:spec = 'highlight default JinDetailBorder'
  for l:mode in ['gui', 'cterm']
    let l:spec .= printf(' %sfg=%s %sbg=%s', l:mode, s:color('FloatBorder', 'fg', l:mode),
          \ l:mode, s:color('Normal', 'bg', l:mode))
  endfor
  execute l:spec
endfunction

" The color of a group: its text, or with 'reverse', what it is drawn on.
function! s:color(group, what, mode) abort
  let l:id = synIDtrans(hlID(a:group))
  let l:reverse = synIDattr(l:id, 'reverse', a:mode)
  let l:color = synIDattr(l:id, (a:what ==# 'fg') != l:reverse ? 'fg#' : 'bg#', a:mode)
  return l:color ==# '' || l:color ==# '-1' ? 'NONE' : l:color
endfunction

" A color as [red, green, blue], from "#rrggbb" or a number of the xterm
" palette; [] for one that names no color, such as NONE.
function! s:rgb(color) abort
  if a:color =~# '^#\x\{6}$'
    return map([1, 3, 5], {_, i -> str2nr(a:color[i : i + 1], 16)})
  elseif a:color !~# '^\d\+$'
    return []
  endif
  let l:n = str2nr(a:color)
  if l:n < 16
    return s:palette[l:n]
  elseif l:n < 232
    let l:levels = [0, 95, 135, 175, 215, 255]
    return [l:levels[(l:n - 16) / 36], l:levels[(l:n - 16) / 6 % 6], l:levels[(l:n - 16) % 6]]
  endif
  let l:gray = 8 + (l:n - 232) * 10
  return [l:gray, l:gray, l:gray]
endfunction
let s:palette = [
      \ [0, 0, 0], [205, 0, 0], [0, 205, 0], [205, 205, 0],
      \ [0, 0, 238], [205, 0, 205], [0, 205, 205], [229, 229, 229],
      \ [127, 127, 127], [255, 0, 0], [0, 255, 0], [255, 255, 0],
      \ [92, 92, 255], [255, 0, 255], [0, 255, 255], [255, 255, 255]]

function! s:luminance(rgb) abort
  let l:linear = map(copy(a:rgb), {_, c -> c / 255.0 <= 0.03928
        \ ? c / 255.0 / 12.92 : pow((c / 255.0 + 0.055) / 1.055, 2.4)})
  return 0.2126 * l:linear[0] + 0.7152 * l:linear[1] + 0.0722 * l:linear[2]
endfunction

" Whether text in `fg` stands out on `bg`, as WCAG measures the contrast of
" large text. Colors that cannot be told are taken to.
function! s:readable(fg, bg) abort
  let [l:fg, l:bg] = [s:rgb(a:fg), s:rgb(a:bg)]
  if empty(l:fg) || empty(l:bg)
    return 1
  endif
  let [l:a, l:b] = [s:luminance(l:fg), s:luminance(l:bg)]
  " max() and min() take no Float.
  let [l:light, l:dark] = l:a > l:b ? [l:a, l:b] : [l:b, l:a]
  return (l:light + 0.05) / (l:dark + 0.05) >= 3.0
endfunction

" The color of the xterm palette nearest [red, green, blue], of its cube or
" its grays.
function! s:xterm(rgb) abort
  let l:levels = [0, 95, 135, 175, 215, 255]
  let l:index = []
  for l:c in a:rgb
    call add(l:index, l:c < 48 ? 0 : l:c < 115 ? 1 : (l:c - 35) / 40)
  endfor
  let l:cube = map(copy(l:index), {_, i -> l:levels[i]})
  let l:average = (a:rgb[0] + a:rgb[1] + a:rgb[2]) / 3
  let l:step = l:average > 238 ? 23 : l:average < 8 ? 0 : (l:average - 3) / 10
  let l:gray = 8 + l:step * 10
  let l:far_cube = 0
  let l:far_gray = 0
  for l:i in range(3)
    let l:far_cube += (a:rgb[l:i] - l:cube[l:i]) * (a:rgb[l:i] - l:cube[l:i])
    let l:far_gray += (a:rgb[l:i] - l:gray) * (a:rgb[l:i] - l:gray)
  endfor
  return l:far_gray < l:far_cube
        \ ? 232 + l:step
        \ : 16 + l:index[0] * 36 + l:index[1] * 6 + l:index[2]
endfunction

" `fg` made darker on a light `bg`, or lighter on a dark one, by as little
" as makes it readable, its hue kept; '' when either is no color.
function! s:adjust(fg, bg, mode) abort
  let [l:fg, l:bg] = [s:rgb(a:fg), s:rgb(a:bg)]
  if empty(l:fg) || empty(l:bg)
    return ''
  endif
  let l:toward = s:luminance(l:bg) > 0.18 ? 0 : 255
  for l:step in range(1, 10)
    let l:rgb = []
    for l:c in l:fg
      call add(l:rgb, float2nr(round(l:c + (l:toward - l:c) * l:step / 10.0)))
    endfor
    let l:color = a:mode ==# 'gui'
          \ ? printf('#%02x%02x%02x', l:rgb[0], l:rgb[1], l:rgb[2])
          \ : string(s:xterm(l:rgb))
    if s:readable(l:color, a:bg)
      return l:color
    endif
  endfor
  return ''
endfunction

" The parts of the statusline of a view are drawn in JinStatuslineInk{Name},
" made of the colors of JinStatusline{Name}: the badge of the view in both of
" them, the rest in its text color over the background of JinStatusline,
" which no link can express. Groups meant for text on the editor's
" background may not stand out on a statusline's, light in many
" colorschemes; such text is made darker or lighter until it does, or keeps
" the color of JinStatusline itself where the colors cannot be told. Neovim
" draws every part with the attributes of StatusLine added, so a reversed
" JinStatusline makes each part reversed, with its colors swapped to match.
function! s:inks() abort
  let l:line = synIDtrans(hlID('JinStatusline'))
  for l:name in ['View', 'Edit', 'Entry', 'Commit', 'Here', 'Dim', 'Alert', 'Selected']
    let l:group = 'JinStatusline' . l:name
    let l:badge = l:name ==# 'View' || l:name ==# 'Edit'
    let l:spec = 'highlight JinStatuslineInk' . l:name
    for l:mode in ['gui', 'cterm']
      let l:fg = s:color(l:group, 'fg', l:mode)
      let l:bg = s:color(l:badge ? l:group : 'JinStatusline', 'bg', l:mode)
      if !l:badge && !s:readable(l:fg, l:bg)
        let l:adjusted = s:adjust(l:fg, l:bg, l:mode)
        let l:fg = empty(l:adjusted) ? s:color('JinStatusline', 'fg', l:mode) : l:adjusted
      endif
      let l:attrs = synIDattr(synIDtrans(hlID(l:group)), 'bold', l:mode) ? ['bold'] : []
      if synIDattr(l:line, 'reverse', l:mode)
        let [l:fg, l:bg] = [l:bg, l:fg]
        call add(l:attrs, 'reverse')
      endif
      let l:spec .= printf(' %sfg=%s %sbg=%s %s=%s', l:mode, l:fg, l:mode, l:bg,
            \ l:mode, empty(l:attrs) ? 'NONE' : join(l:attrs, ','))
    endfor
    execute l:spec
  endfor
endfunction
call s:highlight()

" A buffer read again stays empty until jj answers, while a jump back to it,
" or a plugin restoring its view, lands on the line it was left on at once:
" the empty lines up to that line keep them from finding no such line.
function! s:make_room(bufnr) abort
  let l:cursor = getbufvar(a:bufnr, 'jin_cursor', [])
  if empty(l:cursor) || l:cursor[0] <= 1
    return
  endif
  call setbufvar(a:bufnr, '&modifiable', 1)
  call setbufline(a:bufnr, 1, repeat([''], l:cursor[0]))
  call setbufvar(a:bufnr, '&modified', 0)
endfunction

augroup jin_plugin
  autocmd!
  autocmd BufEnter,FocusGained * call jin#component#touch()
  autocmd User JinCommandPost call jin#component#touch(1)
  " Not left to the reading, which ends only when jj answers: BufEnter comes
  " first, and plugins that work on files, such as language clients, attach
  " to a buffer they see with no 'buftype' there.
  autocmd BufReadCmd jin://*
        \ call setbufvar(str2nr(expand('<abuf>')), '&buftype', 'nofile')
        \ | call s:make_room(str2nr(expand('<abuf>')))
        \ | call luaeval('require("jin.host.entry").read_buffer(_A[1], _A[2])',
        \ [str2nr(expand('<abuf>')), expand('<amatch>')])
  autocmd BufLeave jin://* let b:jin_cursor = [line('.'), col('.')]
  " Set locally, 'statusline' holds for the view in that window only; the
  " other buffers the window shows keep their own. BufWinEnter alone misses
  " a view shown in a second window.
  autocmd BufWinEnter,BufEnter jin://* call jin#statusline#attach()
  " Every window, so that leaving a view for any other one makes it inactive.
  autocmd WinEnter * if exists('*jin#statusline#enter') | call jin#statusline#enter() | endif
  autocmd CursorMoved jin://*
        \ call luaeval('require("jin.host.entry").cursor_moved(_A)', bufnr())
  autocmd BufWinEnter jin://*
        \ call luaeval('require("jin.host.entry").buffer_shown(_A)', str2nr(expand('<abuf>')))
  autocmd BufEnter,WinEnter jin://*
        \ call luaeval('require("jin.host.entry").detail_entered(_A)', bufnr())
  autocmd WinLeave,BufLeave jin://*
        \ call luaeval('require("jin.host.entry").detail_left(_A)', bufnr())
  " Their <amatch> is the window, not the buffer.
  autocmd WinClosed *
        \ call luaeval('require("jin.host.entry").window_closed(_A)', str2nr(expand('<amatch>')))
  autocmd WinScrolled,VimResized * call luaeval('require("jin.host.entry").windows_scrolled()')
  autocmd ColorScheme * call s:highlight()
  autocmd BufWriteCmd jin://*
        \ call luaeval('require("jin.host.entry").write_buffer(_A)', str2nr(expand('<abuf>')))
  autocmd BufUnload jin://*
        \ call luaeval('require("jin.host.entry").forget_buffer(_A)', str2nr(expand('<abuf>')))
  autocmd User JinCommandPost
        \ call luaeval('require("jin.host.entry").reload_buffers()')
  autocmd BufEnter jin://*
        \ call luaeval('require("jin.host.entry").refresh_buffers(_A)', str2nr(expand('<abuf>')))
  autocmd FocusGained * call luaeval('require("jin.host.entry").refresh_buffers(0)')
augroup END
