if exists('g:loaded_jin') || !(has('nvim') || has('lua'))
  finish
endif
let g:loaded_jin = 1

function! s:complete(arglead, cmdline, cursorpos) abort
  return luaeval('require("jin.host.entry").complete(_A[1], _A[2], _A[3])',
        \ [a:arglead, a:cmdline, a:cursorpos])
endfunction

" No -bar: `|` is a revset operator and must reach jj. The line is handed
" over as typed (<q-args>) so that vim-jin can split it with shell quoting.
command! -nargs=* -complete=customlist,s:complete Jin
      \ call luaeval('require("jin.host.entry").jin(_A)', <q-args>)
