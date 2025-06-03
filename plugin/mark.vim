" Script Name: mark.vim
" Description: Highlight several words in different colors simultaneously.
"
" Copyright:   (C) 2008-2025 Ingo Karkat
"              (C) 2005-2008 Yuheng Xie
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:  Ingo Karkat <ingo@karkat.de>
" Orig Author: Yuheng Xie <elephant@linux.net.cn>
" Contributors:Luc Hermitte, Ingo Karkat
"
" DEPENDENCIES:
"	- Requires Vim 7.1 with "matchadd()", or Vim 7.2 or higher.
"	- ingo-library.vim plugin
"
" Version:     3.4.0

" Avoid installing twice or when in unsupported Vim version.
if exists('g:loaded_mark') || (v:version == 701 && ! exists('*matchadd')) || (v:version < 701)
	finish
endif
let g:loaded_mark = 1
let s:save_cpo = &cpo
set cpo&vim

"- configuration --------------------------------------------------------------

if ! exists('g:mwHistAdd')
	let g:mwHistAdd = '/@'
endif

if ! exists('g:mwAutoLoadMarks')
	let g:mwAutoLoadMarks = 0
endif

if ! exists('g:mwAutoSaveMarks')
	let g:mwAutoSaveMarks = 1
endif

if ! exists('g:mwDefaultHighlightingNum')
	let g:mwDefaultHighlightingNum = -1
endif
if ! exists('g:mwDefaultHighlightingPalette')
	let g:mwDefaultHighlightingPalette = 'original'
endif
if ! exists('g:mwPalettes')
	let g:mwPalettes = {
	\	'original': [
		\   { 'ctermbg':'Cyan',       'ctermfg':'Black', 'guibg':'#8CCBEA', 'guifg':'Black' },
		\   { 'ctermbg':'Green',      'ctermfg':'Black', 'guibg':'#A4E57E', 'guifg':'Black' },
		\   { 'ctermbg':'Yellow',     'ctermfg':'Black', 'guibg':'#FFDB72', 'guifg':'Black' },
		\   { 'ctermbg':'Red',        'ctermfg':'Black', 'guibg':'#FF7272', 'guifg':'Black' },
		\   { 'ctermbg':'Magenta',    'ctermfg':'Black', 'guibg':'#FFB3FF', 'guifg':'Black' },
		\   { 'ctermbg':'Blue',       'ctermfg':'Black', 'guibg':'#9999FF', 'guifg':'Black' },
		\],
	\	'extended': function('mark#palettes#Extended'),
	\	'maximum': function('mark#palettes#Maximum')
	\}
	if has('gui_running')
		call extend(g:mwPalettes, {
		\	'soft': function('mark#palettes#Soft'),
		\	'softer': function('mark#palettes#Softer'),
		\})
	endif
endif

if ! exists('g:mwDirectGroupJumpMappingNum')
	let g:mwDirectGroupJumpMappingNum = 9
endif

if ! exists('g:mwExclusionPredicates')
	let g:mwExclusionPredicates = (v:version == 702 && has('patch61') || v:version > 702 ? [function('mark#DefaultExclusionPredicate')] : [])
endif

if ! exists('g:mwMaxMatchPriority')
	" Default the highest match priority to -10, so that we do not override the
	" 'hlsearch' of 0, and still allow other custom highlightings to sneak in
	" between.
	let g:mwMaxMatchPriority = -10
endif


"- default highlightings ------------------------------------------------------

function! s:GetPalette()
	let l:palette = []
	if type(g:mwDefaultHighlightingPalette) == type([])
		" There are custom color definitions, not a named built-in palette.
		return g:mwDefaultHighlightingPalette
	endif
	if ! has_key(g:mwPalettes, g:mwDefaultHighlightingPalette)
		if ! empty(g:mwDefaultHighlightingPalette)
			call ingo#msg#WarningMsg('Mark: Unknown value for g:mwDefaultHighlightingPalette: ' . g:mwDefaultHighlightingPalette)
		endif

		return []
	endif

	if type(g:mwPalettes[g:mwDefaultHighlightingPalette]) == type([])
		return g:mwPalettes[g:mwDefaultHighlightingPalette]
	elseif type(g:mwPalettes[g:mwDefaultHighlightingPalette]) == type(function('tr'))
		return call(g:mwPalettes[g:mwDefaultHighlightingPalette], [])
	else
		call ingo#msg#ErrorMsg(printf('Mark: Invalid value type for g:mwPalettes[%s]', g:mwDefaultHighlightingPalette))
		return []
	endif
