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

function! InitVariable(var, value)
    " returns: 1 if the var is set, 0 otherwise
    if !exists(a:var)
        execute 'let ' . a:var . ' = ' . "'" . a:value . "'"
        return 1
    endif
    return 0
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
            call add(b:vimuxide_fnames, tempname() . ".tmp")
        endfor
        let b:vimuxide_fnames_index = 0
    endif

    let l:vimuxide_fname = b:vimuxide_fnames[b:vimuxide_fnames_index]
    " todo: Would be better to use modulo, but vim doesn't seem to like % here...
    if (b:vimuxide_fnames_index >= b:vimuxide_n_files - 1)
        let b:vimuxide_fnames_index = 0
    else
        let b:vimuxide_fnames_index += 1
    endif 
    "echo 'vimuxide_fname : ' . l:vimuxide_fname
    return l:vimuxide_fname
endfunction

function! TmuxSessionFinder(program_title)
    " search string for pane based on filetype, needs little more work for
    " non interactive codes that depends on makefile
    let l:tmux_sessions = split(system('tmux list-sessions | grep -o ^\\d')) 

    " search for interactive program within current tmux session if vim is
    " within a tmux session, or search last active session
    let l:active_vimuxide_session = 
                \system("tmux list-panes -sF '#{session_name} #{window_index} #P #{pane_title}' | grep ".a:program_title." | grep -o '^\\w\\+ \\w\\+ \\w\\+'")

    " if interactive program is found, save the session name, window name, and
    " pane number of the location
    if strlen(l:active_vimuxide_session)!=0
        let l:tmux_target = split(l:active_vimuxide_session)

        let b:vimuxide_tmux_sessionname = l:tmux_target[0]
        let b:vimuxide_tmux_windowname = l:tmux_target[1]
        let b:vimuxide_tmux_panenumber = l:tmux_target[2]

    " if interactive program cannot be found locally, or within last active
    " session, search within all available tmux sessions
    else
        let l:remote_vimuxide_session = 
                \system("tmux list-panes -aF '#{session_name} #{window_index} #P #{pane_title}' | grep ".a:program_title." | grep -o '^\\w\\+ \w\\+ \\w\\+'")


        " if interactive program is found, save the session name, window name,
        " and pane number of the location
        if strlen(l:remote_vimuxide_session)!=0
            let l:tmux_target = split(l:remote_vimuxide_session)
            let b:vimuxide_tmux_sessionname = l:tmux_target[0]
            let b:vimuxide_tmux_windowname = l:tmux_target[1]
            let b:vimuxide_tmux_panenumber = l:tmux_target[2]

        " if interactive session is not found, set all adresses to 999 for error
        " handling
        else
            let b:vimuxide_tmux_sessionname = 999
            let b:vimuxide_tmux_windowname = 999
            let b:vimuxide_tmux_panenumber = 999
        endif
    endif
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

  " Check if buffer variable exists
  let l:buffer_variable_exists = exists('b:vimuxide_tmux_sessionname') &&
              \exists('b:vimuxide_tmux_windowname') &&
              \exists('b:vimuxide_tmux_panenumber')

  " if buffer variable does not exist, check if global variables exist
  if !l:buffer_variable_exists
      let l:global_variable_exists = exists('g:vimuxide_tmux_sessionname') &&
                  \exists('g:vimuxide_tmux_windowname') &&
                  \exists('g:vimuxide_tmux_panenumber')

      " if global variables does not exist, search for appropriate tmux
      " session
      if !l:global_variable_exists
          let b:vimuxide_n_files=10
          call TmuxSessionFinder(b:vimuxide_program_title)

      else
          let b:vimuxide_n_files = GetVar('vimuxide_n_files', 10)
          let b:vimuxide_tmux_sessionname = g:vimuxide_tmux_sessionname
          let b:vimuxide_tmux_windowname = g:vimuxide_tmux_windowname
          let b:vimuxide_tmux_panenumber = g:vimuxide_tmux_panenumber
      endif
 endif
endfunction

function! g:CallSystem(cmd)
  " Execute the given system command, reporting errors if any
  let l:out = system(a:cmd)
  if v:shell_error != 0
    echom 'Vimuxide, error running ' . a:cmd . ' : ' . l:out
  end
endfunction

function! CopyToTmux(code, run_command)
    if b:vimuxide_tmux_sessionname == 999
        call UnsetTmuxSettings()
        echom 'Appropriate Tmux/'.&filetype.' Session DOES NOT EXIST!'
        return
    else
        " Copy the given code to tmux. We use a temp file for that
        " If the file is empty, it seems like tmux load-buffer keep the current
        " buffer and this cause the last command to be repeated. We do not want that
        " to happen, so add a dummy string
        let l:lines = split(a:code, "\n")

        let l:n_lines = len(l:lines)
        if l:n_lines == 0
            call add(l:lines, ' ')
        end

        let l:vimuxide_fname = GetNextTempFile()
        call writefile(l:lines, l:vimuxide_fname)

        " tmux format for target is {session}:{window}.{pane}, e.g., 0:0:0
        let target = b:vimuxide_tmux_sessionname . ':'
                   \ . b:vimuxide_tmux_windowname . '.'
                   \ . b:vimuxide_tmux_panenumber

        " clear the command prompt first, before sending the code
        call CallSystem("tmux send-keys -t ".target." C-c")
        " send command to target tmux session:window.pane
        call CallSystem("tmux send-keys -t ".target." '".a:run_command." ".l:vimuxide_fname."' C-m")

        " below is python specific.. should think about how to change this when
        " other language is added
        " ipython requires multiple enter keys that depends on line length
        " after loading code with %load -y file
        if l:n_lines > 1
            call CallSystem("tmux send-keys -t ".target." C-m C-m")
        else
            call CallSystem("tmux send-keys -t ".target." C-m")
        endif

        " output messages to tell where code is pasted 
        echom 'Code is Successfully Copied to '.b:vimuxide_tmux_sessionname.':'.b:vimuxide_tmux_windowname.'.'.b:vimuxide_tmux_panenumber
    endif
