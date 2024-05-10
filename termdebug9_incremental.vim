vim9script

# Debugger plugin using gdb.

# Author: Bram Moolenaar
# Copyright: Vim license applies, see ":help license"
# Last Change: 2023 Nov 02

# WORK IN PROGRESS - The basics works stable, more to come
# Note: In general you need at least GDB 7.12 because this provides the
# frame= response in MI thread-selected events we need to sync stack to file.
# The one included with "old" MingW is too old (7.6.1), you may upgrade it or
# use a newer version from http://www.equation.com/servlet/equation.cmd?fa=gdb

# There are two ways to run gdb:
# - In a terminal window; used if possible, does not work on MS-Windows
#   Not used when g:termdebug_use_prompt is set to 1.
# - Using a "prompt" buffer; may use a terminal window for the program

# For both the current window is used to view source code and shows the
# current statement from gdb.

# USING A TERMINAL WINDOW

# Opens two visible terminal windows:
# 1. runs a pty for the debugged program, as with ":term NONE"
# 2. runs gdb, passing the pty of the debugged program
# A third terminal window is hidden, it is used for communication with gdb.

# USING A PROMPT BUFFER

# Opens a window with a prompt buffer to communicate with gdb.
# Gdb is run as a job with callbacks for I/O.
# On Unix another terminal window is opened to run the debugged program
# On MS-Windows a separate console is opened to run the debugged program

# The communication with gdb uses GDB/MI.  See:
# https://sourceware.org/gdb/current/onlinedocs/gdb/GDB_002fMI.html

# TODO: uncomment
# In case this gets sourced twice.
# if exists(":Termdebug")
#   finish
# endif

# Former s: variables shall be declared outside

var way = 'terminal'
var err = 'no errors'

var pc_id = 12
var asm_id = 13
var break_id = 14  # breakpoint number is added to this
var stopped = 1
var running = 0

var parsing_disasm_msg = 0
var asm_lines = []
var asm_addr = ''

# These shall be constants but cannot be initialized here
# They indicate the buffer numbers of the main buffers used
var gdbbuf = 0
var varbuf = 0
var asmbuf = 0
var promptbuf = 0
# This is for the "debugged program" thing
var ptybuf = 0
var commbuf = 0

# UBA They shall be initialized with... nothing.
var gdbjob = job_start('NONE')
var gdb_channel = ch_open('127.0.0.1:1234')
# These changes because they relate to windows
var pid = 0
var gdbwin = 0
var varwin = 0
var asmwin = 0
var ptywin = 0
var sourcewin = 0

# Contains breakpoints that have been placed, key is a string with the GDB
# breakpoint number.
# Each entry is a dict, containing the sub-breakpoints.  Key is the subid.
# For a breakpoint that is just a number the subid is zero.
# For a breakpoint "123.4" the id is "123" and subid is "4".
# Example, when breakpoint "44", "123", "123.1" and "123.2" exist:
# {'44': {'0': entry}, '123': {'0': entry, '1': entry, '2': entry}}
var breakpoints = {}

# Contains breakpoints by file/lnum.  The key is "fname:lnum".
# Each entry is a list of breakpoint IDs at that position.
var breakpoint_locations = {}


var evalFromBalloonExpr = 1
var evalFromBalloonExprResult = ''
var ignoreEvalError = 1

# Remember the old value of 'signcolumn' for each buffer that it's set in, so
# that we can restore the value for all buffers.
var signcolumn_buflist = [bufnr()]
var save_columns = 0

var allleft = 0
# This was s:vertical but I cannot use vertical as variable name
var vvertical = 0

# Need either the +terminal feature or +channel and the prompt buffer.
# The terminal feature does not work with gdb on win32.
if has('terminal') && !has('win32')
    way = 'terminal'
elseif has('channel') && exists('*prompt_setprompt')
    way = 'prompt'
