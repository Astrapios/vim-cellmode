" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by <C-r>=g:vimuxide_block_separator<CR>
"
" You can define the following globals or buffer config variables
"  let g:vimuxide_tmux_sessionname='$ipython'
"  let g:vimuxide_tmux_windowname='ipython'
"  let g:vimuxide_tmux_panenumber='0'
"  let g:vimuxide_block_separator='#%%'

function! GetVar(name, default)
  " Return a value for the given variable, looking first into buffer, then
  " globals and defaulting to default
  if (exists ("g:" . a:name))
    return g:{a:name}
  else
    return a:default
  end
endfunction

function! CleanupTempFiles()
  " Called when leaving current buffer; Cleans up temporary files
  if (exists('b:vimuxide_fnames'))
    for fname in b:vimuxide_fnames
      call delete(fname)
    endfor
    unlet b:vimuxide_fnames
  end
endfunction

function! GetNextTempFile()
  " Returns the next temporary filename to use
  "
  " We use temporary files to communicate with tmux. That is we :
  " - write the content of a register to a tmpfile
  " - have ipython running inside tmux load and run the tmpfile
  " If we use only one temporary file, quick execution of multiple cells will
  " result in the tmpfile being overrident. So we use multiple tmpfile that
  " act as a rolling buffer (the size of which is configured by
  " vimuxide_n_files)
  if !exists("b:vimuxide_fnames")
    au BufDelete <buffer> call CleanupTempFiles()
    let b:vimuxide_fnames = []
    for i in range(1, b:vimuxide_n_files)
      call add(b:vimuxide_fnames, tempname() . ".ipy")
    endfor
    let b:vimuxide_fnames_index = 0
  end
  let l:vimuxide_fname = b:vimuxide_fnames[b:vimuxide_fnames_index]
  " TODO: Would be better to use modulo, but vim doesn't seem to like % here...
  if (b:vimuxide_fnames_index >= b:vimuxide_n_files - 1)
    let b:vimuxide_fnames_index = 0
  else
    let b:vimuxide_fnames_index += 1
  endif

  "echo 'vimuxide_fname : ' . l:vimuxide_fname
  return l:vimuxide_fname
endfunction

function! GetSessionName()
    let l:out = system("tmux display-message -p '#S'")[:-2] "[:-2] removes the null character

    return l:out
endfunction

function! GetWindowName()
    let l:out = system("tmux display-message -p '#W'")[:-2] "[:-2] removes the null character

    return l:out
endfunction

function! DefaultVars()
  " Load and set defaults config variables :
  " - b:vimuxide_fname temporary filename
  " - g:vimuxide_tmux_sessionname, g:vimuxide_tmux_windowname,
  "   g:vimuxide_tmux_panenumber : default tmux
  "   target
  " - b:vimuxide_tmux_sessionname, b:vimuxide_tmux_windowname,
  "   b:vimuxide_tmux_panenumber :
  "   buffer-specific target (defaults to g:)
  let b:vimuxide_n_files = GetVar('vimuxide_n_files', 10)

    " Automatically detects tmux session unless globally defined
  let b:vimuxide_tmux_sessionname = GetVar('vimuxide_tmux_sessionname', GetSessionName())
  let b:vimuxide_tmux_windowname = GetVar('vimuxide_tmux_windowname', GetWindowName())
  let b:vimuxide_tmux_panenumber = GetVar('vimuxide_tmux_panenumber', '1')

endfunction

function! g:CallSystem(cmd)
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
  let l:vimuxide_fname = GetNextTempFile()
  call writefile(l:lines, l:vimuxide_fname)

  " tmux requires the sessionname to start with $ (for example $ipython to
  " target the session named 'ipython'). Except in the case where we
  " want to target the current tmux session (with vim running in tmux)
  let target = b:vimuxide_tmux_sessionname . ':'
             \ . b:vimuxide_tmux_windowname . '.'
             \ . b:vimuxide_tmux_panenumber

  " Ipython has some trouble if we paste large buffer if it has been started
  " in a small console. We use %load to work around that
  "call CallSystem('tmux load-buffer ' . l:vimuxide_fname)
  "call CallSystem('tmux paste-buffer -t ' . target)
  call CallSystem("tmux set-buffer \"%load -y " . l:vimuxide_fname . "\n\"")
  call CallSystem('tmux paste-buffer -t "' . target . '"')
  " In ipython5, the cursor starts at the top of the lines, so we have to move
  " to the bottom
  let downlist = repeat('Down ', len(l:lines) + 1)
  call CallSystem('tmux send-keys -t "' . target . '" ' . downlist)
  " Simulate double enter to run loaded code
  call CallSystem('tmux send-keys -t "' . target . '" Enter Enter')
endfunction

function! ResetTmuxSettings()
  "  reset below varaibles
  "  g:vimuxide_tmux_sessionname='$ipython'
  "  g:vimuxide_tmux_windowname='ipython'
  "  g:vimuxide_tmux_panenumber='0'
  let g:vimuxide_tmux_sessionname = input("New sessionname: ", '0')
  let g:vimuxide_tmux_windowname = input("New Window #: ", '0')
  let g:vimuxide_tmux_panenumber = input("New Pane #: ", '1')
endfunction

function! UnsetTmuxSettings()
  unlet g:vimuxide_tmux_sessionname
  unlet g:vimuxide_tmux_windowname
  unlet g:vimuxide_tmux_panenumber
endfunction

" Returns: 1 if the var is set, 0 otherwise
function! InitVariable(var, value)
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
endfunction
