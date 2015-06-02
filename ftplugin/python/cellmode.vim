" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by ##
"
" You can define the following globals or buffer config variables
"  let g:tmux_sessionname='ipython'
"  let g:tmux_windowname='ipython'
"  let g:tmux_panenumber='0'
"  let g:screen_sessionname='ipython'
"  let g:screen_window='0'
"  let g:cellmode_use_tmux=1

function! PythonUnindent(code)
  " The code is unindented so the first selected line has 0 indentation
  " So you can select a statement from inside a function and it will run
  " without python complaining about indentation.
  let l:lines = split(a:code, "\n")
  if len(l:lines) == 0 " Special case for empty string
    return a:code
  end
  let l:nindents = strlen(matchstr(l:lines[0], '^\s*'))
  " Remove nindents from each line
  let l:subcmd = 'substitute(v:val, "^\\s\\{' . l:nindents . '\\}", "", "")'
  call map(l:lines, l:subcmd)
  let l:ucode = join(l:lines, "\n")
  return l:ucode
endfunction

function! GetVar(name, default)
  " Return a value for the given variable, looking first into buffer, then
  " globals and defaulting to default
  if (exists ("b:" . a:name))
    return b:{a:name}
  elseif (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction

function! DefaultVars()
  " Load and set defaults config variables :
  " - b:cellmode_fname temporary filename
  " - g:tmux_sessionname, g:tmux_windowname, g:tmux_panenumber : default tmux
  "   target
  " - b:tmux_sessionname, b:tmux_windowname, b:tmux_panenumber :
  "   buffer-specific target (defaults to g:)
  if !exists("b:cellmode_fname")
    let b:cellmode_fname = GetVar('cellmode_fname', tempname())
    echo 'cellmode_fname : ' . b:cellmode_fname
  end

  if !exists("b:cellmode_use_tmux")
    let b:cellmode_use_tmux = GetVar('cellmode_use_tmux', 1)
  end

  if !exists("b:tmux_sessionname") || !exists("b:tmux_windowname") || !exists("b:tmux_panenumber")
    let b:tmux_sessionname = GetVar('tmux_sessionname', 'ipython')
    let b:tmux_windowname = GetVar('tmux_windowname', 'ipython')
    let b:tmux_panenumber = GetVar('tmux_panenumber', '0')
  end

  if !exists("g:screen_sessionname") || !exists("b:screen_window")
    let b:screen_sessionname = GetVar('screen_sessionname', 'ipython')
    let b:screen_window = GetVar('screen_window', '0')
  end
endfunction

function! CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vim-cellmode, error running ' . a:cmd . ' : ' . l:out
  end
endfunction

function! CopyToTmux(code)
  " Copy the given code to tmux. We use a temp file for that
  let l:lines = split(a:code, "\n")
  " If the file is empty, it seems like tmux load-buffer keep the current
  " buffer and this cause the last command to be repeated. We do not want that
  " to happen, so add a dummy string
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  call writefile(l:lines, b:cellmode_fname)

  let target = '$' . b:tmux_sessionname . ':' . b:tmux_windowname . '.' . b:tmux_panenumber
  " Ipython has some trouble if we paste large buffer if it has been started
  " in a small console. %load seems to work fine, so use that instead
  "call system('tmux load-buffer ' . b:cellmode_fname)
  "call system('tmux paste-buffer -t ' . target)
  "call system("tmux set-buffer \"%run -i " . b:cellmode_fname . "\n\"")
  call CallSystem("tmux set-buffer \"%load -y " . b:cellmode_fname . "\n\"")
  call CallSystem('tmux paste-buffer -t "' . target . '"')
  " Simulate double enter to scroll through and run loaded code
  call CallSystem('tmux send-keys -t "' . target . '" Enter Enter')
endfunction

function! CopyToScreen(code)
  let l:lines = split(a:code, "\n")
  " If the file is empty, it seems like tmux load-buffer keep the current
  " buffer and this cause the last command to be repeated. We do not want that
  " to happen, so add a dummy string
  if len(l:lines) == 0
    call add(l:lines, ' ')
  end
  call writefile(l:lines, b:cellmode_fname)

  if has('macunix')
    call system("pbcopy < " . b:cellmode_fname)
  else
    call system("xclip -i -selection c " . b:cellmode_fname)
  end
  call system("screen -S " . b:screen_sessionname . " -p " . b:screen_window . " -X stuff '%paste'")
endfunction

function! RunTmuxPythonReg()
  call DefaultVars()
  " Paste into tmux the content of the register @a
  let l:code = PythonUnindent(@a)
  if b:cellmode_use_tmux
    call CopyToTmux(l:code)
  else
    call CopyToScreen(l:code)
  end
endfunction

function! RunTmuxPythonCell(restore_cursor)
  " This is to emulate MATLAB's cell mode
  " Cells are delimited by ##. Note that there should be a ## at the end of the
  " file
  " The :?##?;/##/ part creates a range with the following
  " ?##? search backwards for ##

  " Then ';' starts the range from the result of the previous search (##)
  " /##/ End the range at the next ##
  " See the doce on 'ex ranges' here :
  " http://tnerual.eriogerg.free.fr/vimqrc.html
  call DefaultVars()
  if a:restore_cursor
    let l:cursor_pos = getpos(".")
  end
  silent :?##?;/##/y a

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of previously yanked text
  execute "normal! j"

  " The above will have the leading and ending ## in the register, but we
  " have to remove them (especially leading one) to get a correct indentation
  " estimate. So just select the correct subrange of lines [1:-2]
  let @a=join(split(@a, "\n")[1:-2], "\n")
  call RunTmuxPythonReg()
  if a:restore_cursor
    call setpos(".", l:cursor_pos)
  end
endfunction

function! RunTmuxPythonChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  call RunTmuxPythonReg()
endfunction

vmap <silent> <C-c> :call RunTmuxPythonChunk()<CR>
noremap <silent> <C-b> :call RunTmuxPythonCell(0)<CR>
noremap <silent> <C-g> :call RunTmuxPythonCell(1)<CR>