endfunction

function! CodeUnindent(code)
    " The code is unindented so the first selected line has 0 indentation
    " So you can select a statement from inside a function and it will run
    " without program such as python complaining about indentation.
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

function! TmuxSendReg()
  " Paste into tmux the content of the register @a after unindentation, if
  " there is a global indentation across the copied code block
  let l:code = CodeUnindent(@a)
  call CopyToTmux(l:code, b:vimuxide_run_command)
endfunction

function! TmuxSendCell(restore_cursor)
  " This is to emulate MATLAB's cell mode.
  
  " initialize tmux target address
  call DefaultVars()

  " save current view, and use this if cursor needs to be restored
  let l:winview = winsaveview()

  " \v in front of regular expression to avoid vim specific rules
  " however, for code blocks, special characters are used, so vim specific
  " rules are more useful
  let l:block_search_regex =
              \'\(^\s*\)\?'.g:vimuxide_block_separator

  " search for block separator to take care of each case
  let l:block_search_backward = search(l:block_search_regex, 'bnW')
  let l:block_search_forward = search(l:block_search_regex, 'nW')


  "=================== Different cases for block separators ==================
  " if block separator is found both top and bottom:
  if l:block_search_backward !=0 && l:block_search_forward !=0

      "ignore line with the block separator, this is required to get correct
      "indentation estimate.
      let l:line_start = l:block_search_backward+1
      let l:line_end = l:block_search_forward-1

      "copy lines within block separators
      silent :exec l:line_start.";".l:line_end."y a"
      let @a=join(split(@a, "\n"), "\n")

      "since this code block is within separator, this means that there is a
      "next block. so move into the next block
      let l:restore_cursor = 0

  " if block separator does not exist in the file:
  elseif l:block_search_backward == 0 && l:block_search_forward == 0
      silent :exec "%y a"
      let @a=join(split(@a, "\n"), "\n")

      " no need to move cursor, since there are no blocks anyways
      let l:restore_cursor = 1

  " if block separator only exists in the forward direciton:
  elseif l:block_search_backward == 0 
      let l:line_end = +l:block_search_forward-1

      silent :exec "1;".l:line_end."y a"
      let @a=join(split(@a, "\n"), "\n")

      " this also means that there is a next block. So move to the next block
      let l:restore_cursor = 0

  " if block separator only exists in the backward direciton:
  else
      let l:line_start = +l:block_search_backward+1
      silent :exec l:line_start.";$y a"

      let @a=join(split(@a, "\n"), "\n")

      " this means this block is the last block, so no need to move cursor
      let l:restore_cursor = 1
  end
  "=================== Different cases END==================

  " Now, we want to position ourselves inside the next block to allow block
  " execution chaining (of course if restore_cursor is true, this is a no-op)
  if a:restore_cursor || l:restore_cursor
    call winrestview(l:winview)
  else
     " move position to end of copied block
    execute "normal! ']"
     " move down to next block
    execute "normal! 2j"
  end

  " send copied code to existing tmux session
  call TmuxSendReg()
endfunction

function! TmuxSendAllCellsAbove()
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
  call TmuxSendReg()
  call setpos(".", l:cursor_pos)
endfunction

function! TmuxSendChunk() range
  call DefaultVars()
  " Yank current selection to register a
  silent normal gv"ay
  call TmuxSendReg()
endfunction

function! ResetTmuxSettings()
    "  reset both global and buffer variables to user input, 0:0.0 is predefined
    "  rest values
    let b:vimuxide_tmux_sessionname = input("New sessionname: ", '0')
    let b:vimuxide_tmux_windowname = input("New Window #: ", '0')
    let b:vimuxide_tmux_panenumber = input("New Pane #: ", '0')
endfunction

function! UnsetTmuxSettings()
    " unset variables, so automatic session finding can work again
    if exists('b:vimuxide_tmux_sessionname') &&
              \exists('b:vimuxide_tmux_windowname') &&
              \exists('b:vimuxide_tmux_panenumber')
      unlet b:vimuxide_tmux_sessionname
      unlet b:vimuxide_tmux_windowname
      unlet b:vimuxide_tmux_panenumber
    endif

    if exists('g:vimuxide_tmux_sessionname') &&
              \exists('g:vimuxide_tmux_windowname') &&
              \exists('g:vimuxide_tmux_panenumber')
      unlet g:vimuxide_tmux_sessionname
      unlet g:vimuxide_tmux_windowname
      unlet g:vimuxide_tmux_panenumber
    endif
endfunction

call InitVariable("g:vimuxide_default_mappings", 1)
