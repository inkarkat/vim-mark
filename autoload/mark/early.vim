" mark/early.vim: Early autoload functions.
"
" DEPENDENCIES:
"   - ingo-library.vim plugin
"
" Copyright: (C) 2025 Ingo Karkat
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:	Ingo Karkat <ingo@karkat.de>
"
" Version:      3.4.0

function! mark#early#GetMarksVariable( ... )
	return printf('MARK_%s', (a:0 ? a:1 : (ingo#plugin#persistence#CanPersist() == 2 ? 'marks': 'MARKS')))  " DWIM: Default to g:MARK_marks if only persistence for :mksession is configured
endfunction

" vim: set ts=8 sts=4 sw=4 noexpandtab ff=unix fdm=syntax :