else
    if has('terminal')
        err = 'Cannot debug, missing prompt buffer support'
    else
        err = 'Cannot debug, +channel feature is not supported'
    endif
    command! -nargs=* -complete=file -bang Termdebug echoerr err
    command -nargs=+ -complete=file -bang TermdebugCommand echoerr err
    finish
endif

# UBA I think this could be removed in Vim9
var keepcpo = &cpo
set cpo&vim

# The command that starts debugging, e.g. ":Termdebug vim".
# To end type "quit" in the gdb window.
command -nargs=* -complete=file -bang Termdebug StartDebug(<bang>0, <f-args>)
command -nargs=+ -complete=file -bang TermdebugCommand StartDebugCommand(<bang>0, <f-args>)


# Take a breakpoint number as used by GDB and turn it into an integer.
# The breakpoint may contain a dot: 123.4 -> 123004
# The main breakpoint has a zero subid.
def Breakpoint2SignNumber(id: number, subid: number): number
    return break_id + id * 1000 + subid
enddef

# Define or adjust the default highlighting, using background "new".
# When the 'background' option is set then "old" has the old value.
def Highlight(init: bool, old: string, new: string)
    var default = init ? 'default ' : ''
    if new ==# 'light' && old !=# 'light'
        exe "hi " .. default .. "debugPC term=reverse ctermbg=lightblue guibg=lightblue"
    elseif new ==# 'dark' && old !=# 'dark'
        exe "hi " .. default .. "debugPC term=reverse ctermbg=darkblue guibg=darkblue"
    endif
enddef

# Define the default highlighting, using the current 'background' value.
def InitHighlight()
    call Highlight(1, '', &background)
    hi default debugBreakpoint term=reverse ctermbg=red guibg=red
    hi default debugBreakpointDisabled term=reverse ctermbg=gray guibg=gray
enddef

# Setup an autocommand to redefine the default highlight when the colorscheme
# is changed.
def InitAutocmd()
    augroup TermDebug
        autocmd!
        autocmd ColorScheme * InitHighlight()
    augroup END
enddef

# Get the command to execute the debugger as a list, defaults to ["gdb"].
def GetCommand(): list<string>
    var cmd = 'gdb'
    # UBA
    cmd = 'arm-none-eabi-gdb'
    if exists('g:termdebug_config')
            = get(g:termdebug_config, 'command', 'gdb')
    elseif exists('g:termdebugger')
        cmd = g:termdebugger
    endif

    # Sweet!
    return type(cmd) == v:t_list ? copy(cmd) : [cmd]
enddef

def Echoerr(msg: string)
    echohl ErrorMsg | echom '[termdebug] ' .. msg | echohl None
enddef

def StartDebug(bang: bool, ...gdb_args: list<string>)
    # First argument is the command to debug, second core file or process ID.
    StartDebug_internal({'gdb_args': gdb_args, 'bang': bang})
enddef

def StartDebugCommand(bang: bool, ...args: list<string>) # TODO: check bang arg
    # First argument is the command to debug, rest are run arguments.
    StartDebug_internal({'gdb_args': [args[0]], 'proc_args': args[1:], 'bang': bang})
enddef


