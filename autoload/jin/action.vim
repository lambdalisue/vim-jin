" Completes the action names of the current vim-jin buffer, for the prompt of
" the choice action.
function! jin#action#complete(arglead, cmdline, cursorpos) abort
  return filter(copy(get(b:, 'jin_actions', [])), { _, v -> stridx(v, a:arglead) == 0 })
endfunction
