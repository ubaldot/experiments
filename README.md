# Termdebug9: how to test it

Verify that you have both `gcc` and `gdb` installed.    
Then do the following:

1. Download `termdebug9.vim` script
2. Run `source termdebug9.vim`
3. Run `:Termdebug`

... the above as first steps. 

Then, build the source code example contained in the `source` folder.
Run again `:Termdebug /path/to/your/built/file` and do ordinary debug activities (add breakpoints, step, continue, etc). 

For more info `:h Termdebug`. 
