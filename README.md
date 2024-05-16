# Termdebug9

## OBS! There are three branches

1. `AS-IS` is the porting "as-is" from legacy vim script to vim9
2. `main` is the main branch
3. `1-proposed changed` is the branch containing the changes described in the
   only issue in the issue tracker.

# How to test it

Verify that you have both `gcc` and `gdb` installed. Then do the following:

1. Download `termdebug9.vim` script
2. Run `:source termdebug9.vim`
3. Run `:Termdebug`

Please, report any error that you may see.

Then, if things went fine, build the source code example contained in the
`source` folder with `gcc`. Run again `:Termdebug /path/to/your/built/file`
and do ordinary debug activities (add breakpoints, step, continue, etc).

For more info `:h Termdebug`.
