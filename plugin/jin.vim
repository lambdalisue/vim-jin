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

for s:name in ['JinLog', 'JinShow', 'JinDiff', 'JinFile', 'JinOpLog', 'JinEvolog']
  execute printf(
        \ 'command! -bang -nargs=* -complete=customlist,%s %s'
        \ . ' call luaeval(''require("jin.host.entry").view(_A[1], _A[2], _A[3], _A[4])'','
        \ . ' [''%s'', <q-args>, <bang>0, <q-mods>])',
        \ expand('<SID>') . 'complete_view', s:name, s:name)
endfor
unlet s:name

function! s:highlight() abort
  highlight default link JinCursorEntry CursorLine
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
  " Not left to the reading, which ends only when jj answers: BufEnter comes
  " first, and plugins that work on files, such as language clients, attach
  " to a buffer they see with no 'buftype' there.
  autocmd BufReadCmd jin://*
        \ call setbufvar(str2nr(expand('<abuf>')), '&buftype', 'nofile')
        \ | call s:make_room(str2nr(expand('<abuf>')))
        \ | call luaeval('require("jin.host.entry").read_buffer(_A[1], _A[2])',
        \ [str2nr(expand('<abuf>')), expand('<amatch>')])
  autocmd BufLeave jin://* let b:jin_cursor = [line('.'), col('.')]
  autocmd CursorMoved jin://*
        \ call luaeval('require("jin.host.entry").cursor_moved(_A)', bufnr())
  autocmd ColorScheme * call s:highlight()
  autocmd BufUnload jin://*
        \ call luaeval('require("jin.host.entry").forget_buffer(_A)', str2nr(expand('<abuf>')))
  autocmd User JinCommandPost
        \ call luaeval('require("jin.host.entry").reload_buffers()')
  autocmd BufEnter jin://*
        \ call luaeval('require("jin.host.entry").refresh_buffers(_A)', str2nr(expand('<abuf>')))
  autocmd FocusGained * call luaeval('require("jin.host.entry").refresh_buffers(0)')
augroup END
