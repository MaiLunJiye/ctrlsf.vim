" Default Config {{{
if !exists('g:ctrlsf_open_left')
    let g:ctrlsf_open_left = 1
endif

if !exists('g:ctrlsf_ackprg')
    let g:ctrlsf_ackprg = 'ack'
endif

if !exists('g:ctrlsf_auto_close')
    let g:ctrlsf_auto_close = 1
endif

if !exists('g:ctrlsf_context')
    let g:ctrlsf_context = '-C 3'
endif
" }}}

" Global Variables {{{
let s:match_table    = []
let s:jump_table     = []
let s:ackprg_options = {}
" }}}

" Constants {{{
let s:ACK_ARGLIST = {
    \ '-A' : { 'argt': 'space', 'argc': 1, 'alias': '--after-context' },
    \ '-B' : { 'argt': 'space', 'argc': 1, 'alias': '--before-context' },
    \ '-C' : { 'argt': 'space', 'argc': 1, 'alias': '--context' },
    \ '-g' : { 'argt': 'space', 'argc': 1 },
    \ '--match' : { 'argt': 'space',  'argc': 1 },
    \ '--pager' : { 'argt': 'equals', 'argc': 1 },
    \ '--context'        : { 'argt': 'equals', 'argc': 1 },
    \ '--after-context'  : { 'argt': 'equals', 'argc': 1 },
    \ '--before-context' : { 'argt': 'equals', 'argc': 1 },
    \ '--file-from'      : { 'argt': 'equals', 'argc': 1 },
    \ }
let s:AG_ARGLIST = {
    \ '-A' : { 'argt': 'space', 'argc': 1, 'alias': '--after' },
    \ '-B' : { 'argt': 'space', 'argc': 1, 'alias': '--before' },
    \ '-C' : { 'argt': 'space', 'argc': 1, 'alias': '--context' },
    \ '-g' : { 'argt': 'space', 'argc': 1 },
    \ '-G' : { 'argt': 'space', 'argc': 1, 'alias': '--file-search-regex' },
    \ '-i' : { 'argt': 'none',  'argc': 0, 'alias': '--ignore-case' },
    \ '-m' : { 'argt': 'space', 'argc': 1, 'alias': '--max-count' },
    \ '-p' : { 'argt': 'space', 'argc': 1, 'alias': '--path-to-agignore' },
    \ '--after'       : { 'argt': 'space', 'argc': 1 },
    \ '--before'      : { 'argt': 'space', 'argc': 1 },
    \ '--context'     : { 'argt': 'space', 'argc': 1 },
    \ '--depth'       : { 'argt': 'space', 'argc': 1 },
    \ '--file-from'   : { 'argt': 'space', 'argc': 1 },
    \ '--ignore'      : { 'argt': 'space', 'argc': 1 },
    \ '--ignore-case' : { 'argt': 'none',  'argc': 0 },
    \ '--ignore-dir'  : { 'argt': 'space', 'argc': 1 },
    \ '--max-count'   : { 'argt': 'space', 'argc': 1 },
    \ '--pager'       : { 'argt': 'space', 'argc': 1 },
    \ '--file-search-regex' : { 'argt': 'space', 'argc': 1 },
    \ '--path-to-agignore'  : { 'argt': 'space', 'argc': 1 },
    \ }
let s:ARGLIST = {
    \ 'ack' : s:ACK_ARGLIST,
    \ 'ag'  : s:AG_ARGLIST,
    \ }
" }}}

func! CtrlSF#Search(args) abort
    call s:OpenWindow()

    call s:ParseAckprgOptions(a:args)

    let ackprg_output = system(s:BuildCommand(a:args))

    call s:ParseAckprgOutput(ackprg_output)

    setl modifiable
    silent %delete _
    silent 0put =s:RenderContent()
    setl nomodifiable

    if exists('b:current_syntax') && b:current_syntax == 'ctrlsf'
        call clearmatches()
        let pattern = s:ackprg_options['pattern']
        call matchadd('ctrlsfMatch', pattern)
    endif

    call cursor(1, 1)
endf

func! CtrlSF#OpenWindow() abort
    call s:OpenWindow()
endf

func! CtrlSF#CloseWindow() abort
    call s:CloseWindow()
endf

" A primitive approach. *CAN NOT* guarantee to parse correctly in the worst
" situation.
func! s:ParseAckprgOptions(args)
    let s:ackprg_options = {}

    let args = a:args
    let prg  = g:ctrlsf_ackprg

    " example: "a b" -> a\ b, "a\" b" -> a\"\ b
    let args = substitute(args, '\v(\\)@<!"(.{-})(\\)@<!"', '\=escape(submatch(2)," ")', 'g')

    " example: 'a b' -> a\ b
    let args = substitute(args, '\v''(.{-})''', '\=escape(submatch(1)," ")', 'g')

    let argv = split(args, '\v(\\)@<!\s+')
    call map(argv, 'substitute(v:val, ''\\ '', " ", "g")')

    let argc = len(argv)

    let path = []
    let i    = 0
    while i < argc
        let arg = argv[i]

        let tmp_match = matchstr(arg, '^[0-9A-Za-z-]\+\ze=')
        if !empty(tmp_match)
            let arg = tmp_match
        endif

        if has_key(s:ARGLIST[prg], arg)
            let arginfo = s:ARGLIST[prg][arg]
            let key = exists('arginfo.alias') ? arginfo.alias : arg

            if arginfo.argt == 'space'
                let s:ackprg_options[key] = argv[ i+1 : i+arginfo.argc ]
                let i += arginfo.argc
            elseif arginfo.argt == 'none'
                let s:ackprg_options[key] = 1
            elseif arginfo.argt == 'equals'
                let s:ackprg_options[key] = matchstr(argv[i], '^[^=]*=\zs.*$')
            endif
        else
            if arg =~ '^-'
                " unlisted arguments
                let s:ackprg_options[arg] = 1
            else
                " possible path
                call add(path, arg)
            endif
        endif

        let i += 1
    endwhile

    if !has_key(s:ackprg_options, '--match')
        let pattern = empty(path) ? '' : remove(path, 0)
        let s:ackprg_options['--match'] = [pattern]
    endif

    " currently these are arguments we are interested
    let s:ackprg_options['path']    = path
    let s:ackprg_options['pattern'] = s:ackprg_options['--match'][0]
