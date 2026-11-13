" Completes from the candidates the prompt of an action was given.
function! jin#input#complete(arglead, cmdline, cursorpos) abort
  return filter(copy(get(b:, 'jin_input_candidates', [])), { _, v -> stridx(v, a:arglead) == 0 })
endfunction
