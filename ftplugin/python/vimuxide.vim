" Implementation of a MATLAB-like cellmode for python scripts where cells
" are delimited by <C-r>=g:vimuxide_block_separator<CR>
"
" You can define the following globals or buffer config variables
"  let g:vimuxide_tmux_sessionname='$ipython'
"  let g:vimuxide_tmux_windowname='ipython'
"  let g:vimuxide_tmux_panenumber='0'
"  let g:vimuxide_block_separator='#%%'

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

function! RunTmuxPythonReg()
  " Paste into tmux the content of the register @a
  let l:code = PythonUnindent(@a)
  call CopyToTmux(l:code)
endfunction

function! RunTmuxPythonCell(restore_cursor)
  " This is to emulate MATLAB's cell mode.
  " Cells are delimited by g:vimuxide_block_separator. Note that there should be a g:vimuxide_block_separator at the end of the file.
  " <C-r>= before and <CR> after the variable is required to properly escape the value to the
  " command mode
  " The :?<C-r>=g:vimuxide_block_separator<CR>?;/<C-r>=g:vimuxide_block_separator<CR>/ part creates a range with the following
  " ?<C-r>=g:vimuxide_block_separator<CR>? search backwards for g:vimuxide_block_separator

  " Then ';' starts the range from the result of the previous search (<C-r>=g:vimuxide_block_separator<CR>)
  " /<C-r>=g:vimuxide_block_separator<CR>/ End the range at the next <C-r>=g:vimuxide_block_separator<CR>
  " See the doce on 'ex ranges' here :
  " http://tnerual.eriogerg.free.fr/vimqrc.html
  call DefaultVars()
  if a:restore_cursor
    let l:winview = winsaveview()
  end
  silent :exec "?".g:vimuxide_block_separator."?;/".g:vimuxide_block_separator."/y a"

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  " Move to the last character of the previously yanked text
  execute "normal! ']"
  " Move one line down
  execute "normal! j"

  " The above will have the leading and ending <C-r>=g:vimuxide_block_separator<CR> in the register, but we
  " have to remove them (especially leading one) to get a correct indentation
  " estimate. So just select the correct subrange of lines [1:-2]
  let @a=join(split(@a, "\n")[1:-2], "\n")
  call RunTmuxPythonReg()
  if a:restore_cursor
    call winrestview(l:winview)
  end
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


function! RunTmuxPythonAllCellsAbove()
  " Executes all the cells above the current line. That is, everything from
  " the beginning of the file to the closest <C-r>=g:vimuxide_block_separator<CR> above the current line
  call DefaultVars()

  " Ask the user for confirmation, this could lead to huge execution
  if input("Execute all cells above ? [y]|n ", 'y') != "y"
    return
  endif

  let l:cursor_pos = getpos(".")

  " Creates a range from the first line to the closest <C-r>=g:vimuxide_block_separator<CR> above the current
  " line (?<C-r>=g:vimuxide_block_separator<CR>? searches backward for <C-r>=g:vimuxide_block_separator<CR>)
  silent :exec "1,?".g:vimuxide_block_separator."?y a"

  let @a=join(split(@a, "\n")[:-2], "\n")
  call RunTmuxPythonReg()
  call setpos(".", l:cursor_pos)
endfunction

function! RunTmuxPythonChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  call RunTmuxPythonReg()
endfunction

" Returns:
"   1 if the var is set, 0 otherwise
function! InitVariable(var, value)
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
endfunction

call InitVariable("g:vimuxide_default_mappings", 1)

if g:vimuxide_default_mappings
    vmap <silent> <C-c> :call RunTmuxPythonChunk()<CR>
    noremap <silent> <C-b> :call RunTmuxPythonCell(0)<CR>
    noremap <silent> <C-g> :call RunTmuxPythonCell(1)<CR>
    noremap <F7> :call ResetTmuxSettings()<CR>
    noremap <F8> :call UnsetTmuxSettings()<CR>
endif
