vim9script

# Test for the termdebug plugin
# Copied and adjusted from Vim distribution

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
       WaitForAssert(() => assert_equal('02', sign_getdefined('debugBreakpoint2.0')[0].text))
    endif
    if count == 10
       WaitForAssert(() => assert_equal('0A', sign_getdefined('debugBreakpoint10.0')[0].text))
    endif
    if count == 168
       WaitForAssert(() => assert_equal('A8', sign_getdefined('debugBreakpoint168.0')[0].text))
    endif
    if count == 255
       WaitForAssert(() => assert_equal('FF', sign_getdefined('debugBreakpoint255.0')[0].text))
    endif
    if count == 256
       WaitForAssert(() => assert_equal('F+', sign_getdefined('debugBreakpoint256.0')[0].text))
    endif
    if count == 258
       WaitForAssert(() => assert_equal('F+', sign_getdefined('debugBreakpoint258.0')[0].text))
    endif
    count += 1
  endwhile

  count = 0
  # 60 is approx spaceBuffer * 3
  # if winwidth(0) <= 78 + 60
  #   execute("Var")
  #   assert_equal(winnr(), winnr('$'))
  #   # assert_equal(['col', [['leaf', 1002], ['leaf', 1001], ['leaf', 1000], ['leaf', 1003 + count]]], winlayout())
  #   # UBA: OBS: For some reason at Termdebug startup winid 1002 got lost. The same
  #   # for the other windows.
  #   assert_equal(['col', [['leaf', 1003], ['leaf', 1001], ['leaf', 1000], ['leaf', 1004 + count]]], winlayout())
  #   count += 1
  #   execute(':bw!')
  #   execute("Asm")
  #   assert_equal(winnr(), winnr('$'))
  #   assert_equal(['col', [['leaf', 1003], ['leaf', 1001], ['leaf', 1000], ['leaf', 1004 + count]]], winlayout())
  #   count += 1
  #   execute(':bw!')
  # endif

  # set columns=160
  # term_wait(gdb_buf)
  # var winw = winwidth(0)
  # execute("Var")
  # if winwidth(0) < winw
  #   assert_equal(winnr(), winnr('$') - 1)
  #   redraw!
  #   assert_equal(['col', [['leaf', 1003], ['leaf', 1001], ['row', [['leaf', 1004 + count], ['leaf', 1000]]]]], winlayout())
  #   count += 1
  #   execute(':bw!')
  # endif
  # winw = winwidth(0)
  # execute("Asm")
  # if winwidth(0) < winw
  #    assert_equal(winnr(), winnr('$') - 1)
  #    assert_equal(['col', [['leaf', 1003], ['leaf', 1001], ['row', [['leaf', 1004 + count], ['leaf', 1000]]]]], winlayout())
  #   count += 1
  #   execute(':bw!')
  # endif
  # set columns&
  # term_wait(gdb_buf)

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
  var default_key_mapping =
        \ ['R', 'C', 'B', 'D', 'S', 'O', 'F', 'X', 'I', 'U', 'K', 'T', '+', '-',]

  for key in default_key_mapping
    assert_true(maparg(key, 'n', 0, 1)->empty())
  endfor
  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  for key in default_key_mapping
    assert_false(maparg(key, 'n', 0, 1)->empty())
    assert_false(maparg(key, 'n', 0, 1).buffer)
  endfor
  assert_equal('<cmd>Evaluate', maparg('K', 'n', 0, 1).rhs)
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  assert_true(maparg('K', 'n', 0, 1)->empty())
  assert_true(maparg('-', 'n', 0, 1)->empty())
  assert_true(maparg('+', 'n', 0, 1)->empty())
  execute(":%bw!")

  for key in default_key_mapping
    exe $'nnoremap {key} :echom "{key}"<cr>'
  endfor

  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  for key in default_key_mapping
    assert_false(maparg(key, 'n', 0, 1)->empty())
    assert_false(maparg(key, 'n', 0, 1).buffer)
  endfor
  assert_equal('<cmd>Evaluate', maparg('K', 'n', 0, 1).rhs)
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  for key in default_key_mapping
    assert_false(maparg(key, 'n', 0, 1)->empty())
    assert_false(maparg(key, 'n', 0, 1).buffer)
  endfor
  assert_equal(':echom "K"<CR>', maparg('K', 'n', 0, 1).rhs)
  execute(":%bw!")

  # Termdebug overwrites everything if use_default_mapping is true
  for key in default_key_mapping
    exe $'nnoremap <buffer> {key} :echom "b{key}"<cr>'
  endfor

  Termdebug
  WaitForAssert(() => assert_equal(3, winnr('$')))
  wincmd b
  for key in default_key_mapping
    assert_true(maparg(key, 'n', 0, 1).buffer)
  endfor
  assert_equal(':echom "bK"<cr>', maparg('K', 'n', 0, 1).rhs)
  wincmd t
  quit!
  redraw!
  WaitForAssert(() => assert_equal(1, winnr('$')))
  for key in default_key_mapping
    assert_true(maparg(key, 'n', 0, 1).buffer)
  endfor
  assert_equal(':echom "bK"<cr>', maparg('K', 'n', 0, 1).rhs)
  execute(":%bw!")
enddef
#
def g:Test_termdebug_bufnames()
  # Test if user has filename/folders named gdb in the current directory
  g:termdebug_config = {}
  g:termdebug_config['use_prompt'] = 1
  var filename = 'gdb'
  var error_message = "You have a file/folder named '" .. filename .. "'"

  writefile(['This', 'is', 'a', 'test'], filename, 'D')
  # Throw away the file once the test has done.
  Termdebug
  # WaitForAssert(() => assert_true(execute('messages') =~ error_message))
  WaitForAssert(() => assert_equal(1, winnr('$')))
  wincmd t
  quit!
  # execute(":%bw!")
  redraw!
  sleep 5
enddef
