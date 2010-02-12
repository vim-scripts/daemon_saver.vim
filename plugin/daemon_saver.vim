" ============================================================================
" File:					daemon_saver.vim
" Maintainer:		Krzysztof Szatan <k.szatan at gmail dot com>
" Version:			2.1
" Last Change:	12th February, 2010
"
" Description:	
" FreeBSD daemon screensaver for Vim.	Based on matrix.vim by Don Yang,
" inspired by src/sys/dev/syscons/daemon/daemon_saver.c from FreeBSD code.
"
" License:			
" Copyright (c) 2010, Krzysztof Szatan.	All rights reserved.
"
" Redistribution and use in source and binary forms, with or without
" modification, are permitted provided that the following conditions are met:
"	
"	  1. Redistributions of source code must retain the above copyright	notice, 
"      this list of conditions and the following disclaimer.
"
"	  2. Redistributions in binary form must reproduce the above copyright notice,
"	     this list of conditions and the following disclaimer in the documentation
"	     and/or other materials	provided with the distribution.
"	
"	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDER ``AS IS'' AND ANY	EXPRESS OR
"	IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
"	MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
"	EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
"	INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
"	BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
"	DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
"	OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
"	NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
"	EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
"								
" ============================================================================

if exists('g:loaded_daemon_saver') || &cp
    finish
endif
let g:loaded_daemon_saver = 1

if !exists('g:daemon_saver_speed')
    let g:daemon_saver_speed = 80
endif

" Daemon in ASCII - author unknown
" Redundant spaces for easier drawing
let s:daemon_ascii = [
	\"             ,        ,         ",
	\"            /(        )`        ",
	\"            \\ \\___   / |        ",
	\"            /- _  `-/  '        ",
	\"           (/\\/ \\ \\   /\\        ",
	\"           / /   | `    \\       ",
	\"           O O   ) /    |       ",
	\"           `-^--'`<     '       ",
	\"          (_.)  _  )   /        ",
	\"           `.___/`    /         ",
	\"             `-----' /          ",
	\"<----.     __ / __   \\          ",
	\"<----|====O)))==) \\) /====      ",
	\"<----'    `--' `.__,' \\         ",
	\"             |        |         ",
	\"              \\       /       /\\",
	\"         ______( (_  / \\______/ ",
	\"       ,'  ,-----'   |          ",
	\"       `--{__________)          "]

" Session file for preserving original window layout
let s:session_file = tempname()

" Check for required vim features {{{
if !has('virtualedit') || !has('windows') || !has('syntax')
	echohl ErrorMsg
	echon 'Not enough features, need at least +virtualedit, +windows and +syntax'
	echohl None
else
	command! Daemon call Daemon()
endif "}}}
function! Daemon() "{{{
	try
		if s:Init()
			echohl ErrorMsg
			echon 'Can not create window'
			echohl None
			return
		endif

		" Starting points of daemon
		let daemon = s:GetDaemonParams()

		while b:run
			if b:w != winwidth(0) || b:h != winheight(0)
				if s:Reset()
					echohl ErrorMsg
					echon 'Window is too small'
					echohl None
					sleep 2
				end
			else
				call s:Animate(daemon)
			endif
		endwhile
	finally
		call s:Cleanup()
	endtry
