" The statusline of vim-jin views, which plugin/jin.vim sets on their
" windows unless g:jin_statusline is 0.
"
"   let g:jin_statusline = 0     " keep your own statusline in views

" The window last entered. While a statusline is drawn, the window it belongs
" to is made the current one, so win_getid() cannot tell the active window.
let s:current = win_getid()

function! jin#statusline#enter() abort
  let s:current = win_getid()
endfunction

let s:EXPR = '%!jin#statusline#render()'

" Draw the statusline of the view the current window shows.
function! jin#statusline#attach() abort
  call jin#statusline#enter()
  if get(g:, 'jin_statusline', 1) && &l:statusline !=# s:EXPR
    let &l:statusline = s:EXPR
  endif
endfunction

" The windows whose statusline is to be given back, by window ID.
let s:giving_back = {}

" Give the window `winid` its user's statusline back, where it was turned off
" or the buffer is no view any more. Not while a statusline is drawn, when
" no option may be set: once that is done.
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
        \ || getwinvar(a:winid, '&statusline') !=# s:EXPR
        \ || (get(g:, 'jin_statusline', 1) && bufname(winbufnr(a:winid)) =~# '^jin://')
    return
  endif
  call win_execute(a:winid, 'setlocal statusline=')
  redrawstatus!
endfunction

" The 'statusline' of the window being drawn: the view's, or the user's own
" where it was turned off since, or where the buffer is no view any more.
function! jin#statusline#render() abort
  let l:winid = get(g:, 'statusline_winid', win_getid())
  let l:bufnr = winbufnr(l:winid)
  if !get(g:, 'jin_statusline', 1) || bufname(l:bufnr) !~# '^jin://'
    call s:give_back(l:winid)
    " Drawn so until then. An expression is left blank, as only the editor
    " evaluates it where it was set, its script-local functions in reach.
    let l:global = &g:statusline
    if empty(l:global)
      return '%<%f %h%m%r%=%-14.(%l,%c%V%) %P'
    endif
    return l:global =~# '^%!' ? '' : l:global
  endif
  return luaeval('require("jin.host.entry").statusline(_A[1], _A[2])',
        \ [l:winid, l:winid == s:current ? v:true : v:false])
endfunction