def StartDebug_internal(dict: dict<any>)
    if gdbbuf > 0
        Echoerr('Terminal debugger already running, cannot run two')
        return
    endif
    var gdbcmd = GetCommand()
    if !executable(gdbcmd[0])
        Echoerr('Cannot execute debugger program "' .. gdbcmd[0] .. '"')
        return
    endif

    if exists('#User#TermdebugStartPre')
        doauto <nomodeline> User TermdebugStartPre
    endif

    # Uncomment this line to write logging in "debuglog".
    # call ch_logfile('debuglog', 'w')

    # Assume current window is the source code window
    sourcewin = win_getid()
    save_columns = 0
    allleft = 0
    var wide = 0

    if exists('g:termdebug_config')
        wide = get(g:termdebug_config, 'wide', 0)
    elseif exists('g:termdebug_wide')
        wide = g:termdebug_wide
    endif
    if wide > 0
        if &columns < wide
            save_columns = &columns
            &columns = wide
            # If we make the Vim window wider, use the whole left half for the debug
            # windows.
            allleft = 1
        endif
        vvertical = 1
    else
        vvertical = 0
    endif

    # Override using a terminal window by setting g:termdebug_use_prompt to 1.
    var use_prompt = 0
    if exists('g:termdebug_config')
        use_prompt = get(g:termdebug_config, 'use_prompt', 0)
    elseif exists('g:termdebug_use_prompt')
        use_prompt = g:termdebug_use_prompt
    endif
    if has('terminal') && !has('win32') && !use_prompt
        way = 'terminal'
    else
        way = 'prompt'
    endif

    # UBA
    way = 'prompt'

    if way == 'prompt'
        StartDebug_prompt(dict)
    else
        StartDebug_term(dict)
    endif

    # TODO Add eventual other windows here
    # if GetDisasmWindow()
    #   var curwinid = win_getid()
    #   GotoAsmwinOrCreateIt()
    #   win_gotoid(curwinid)
    # endif

    # if GetVariablesWindow()
    #    var curwinid = win_getid()
    #    GotoVariableswinOrCreateIt()
    #    win_gotoid(curwinid)
    # endif

    if exists('#User#TermdebugStartPost')
        doauto <nomodeline> User TermdebugStartPost
    endif
enddef

# Use when debugger didn't start or ended.
def CloseBuffers()
    if ptybuf > 0
        exe 'bwipe! ' .. ptybuf
    endif
    if commbuf > 0
        exe 'bwipe! ' .. commbuf
    endif
    if asmbuf > 0 && bufexists(asmbuf)
        exe 'bwipe! ' .. asmbuf
    endif
    if varbuf > 0 && bufexists(varbuf)
        exe 'bwipe! ' .. varbuf
    endif
    running = 0
    # TODO: Check if this is OK
    # unlet! gdbwin = 0
    gdbwin = 0
enddef

def CheckGdbRunning(): string
    var gdbproc = term_getjob(gdbbuf)
    var gdbproc_status = 'unknwown'
    if type(gdbproc) == v:t_job
        gdbproc_status = job_status(gdbproc)
    endif
    if gdbproc == v:null || gdbproc_status !=# 'run'
        Echoerr(string(GetCommand()[0]) .. ' exited unexpectedly')
        CloseBuffers()
        return ''
    endif
    return 'ok'
enddef

