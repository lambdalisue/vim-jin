" Statusline components, such as
"
"   set statusline+=%{jin#component#get('change')}
"
" A component never fails and never runs jj while the statusline is drawn:
" it shows what the last refresh found. Refreshes run in the background and
" fire User JinComponentPost when a component changed.

function! jin#component#get(name) abort
  return luaeval('require("jin.host.entry").component(_A)', a:name)
endfunction

function! jin#component#touch(...) abort
  call luaeval('require("jin.host.entry").touch_components(_A)', get(a:000, 0, 0))
endfunction
