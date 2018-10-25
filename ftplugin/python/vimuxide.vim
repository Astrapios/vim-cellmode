let b:vimuxide_program_title = GetVar("vimuxide_python_program_title", "python")
let b:vimuxide_run_command = GetVar("vimuxide_python_run_command", "%run -ni")
let b:vimuxide_block_separator = GetVar("vimuxide_block_separator", "# %%")

"Run entire python file
function! RunPythonFile()
    call DefaultVars()

    " if appropriate session does not exist
    if b:vimuxide_tmux_sessionname == 999
        call UnsetTmuxSettings()
        echom 'Appropriate Tmux/'.&filetype.' Session DOES NOT EXIST!'
        return

    " if appropriate session is found
    else
        " get file directory and file name
        let l:file_directory=expand('%:p:h')
        let l:file_name=expand('%:t')

        " define tmux session, window, and pane
        let l:target = b:vimuxide_tmux_sessionname . ':'
                 \ . b:vimuxide_tmux_windowname . '.'
                 \ . b:vimuxide_tmux_panenumber

        " define commands to send
        
        " For Future, should check to see if CWD is already the directory
        " containing source code
        let l:change_dir = "\"cd "."'".l:file_directory."'\" C-m"
        let l:run_file = "\"run "."'".l:file_name."'\" C-m"

        call CallSystem('tmux send-keys -t ' .l:target." C-c")
        call CallSystem('tmux send-keys -t ' .l:target." ".l:change_dir)
        call CallSystem('tmux send-keys -t ' .l:target." ".l:run_file)
    endif
endfunction

" keyboard mappings for python
if g:vimuxide_default_mappings
    vmap <silent> <C-c> :call TmuxSendChunk()<CR>
    noremap <silent> <C-b> :call TmuxSendCell(0)<CR>
    noremap <silent> <C-g> :call TmuxSendCell(1)<CR>
    noremap <F5> :update<CR>:call RunPythonFile()<CR>
    noremap <F7> :call ResetTmuxSettings()<CR>
    noremap <F8> :call UnsetTmuxSettings()<CR>
endif