# Open a terminal window without a job, to run the debugged program in.
def StartDebug_term(dict: dict<any>)
    ptybuf = term_start('NONE', {
                \ 'term_name': 'debugged program',
                \ 'vertical': vvertical,
                \ })
    if ptybuf == 0
        Echoerr('Failed to open the program terminal window')
        return
    endif
    var pty = job_info(term_getjob(ptybuf))['tty_out']
    ptywin = win_getid()
    if vvertical
        # Assuming the source code window will get a signcolumn, use two more
        # columns for that, thus one less for the terminal window.
        exe (&columns / 2 - 1) .. "wincmd |"
        if allleft
            # use the whole left column
            wincmd H
        endif
    endif

    # Create a hidden terminal window to communicate with gdb
    commbuf = term_start('NONE', {
                \ 'term_name': 'gdb communication',
                \ 'out_cb': function('CommOutput'),
                \ 'hidden': 1,
                \ })
    if commbuf == 0
        Echoerr('Failed to open the communication terminal window')
        exe 'bwipe! ' .. ptybuf
        return
    endif
    var commpty = job_info(term_getjob(commbuf))['tty_out']

    var gdb_args = get(dict, 'gdb_args', [])
    var proc_args = get(dict, 'proc_args', [])

    var gdb_cmd = GetCommand()

    if exists('g:termdebug_config') && has_key(g:termdebug_config, 'command_add_args')
        gdb_cmd = g:termdebug_config.command_add_args(gdb_cmd, pty)
    else
        # Add -quiet to avoid the intro message causing a hit-enter prompt.
        gdb_cmd += ['-quiet']
        # Disable pagination, it causes everything to stop at the gdb
        gdb_cmd += ['-iex', 'set pagination off']
        # Interpret commands while the target is running.  This should usually only
        # be exec-interrupt, since many commands don't work properly while the
        # target is running (so execute during startup).
        gdb_cmd += ['-iex', 'set mi-async on']
        # Open a terminal window to run the debugger.
        gdb_cmd += ['-tty', pty]
        # Command executed _after_ startup is done, provides us with the necessary
        # feedback
        gdb_cmd += ['-ex', 'echo startupdone\n']
    endif

    if exists('g:termdebug_config') && has_key(g:termdebug_config, 'command_filter')
        gdb_cmd = g:termdebug_config.command_filter(gdb_cmd)
    endif

    # Adding arguments requested by the user
    gdb_cmd += gdb_args
    echo "starting gdb with: " .. join(gdb_cmd)

    ch_log('executing "' .. join(gdb_cmd) .. '"')
    # TODO: for the other windows create first a split and then wincmd L. Resize
    # also a bit
    gdbbuf = term_start(gdb_cmd, {
                \ 'term_name': gdb_cmd[0],
                \ 'term_finish': 'close',
                \ })
    # \ 'term_name': 'gdb',
    # UBA
    if gdbbuf == 0
        Echoerr('Failed to open the gdb terminal window')
        CloseBuffers()
        return
    endif
    gdbwin = win_getid()

    # Wait for the "startupdone" message before sending any commands.
    var counter = 0
    var counter_max = 300
    var success = false
    while success == false && counter < counter_max
        if CheckGdbRunning() != 'ok'
            # Failure. If NOK just return.
            # TODO: call CloseBuffers()?
            return
        endif

        for lnum in range(1, 200)
            if term_getline(gdbbuf, lnum) =~ 'startupdone'
                success = true
            endif
        endfor

        # Each count is 10ms
        counter += 1
        sleep 10m
    endwhile

    if success == false
        Echoerr('Failed to startup the gdb program.')
        CloseBuffers()
        return
    endif

    # ---- gdb started. Next, let's set the MI interface. ---
    # Set arguments to be run.
    if len(proc_args)
        term_sendkeys(gdbbuf, 'server set args ' .. join(proc_args) .. "\r")
    endif

    # Connect gdb to the communication pty, using the GDB/MI interface.
    # Prefix "server" to avoid adding this to the history.
    term_sendkeys(gdbbuf, 'server new-ui mi ' .. commpty .. "\r")

    # Wait for the response to show up, users may not notice the error and wonder
    # why the debugger doesn't work.
    counter = 0
    counter_max = 300
    success = false
    while success == false && counter < counter_max
        if CheckGdbRunning() != 'ok'
            return
        endif

        var response = ''
        for lnum in range(1, 200)
            var line1 = term_getline(gdbbuf, lnum)
            var line2 = term_getline(gdbbuf, lnum + 1)
            if line1 =~ 'new-ui mi '
                # response can be in the same line or the next line
                response = line1 .. line2
                if response =~ 'Undefined command'
                    Echoerr('Sorry, your gdb is too old, gdb 7.12 is required')
                    # CHECKME: possibly send a "server show version" here
                    CloseBuffers()
                    return
                endif
                if response =~ 'New UI allocated'
                    # Success!
                    success = true
                endif
            elseif line1 =~ 'Reading symbols from' && line2 !~ 'new-ui mi '
                # Reading symbols might take a while, try more times
                counter -= 1
            endif
        endfor
        if response =~ 'New UI allocated'
            break
        endif
        counter += 1
        sleep 10m
    endwhile

    if success == false
        Echoerr('Cannot check if your gdb works, continuing anyway')
        return
    endif

    job_setoptions(term_getjob(gdbbuf), {'exit_cb': function('EndTermDebug')})

    # Set the filetype, this can be used to add mappings.
    set filetype=termdebug

    StartDebugCommon(dict)