endfunction "}}}
function! s:Init() "{{{
	" Create new buffer and hide the existing buffers.  Hiding the
	" existing buffers without switching to a new buffer preserves
	" undo history.
	let s:o_wmh = &wmh
	let s:o_wmw = &wmw
	set wmh=1
	set wmw=1

	" Check for NERDTree
	if exists("t:NERDTreeBufName")
		let s:nerd_num = bufwinnr(t:NERDTreeBufName)
	else
		let s:nerd_num = -1
	endif
	if s:nerd_num != -1
		NERDTreeToggle
	endif

	" Check for TagList
	let s:tlist_num = bufwinnr(g:TagList_title)
	if s:tlist_num != -1
		TlistToggle
	endif

	let s:o_ssop = &ssop
	set ssop=blank,buffers,folds,globals,help,unix,winsize,localoptions,options
	exec 'mksession! ' . s:session_file
	let s:num_orig_win = winnr("$")

	let s:o_hid = &hid
	set hid

	" move to top window, so created window will become window 1,
	" then attempt to create new window
	1 wincmd w
	silent! new

	" check that there really is an additional window
	if winnr("$") != s:num_orig_win + 1
		return 1
	endif
	let s:newbuf = bufnr('%')

	" close all but window 1, which is the new window
	only

	setl bh=delete bt=nofile ma nolist nonu noro noswf tw=0 nowrap fdc=0

	" Set GUI options
	if has('gui')
		let s:o_gcr = &gcr
		let s:o_go = &go
		set gcr=a:ver1-blinkon0 go=
	endif
	if has('cmdline_info')
		let s:o_ru = &ru
		let s:o_sc = &sc
		set noru nosc
	endif
	if has('title')
		let s:o_ts = &titlestring
		exec 'set titlestring=\ '
	endif
	if v:version >= 700
		let s:o_spell = &spell
		let s:o_cul = &cul
		let s:o_cuc = &cuc
		set nospell nocul nocuc
	endif
	let s:o_ch = &ch
	let s:o_ls = &ls
	let s:o_lz = &lz
	let s:o_siso = &siso
	let s:o_sm = &sm
	let s:o_smd = &smd
	let s:o_so = &so
	let s:o_ve = &ve
	set ch=1 ls=0 lz nosm nosmd siso=0 so=0 ve=all

	" Clear screen and initialize objects
	call s:Reset()

	" Remember background color
	" NOTE: Maybe it's possible to do it better?
	redir => normal_color
	silent! hi Normal 
	redir END
	let s:normal_gbg = matchstr(normal_color, 'guibg=\S*') 
	let s:normal_bg = matchstr(normal_color, 'ctermbg=\S*') 

	" Remember gui cursor color. 
	redir => cursor_color
	silent! hi Cursor
	redir END
	let s:cursor_bg = matchstr(cursor_color, 'guibg=\S*') 
	let s:cursor_fg = matchstr(cursor_color, 'guifg=\S*') 

	" Set colors
	hi Normal ctermbg=Black guibg=Black
	hi Normal ctermbg=Black guibg=Black
	hi Cursor guibg=Black guifg=Black
	hi DaemonNormal ctermfg=Red ctermbg=Black guifg=Red guibg=#000000
	hi DaemonIris ctermfg=Blue ctermbg=Black guifg=Blue guibg=#000000
	hi DaemonEyes ctermfg=White ctermbg=Black guifg=White guibg=#000000
	hi DaemonFork ctermfg=Yellow ctermbg=Black guifg=Yellow guibg=#000000
	hi DaemonShoes ctermfg=Cyan ctermbg=Black guifg=Cyan guibg=#000000
	sy match DaemonNormal /^.*/ contains=DaemonIris,DaemonEyes,DaemonFork,DaemonShoes
	sy match DaemonIris 'O O' contained
	sy match DaemonEyes / _ -/he=e-1, contained
	sy match DaemonEyes /- _ /hs=s+1, contained
	sy match DaemonEyes '/\\/ \\' contained
	sy match DaemonEyes '/ \\/\\' contained
	sy match DaemonEyes '/ /   |' contained
	sy match DaemonEyes '|   \\ \\' contained
	sy match DaemonEyes ' ) / 'he=e-3, contained
	sy match DaemonEyes ' \\ ( 'hs=s+3, contained
	sy match DaemonEyes /`--^-'/ contained
	sy match DaemonEyes /`-^--'/ contained
	sy match DaemonFork '=' contained
	sy match DaemonFork /[\.|`]---->/ contained
	sy match DaemonFork /<----[\.|']/ contained
	sy match DaemonShoes /______(/he=e-1 contained
	sy match DaemonShoes /)______/hs=s+1 contained
  sy match DaemonShoes /,'  ,-----'   |/ contained
  sy match DaemonShoes /|   `-----.  `./ contained
  sy match DaemonShoes /`--{__________)/ contained
	sy match DaemonShoes /(__________}--'/ contained

	let b:run = 1
	return 0
endfunction "}}}
function! s:Reset() "{{{
	" Clear screen
	let b:w = winwidth(0)
	let b:h = winheight(0)

	" Delete contents of the buffer, create b:h lines and go to the top
	exec 'norm! gg"_dG' . b:h . "O\<Esc>gg"
	redraw
	if b:w < 34 || b:h < 21
		let b:run = 0
		return 1
	endif
	return 0
endfunction "}}}
function! s:Animate(daemon) "{{{
	" Clear screen
	exec 'norm! gg"_dG' . b:h . "O\<Esc>gg"

	call s:Draw(a:daemon)
	redraw
	if getchar(1)
		let char = char2nr(getchar(0))
		if char != 48
			let b:run = 0
		endif
	endif
	exec 'sleep ' . g:daemon_saver_speed . 'm'
	call s:NextPosition(a:daemon)
endfunction "}}}
function! s:Draw(daemon) "{{{
	" Draw daemon at x, y coordinates
	
	for i in range(0, len(s:daemon_ascii)-1)
		call cursor(a:daemon['x'] + i, a:daemon['y'])
		let line = s:daemon_ascii[i]
		if a:daemon['ydir'] == 1
			let line = s:Reverse(line)
		endif
		silent! exec "norm! i" . line . "\<Esc>"
	endfor
endfunction "}}}
function! s:NextPosition(daemon) "{{{
	if a:daemon['x'] <= 1 && a:daemon['xdir'] == -1
		let a:daemon['xdir'] = 1
	endif
	if a:daemon['y'] <= 1 && a:daemon['ydir'] == -1
		let a:daemon['ydir'] = 1
	endif
	if a:daemon['x'] >= b:h - a:daemon['height'] + 1 && a:daemon['xdir'] == 1
		let a:daemon['xdir'] = -1
	endif
	if a:daemon['y'] >= b:w - a:daemon['width'] && a:daemon['ydir'] == 1
		let a:daemon['ydir'] = -1
	endif
	let a:daemon['x'] += a:daemon['xdir']
	let a:daemon['y'] += a:daemon['ydir']
endfunction "}}}
function! s:Cleanup() "{{{
	" Restore options
	if has('gui')
		let &gcr = s:o_gcr
		let &go = s:o_go
		unlet s:o_gcr s:o_go
	endif
	if has('cmdline_info')
		let &ru = s:o_ru
		let &sc = s:o_sc
		unlet s:o_ru s:o_sc
	endif
	if has('title')
		let &titlestring = s:o_ts
		unlet s:o_ts
	endif
	if v:version >= 700
		let &spell = s:o_spell
		let &cul = s:o_cul
		let &cuc = s:o_cuc
		unlet s:o_cul s:o_cuc
	endif
	let &ch = s:o_ch
	let &ls = s:o_ls
	let &lz = s:o_lz
	let &siso = s:o_siso
	let &sm = s:o_sm
	let &smd = s:o_smd
	let &so = s:o_so
	let &ve = s:o_ve
	let &hid = s:o_hid
	unlet s:o_ch s:o_ls s:o_lz s:o_siso s:o_sm s:o_smd s:o_so s:o_ve s:o_hid

	" Restore colors
	exec "hi Normal " . s:normal_bg . " " . s:normal_gbg
	exec "hi Cursor " . s:cursor_bg . " " . s:cursor_fg

	" Restore old buffers
	exec 'source ' . s:session_file
	exec 'bwipe ' . s:newbuf
	unlet s:newbuf

	"Restore window min sizes
	let &wmh = s:o_wmh
	let &wmw = s:o_wmw

	let &ssop = s:o_ssop

	unlet s:normal_bg s:normal_gbg s:cursor_bg s:cursor_fg s:o_wmh s:o_wmw
	
	syntax on

	" Restore NERDTree
	if s:nerd_num != -1
		NERDTreeToggle
	endif

	" Restore TagList
	if s:tlist_num != -1
		TlistToggle
	endif

	unlet s:tlist_num s:nerd_num
endfunction "}}}
function! s:GetDaemonParams() "{{{
	let daemon = {}
	let daemon['x']    = 1
	let daemon['xdir'] = 1
	let daemon['y']    = 1
	let daemon['ydir'] = 1
	let daemon['height'] = len(s:daemon_ascii)
	let daemon['width']  = len(s:daemon_ascii[0])
	return daemon
endfunction "}}}
function! s:Reverse(line) "{{{
	let rev_chars = {"(" : ")", ")" : "(", "<" : ">", ">" : "<", "," : ".",
								\	 "/" : '\', '\' : "/", "{" : "}", "`" : "'", "'" : "`"}
	let line = reverse(split(a:line, '\zs'))
	for i in range(0, len(line)-1)
		if has_key(rev_chars, line[i])
			let line[i] = rev_chars[line[i]]
		endif
	endfor
	return join(line, '')
endfunction "}}}

" vim:fdm=marker:sw=2:ts=2:sts=0
