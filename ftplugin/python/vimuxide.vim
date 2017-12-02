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

  " save current view, and use this if cursor needs to be restored
  let l:winview = winsaveview()

  " search for block separator to take care of each case
  let l:block_search_backward = search(g:vimuxide_block_separator, 'bnW')
  let l:block_search_forward = search(g:vimuxide_block_separator, 'nW')


  "=================== Different cases for block separators ==================
  " if block separator is found both top and bottom:
  if l:block_search_backward !=0 && l:block_search_forward !=0
      silent :exec "?".g:vimuxide_block_separator."?;/".g:vimuxide_block_separator."/y a"
      " The above will have the leading and ending <C-r>=g:vimuxide_block_separator<CR> in the register, but we
      " have to remove them (especially leading one) to get a correct indentation
      " estimate. So just select the correct subrange of lines [1:-2]
      let @a=join(split(@a, "\n")[1:-2], "\n")
      let l:restore_cursor = 0

  " if block separator does not exist in the file:
  elseif l:block_search_backward == 0 && l:block_search_forward == 0
      silent :exec "%y a"
      let @a=join(split(@a, "\n")[0:-1], "\n")
      let l:restore_cursor = 1

  " if block separator only exists in the forward direciton:
  elseif l:block_search_backward == 0 
      silent :exec "1;/".g:vimuxide_block_separator."/y a"
      let @a=join(split(@a, "\n")[0:-2], "\n")
      let l:restore_cursor = 0

  " if block separator only exists in the backward direciton:
  else
      silent :exec "?".g:vimuxide_block_separator."?;$y a"
      let @a=join(split(@a, "\n")[1:-1], "\n")
      let l:restore_cursor = 1
  end
  "=================== Different cases END==================

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op
  if a:restore_cursor || l:restore_cursor
    call winrestview(l:winview)
  else
    execute "normal! ']"
    execute "normal! j"
  end

  call RunTmuxPythonReg()
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

function! RunTmuxPythonFile()
    " get file directory and file name
    let l:file_directory=expand('%:p:h')
    let l:file_name=expand('%:t')

    " define tmux session, window, and pane
    call DefaultVars()
    let l:target = b:vimuxide_tmux_sessionname . ':'
             \ . b:vimuxide_tmux_windowname . '.'
             \ . b:vimuxide_tmux_panenumber

    " define commands to send
    let l:change_dir = "'cd \"".l:file_directory."\"' C-m"
    let l:run_file = "'run \"".l:file_name."\"' C-m"

    call CallSystem("tmux send-keys -t " .l:target." ".l:change_dir)
    call CallSystem("tmux send-keys -t " .l:target." ".l:run_file)
endfunction

call InitVariable("g:vimuxide_default_mappings", 1)

if g:vimuxide_default_mappings
    vmap <silent> <C-c> :call RunTmuxPythonChunk()<CR>
    noremap <silent> <C-b> :call RunTmuxPythonCell(0)<CR>
    noremap <silent> <C-g> :call RunTmuxPythonCell(1)<CR>
    noremap <F5> :w<CR>:call RunTmuxPythonFile()<CR>
    noremap <F7> :call ResetTmuxSettings()<CR>
    noremap <F8> :call UnsetTmuxSettings()<CR>
endif