enddef

# Open a window with a prompt buffer to run gdb in.
def StartDebug_prompt(dict: dict<any>)
    if vvertical
        vertical new
    else
        new
    endif
    gdbwin = win_getid()
    promptbuf = bufnr('')
    prompt_setprompt(promptbuf, 'gdb> ')
    set buftype=prompt
    # UBA
    # file gdb
    file arm-none-eabi-gdb
    # TODO
    prompt_setcallback(promptbuf, function('PromptCallback'))
    prompt_setinterrupt(promptbuf, function('PromptInterrupt'))

    if vvertical
        # Assuming the source code window will get a signcolumn, use two more
        # columns for that, thus one less for the terminal window.
        exe (&columns / 2 - 1) .. "wincmd |"
    endif

    var gdb_args = get(dict, 'gdb_args', [])
    var proc_args = get(dict, 'proc_args', [])

    var gdb_cmd = GetCommand()
    # Add -quiet to avoid the intro message causing a hit-enter prompt.
    gdb_cmd += ['-quiet']
    # Disable pagination, it causes everything to stop at the gdb, needs to be run early
    gdb_cmd += ['-iex', 'set pagination off']
    # Interpret commands while the target is running.  This should usually only
    # be exec-interrupt, since many commands don't work properly while the
    # target is running (so execute during startup).
    gdb_cmd += ['-iex', 'set mi-async on']
    # directly communicate via mi2
    gdb_cmd += ['--interpreter=mi2']

    # Adding arguments requested by the user
    gdb_cmd += gdb_args

    ch_log('executing "' .. join(gdb_cmd) .. '"')
    gdbjob = job_start(gdb_cmd, {
                \ 'exit_cb': function('EndPromptDebug'),
                \ 'out_cb': function('GdbOutCallback'),
                \ })
    if job_status(gdbjob) != "run"
        Echoerr('Failed to start gdb')
        exe 'bwipe! ' .. promptbuf
        return
    endif
    exe $'au BufUnload <buffer={promptbuf}> ++once ' ..
                \ 'call job_stop(gdbjob, ''kill'')'
    # Mark the buffer modified so that it's not easy to close.
    set modified
    gdb_channel = job_getchannel(gdbjob)

    ptybuf = 0
    if has('win32')
        # MS-Windows: run in a new console window for maximum compatibility
        SendCommand('set new-console on')
    elseif has('terminal')
        # Unix: Run the debugged program in a terminal window.  Open it below the
        # gdb window.
        belowright ptybuf = term_start('NONE', {
                    \ 'term_name': 'debugged program',
                    \ })
        if ptybuf == 0
            Echoerr('Failed to open the program terminal window')
            job_stop(gdbjob)
            return
        endif
        ptywin = win_getid()
        var pty = job_info(term_getjob(ptybuf))['tty_out']
        SendCommand('tty ' .. pty)

        # Since GDB runs in a prompt window, the environment has not been set to
        # match a terminal window, need to do that now.
        SendCommand('set env TERM = xterm-color')
        SendCommand('set env ROWS = ' .. winheight(ptywin))
        SendCommand('set env LINES = ' .. winheight(ptywin))
        SendCommand('set env COLUMNS = ' .. winwidth(ptywin))
        SendCommand('set env COLORS = ' .. &t_Co)
        SendCommand('set env VIM_TERMINAL = ' .. v:version)
    else
        # TODO: open a new terminal, get the tty name, pass on to gdb
        SendCommand('show inferior-tty')
    endif
    SendCommand('set print pretty on')
    SendCommand('set breakpoint pending on')

    # Set arguments to be run
    if len(proc_args)
        SendCommand('set args ' .. join(proc_args))
    endif

    StartDebugCommon(dict)
    startinsert
