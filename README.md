VimuxIDE
============

VimuxIDE is a vim plugin that enables interaction between a script and a 
interpreter, such as *Ipython*, through *tmux*. The plugin currently supports 
Python and Matlab, however, it can be easily extended to other scripting 
languages. 

Requirements
------------

*tmux* > 2.6

Installation
------------

using vim-plug
    Plug 'astrapios/vimuxide'

Key mappings
-----------

By default, the following mappings are enabled :

* `<C-c>` sends the currently selected lines to *tmux*
* `<C-g>` sends the current block to *tmux*
* `<C-b>` sends the current block to *tmux* and moves cursor to the next block
* `<F5>` saves script if its updated, and then runs the entire script
* `<F7>` prompts user to provide *tmux* session, window, and pane info
* `<F8>` resets buffer variables that contain *tmux* session, window, and pane info

You can disable default mappings and redefine mappings by:

    let g:vimuxide_default_mappings='0'

    vmap <silent> <C-c> :call TmuxSendChunk()<CR>
    noremap <silent> <C-b> :call TmuxSendCell(0)<CR>
    noremap <silent> <C-g> :call TmuxSendCell(1)<CR>
    noremap <F5> :update<CR>:call RunPythonFile()<CR>
    noremap <F7> :call ResetTmuxSettings()<CR>
    noremap <F8> :call UnsetTmuxSettings()<CR>
    
In addition, there is a function to execute all cells above the current line
which isn't bound to any key by default, but one can easily bind it by:

    noremap <silent> <C-a> :call tmuxSendAllCellsAbove()<CR>

Options
-------

String separating blocks of code is defined using:

    g:vimuxide_block_separator

For python program the default is `'# %%'`.

Also, one can configure the target *tmux* session/window/pane manually using:

    g:vimuxide_tmux_sessionname
    g:vimuxide_tmux_windowname
    g:vimuxide_tmux_panenumber

If these global variables are not defined, the plugin will search for all
open *tmux* pane names to search for pane with the interpreter. For 
example, when python script is open in vim, the plugin searches for `'python'` from all *tmux* panes by default. Within *tmux*, pane name can be set using:

    *tmux* select-pane [-t <sessionName>:<windowName>.<PaneNumber>] -T <paneTitle>

This plugin relies on temporary files to send text from vim to *tmux*. To 
allow cell execution queuing, it uses a rolling buffer of temporary files. You 
can control the size of the buffer by defining:

    g:vimuxide_n_files
    
Otherwise, it is set to 10 by default.

One can define:

    g:vimuxide_program_title
    g:vimuxide_run_command

to override default search string for finding a *tmux* pane with an 
interpreter. `g:vimuxide_program_title` is the *tmux* pane name to search for 
the interpreter such as *ipython*, and `g:vimuxide_run_command` is the 
command used to run the block script. For example, for python filetype, the 
default values are `b:vimuxide_program_title='python'` and 
`b:vimuxide_run_command='%run -ni'`.

Usage
-----

Blocks are defined using `g:vimuxide_block_separator`. Otherwise, the plugin
asks for block separator string during runtime. Now consider the following python script with blocks defined using `# %%` : 

    import numpy as np
    print 'Hello'                    # (1)
    np.zeros(3)
    # %%
    if True:
        print 'Yay !'                # (2)
        print 'Foo'                  # (3)

If you put your cursor anywhere within the first block marked 
with (1), and hit `<C-G>`, the 3 lines in the first block will be sent to 
*tmux* without changing the cursor location.

If you hit `<C-B>`, the same will happen but the cursor will move to the line 
after the `# %%` (so that you can run a block at a time).

One can also visual select lines and hit `<C-C>` to send the selection to 
*tmux*. The visual mode is exited after execution. The plugin automatically 
de-indents selected lines so that the first line has no indentation. So even 
if you select the line marked (2) and (3), the print statements will be 
de-indented and sent to *tmux*. Therefore, *ipython* will correctly run them.

It is important to note that placing a block separator at the beginning or at 
the end of a script is completely optional. Therefore, they can be added or 
removed without altering the plugin behavior.