endf

func! s:BuildCommand(args)
    let prg      = g:ctrlsf_ackprg
    let uargs    = escape(a:args, '%#!')
    let prg_args = {
        \ 'ack' : '--heading --group --nocolor --nobreak --column',
        \ 'ag'  : '--heading --group --nocolor --nobreak --column',
        \ }
    return printf('%s %s %s %s 2>/dev/null', prg, prg_args[prg], g:ctrlsf_context, uargs)
endf

func! s:OpenWindow()
    if s:FocusCtrlsfWindow() != -1
        return
    endif

    let openpos = g:ctrlsf_open_left ? 'topleft vertical ' : 'botright vertical '
    exec 'silent keepalt ' . openpos . 'split ' . '__CtrlSF__'

    call s:InitWindow()
endf

func! s:FocusCtrlsfWindow()
    let ctrlsf_winnr = bufwinnr('__CtrlSF__')
    if ctrlsf_winnr == -1
        return -1
    else
        exec ctrlsf_winnr . 'wincm w'
        return ctrlsf_winnr
    endif
endf

func! s:InitWindow()
    setl filetype=ctrlsf
    setl noreadonly
    setl buftype=nofile
    setl bufhidden=hide
    setl noswapfile
    setl nobuflisted
    setl nomodifiable
    setl nolist
    setl nonumber
    setl nowrap
    setl winfixwidth
    setl textwidth=0
    setl nospell

    let &winwidth = exists('g:ctrlsf_width') ? g:ctrlsf_width : &columns/2
    wincmd =

    " default map
    map <silent><buffer> <CR> :call <SID>JumpTo()<CR>
    map <silent><buffer> q    :call <SID>CloseWindow()<CR>
endf

func! s:CloseWindow()
    if s:FocusCtrlsfWindow() == -1
        return
    endif

    " Surely we are in CtrlSF window
    close
endf

func! s:JumpTo()
    let [file, lnum, col] = s:jump_table[line('.') - 1]

    if empty(file) || empty(lnum)
        return
    endif

    if g:ctrlsf_auto_close
        call s:CloseWindow()
    endif

    call s:FocusTargetWindow(file)

    exec 'normal ' . lnum . 'z.'
    call cursor(lnum, col)
endf

func! s:FocusTargetWindow(file)
    let target_winnr = bufwinnr(a:file)

    if target_winnr == -1
        let target_winnr = winnr('#')
        let need_open_file = 1
    endif

    exec target_winnr . 'wincmd w'

    if exists('need_open_file')
        if &modified
            exec 'silent split ' . a:file
        else
            exec 'edit ' . a:file
        endif
    endif
endf

func! s:ParseAckprgOutput(raw_output)
    let s:match_table = []

    for line in split(a:raw_output, '\n')
        " ignore blank line
        if line =~ '^$'
            continue
        endif

        let matched = matchlist(line, '\v^(\d*)([-:])(\d*)([-:])?(.*)$')

        " if line doesn't match, consider it as filename
        if empty(matched)
            call add(s:match_table, {
                \ 'filename' : line,
                \ 'lines'    : [],
                \ })
        else
            call add(s:match_table[-1]['lines'], {
                \ 'lnum'    : matched[1],
                \ 'matched' : matched[2],
                \ 'col'     : matched[3],
                \ 'content' : matched[5],
                \ })
        endif
    endfo
endf

func! s:RenderContent()
    let s:jump_table = []

    let output = ''
    for file in s:match_table
        " Filename
        let output .= s:FormatAndSetJmp('filename', file.filename)

        " Result
        for line in file.lines
            if !empty(line.lnum)
                let output .= s:FormatAndSetJmp('normal', line, {
                    \ 'file' : file.filename,
                    \ 'lnum' : line.lnum,
                    \ 'col'  : line.col,
                    \ })
            else
                let output .= s:FormatAndSetJmp('ellipsis')
            endif
        endfo

        " Insert empty line between files
        if file isnot s:match_table[-1]
            let output .= s:FormatAndSetJmp('blank')
        endif
    endfo

    return output
endf

func! s:FormatAndSetJmp(type, ...)
    let line    = exists('a:1') ? a:1 : ''
    let jmpinfo = exists('a:2') ? a:2 : {}

    let output = s:FormatLine(a:type, line)

    if !empty(jmpinfo)
        call s:SetJmp(jmpinfo.file, jmpinfo.lnum, jmpinfo.col)
    else
        call s:SetJmp('', '', '')
    endif

    return output
endf

func! s:FormatLine(type, line)
    let output = ''
    let line   = a:line

    if a:type == 'filename'
        let output .= line . ":\n"
    elseif a:type == 'normal'
        let output .= line.lnum . line.matched
        let output .= repeat(' ', 12 - len(output)) . line.content . "\n"
    elseif a:type == 'ellipsis'
        let output .= repeat('.', 4) . "\n"
    elseif a:type == 'blank'
        let output .= "\n"
    endif

    return output
endf

func! s:SetJmp(file, line, col)
    call add(s:jump_table, [a:file, a:line, a:col])
endf

" vim: set foldmarker={{{,}}} foldlevel=0 foldmethod=marker spell:
