" Script Name: mark.vim
" Description: Highlight several words in different colors simultaneously.
"
" Copyright:   (C) 2008-2024 Ingo Karkat
"              (C) 2005-2008 Yuheng Xie
"   The VIM LICENSE applies to this script; see ':help copyright'.
"
" Maintainer:  Ingo Karkat <ingo@karkat.de>
"
" DEPENDENCIES:
"   - ingo-library.vim plugin
"   - SearchSpecial.vim plugin (optional)
"
" Version:     3.2.1

try
	call ingo#version#Has('1.046')
catch /^ingo-library:/
	echoerr v:exception
catch /^Vim\%((\a\+)\)\=:/
	echoerr printf('The ingo-library dependency is missing; see :help %s-dependencies', expand('<sfile>:t:r'))
endtry

"- functions ------------------------------------------------------------------

silent! call SearchSpecial#DoesNotExist()	" Execute a function to force autoload.
if exists('*SearchSpecial#WrapMessage')
	function! s:WrapMessage( searchType, searchPattern, isBackward )
		redraw
		call SearchSpecial#WrapMessage(a:searchType, a:searchPattern, a:isBackward)
	endfunction
	function! s:EchoSearchPattern( searchType, searchPattern, isBackward )
		call SearchSpecial#EchoSearchPattern(a:searchType, a:searchPattern, a:isBackward)
	endfunction
else
	function! s:Trim( message )
		" Limit length to avoid "Hit ENTER" prompt.
		return strpart(a:message, 0, (&columns / 2)) . (len(a:message) > (&columns / 2) ? "..." : "")
	endfunction
	function! s:WrapMessage( searchType, searchPattern, isBackward )
		redraw
		let v:warningmsg = printf('%s search hit %s, continuing at %s', a:searchType, (a:isBackward ? 'TOP' : 'BOTTOM'), (a:isBackward ? 'BOTTOM' : 'TOP'))
		echohl WarningMsg
		echo s:Trim(v:warningmsg)
		echohl None
	endfunction
	function! s:EchoSearchPattern( searchType, searchPattern, isBackward )
		let l:message = (a:isBackward ? '?' : '/') .  a:searchPattern
		echohl SearchSpecialSearchType
		echo a:searchType
		echohl None
		echon s:Trim(l:message)
	endfunction
endif

function! s:EscapeText( text )
	return substitute( escape(a:text, '\' . '^$.*[~'), "\n", '\\n', 'ge' )
endfunction
function! s:IsIgnoreCase( expr )
	return ((exists('g:mwIgnoreCase') ? g:mwIgnoreCase : &ignorecase) && a:expr !~# '\\\@<!\\C')
endfunction
" Mark the current word, like the built-in star command.
" If the cursor is on an existing mark, remove it.
function! mark#MarkCurrentWord( groupNum, ... )
	let l:markWholeWordOnly = (a:0 >= 1 ? a:1 : 1)
	let l:regexp = (a:groupNum == 0 ? mark#CurrentMark()[0] : '')
	if empty(l:regexp)
		let l:cword = expand('<cword>')
		if ! empty(l:cword)
			let l:regexp = s:EscapeText(l:cword)
			" The star command only creates a \<whole word\> search pattern if the
			" <cword> actually only consists of keyword characters.
			if l:cword =~# '^\k\+$' && l:markWholeWordOnly
				let l:regexp = '\<' . l:regexp . '\>'
			endif
		endif
	endif
	return (empty(l:regexp) ? 0 : mark#DoMark(a:groupNum, l:regexp)[0])
endfunction

function! mark#GetVisualSelection()
	let save_clipboard = &clipboard
	set clipboard= " Avoid clobbering the selection and clipboard registers.
	let save_reg = getreg('"')
	let save_regmode = getregtype('"')
	silent normal! gvy
	let res = getreg('"')
	call setreg('"', save_reg, save_regmode)
	let &clipboard = save_clipboard
	return res
endfunction
function! mark#GetVisualSelectionAsLiteralPattern()
	return s:EscapeText(mark#GetVisualSelection())
endfunction
function! mark#GetVisualSelectionAsRegexp()
	return substitute(mark#GetVisualSelection(), '\n', '', 'g')
endfunction
function! mark#GetVisualSelectionAsLiteralWhitespaceIndifferentPattern()
	return substitute(escape(mark#GetVisualSelection(), '\' . '^$.*[~'), '\_s\+', '\\_s\\+', 'g')
endfunction

" Manually input a regular expression.
function! mark#MarkRegex( groupNum, regexpPreset )
	call inputsave()
		echohl Question
			let l:regexp = input('Input pattern to mark: ', a:regexpPreset)
		echohl None
	call inputrestore()
	if empty(l:regexp)
		call ingo#err#Clear()
		return 0
	endif

	redraw " This is necessary when the user is queried for the mark group.
	return mark#DoMarkAndSetCurrent(a:groupNum, ingo#regexp#magic#Normalize(l:regexp))[0]
endfunction

function! s:Cycle( ... )
	let l:currentCycle = s:cycle
	let l:newCycle = (a:0 ? a:1 : s:cycle) + 1
	let s:cycle = (l:newCycle < s:markNum ? l:newCycle : 0)
	return l:currentCycle
endfunction
function! s:FreeGroupIndex()
	let i = 0
	while i < s:markNum
		if empty(s:pattern[i])
			return i
		endif
		let i += 1
	endwhile
	return -1
endfunction
function! mark#NextUsedGroupIndex( isBackward, isWrapAround, startIndex, count )
	if a:isBackward
		let l:indices = range(a:startIndex - 1, 0, -1)
		if a:isWrapAround
			let l:indices += range(s:markNum - 1, a:startIndex + 1, -1) :
		endif
	else
		let l:indices = range(a:startIndex + 1, s:markNum - 1)
		if a:isWrapAround
			let l:indices += range(0, max([-1, a:startIndex - 1]))
		endif
	endif

	let l:count = a:count
	for l:i in l:indices
		if ! empty(s:pattern[l:i])
			let l:count -= 1
			if l:count == 0
				return l:i
			endif
		endif
	endfor
	return -1
endfunction

function! mark#DefaultExclusionPredicate()
	return (exists('b:nomarks') && b:nomarks) || (exists('w:nomarks') && w:nomarks) || (exists('t:nomarks') && t:nomarks)
endfunction

" Set match / clear matches in the current window.
function! s:MarkMatch( indices, expr )
	if ! exists('w:mwMatch')
		let w:mwMatch = repeat([0], s:markNum)
	elseif len(w:mwMatch) != s:markNum
		" The number of marks has changed.
		if len(w:mwMatch) > s:markNum
			" Truncate the matches.
			for l:match in filter(w:mwMatch[s:markNum : ], 'v:val > 0')
				silent! call matchdelete(l:match)
			endfor
			let w:mwMatch = w:mwMatch[0 : (s:markNum - 1)]
		else
			" Expand the matches.
			let w:mwMatch += repeat([0], (s:markNum - len(w:mwMatch)))
		endif
	endif

	for l:index in a:indices
		if w:mwMatch[l:index] > 0
			silent! call matchdelete(w:mwMatch[l:index])
			let w:mwMatch[l:index] = 0
		endif
	endfor

	if ! empty(a:expr)
		let l:index = a:indices[0]	" Can only set one index for now.

		" Info: matchadd() does not consider the 'magic' (it's always on),
		" 'ignorecase' and 'smartcase' settings.
		" Make the match according to the 'ignorecase' setting, like the star command.
		" (But honor an explicit case-sensitive regexp via the /\C/ atom.)
		let l:expr = (s:IsIgnoreCase(a:expr) ? '\c' : '') . a:expr

		" To avoid an arbitrary ordering of highlightings, we assign a different
		" priority based on the highlight group.
		let l:priority = g:mwMaxMatchPriority - s:markNum + 1 + l:index

		let w:mwMatch[l:index] = matchadd('MarkWord' . (l:index + 1), l:expr, l:priority)
	endif
endfunction
" Initialize mark colors in a (new) window.
function! mark#UpdateMark( ... )
	for l:Predicate in g:mwExclusionPredicates
		if ingo#actions#EvaluateOrFunc(l:Predicate)
			" The window may have had marks applied previously. Clear any
			" existing matches.
			call s:MarkMatch(range(s:markNum), '')

			return
		endif
	endfor

	if a:0
		call call('s:MarkMatch', a:000)
	else
		let i = 0
		while i < s:markNum
			if ! s:enabled || empty(s:pattern[i])
				call s:MarkMatch([i], '')
			else
				call s:MarkMatch([i], s:pattern[i])
			endif
			let i += 1
		endwhile
	endif
endfunction
" Update matches in all windows.
function! mark#UpdateScope( ... )
	call call('ingo#window#iterate#All', [function('mark#UpdateMark')] + a:000)
endfunction

function! s:MarkEnable( enable, ...)
	if s:enabled != a:enable
		" En-/disable marks and perform a full refresh in all windows, unless
		" explicitly suppressed by passing in 0.
		let s:enabled = a:enable
		if g:mwAutoSaveMarks
			let g:MARK_ENABLED = s:enabled
		endif

		if ! a:0 || ! a:1
			call mark#UpdateScope()
		endif
	endif
endfunction
function! s:EnableAndMarkScope( indices, expr )
	if s:enabled
		" Marks are already enabled, we just need to push the changes to all
		" windows.
		call mark#UpdateScope(a:indices, a:expr)
	else
		call s:MarkEnable(1)
	endif
endfunction

" Toggle visibility of marks, like :nohlsearch does for the regular search
" highlighting.
function! mark#Toggle()
	if s:enabled
		call s:MarkEnable(0)
		echo 'Disabled marks'
	else
		call s:MarkEnable(1)

		let l:markCnt = mark#GetCount()
		echo 'Enabled' (l:markCnt > 0 ? l:markCnt . ' ' : '') . 'marks'
	endif
endfunction


" Mark or unmark a regular expression.
function! mark#Clear( groupNum )
	if a:groupNum > 0
		return mark#DoMark(a:groupNum, '')[0]
	else
		let l:markText = mark#CurrentMark()[0]
		if empty(l:markText)
			return mark#DoMark(a:groupNum)[0]
		else
			return mark#DoMark(a:groupNum, l:markText)[0]
		endif
	endif
endfunction
function! s:SetPattern( index, pattern )
	let s:pattern[a:index] = a:pattern

	if g:mwAutoSaveMarks
		call s:SavePattern()
	endif
endfunction
function! mark#ClearAll()
	let i = 0
	let indices = []
	while i < s:markNum
		if ! empty(s:pattern[i])
			call s:SetPattern(i, '')
			call add(indices, i)
		endif
		let i += 1
	endwhile
	let s:lastSearch = -1

	" Re-enable marks; not strictly necessary, since all marks have just been
	" cleared, and marks will be re-enabled, anyway, when the first mark is
	" added. It's just more consistent for mark persistence. But save the full
	" refresh, as we do the update ourselves.
	call s:MarkEnable(0, 0)

	call mark#UpdateScope(l:indices, '')

	if len(indices) > 0
		echo 'Cleared all' len(indices) 'marks'
	else
		echo 'All marks cleared'
	endif
endfunction
function! s:SetMark( index, regexp, ... )
	if a:0
		if s:lastSearch == a:index
			let s:lastSearch = a:1
		endif
	endif
	call s:SetPattern(a:index, a:regexp)
	call s:EnableAndMarkScope([a:index], a:regexp)
endfunction
function! s:ClearMark( index )
	" A last search there is reset.
	call s:SetMark(a:index, '', -1)
endfunction
function! s:RenderName( groupNum )
	return (empty(s:names[a:groupNum - 1]) ? '' : ':' . s:names[a:groupNum - 1])
endfunction
function! s:EnrichSearchType( searchType )
	if a:searchType !=# 'mark*'
		return a:searchType
	endif

	let [l:markText, l:markPosition, l:markIndex] = mark#CurrentMark()
	return (l:markIndex >= 0 ? a:searchType . (l:markIndex + 1) .  s:RenderName(l:markIndex + 1) : a:searchType)
endfunction
function! s:RenderMark( groupNum )
	return 'mark-' . a:groupNum . s:RenderName(a:groupNum)
endfunction
function! s:EchoMark( groupNum, regexp )
	call s:EchoSearchPattern(s:RenderMark(a:groupNum), a:regexp, 0)
endfunction
function! s:EchoMarkCleared( groupNum )
	echohl SearchSpecialSearchType
	echo s:RenderMark(a:groupNum)
	echohl None
	echon ' cleared'
endfunction
function! s:EchoMarksDisabled()
	echo 'All marks disabled'
endfunction

function! s:SplitIntoAlternatives( pattern )
	return ingo#regexp#split#TopLevelBranches(a:pattern)
endfunction

" Return [success, markGroupNum]. success is true when the mark has been set or
" cleared. markGroupNum is the mark group number where the mark was set. It is 0
" if the group was cleared.
function! mark#DoMark( groupNum, ... )
	call ingo#err#Clear()
	if s:markNum <= 0
		" Uh, somehow no mark highlightings were defined. Try to detect them again.
		call mark#Init()
		if s:markNum <= 0
			" Still no mark highlightings; complain.
			call ingo#err#Set('No mark highlightings defined')
			return [0, 0]
		endif
	endif

	let l:groupNum = a:groupNum
	if l:groupNum > s:markNum
		" This highlight group does not exist.
		let l:groupNum = mark#QueryMarkGroupNum()
		if l:groupNum < 1 || l:groupNum > s:markNum
			return [0, 0]
		endif
	endif

	let regexp = (a:0 ? a:1 : '')
	if empty(regexp)
		if l:groupNum == 0
			if a:0
				" :Mark // looks more like a typo than a command to disable all
				" marks; prevent that, and only accept :Mark for it.
				call ingo#err#Set('Do not pass empty pattern to disable all marks')
				return [0, 0]
			endif

			" Disable all marks.
			call s:MarkEnable(0)
			call s:EchoMarksDisabled()
		else
			" Clear the mark represented by the passed highlight group number.
			call s:ClearMark(l:groupNum - 1)
			if a:0 >= 2 | let s:names[l:groupNum - 1] = a:2 | endif
			call s:EchoMarkCleared(l:groupNum)
		endif

		return [1, 0]
	endif

	if l:groupNum == 0
		" Clear the mark if it has been marked.
		let i = 0
		while i < s:markNum
			if regexp ==# s:pattern[i]
				call s:ClearMark(i)
				if a:0 >= 2 | let s:names[i] = a:2 | endif
				call s:EchoMarkCleared(i + 1)
				return [1, 0]
			endif
			let i += 1
		endwhile
	else
		" Add / subtract the pattern as an alternative to the mark represented
		" by the passed highlight group number.
		let existingPattern = s:pattern[l:groupNum - 1]
		if ! empty(existingPattern)
			let alternatives = s:SplitIntoAlternatives(existingPattern)
			if index(alternatives, regexp) == -1
				let regexp = join(ingo#regexp#split#AddPatternByProjectedMatchLength(alternatives, regexp), '\|')
			else
				let regexp = join(filter(alternatives, 'v:val !=# regexp'), '\|')
				if empty(regexp)
					call s:ClearMark(l:groupNum - 1)
					if a:0 >= 2 | let s:names[l:groupNum - 1] = a:2 | endif
					call s:EchoMarkCleared(l:groupNum)
					return [1, 0]
				endif
			endif
		endif
	endif

	" add to history
	if stridx(g:mwHistAdd, '/') >= 0
		call histadd('/', regexp)
	endif
	if stridx(g:mwHistAdd, '@') >= 0
		call histadd('@', regexp)
	endif

	if l:groupNum == 0
		let i = s:FreeGroupIndex()
		if i != -1
			" Choose an unused highlight group. The last search is kept untouched.
			call s:Cycle(i)
			call s:SetMark(i, regexp)
		else
			" Choose a highlight group by cycle. A last search there is reset.
			let i = s:Cycle()
			call s:SetMark(i, regexp, -1)
		endif
	else
		let i = l:groupNum - 1
		" Use and extend the passed highlight group. A last search is updated
		" and thereby kept active.
		call s:SetMark(i, regexp, i)
	endif

	if a:0 >= 2 | let s:names[i] = a:2 | endif
	call s:EchoMark(i + 1, regexp)
	return [1, i + 1]
endfunction
function! mark#DoMarkAndSetCurrent( groupNum, ... )
	" To avoid accepting an invalid regular expression (e.g. "\(blah") and then
	" causing ugly errors on every mark update, check the patterns passed by the
	" user for validity. (We assume that the expressions generated by the plugin
	" itself from literal text are all valid.)
	if a:0 && ! ingo#regexp#IsValid(a:1)
		return [0, 0]
	endif

	let l:result = call('mark#DoMark', [a:groupNum] + a:000)
	let l:markGroupNum = l:result[1]
	if l:markGroupNum > 0
		let s:lastSearch = l:markGroupNum - 1
	endif

	return l:result
endfunction
function! mark#SetMark( groupNum, ... )
	" For the :Mark command, don't query when the passed mark group doesn't
	" exist (interactivity in Ex commands is unexpected). Instead, return an
	" error.
	if s:markNum > 0 && a:groupNum > s:markNum
		call ingo#err#Set(printf('Only %d mark highlight groups', s:markNum))
		return 0
	endif
	if a:0
		let [l:pattern, l:nameArgument] = ingo#cmdargs#pattern#ParseUnescapedWithLiteralWholeWord(a:1, '\(\s\+as\%(\s\+\(.\{-}\)\)\?\)\?\s*')
		let l:pattern = ingo#regexp#magic#Normalize(l:pattern)  " We'd strictly only have to do this for /{pattern}/, not for whole word(s), but as the latter doesn't contain magicness atoms, it doesn't hurt, and with this we don't need to explicitly distinguish between the two cases.
		if ! empty(l:nameArgument)
			let l:name = substitute(l:nameArgument, '^\s\+as\s*', '', '')
			return mark#DoMarkAndSetCurrent(a:groupNum, l:pattern, l:name)
		else
			return mark#DoMarkAndSetCurrent(a:groupNum, l:pattern)
		endif
	else
		return mark#DoMarkAndSetCurrent(a:groupNum)
	endif
endfunction

" Return [mark text, mark start position, mark index] of the mark under the
" cursor (or ['', [], -1] if there is no mark).
function! mark#CurrentMark()
	" Highlighting groups with higher numbers take precedence over lower numbers,
	" and therefore its marks appear "above" other marks. To retrieve the visible
	" mark in case of overlapping marks, we need to check from highest to lowest
	" highlight group.
	let i = s:markNum - 1
	while i >= 0
		if ! empty(s:pattern[i])
			let l:matchPattern = (s:IsIgnoreCase(s:pattern[i]) ? '\c' : '\C') . s:pattern[i]

			let [l:startPosition, l:endPosition] = ingo#area#frompattern#GetCurrent(l:matchPattern, {'firstLnum': 1, 'lastLnum': line('$')})
			if l:startPosition != [0, 0]
				return [s:pattern[i], l:startPosition, i]
			endif
		endif
		let i -= 1
	endwhile
	return ['', [], -1]
endfunction

" Search current mark.
function! mark#SearchCurrentMark( isBackward )
	let l:result = 0

	let [l:markText, l:markPosition, l:markIndex] = mark#CurrentMark()
	if empty(l:markText)
		if s:lastSearch == -1
			let l:result = mark#SearchAnyMark(a:isBackward)
			let s:lastSearch = mark#CurrentMark()[2]
		else
			let l:result = s:Search(s:pattern[s:lastSearch], v:count1, a:isBackward, [], s:RenderMark(s:lastSearch + 1))
		endif
	else
		let l:result = s:Search(l:markText, v:count1, a:isBackward, l:markPosition, s:RenderMark(l:markIndex + 1) . (l:markIndex ==# s:lastSearch ? '' : '!'))
		let s:lastSearch = l:markIndex
	endif

	return l:result
endfunction

function! mark#SearchGroupMark( groupNum, count, isBackward, isSetLastSearch )
	call ingo#err#Clear()
	if a:groupNum == 0
		" No mark group number specified; use last search, and fall back to
		" current mark if possible.
		if s:lastSearch == -1
			let [l:markText, l:markPosition, l:markIndex] = mark#CurrentMark()
			if empty(l:markText)
				return 0
			endif
		else
			let l:markIndex = s:lastSearch
			let l:markText = s:pattern[l:markIndex]
			let l:markPosition = []
		endif
	else
		let l:groupNum = a:groupNum
		if l:groupNum > s:markNum
			" This highlight group does not exist.
			let l:groupNum = mark#QueryMarkGroupNum()
			if l:groupNum < 1 || l:groupNum > s:markNum
				return 0
			endif
		endif

		let l:markIndex = l:groupNum - 1
		let l:markText = s:pattern[l:markIndex]
		let l:markPosition = []
	endif

	let l:result =  s:Search(l:markText, a:count, a:isBackward, l:markPosition, s:RenderMark(l:markIndex + 1) . (l:markIndex ==# s:lastSearch ? '' : '!'))
	if a:isSetLastSearch
		let s:lastSearch = l:markIndex
	endif
	return l:result
endfunction

function! mark#SearchNextGroup( count, isBackward )
	if s:lastSearch == -1
		" Fall back to current mark in case of no last search.
		let [l:markText, l:markPosition, l:markIndex] = mark#CurrentMark()
		if empty(l:markText)
			" Fall back to next group that would be taken.
			let l:groupIndex = s:GetNextGroupIndex()
		else
			let l:groupIndex = l:markIndex
		endif
	else
		let l:groupIndex = s:lastSearch
	endif

	let l:groupIndex = mark#NextUsedGroupIndex(a:isBackward, 1, l:groupIndex, a:count)
	if l:groupIndex == -1
		call ingo#err#Set(printf('No %s mark group%s used', (a:count == 1 ? '' : a:count . ' ') . (a:isBackward ? 'previous' : 'next'), (a:count == 1 ? '' : 's')))
		return 0
	endif
	return mark#SearchGroupMark(l:groupIndex + 1, 1, a:isBackward, 1)
endfunction


function! mark#NoMarkErrorMessage()
	call ingo#err#Set('No marks defined')
endfunction
function! s:ErrorMessage( searchType, searchPattern, isBackward )
	if &wrapscan
		let l:errmsg = a:searchType . ' not found: ' . a:searchPattern
	else
		let l:errmsg = printf('%s search hit %s without match for: %s', a:searchType, (a:isBackward ? 'TOP' : 'BOTTOM'), a:searchPattern)
	endif
	call ingo#err#Set(l:errmsg)
endfunction

" Wrapper around search() with additonal search and error messages and "wrapscan" warning.
function! s:Search( pattern, count, isBackward, currentMarkPosition, searchType )
	if empty(a:pattern)
		call mark#NoMarkErrorMessage()
		return 0
	endif

	let l:save_view = winsaveview()

	" searchpos() obeys the 'smartcase' setting; however, this setting doesn't
	" make sense for the mark search, because all patterns for the marks are
	" concatenated as branches in one large regexp, and because patterns that
	" result from the *-command-alike mappings should not obey 'smartcase' (like
	" the * command itself), anyway. If the :Mark command wants to support
	" 'smartcase', it'd have to emulate that into the regular expression.
	" Instead of temporarily unsetting 'smartcase', we force the correct
	" case-matching behavior through \c / \C.
	let l:searchPattern = (s:IsIgnoreCase(a:pattern) ? '\c' : '\C') . a:pattern

	let l:count = a:count
	let l:isWrapped = 0
	let l:isMatch = 0
	let l:line = 0
	while l:count > 0
		let [l:prevLine, l:prevCol] = [line('.'), col('.')]

		" Search for next match, 'wrapscan' applies.
		let [l:line, l:col] = searchpos( l:searchPattern, (a:isBackward ? 'b' : '') )

"****D echomsg '****' a:isBackward string([l:line, l:col]) string(a:currentMarkPosition) l:count
		if a:isBackward && l:line > 0 && [l:line, l:col] == a:currentMarkPosition && l:count == a:count
			" On a search in backward direction, the first match is the start of the
			" current mark (if the cursor was positioned on the current mark text, and
			" not at the start of the mark text).
			" In contrast to the normal search, this is not considered the first
			" match. The mark text is one entity; if the cursor is positioned anywhere
			" inside the mark text, the mark text is considered the current mark. The
			" built-in '*' and '#' commands behave in the same way; the entire <cword>
			" text is considered the current match, and jumps move outside that text.
			" In normal search, the cursor can be positioned anywhere (via offsets)
			" around the search, and only that single cursor position is considered
			" the current match.
			" Thus, the search is retried without a decrease of l:count, but only if
			" this was the first match; repeat visits during wrapping around count as
			" a regular match. The search also must not be retried when this is the
			" first match, but we've been here before (i.e. l:isMatch is set): This
			" means that there is only the current mark in the buffer, and we must
			" break out of the loop and indicate that search wrapped around and no
			" other mark was found.
			if l:isMatch
				let l:isWrapped = 1
				break
			endif

			" The l:isMatch flag is set so if the final mark cannot be reached, the
			" original cursor position is restored. This flag also allows us to detect
			" whether we've been here before, which is checked above.
			let l:isMatch = 1
		elseif l:line > 0
			let l:isMatch = 1
			let l:count -= 1

			" Note: No need to check 'wrapscan'; the wrapping can only occur if
			" 'wrapscan' is actually on.
			if ! a:isBackward && (l:prevLine > l:line || l:prevLine == l:line && l:prevCol >= l:col)
				let l:isWrapped = 1
			elseif a:isBackward && (l:prevLine < l:line || l:prevLine == l:line && l:prevCol <= l:col)
				let l:isWrapped = 1
			endif
		else
			break
		endif
	endwhile

	" We're not stuck when the search wrapped around and landed on the current
	" mark; that's why we exclude a possible wrap-around via a:count == 1.
	let l:isStuckAtCurrentMark = ([l:line, l:col] == a:currentMarkPosition && a:count == 1)
"****D echomsg '****' l:line l:isStuckAtCurrentMark l:isWrapped l:isMatch string([l:line, l:col]) string(a:currentMarkPosition)
	if l:line > 0 && ! l:isStuckAtCurrentMark
		let l:matchPosition = getpos('.')

		" Open fold at the search result, like the built-in commands.
		normal! zv

		" Add the original cursor position to the jump list, like the
		" [/?*#nN] commands.
		" Implementation: Memorize the match position, restore the view to the state
		" before the search, then jump straight back to the match position. This
		" also allows us to set a jump only if a match was found. (:call
		" setpos("''", ...) doesn't work in Vim 7.2)
		call winrestview(l:save_view)
		normal! m'
		call setpos('.', l:matchPosition)

		" Enable marks (in case they were disabled) after arriving at the mark (to
		" avoid unnecessary screen updates) but before the error message (to avoid
		" it getting lost due to the screen updates).
		call s:MarkEnable(1)

		if l:isWrapped
			call s:WrapMessage(s:EnrichSearchType(a:searchType), a:pattern, a:isBackward)
		else
			call s:EchoSearchPattern(s:EnrichSearchType(a:searchType), a:pattern, a:isBackward)
		endif
		return 1
	else
		if l:isMatch
			" The view has been changed by moving through matches until the end /
			" start of file, when 'nowrapscan' forced a stop of searching before the
			" l:count'th match was found.
			" Restore the view to the state before the search.
			call winrestview(l:save_view)
		endif

		" Enable marks (in case they were disabled) after arriving at the mark (to
		" avoid unnecessary screen updates) but before the error message (to avoid
		" it getting lost due to the screen updates).
		call s:MarkEnable(1)

		if l:line > 0 && l:isStuckAtCurrentMark && l:isWrapped
			call s:WrapMessage(s:EnrichSearchType(a:searchType), a:pattern, a:isBackward)
			return 1
		else
			call s:ErrorMessage(a:searchType, a:pattern, a:isBackward)
			return 0
		endif
	endif
endfunction

" Combine all marks into one regexp.
function! mark#AnyMarkPattern()
	return join(filter(copy(s:pattern), '! empty(v:val)'), '\|')
endfunction

" Search any mark.
function! mark#SearchAnyMark( isBackward )
	let l:markPosition = mark#CurrentMark()[1]
	let l:markText = mark#AnyMarkPattern()
	let s:lastSearch = -1
	return s:Search(l:markText, v:count1, a:isBackward, l:markPosition, 'mark*')
endfunction

" Search last searched mark.
function! mark#SearchNext( isBackward, ... )
	let l:markText = mark#CurrentMark()[0]
	if empty(l:markText)
		return 0    " Fall back to the built-in * / # command (done by the mapping).
	endif

	" Use the provided search type or choose depending on last use of
	" <Plug>MarkSearchCurrentNext / <Plug>MarkSearchAnyNext.
	call call(a:0 ? a:1 : (s:lastSearch == -1 ? 'mark#SearchAnyMark' : 'mark#SearchCurrentMark'), [a:isBackward])
	return 1
endfunction



" Load mark patterns from list.
function! mark#Load( marks, enabled )
	if s:markNum > 0 && len(a:marks) > 0
		" Initialize mark patterns (and optional names) with the passed list.
		" Ensure that, regardless of the list length, s:pattern / s:names
		" contain exactly s:markNum elements.
		for l:index in range(s:markNum)
			call s:DeserializeMark(get(a:marks, l:index, ''), l:index)
		endfor

		let s:enabled = a:enabled

		call mark#UpdateScope()

		" The list of patterns may be sparse, return only the actual patterns.
		return mark#GetCount()
	endif
	return 0
endfunction

" Access the list of mark patterns.
function! s:SerializeMark( index )
	return (empty(s:names[a:index]) ? s:pattern[a:index] : {'pattern': s:pattern[a:index], 'name': s:names[a:index]})
endfunction
function! s:Deserialize( mark )
	return (type(a:mark) == type({}) ? [get(a:mark, 'pattern', ''), get(a:mark, 'name', '')] : [a:mark, ''])
endfunction
function! s:DeserializeMark( mark, index )
	let [s:pattern[a:index], s:names[a:index]] = s:Deserialize(a:mark)
endfunction
function! mark#ToList()
	" Trim unused patterns from the end of the list, the amount of available marks
	" may differ on the next invocation (e.g. due to a different number of
	" highlight groups in Vim and GVIM). We want to keep empty patterns in the
	" front and middle to maintain the mapping to highlight groups, though.
	let l:highestNonEmptyIndex = s:markNum - 1
	while l:highestNonEmptyIndex >= 0 && empty(s:pattern[l:highestNonEmptyIndex]) && empty(s:names[l:highestNonEmptyIndex])
		let l:highestNonEmptyIndex -= 1
	endwhile

	return (l:highestNonEmptyIndex < 0 ? [] : map(range(0, l:highestNonEmptyIndex), 's:SerializeMark(v:val)'))
endfunction

" Return the mark number that represents a:pattern (regexp / literal text (as
" set from <Leader>m or :Mark {pattern}) with a:isLiteral = 1), or 0 if not
" found. With a:isConsiderAlternatives = 1, will also look for individual
" alternatives (set from {N}<Leader>m or :{N}Mark).
function! mark#GetMarkNumber( pattern, isLiteral, isConsiderAlternatives ) abort
	let l:searchPattern = ingo#regexp#magic#Normalize(a:isLiteral ? ingo#regexp#FromLiteralText(a:pattern, 1, '') : a:pattern)
	if empty(l:searchPattern) | return 0 | endif

	let l:i = 0
	while l:i < s:markNum
		if l:searchPattern ==# s:pattern[l:i] || (a:isConsiderAlternatives && index(s:SplitIntoAlternatives(s:pattern[l:i]), l:searchPattern) != -1)
			return l:i + 1
		endif
		let l:i += 1
	endwhile

	return 0
endfunction

" Common functions for :MarkLoad and :MarkSave
function! mark#MarksVariablesComplete( ArgLead, CmdLine, CursorPos )
	return sort(map(filter(keys(g:), 'v:val !~# "^MARK_\\%(MARKS\\|ENABLED\\)$" && v:val =~# "\\V\\^MARK_' . (empty(a:ArgLead) ? '\\S' : escape(a:ArgLead, '\')) . '"'), 'v:val[5:]'))
endfunction
function! s:GetMarksVariable( ... )
	return printf('MARK_%s', (a:0 ? a:1 : 'MARKS'))
endfunction

" :MarkLoad command.
function! mark#LoadCommand( isShowMessages, ... )
	try
		let l:marksVariable = call('s:GetMarksVariable', a:000)
		let l:isEnabled = (a:0 ? exists('g:' . l:marksVariable) : (exists('g:MARK_ENABLED') ? g:MARK_ENABLED : 1))

		let l:marks = ingo#plugin#persistence#Load(l:marksVariable, [])
		if empty(l:marks)
			call ingo#err#Set('No marks stored under ' . l:marksVariable . (ingo#plugin#persistence#CanPersist(l:marksVariable) ? '' : ", and persistence not configured via ! flag in 'viminfo'"))
			return 0
		endif

		let l:loadedMarkNum = mark#Load(l:marks, l:isEnabled)

		if a:isShowMessages
			if l:loadedMarkNum == 0
				echomsg 'No persistent marks defined in ' . l:marksVariable
			else
				echomsg printf('Loaded %d mark%s', l:loadedMarkNum, (l:loadedMarkNum == 1 ? '' : 's')) . (s:enabled ? '' : '; marks currently disabled')
			endif
		endif

		return 1
	catch /^Load:/
		if a:0
			call ingo#err#Set(printf('Corrupted persistent mark info in %s', l:marksVariable))
			execute 'unlet! g:' . l:marksVariable
		else
			call ingo#err#Set('Corrupted persistent mark info in g:MARK_MARKS and g:MARK_ENABLED')
			unlet! g:MARK_MARKS
			unlet! g:MARK_ENABLED
		endif
		return 0
	endtry
endfunction

" :MarkSave command.
function! s:SavePattern( ... )
	let l:savedMarks = mark#ToList()

	let l:marksVariable = call('s:GetMarksVariable', a:000)
	call ingo#plugin#persistence#Store(l:marksVariable, l:savedMarks)
	if ! a:0
		let g:MARK_ENABLED = s:enabled
	endif

	return (empty(l:savedMarks) ? 2 : 1)
endfunction
function! mark#SaveCommand( ... )
	if ! ingo#plugin#persistence#CanPersist()
		if ! a:0
			call ingo#err#Set("Cannot persist marks, need ! flag in 'viminfo': :set viminfo+=!")
			return 0
		elseif a:1 =~# '^\L\+$'
			call ingo#msg#WarningMsg("Cannot persist marks, need ! flag in 'viminfo': :set viminfo+=!")
		endif
	endif

	let l:result = call('s:SavePattern', a:000)
	if l:result == 2
		call ingo#msg#WarningMsg('No marks defined')
	endif
	return l:result
endfunction

" :MarkYankDefinitions and :MarkYankDefinitionsOneLiner commands.
function! mark#GetDefinitionCommands( isOneLiner )
	let l:marks = mark#ToList()
	if empty(l:marks)
		return []
	endif

	let l:commands = []
	for l:i in range(len(l:marks))
		if ! empty(l:marks[l:i])
			let [l:pattern, l:name] = s:Deserialize(l:marks[l:i])
			call add(l:commands, printf('%dMark! /%s/%s', l:i + 1, escape(l:pattern, '/'), (empty(l:name) ? '' : ' as ' . l:name)))
		endif
	endfor

	return (a:isOneLiner ? [join(map(l:commands, '"exe " . string(v:val)'), ' | ')] : l:commands)
endfunction
function! mark#YankDefinitions( isOneLiner, register )
	let l:commands = mark#GetDefinitionCommands(a:isOneLiner)
	if empty(l:commands)
		call ingo#err#Set('No marks defined')
		return 0
	endif

	return ! setreg(a:register, join(l:commands, "\n"))
endfunction

" :MarkName command.
function! s:HasNamedMarks()
	return (! empty(filter(copy(s:names), '! empty(v:val)')))
endfunction
function! mark#SetName( isClearAll, groupNum, name )
	if a:isClearAll
		if a:groupNum != 0
			call ingo#err#Set('Use either [!] to clear all names, or [N] to name a single group, but not both.')
			return 0
		endif
		let s:names = repeat([''], s:markNum)
	elseif a:groupNum > s:markNum
		call ingo#err#Set(printf('Only %d mark highlight groups', s:markNum))
		return 0
	else
		let s:names[a:groupNum - 1] = a:name
	endif
	return 1
endfunction


" Query mark group number.
function! s:GetNextGroupIndex()
	let l:nextGroupIndex = s:FreeGroupIndex()
	if l:nextGroupIndex == -1
		let l:nextGroupIndex = s:cycle
	endif
	return l:nextGroupIndex
endfunction
function! s:GetMarker( index, nextGroupIndex )
	let l:marker = ''
	if s:lastSearch == a:index
		let l:marker .= '/'
	endif
	if a:index == a:nextGroupIndex
		let l:marker .= '>'
	endif
	return l:marker
endfunction
function! s:GetAlternativeCount( pattern )
	return len(s:SplitIntoAlternatives(a:pattern))
endfunction
function! s:PrintMarkGroup( nextGroupIndex )
	for i in range(s:markNum)
		echon ' '
		execute 'echohl MarkWord' . (i + 1)
		let c = s:GetAlternativeCount(s:pattern[i])
		echon printf('%1s%s%2d ', s:GetMarker(i, a:nextGroupIndex), (c ? (c > 1 ? c : '') . '*' : ''), (i + 1))
		echohl None
	endfor
endfunction
function! mark#QueryMarkGroupNum()
	echohl Question
	echo 'Mark?'
	echohl None
	let l:nextGroupIndex = s:GetNextGroupIndex()
	call s:PrintMarkGroup(l:nextGroupIndex)

	let l:nr = 0
	while 1
		let l:char = nr2char(getchar())

		if l:char ==# "\<CR>"
			return (l:nr == 0 ? l:nextGroupIndex + 1 : l:nr)
		elseif l:char !~# '\d'
			return -1
		endif
		echon l:char

		let l:nr = 10 * l:nr + l:char
		if s:markNum < 10 * l:nr
			return l:nr
		endif
	endwhile
endfunction

" :Marks command.
function! mark#List()
	let l:hasNamedMarks = s:HasNamedMarks()
	echohl Title
	if l:hasNamedMarks
		echo "group:name\tpattern"
	else
		echo 'group     pattern'
	endif
	echohl None
	echon '   (N) # of alternatives   > next mark group    / current search mark'
	let l:nextGroupIndex = s:GetNextGroupIndex()
	for i in range(s:markNum)
		execute 'echohl MarkWord' . (i + 1)
		let l:alternativeCount = s:GetAlternativeCount(s:pattern[i])
		let l:alternativeCountString = (l:alternativeCount > 1 ? ' (' . l:alternativeCount . ')' : '')
		let [l:name, l:format] = (empty(s:names[i]) ? ['', '%-4s'] : [':' . s:names[i], '%-10s'])
		echo printf('%1s%3d' . l:format . ' ', s:GetMarker(i, l:nextGroupIndex), (i + 1), l:name . l:alternativeCountString)
		echohl None
		echon (l:hasNamedMarks ? "\t" : ' ') . s:pattern[i]
	endfor

	if ! s:enabled
		echo 'Marks are currently disabled.'
	endif
endfunction


" :Mark command completion.
function! mark#Complete( ArgLead, CmdLine, CursorPos )
	let l:cmdlineBeforeCursor = strpart(a:CmdLine, 0, a:CursorPos)
	let l:matches = matchlist(l:cmdlineBeforeCursor, '\C\(\d*\)\s*Mark!\?\s\+\V' . escape(a:ArgLead, '\'))
	if empty(l:matches)
		return []
	endif

	" Complete from the command's mark group, or all groups when none is
	" specified.
	let l:groupNum = 0 + l:matches[1]
	let l:patterns =(l:groupNum == 0 || empty(get(s:pattern, l:groupNum - 1, '')) ? s:GetUsedPatterns() : [s:pattern[l:groupNum - 1]])

	" Complete both the entire pattern as well as its individual alternatives.
	let l:expandedPatterns = []
	for l:pattern in l:patterns
		if index(l:expandedPatterns, l:pattern) == -1
			call add(l:expandedPatterns, l:pattern)
		endif
		let l:alternatives = s:SplitIntoAlternatives(l:pattern)
		if len(l:alternatives) > 1
			for l:alternative in l:alternatives
				if index(l:expandedPatterns, l:alternative) == -1
					call add(l:expandedPatterns, l:alternative)
				endif
			endfor
		endif
	endfor

	call map(l:expandedPatterns, '"/" . escape(v:val, "/") . "/"')

	" Filter according to the argument lead. Allow to omit the frequent initial
	" \< atom in the lead.
	return filter(l:expandedPatterns, "v:val =~ '^\\%(\\\\<\\)\\?\\V' . " . string(escape(a:ArgLead, '\')))
endfunction


"- integrations ----------------------------------------------------------------

" Access the number of possible marks.
function! mark#GetGroupNum()
	return s:markNum
endfunction

" Access the number of defined marks.
function! s:GetUsedPatterns()
	return filter(copy(s:pattern), '! empty(v:val)')
endfunction
function! mark#GetCount()
	return len(s:GetUsedPatterns())
endfunction

" Access the current / passed index pattern.
function! mark#GetPattern( ... )
	if a:0
		return s:pattern[a:1]
	else
		return (s:lastSearch == -1 ? '' : s:pattern[s:lastSearch])
	endif
endfunction

" Are marks currently enabled?
function! mark#IsEnabled() abort
	return s:enabled
endfunction


"- initializations ------------------------------------------------------------

augroup Mark
	autocmd!
	autocmd BufWinEnter * call mark#UpdateMark()
	autocmd WinEnter * if ! exists('w:mwMatch') | call mark#UpdateMark() | endif
	autocmd TabEnter * call mark#UpdateScope()
augroup END

" Define global variables and initialize current scope.
function! mark#Init()
	let s:markNum = 0
	while hlexists('MarkWord' . (s:markNum + 1))
		let s:markNum += 1
	endwhile
	let s:pattern = repeat([''], s:markNum)
	let s:names = repeat([''], s:markNum)
	let s:cycle = 0
	let s:lastSearch = -1
	let s:enabled = 1
endfunction
function! mark#ReInit( newMarkNum )
	if a:newMarkNum < s:markNum " There are less marks than before.
		" Clear the additional highlight groups.
		for i in range(a:newMarkNum + 1, s:markNum)
			execute 'highlight clear MarkWord' . (i + 1)
		endfor

		" Truncate the mark patterns.
		let s:pattern = s:pattern[0 : (a:newMarkNum - 1)]
		let s:names = s:names[0 : (a:newMarkNum - 1)]

		" Correct any indices.
		let s:cycle = min([s:cycle, (a:newMarkNum - 1)])
		let s:lastSearch = (s:lastSearch < a:newMarkNum ? s:lastSearch : -1)
	elseif a:newMarkNum > s:markNum " There are more marks than before.
		" Expand the mark patterns.
		let s:pattern += repeat([''], (a:newMarkNum - s:markNum))
		let s:names += repeat([''], (a:newMarkNum - s:markNum))
	endif

	let s:markNum = a:newMarkNum
endfunction

call mark#Init()
if exists('g:mwDoDeferredLoad') && g:mwDoDeferredLoad
	unlet g:mwDoDeferredLoad
	call mark#LoadCommand(0)
else
	call mark#UpdateScope()
endif

" vim: ts=4 sts=0 sw=4 noet
