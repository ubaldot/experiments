# Termdebug9: how to test it

Verify that you have `gdb` installed. Then either you run the tests
automatically by sourcing `test/run_tests.sh` script or you can do the
following:

If you want to give it a shot manually, do the following:

1. Clone the repo
2. Run `:source termdebug9.vim`
3. Run `:Termdebug`

Please, report any error that you may see.

Then, if things went fine, build the source code example contained in the
`source` folder with `gcc`. Run again `:Termdebug /path/to/your/built/file`
and do ordinary debug activities (add breakpoints, step, continue, etc).

For more info `:h Termdebug`.

Default mapings

    nnoremap <silent> B <cmd>Break<cr>
    nnoremap <silent> T <cmd>Tbreak<cr>
    nnoremap <silent> D <cmd>Clear<cr>
    nnoremap <silent> C <cmd>Continue<cr>
    nnoremap <silent> I <cmd>Step<cr>
    nnoremap <silent> O <cmd>Next<cr>
    nnoremap <silent> F <cmd>Finish<cr>
    nnoremap <silent> S <cmd>Stop<cr>
    nnoremap <silent> U <cmd>Until<cr>
    nnoremap <silent> K <cmd>Evaluate
    nnoremap <silent> R <cmd>Run<cr>
    nnoremap <silent> X <ScriptCmd>TermDebugSendCommand('set confirm off')<cr><ScriptCmd>TermDebugSendCommand('exit')<cr>