endfunction
function! s:DefineHighlightings( palette, isOverride )
	let l:command = (a:isOverride ? 'highlight' : 'highlight def')
	let l:highlightingNum = (g:mwDefaultHighlightingNum == -1 ? len(a:palette) : g:mwDefaultHighlightingNum)
	for i in range(1, l:highlightingNum)
		execute l:command 'MarkWord' . i join(map(items(a:palette[i - 1]), 'join(v:val, "=")'))
	endfor
	return l:highlightingNum
endfunction
call s:DefineHighlightings(s:GetPalette(), 0)
augroup MarkInitialization
	autocmd!
	autocmd ColorScheme * call <SID>DefineHighlightings(<SID>GetPalette(), 0)
augroup END

" Default highlighting for the special search type.
" You can override this by defining / linking the 'SearchSpecialSearchType'
" highlight group before this script is sourced.
highlight def link SearchSpecialSearchType MoreMsg



"- marks persistence ----------------------------------------------------------

if g:mwAutoLoadMarks
	" As the viminfo is only processed after sourcing of the runtime files, the
	" persistent global variables are not yet available here. Defer this until Vim
	" startup has completed.
	" Duplicated to +/function!\ s:GetMarksVariable/ ../autoload/mark.vim
	function! s:GetMarksVariable( ... )
		return printf('MARK_%s', (a:0 ? a:1 : (ingo#plugin#persistence#CanPersist() == 2 ? 'marks': 'MARKS')))  " DWIM: Default to g:MARK_marks if only persistence for :mksession is configured
	endfunction
	function! s:AutoLoadMarks()
		let l:marksVariable = s:GetMarksVariable()
		if g:mwAutoLoadMarks && exists('g:' . l:marksVariable) && ! empty(ingo#plugin#persistence#Load(l:marksVariable, []))
			" Note: Avoid triggering the autoload unless there actually are persistent
			" marks.
			if ! exists('g:MARK_ENABLED') || g:MARK_ENABLED
				" There are persistent marks and they haven't been disabled; we need to
				" show them right now.
				call mark#LoadCommand(0)
			else
				" Though there are persistent marks, they have been disabled. We avoid
				" sourcing the autoload script and its invasive autocmds right now;
				" maybe the marks are never turned on. We just inform the autoload
				" script that it should do this once it is sourced on-demand by a
				" mark mapping or command.
				let g:mwDoDeferredLoad = 1
			endif
		endif
	endfunction

	augroup MarkInitialization
		autocmd! VimEnter * call <SID>AutoLoadMarks()
	augroup END
endif



"- commands -------------------------------------------------------------------

let s:hasOtherArgumentAddressing = v:version == 801 && has('patch560') || v:version > 801

if s:hasOtherArgumentAddressing
	command! -bang -range=0 -addr=other -nargs=? -complete=customlist,mark#Complete Mark if <bang>0 | silent call mark#DoMark(<count>, '') | endif | if ! mark#SetMark(<count>, <f-args>)[0] | echoerr ingo#err#Get() | endif
else
	command! -bang -range=0             -nargs=? -complete=customlist,mark#Complete Mark if <bang>0 | silent call mark#DoMark(<count>, '') | endif | if ! mark#SetMark(<count>, <f-args>)[0] | echoerr ingo#err#Get() | endif
endif
command! -bar MarkClear call mark#ClearAll()
command! -bar Marks call mark#List()

command! -bar -nargs=? -complete=customlist,mark#MarksVariablesComplete MarkLoad if ! mark#LoadCommand(1, <f-args>) | echoerr ingo#err#Get() | endif
command! -bar -nargs=? -complete=customlist,mark#MarksVariablesComplete MarkSave if ! mark#SaveCommand(<f-args>) | echoerr ingo#err#Get() | endif
command! -bar -register MarkYankDefinitions         if ! mark#YankDefinitions(0, <q-reg>) | echoerr ingo#err#Get()| endif
command! -bar -register MarkYankDefinitionsOneLiner if ! mark#YankDefinitions(1, <q-reg>) | echoerr ingo#err#Get()| endif
function! s:SetPalette( paletteName )
	if type(g:mwDefaultHighlightingPalette) == type([])
		" Convert the directly defined list to a palette named "default".
		let g:mwPalettes['default'] = g:mwDefaultHighlightingPalette
		unlet! g:mwDefaultHighlightingPalette   " Avoid E706.
	endif
	let g:mwDefaultHighlightingPalette = a:paletteName

	let l:palette = s:GetPalette()
	if empty(l:palette)
		return
	endif

	call mark#ReInit(s:DefineHighlightings(l:palette, 1))
	call mark#UpdateScope()
endfunction
function! s:MarkPaletteComplete( ArgLead, CmdLine, CursorPos )
	return sort(filter(keys(g:mwPalettes), 'v:val =~ ''\V\^'' . escape(a:ArgLead, "\\")'))
endfunction
command! -bar -nargs=1 -complete=customlist,<SID>MarkPaletteComplete MarkPalette call <SID>SetPalette(<q-args>)
if s:hasOtherArgumentAddressing
	command! -bar -bang -range=0 -addr=other -nargs=? MarkName if ! mark#SetName(<bang>0, <count>, <q-args>) | echoerr ingo#err#Get() | endif
else
	command! -bar -bang -range=0             -nargs=? MarkName if ! mark#SetName(<bang>0, <count>, <q-args>) | echoerr ingo#err#Get() | endif
endif

unlet s:hasOtherArgumentAddressing



"- mappings -------------------------------------------------------------------

nnoremap <silent> <Plug>MarkSet               :<C-u>if ! mark#MarkCurrentWord(v:count)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>endif<CR>
nnoremap <silent> <Plug>MarkPartialWord       :<C-u>if ! mark#MarkCurrentWord(v:count, 0)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>endif<CR>
vnoremap <silent> <Plug>MarkSet               :<C-u>if ! mark#DoMark(v:count, mark#GetVisualSelectionAsLiteralPattern())[0]<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>endif<CR>
vnoremap <silent> <Plug>MarkIWhiteSet         :<C-u>if ! mark#DoMark(v:count, mark#GetVisualSelectionAsLiteralWhitespaceIndifferentPattern())[0]<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>endif<CR>
nnoremap <silent> <Plug>MarkRegex             :<C-u>if ! mark#MarkRegex(v:count, '')<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
vnoremap <silent> <Plug>MarkRegex             :<C-u>if ! mark#MarkRegex(v:count, mark#GetVisualSelectionAsRegexp())<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkClear             :<C-u>if ! mark#Clear(v:count)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkAllClear          :<C-u>call mark#ClearAll()<CR>
nnoremap <silent> <Plug>MarkConfirmAllClear   :<C-u>if confirm('Really delete all marks? This cannot be undone.', "&Yes\n&No") == 1<Bar>call mark#ClearAll()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkToggle            :<C-u>call mark#Toggle()<CR>

nnoremap <silent> <Plug>MarkSearchCurrentNext :<C-u>if ! mark#SearchCurrentMark(0)<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCurrentPrev :<C-u>if ! mark#SearchCurrentMark(1)<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchAnyNext     :<C-u>if ! mark#SearchAnyMark(0)<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchAnyPrev     :<C-u>if ! mark#SearchAnyMark(1)<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
" When typed, [*#nN] open the fold at the search result, but inside a mapping or
" :normal this must be done explicitly via 'zv'.
nnoremap <silent> <Plug>MarkSearchNext          :<C-u>if ! mark#SearchNext(0)<Bar>execute 'normal!' v:count1 . '*zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchPrev          :<C-u>if ! mark#SearchNext(1)<Bar>execute 'normal!' v:count1 . '#zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchOrCurNext     :<C-u>if ! mark#SearchNext(0,'mark#SearchCurrentMark')<Bar>execute 'normal!' v:count1 . '*zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchOrCurPrev     :<C-u>if ! mark#SearchNext(1,'mark#SearchCurrentMark')<Bar>execute 'normal!' v:count1 . '#zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchOrAnyNext     :<C-u>if ! mark#SearchNext(0,'mark#SearchAnyMark')<Bar>execute 'normal!' v:count1 . '*zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchOrAnyPrev     :<C-u>if ! mark#SearchNext(1,'mark#SearchAnyMark')<Bar>execute 'normal!' v:count1 . '#zv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchAnyOrDefaultNext      :<C-u>if mark#IsEnabled() && mark#GetCount() > 0<Bar>if ! mark#SearchAnyMark(0)<Bar>echoerr ingo#err#Get()<Bar>endif<Bar>else<Bar>execute 'normal!' v:count1 . 'nzv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchAnyOrDefaultPrev      :<C-u>if mark#IsEnabled() && mark#GetCount() > 0<Bar>if ! mark#SearchAnyMark(1)<Bar>echoerr ingo#err#Get()<Bar>endif<Bar>else<Bar>execute 'normal!' v:count1 . 'Nzv'<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchGroupNext     :<C-u>if ! mark#SearchGroupMark(v:count, 1, 0, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchGroupPrev     :<C-u>if ! mark#SearchGroupMark(v:count, 1, 1, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchUsedGroupNext	:<C-u>if ! mark#SearchNextGroup(v:count1, 0)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchUsedGroupPrev	:<C-u>if ! mark#SearchNextGroup(v:count1, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadeStartWithStop  :<C-u>if ! mark#cascade#Start(v:count, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"   <Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadeNextWithStop   :<C-u>if ! mark#cascade#Next(v:count1, 1, 0)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadePrevWithStop   :<C-u>if ! mark#cascade#Next(v:count1, 1, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadeStartNoStop    :<C-u>if ! mark#cascade#Start(v:count, 0)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"   <Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadeNextNoStop     :<C-u>if ! mark#cascade#Next(v:count1, 0, 0)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>
nnoremap <silent> <Plug>MarkSearchCascadePrevNoStop     :<C-u>if ! mark#cascade#Next(v:count1, 0, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>

function! s:MakeDirectGroupMappings( isDefineDefaultMappings )
	for l:cnt in range(1, g:mwDirectGroupJumpMappingNum)
		for [l:isBackward, l:direction, l:keyModifier] in [[0, 'Next', ''], [1, 'Prev', 'C-']]
			let l:plugMappingName = printf('<Plug>MarkSearchGroup%d%s', l:cnt, l:direction)
			execute printf('nnoremap <silent> %s :<C-u>if ! mark#SearchGroupMark(%d, v:count1, %d, 1)<Bar>execute "normal! \<lt>C-\>\<lt>C-n>\<lt>Esc>"<Bar>echoerr ingo#err#Get()<Bar>endif<CR>', l:plugMappingName, l:cnt, l:isBackward)
			if a:isDefineDefaultMappings && ! hasmapto(l:plugMappingName, 'n')
				execute printf('nmap <%sk%d> %s', l:keyModifier, l:cnt, l:plugMappingName)
			endif
		endfor
	endfor
endfunction
call s:MakeDirectGroupMappings(! exists('g:mw_no_mappings'))
delfunction s:MakeDirectGroupMappings

if exists('g:mw_no_mappings')
	let &cpo = s:save_cpo
	unlet s:save_cpo
	finish
endif

if !hasmapto('<Plug>MarkSet', 'n')
	nmap <unique> <Leader>m <Plug>MarkSet
endif
if !hasmapto('<Plug>MarkPartialWord', 'n')
	nmap <unique> <Leader>gm <Plug>MarkPartialWord
endif
if !hasmapto('<Plug>MarkSet', 'x')
	xmap <unique> <Leader>m <Plug>MarkSet
endif
" No default mapping for <Plug>MarkIWhiteSet.
if !hasmapto('<Plug>MarkRegex', 'n')
	nmap <unique> <Leader>r <Plug>MarkRegex
endif
if !hasmapto('<Plug>MarkRegex', 'x')
	xmap <unique> <Leader>r <Plug>MarkRegex
endif
if !hasmapto('<Plug>MarkClear', 'n')
	nmap <unique> <Leader>n <Plug>MarkClear
endif
" No default mapping for <Plug>MarkAllClear.
" No default mapping for <Plug>MarkConfirmAllClear.
" No default mapping for <Plug>MarkToggle.

if !hasmapto('<Plug>MarkSearchCurrentNext', 'n')
	nmap <unique> <Leader>* <Plug>MarkSearchCurrentNext
endif
if !hasmapto('<Plug>MarkSearchCurrentPrev', 'n')
	nmap <unique> <Leader># <Plug>MarkSearchCurrentPrev
endif
if !hasmapto('<Plug>MarkSearchAnyNext', 'n')
	nmap <unique> <Leader>/ <Plug>MarkSearchAnyNext
endif
if !hasmapto('<Plug>MarkSearchAnyPrev', 'n')
	nmap <unique> <Leader>? <Plug>MarkSearchAnyPrev
endif
if !hasmapto('<Plug>MarkSearchNext', 'n')
	nmap <unique> * <Plug>MarkSearchNext
endif
if !hasmapto('<Plug>MarkSearchPrev', 'n')
	nmap <unique> # <Plug>MarkSearchPrev
endif
" No default mapping for <Plug>MarkSearchOrCurNext
" No default mapping for <Plug>MarkSearchOrCurPrev
" No default mapping for <Plug>MarkSearchOrAnyNext
" No default mapping for <Plug>MarkSearchOrAnyPrev
" No default mapping for <Plug>MarkSearchAnyOrDefaultNext
" No default mapping for <Plug>MarkSearchAnyOrDefaultPrev
" No default mapping for <Plug>MarkSearchGroupNext
" No default mapping for <Plug>MarkSearchGroupPrev
" No default mapping for <Plug>MarkSearchUsedGroupNext
" No default mapping for <Plug>MarkSearchUsedGroupPrev

let &cpo = s:save_cpo
unlet s:save_cpo
" vim: ts=4 sts=0 sw=4 noet
