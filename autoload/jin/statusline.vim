" The statusline of vim-jin views, which plugin/jin.vim sets on their
" windows unless g:jin_statusline is 0, and that of the panes of the diff
" editor and the merge tool, which the host sets as it opens them.
"
"   let g:jin_statusline = 0     " keep your own statusline in views

" The window last entered. While a statusline is drawn, the window it belongs
" to is made the current one, so win_getid() cannot tell the active window.
let s:current = win_getid()

function! jin#statusline#enter() abort
  let s:current = win_getid()
endfunction

let s:EXPR = '%!jin#statusline#render()'
let s:PANE = '%!jin#statusline#pane()'

" Draw the statusline of the view the current window shows, or that of the
" pane it is, which names it.
function! jin#statusline#attach() abort
  call jin#statusline#enter()
  if !get(g:, 'jin_statusline', 1)
    return
  endif
  let l:expr = exists('b:jin_pane') ? s:PANE : s:EXPR
  if &l:statusline !=# l:expr
    let &l:statusline = l:expr
  endif
endfunction

" The windows whose statusline is to be given back, by window ID.
let s:giving_back = {}

" Give the window `winid` its user's statusline back, where it was turned off
" or the buffer is no view or pane any more. Not while a statusline is
" drawn, when no option may be set: once that is done.
function! s:give_back(winid) abort
  if has_key(s:giving_back, a:winid)
    return
  endif
  let s:giving_back[a:winid] = 1
  call timer_start(0, {-> s:release(a:winid)})
endfunction

function! s:release(winid) abort
  call remove(s:giving_back, a:winid)
  if win_id2win(a:winid) == 0
    return
  endif
  let l:bufnr = winbufnr(a:winid)
  let l:statusline = getwinvar(a:winid, '&statusline')
  if l:statusline ==# s:EXPR
    if get(g:, 'jin_statusline', 1) && bufname(l:bufnr) =~# '^jin://'
      return
    endif
    call win_execute(a:winid, 'setlocal statusline=')
  elseif l:statusline ==# s:PANE
    if !empty(getbufvar(l:bufnr, 'jin_pane', {}))
      return
    endif
    call win_execute(a:winid, 'setlocal statusline=')
  endif
  if exists('+winbar') && getwinvar(a:winid, '&winbar') ==# s:PANE
        \ && empty(getbufvar(l:bufnr, 'jin_pane', {}))
    call win_execute(a:winid, 'setlocal winbar=')
  endif
  redrawstatus!
endfunction

" The 'statusline' the user has, drawn until theirs is given back. An
" expression is left blank, as only the editor evaluates it where it was set,
" its script-local functions in reach.
function! s:users() abort
  let l:global = &g:statusline
  if empty(l:global)
    return '%<%f %h%m%r%=%-14.(%l,%c%V%) %P'
  endif
  return l:global =~# '^%!' ? '' : l:global
endfunction

" The 'statusline' of the window being drawn: the view's, or the user's own
" where it was turned off since, or where the buffer is no view any more.
function! jin#statusline#render() abort
  let l:winid = get(g:, 'statusline_winid', win_getid())
  let l:bufnr = winbufnr(l:winid)
  if !get(g:, 'jin_statusline', 1) || bufname(l:bufnr) !~# '^jin://'
    call s:give_back(l:winid)
    return s:users()
  endif
  return luaeval('require("jin.host.entry").statusline(_A[1], _A[2])',
        \ [l:winid, l:winid == s:current ? v:true : v:false])
endfunction

" The 'statusline' or the winbar of a pane of the diff editor or the merge
" tool, naming it, or the user's own once the window shows another buffer.
function! jin#statusline#pane() abort
  let l:winid = get(g:, 'statusline_winid', win_getid())
  let l:pane = getbufvar(winbufnr(l:winid), 'jin_pane', {})
  if empty(l:pane)
    call s:give_back(l:winid)
    return s:users()
  endif
  return luaeval('require("jin.host.entry").pane_statusline(_A[1], _A[2])',
        \ [l:pane, l:winid == s:current ? v:true : v:false])
endfunction