enddef

def StartDebugCommon(dict: dict<any>)
    # Sign used to highlight the line where the program has stopped.
    # There can be only one.
    sign_define('debugPC', {'linehl': 'debugPC'})

    # Install debugger commands in the text window.
    win_gotoid(sourcewin)
    # InstallCommands()
    win_gotoid(gdbwin)

    # Enable showing a balloon with eval info
    if has("balloon_eval") || has("balloon_eval_term")
        set balloonexpr=TermDebugBalloonExpr()
        if has("balloon_eval")
            set ballooneval
        endif
        if has("balloon_eval_term")
            set balloonevalterm
        endif
    endif

    augroup TermDebug
        au BufRead * BufRead()
        au BufUnload * BufUnloaded()
        au OptionSet background Highlight(0, v:option_old, v:option_new)
    augroup END

    # Run the command if the bang attribute was given and got to the debug
    # window.
    if get(dict, 'bang', 0)
        SendResumingCommand('-exec-run')
        win_gotoid(ptywin)
    endif
enddef

# Send a command to gdb.  "cmd" is the string without line terminator.
def SendCommand(cmd: string)
    ch_log('sending to gdb: ' .. cmd)
    if way == 'prompt'
        ch_sendraw(gdb_channel, cmd .. "\n")
    else
        term_sendkeys(commbuf, cmd .. "\r")
    endif
enddef

# This is global so that a user can create their mappings with this.
def TermDebugSendCommand(cmd: string)
    if way == 'prompt'
        ch_sendraw(gdb_channel, cmd . "\n")
    else
        var do_continue = 0
        if !stopped
            var do_continue = 1
            Stop
            sleep 10m
        endif
        # TODO: should we prepend CTRL-U to clear the command?
        term_sendkeys(gdbbuf, cmd . "\r")
        if do_continue
            Continue
        endif
    endif
enddef

# Send a command that resumes the program.  If the program isn't stopped the
# command is not sent (to avoid a repeated command to cause trouble).
# If the command is sent then reset stopped.
def SendResumingCommand(cmd: string)
    if stopped
        # reset stopped here, it may take a bit of time before we get a response
        stopped = 0
        ch_log('assume that program is running after this command')
        SendCommand(cmd)
    else
        ch_log('dropping command, program is running: ' .. cmd)
    endif
enddef

# Function called when entering a line in the prompt buffer.
def PromptCallback(text: string)
    SendCommand(text)
enddef

# Function called when pressing CTRL-C in the prompt buffer and when placing a
# breakpoint.
def PromptInterrupt()
    ch_log('Interrupting gdb')
    if has('win32')
        # Using job_stop() does not work on MS-Windows, need to send SIGTRAP to
        # the debugger program so that gdb responds again.
        if pid == 0
            Echoerr('Cannot interrupt gdb, did not find a process ID')
        else
            debugbreak(pid)
        endif
    else
        job_stop(gdbjob, 'int')
    endif
enddef

# Function called when gdb outputs text.
# UBA: Valid only in debug prompt?
def GdbOutCallback(channel: any, text: string)
    ch_log('received from gdb: ' .. text)

    # Disassembly messages need to be forwarded as-is.
    if parsing_disasm_msg
        CommOutput(channel, text)
        return
    endif

    # Drop the gdb prompt, we have our own.
    # Drop status and echo'd commands.
    if text == '(gdb) ' || text == '^done' ||
                \ (text[0] == '&' && text !~ '^&"disassemble')
        return
    endif

    var decoded_text = ''
    if text =~ '^\^error,msg='
        # UBA
        # decoded_text = "foo"
        decoded_text = DecodeMessage(text[11 : ], false)
        if exists('evalexpr') && decoded_text =~ 'A syntax error in expression, near\|No symbol .* in current context'
            # Silently drop evaluation errors.
            # UBA commented this
            # unlet evalexpr
            return
        endif
    elseif text[0] == '~'
        decoded_text = DecodeMessage(text[1 : ], false)
    # UBA
    # decoded_text = "foo"
    else
        CommOutput(channel, text)
        return
    endif

    var curwinid = win_getid()
    win_gotoid(gdbwin)

    # Add the output above the current prompt.
    append(line('$') - 1, decoded_text)
    set modified

    win_gotoid(curwinid)
