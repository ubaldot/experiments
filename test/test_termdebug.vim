vim9script
# Test for the termdebug plugin

import "./common.vim"
var WaitForAssert = common.WaitForAssert

var GDB = exepath('gdb')
if GDB->empty()
  throw 'Skipped: gdb is not found in $PATH'
endif

var GCC = exepath('gcc')
if GCC->empty()
  throw 'Skipped: gcc is not found in $PATH'
endif

def Generate_files(bin_name: string)
  var src_name = bin_name .. '.c'
  var lines =<< trim END
    #include <stdio.h>
    #include <stdlib.h>

    int isprime(int n)
    {
      if (n <= 1)
        return 0;

      for (int i = 2; i <= n / 2; i++)
        if (n % i == 0)
          return 0;

      return 1;
    }

    int main(int argc, char *argv[])
    {
      int n = 7;

      printf("%d is %s prime\n", n, isprime(n) ? "a" : "not a");

      return 0;
    }
  END
   writefile(lines, src_name)
   system($'{GCC} -g -o {bin_name} {src_name}')
enddef

def Cleanup_files(bin_name: string)
   delete(bin_name)
   delete(bin_name .. '.c')
enddef

import '../termdebug9.vim'

def g:Test_termdebug_basic()
  var bin_name = 'XTD_basic'
  var src_name = bin_name .. '.c'
  Generate_files(bin_name)

  edit XTD_basic.c
  Termdebug ./XTD_basic
  WaitForAssert(() => assert_equal(3, winnr('$')))
  var gdb_buf = winbufnr(1)
  wincmd b
  execute("Break 9")
  term_wait(gdb_buf)
  redraw!
  assert_equal([
        \ {'lnum': 9, 'id': 1014, 'name': 'debugBreakpoint1.0',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs)
  execute("Run")
  term_wait(gdb_buf, 400)
  redraw!
  WaitForAssert(() => assert_equal([
        \ {'lnum': 9, 'id': 12, 'name': 'debugPC', 'priority': 110,
        \  'group': 'TermDebug'},
        \ {'lnum': 9, 'id': 1014, 'name': 'debugBreakpoint1.0',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs))

  execute("Finish")
  term_wait(gdb_buf)
  redraw!
  WaitForAssert(() => assert_equal([
        \ {'lnum': 9, 'id': 1014, 'name': 'debugBreakpoint1.0',
        \  'priority': 110, 'group': 'TermDebug'},
        \ {'lnum': 20, 'id': 12, 'name': 'debugPC',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs))
  execute("Continue")
  term_wait(gdb_buf)

  var count = 2
  while count <= 258
    execute("Break")
    term_wait(gdb_buf)
    if count == 2
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint2.0')[0].text, '02'))
    endif
    if count == 10
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint10.0')[0].text, '0A'))
    endif
    if count == 168
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint168.0')[0].text, 'A8'))
    endif
    if count == 255
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint255.0')[0].text, 'FF'))
    endif
    if count == 256
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint256.0')[0].text, 'F+'))
    endif
    if count == 258
       WaitForAssert(() => assert_equal(sign_getdefined('debugBreakpoint258.0')[0].text, 'F+'))
    endif
    count += 1
  endwhile

  count = 0
  # 60 is approx spaceBuffer * 3
  if winwidth(0) <= 78 + 60
    execute("Var")
    assert_equal(winnr(), winnr('$'))
    assert_equal(winlayout(), ['col', [['leaf', 1002], ['leaf', 1001], ['leaf', 1000], ['leaf', 1003 + count]]])
    count += 1
    bw!
    execute("Asm")
    assert_equal(winnr(), winnr('$'))
    assert_equal(winlayout(), ['col', [['leaf', 1002], ['leaf', 1001], ['leaf', 1000], ['leaf', 1003 + count]]])
    count += 1
    bw!
  endif
  set columns=160
  term_wait(gdb_buf)
  var winw = winwidth(0)
  execute("Var")
  if winwidth(0) < winw
     assert_equal(winnr(), winnr('$') - 1)
     assert_equal(winlayout(), ['col', [['leaf', 1002], ['leaf', 1001], ['row', [['leaf', 1003 + count], ['leaf', 1000]]]]])
    count += 1
    bw!
  endif
  winw = winwidth(0)
  execute("Asm")
  if winwidth(0) < winw
     assert_equal(winnr(), winnr('$') - 1)
     assert_equal(winlayout(), ['col', [['leaf', 1002], ['leaf', 1001], ['row', [['leaf', 1003 + count], ['leaf', 1000]]]]])
    count += 1
    bw!
  endif
  set columns&
  term_wait(gdb_buf)

  wincmd t
  # quit Termdebug
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_equal([], sign_getplaced('', {'group': 'TermDebug'})[0].signs)

  Cleanup_files(bin_name)
  execute(":%bw!")
enddef

def g:Test_termdebug_tbreak()
  var bin_name = 'XTD_tbreak'
  var src_name = bin_name .. '.c'

  Generate_files(bin_name)

  execute 'edit ' .. src_name
  execute 'Termdebug ./' .. bin_name

  WaitForAssert(() => assert_equal(3, winnr('$')))
  var gdb_buf = winbufnr(1)
  wincmd b

  var bp_line = 22        # 'return' statement in main
  var temp_bp_line = 10   # 'if' statement in 'for' loop body
  execute ":Tbreak " .. temp_bp_line
  execute ":Break " .. bp_line

  term_wait(gdb_buf)
  redraw!
  # both temporary and normal breakpoint signs were displayed...
  assert_equal([
        \ {'lnum': temp_bp_line, 'id': 1014, 'name': 'debugBreakpoint1.0',
        \  'priority': 110, 'group': 'TermDebug'},
        \ {'lnum': bp_line, 'id': 2014, 'name': 'debugBreakpoint2.0',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs)

  execute("Run")
  term_wait(gdb_buf, 400)
  redraw!
  # debugPC sign is on the line where the temp. bp was set;
  # temp. bp sign was removed after hit;
  # normal bp sign is still present
  WaitForAssert(() => assert_equal([
        \ {'lnum': temp_bp_line, 'id': 12, 'name': 'debugPC', 'priority': 110,
        \  'group': 'TermDebug'},
        \ {'lnum': bp_line, 'id': 2014, 'name': 'debugBreakpoint2.0',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs))

  execute("Continue")
  term_wait(gdb_buf)
  redraw!
  # debugPC is on the normal breakpoint,
  # temp. bp on line 10 was only hit once
  WaitForAssert(() => assert_equal([
        \ {'lnum': bp_line, 'id': 12, 'name': 'debugPC', 'priority': 110,
        \  'group': 'TermDebug'},
        \ {'lnum': bp_line, 'id': 2014, 'name': 'debugBreakpoint2.0',
        \  'priority': 110, 'group': 'TermDebug'}],
        \ sign_getplaced('', {'group': 'TermDebug'})[0].signs))

  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_equal([], sign_getplaced('', {'group': 'TermDebug'})[0].signs)

  Cleanup_files(bin_name)
  execute(":%bw!")
enddef


def g:Test_termdebug_mapping()
  execute(":%bw!")
  assert_true(maparg('K', 'n', 0, 1)->empty())
  assert_true(maparg('-', 'n', 0, 1)->empty())
  assert_true(maparg('+', 'n', 0, 1)->empty())
  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  assert_false(maparg('K', 'n', 0, 1)->empty())
  assert_false(maparg('-', 'n', 0, 1)->empty())
  assert_false(maparg('+', 'n', 0, 1)->empty())
  assert_false(maparg('K', 'n', 0, 1).buffer)
  assert_false(maparg('-', 'n', 0, 1).buffer)
  assert_false(maparg('+', 'n', 0, 1).buffer)
  assert_equal(':Evaluate<CR>', maparg('K', 'n', 0, 1).rhs)
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_true(maparg('K', 'n', 0, 1)->empty())
  assert_true(maparg('-', 'n', 0, 1)->empty())
  assert_true(maparg('+', 'n', 0, 1)->empty())

  execute(":%bw!")
  nnoremap K :echom "K"<cr>
  nnoremap - :echom "-"<cr>
  nnoremap + :echom "+"<cr>
  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  assert_false(maparg('K', 'n', 0, 1)->empty())
  assert_false(maparg('-', 'n', 0, 1)->empty())
  assert_false(maparg('+', 'n', 0, 1)->empty())
  assert_false(maparg('K', 'n', 0, 1).buffer)
  assert_false(maparg('-', 'n', 0, 1).buffer)
  assert_false(maparg('+', 'n', 0, 1).buffer)
  assert_equal(':Evaluate<CR>', maparg('K', 'n', 0, 1).rhs)
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_false(maparg('K', 'n', 0, 1)->empty())
  assert_false(maparg('-', 'n', 0, 1)->empty())
  assert_false(maparg('+', 'n', 0, 1)->empty())
  assert_false(maparg('K', 'n', 0, 1).buffer)
  assert_false(maparg('-', 'n', 0, 1).buffer)
  assert_false(maparg('+', 'n', 0, 1).buffer)
  assert_equal(':echom "K"<cr>', maparg('K', 'n', 0, 1).rhs)

  execute(":%bw!")
  nnoremap <buffer> K :echom "bK"<cr>
  nnoremap <buffer> - :echom "b-"<cr>
  nnoremap <buffer> + :echom "b+"<cr>
  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  assert_true(maparg('K', 'n', 0, 1).buffer)
  assert_true(maparg('-', 'n', 0, 1).buffer)
  assert_true(maparg('+', 'n', 0, 1).buffer)
  assert_equal(maparg('K', 'n', 0, 1).rhs, ':echom "bK"<cr>')
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_true(maparg('K', 'n', 0, 1).buffer)
  assert_true(maparg('-', 'n', 0, 1).buffer)
  assert_true(maparg('+', 'n', 0, 1).buffer)
  assert_equal(':echom "bK"<cr>', maparg('K', 'n', 0, 1).rhs)

  execute(":%bw!")
enddef
#
def g:Test_termdebug_bufnames()
  # Test if user has filename/folders named gdb, Termdebug-gdb-console,
  # etc. in the current directory
  g:termdebug_config = {}
  g:termdebug_config['use_prompt'] = 1
  var filename = 'gdb'
  var replacement_filename = 'Termdebug-gdb-console'

  writefile(['This', 'is', 'a', 'test'], filename, 'D')
  # Throw away the file once the test has done.
  Termdebug
  # Once termdebug has completed the startup you should have 3 windows on screen
  WaitForAssert(() => assert_equal(3, winnr('$')))
  # A file named filename already exists in the working directory,
  # hence you must  the newly created buffer differently
  WaitForAssert(() => assert_false(bufexists(filename)))
  WaitForAssert(() => assert_true(bufexists(replacement_filename)))
  # Quit the debugger
  wincmd t
  quit!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  execute(":%bw!")

  # # Check if error message is in :message
  g:termdebug_config['disasm_window'] = 1
  filename = 'Termdebug-asm-listing'
  writefile(['This', 'is', 'a', 'test'], filename, 'D')
  # writefile(['This', 'is', 'a', 'test'], filename)
  # Check only the head of the error message
  var error_message = "You have a file/folder named '" .. filename .. "'"
  Termdebug
  # Once termdebug has completed the startup you should have 4 windows on screen
  WaitForAssert(() => assert_equal(4, winnr('$')))
  WaitForAssert(() => assert_true(execute('messages') =~ error_message))
  # Close Asm window
  wincmd b
  wincmd q
  # Jump to top window (gbd is located on top during the test)
  wincmd t
  # quit Termdebug
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_equal([], sign_getplaced('', {'group': 'TermDebug'})[0].signs)

  g:termdebug_config = {}
  execute(":%bw!")

enddef


# vim: shiftwidth=2 sts=2 expandtab