enddef

# Decode a message from gdb.  "quotedText" starts with a ", return the text up
# to the next unescaped ", unescaping characters:
# - remove line breaks (unless "literal" is v:true)
# - change \" to "
# - change \\t to \t (unless "literal" is v:true)
# - change \0xhh to \xhh (disabled for now)
# - change \ooo to octal
# - change \\ to \
#   UBA: we may use the standard MI message formats?
def DecodeMessage(quotedText: string, literal: bool): string
    if quotedText[0] != '"'
        Echoerr('DecodeMessage(): missing quote in ' .. quotedText)
        return ''
    endif
    var msg = quotedText
                \ ->substitute('^"\|[^\\]\zs".*', '', 'g')
                \ ->substitute('\\"', '"', 'g')
                #\ multi-byte characters arrive in octal form
                #\ NULL-values must be kept encoded as those break the string otherwise
                \ ->substitute('\\000', NullRepl, 'g')
                # UBA IMPORTANT! Why a lambda function as second argument of substitute? (The
                # following is the original)
                # \ ->substitute('\\\o\o\o',  => eval('"' .. submatch(0) .. '"'), 'g')
                \ ->substitute('\\\o\o\o',  eval('"' .. submatch(0) .. '"'), 'g')
                #\ Note: GDB docs also mention hex encodings - the translations below work
                #\       but we keep them out for performance-reasons until we actually see
                #\       those in mi-returns
                #\ \ ->substitute('\\0x\(\x\x\)', {-> eval('"\x' .. submatch(1) .. '"')}, 'g')
                #\ \ ->substitute('\\0x00', NullRepl, 'g')
                \ ->substitute('\\\\', '\', 'g')
                \ ->substitute(NullRepl, '\\000', 'g')
    if !literal
        # UBA
        # echom msg
        return msg
                    \ ->substitute('\\t', "\t", 'g')
                    \ ->substitute('\\n', '', 'g')
    else
        # UBA
        # echom msg
        return msg
    endif
enddef
const NullRepl = 'XXXNULLXXX'

# Extract the "name" value from a gdb message with fullname="name".
def GetFullname(msg: string)
    if msg !~ 'fullname'
        return ''
    endif

    var name = DecodeMessage(substitute(msg, '.*fullname=', '', ''), true)
    if has('win32') && name =~ ':\\\\'
        # sometimes the name arrives double-escaped
        name = substitute(name, '\\\\', '\\', 'g')
    endif

    return name
enddef

# Extract the "addr" value from a gdb message with addr="0x0001234".
def GetAsmAddr(msg: string)
    if msg !~ 'addr='
        return ''
    endif

    var addr = DecodeMessage(substitute(msg, '.*addr=', '', ''), false)
    return addr
enddef


def EndTermDebug(job: any, status: any)
    if exists('#User#TermdebugStopPre')
        doauto <nomodeline> User TermdebugStopPre
    endif

    exe 'bwipe! ' .. commbuf
    # unlet gdbwin
    gdbwin = 0
    EndDebugCommon()
enddef

def EndDebugCommon()
    var curwinid = win_getid()

    if ptybuf > 0
        exe 'bwipe! ' .. ptybuf
    endif
    if asmbuf > 0
        exe 'bwipe! ' .. asmbuf
    endif
    if varbuf > 0
        exe 'bwipe! ' .. varbuf
    endif
    running = 0

    # Restore 'signcolumn' in all buffers for which it was set.
    win_gotoid(sourcewin)
    var was_buf = bufnr()
    for bufnr in signcolumn_buflist
        if bufexists(bufnr)
            exe ":" .. bufnr .. "buf"
            if exists('b:save_signcolumn')
                &signcolumn = b:save_signcolumn
                unlet b:save_signcolumn
            endif
        endif
    endfor
    if bufexists(was_buf)
        exe ":" .. was_buf .. "buf"
    endif

    # UBA
    # DeleteCommands()

    win_gotoid(curwinid)

    if save_columns > 0
        &columns = save_columns
    endif

    if has("balloon_eval") || has("balloon_eval_term")
        set balloonexpr=
        if has("balloon_eval")
            set noballooneval
        endif
        if has("balloon_eval_term")
            set noballoonevalterm
        endif
    endif

    if exists('#User#TermdebugStopPost')
        doauto <nomodeline> User TermdebugStopPost
    endif

    au! TermDebug
enddef

def EndPromptDebug(job: any, status: any)
    if exists('#User#TermdebugStopPre')
        doauto <nomodeline> User TermdebugStopPre
    endif

    if bufexists(promptbuf)
        exe 'bwipe! ' .. promptbuf
    endif

    EndDebugCommon()
    # UBA
    gdbwin = 0
    # unlet gdbwin
    ch_log("Returning from EndPromptDebug()")
enddef


# Disassembly window - added by Michael Sartain
#
# - CommOutput: &"disassemble $pc\n"
# - CommOutput: ~"Dump of assembler code for function main(int, char**):\n"
# - CommOutput: ~"   0x0000555556466f69 <+0>:\tpush   rbp\n"
# ...
# - CommOutput: ~"   0x0000555556467cd0:\tpop    rbp\n"
# - CommOutput: ~"   0x0000555556467cd1:\tret    \n"
# - CommOutput: ~"End of assembler dump.\n"
# - CommOutput: ^done

# - CommOutput: &"disassemble $pc\n"
# - CommOutput: &"No function contains specified address.\n"
# - CommOutput: ^error,msg="No function contains specified address."
def HandleDisasmMsg(msg: string)
    if msg =~ '^\^done'
        var curwinid = win_getid()
        if win_gotoid(s:asmwin)
            silent! %delete _
            setline(1, asm_lines)
            set nomodified
            set filetype=asm

            var lnum = search('^' .. asm_addr)
            if lnum != 0
                sign_unplace('TermDebug', {'id': asm_id})
                sign_place(asm_id, 'TermDebug', 'debugPC', '%', {'lnum': lnum})
            endif

            win_gotoid(curwinid)
        endif

        parsing_disasm_msg = 0
        asm_lines = []

    elseif msg =~ '^\^error,msg='
        if parsing_disasm_msg == 1
            # Disassemble call ran into an error. This can happen when gdb can't
            # find the function frame address, so let's try to disassemble starting
            # at current PC
            SendCommand('disassemble $pc,+100')
        endif
        parsing_disasm_msg = 0
    elseif msg =~ '^&"disassemble \$pc'
        if msg =~ '+100'
            # This is our second disasm attempt
            parsing_disasm_msg = 2
        endif
    elseif msg !~ '^&"disassemble'
        var value = substitute(msg, '^\~\"[ ]*', '', '')
        value = substitute(value, '^=>[ ]*', '', '')
        value = substitute(value, '\\n\"\r$', '', '')
        value = substitute(value, '\\n\"$', '', '')
        value = substitute(value, '\r', '', '')
        value = substitute(value, '\\t', ' ', 'g')

        if value != '' || !empty(asm_lines)
            add(asm_lines, value)
        endif
    endif
enddef
######## STUBS ##############################################################
def CommOutput(chan: any, msg: any)
    echom msg
enddef

def BufUnloaded()
    echom "Good bye!"
enddef


# StartDebug()
#
#
#
# vim: sw=2 sts=2 et
