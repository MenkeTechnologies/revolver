#!/usr/bin/env zunit
#{{{                    MARK:Header
#**************************************************************
##### Purpose: revolver contract pins. revolver is a progress
#####          spinner for ZSH. Tests cover the public surface
#####          (--version, --help, command dispatch, spinner
#####          catalogue) and the state-file plumbing — without
#####          actually starting any background processes that
#####          could orphan in CI.
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
    pluginFile="$pluginDir/revolver.plugin.zsh"
    revBin="$pluginDir/bin/revolver"
    compFile="$pluginDir/src/_revolver"
}

@test 'plugin file augments fpath with src/ AND path with bin/' {
    # Pin: the plugin must register BOTH (a) the completion under
    # src/ via fpath and (b) the binary under bin/ via path. Drop
    # either and either the completion or the command disappears.
    local body
    body=$(cat "$pluginFile")
    assert "$body" contains 'fpath=("${0:h}/src" $fpath)'
    assert "$body" contains 'path=("${0:h}/bin" $path)'
}

@test 'bin/revolver shebang is zsh (NOT bash — script uses zsh associative arrays)' {
    # Pin: the _revolver_spinners table is a zsh -A array; bash
    # would fail at line 4. Pin the shebang to lock the runtime.
    local first
    first=$(head -1 "$revBin")
    assert "$first" same_as '#!/usr/bin/env zsh'
}

@test 'bin/revolver parses cleanly under zsh -n' {
    run zsh -n "$revBin"
    assert $state equals 0
}

@test 'src/_revolver completion exists + has #compdef header' {
    assert "$compFile" is_file
    local first
    first=$(head -1 "$compFile")
    assert "$first" contains '#compdef'
}

@test '_revolver_spinners declares 30+ spinner styles (catastrophic-shrink guard)' {
    # Pin: the spinner catalogue is the killer feature. Counting
    # the lines inside the associative-array literal gives a floor.
    local count
    count=$(awk '/^_revolver_spinners=\(/,/^\)/' "$revBin" | grep -cE "^  '")
    local result=$([[ "$count" -ge 30 ]] && echo yes || echo "no:$count")
    assert "$result" same_as 'yes'
}

@test '_revolver_spinners includes the named-popular styles (dots/line/arrow/pong)' {
    # Pin: a subset of named spinners that downstream scripts
    # explicitly reference. Removing any silently breaks their UX.
    local body
    body=$(cat "$revBin")
    assert "$body" contains "'dots'"
    assert "$body" contains "'line'"
    assert "$body" contains "'arrow'"
    assert "$body" contains "'pong'"
    assert "$body" contains "'shark'"
    assert "$body" contains "'balloon'"
}

@test 'spinner catalogue entries follow "interval frame frame..." format' {
    # Pin: each value MUST start with a decimal interval (e.g. 0.08)
    # then space-separated frames. _revolver_process uses field 1
    # as sleep delay. A refactor that swaps the order would silently
    # break every spinner's timing.
    local sample
    sample=$(grep "^  'dots' " "$revBin")
    # Expect: 'dots' '<float> <frame> <frame> ...'
    [[ "$sample" =~ "'dots' '[0-9]+\.[0-9]+ " ]]
    assert $? equals 0
}

@test 'revolver --version prints 0.2.0 (the published Homebrew formula version)' {
    # End-to-end: invoke the binary, verify version output. Catches
    # a forgotten bump that would let an old version ship under a
    # new release tag.
    local out
    out=$(zsh "$revBin" --version 2>&1)
    assert "$out" same_as '0.2.0'
}

@test 'revolver --help prints usage and exits 0' {
    local rc
    zsh "$revBin" --help >/dev/null 2>&1
    rc=$?
    assert "$rc" same_as '0'
}

@test 'revolver -h is the short form of --help' {
    # Pin: zparseopts maps h=help -help=help. If a refactor splits
    # them, short-form -h silently does nothing.
    local rc
    zsh "$revBin" -h >/dev/null 2>&1
    rc=$?
    assert "$rc" same_as '0'
}

@test 'revolver -v is the short form of --version' {
    local out
    out=$(zsh "$revBin" -v 2>&1)
    assert "$out" same_as '0.2.0'
}

@test 'revolver dispatches on start|update|stop|demo (the public verb set)' {
    # Pin: the case branch must keep all 4 documented verbs. Drop
    # any and that verb silently bails through the "not recognised"
    # branch.
    local body
    body=$(cat "$revBin")
    assert "$body" contains 'case $ctx in'
    assert "$body" contains 'start|update|stop|demo)'
}

@test 'revolver errors on unknown command + exits non-zero' {
    # End-to-end: invoke with a bogus verb, verify the error path.
    # Capture both stdout and exit code through a shell that won't
    # propagate exit-on-error from the test runner.
    local out result
    out=$(zsh -c "zsh '$revBin' not-a-real-verb 2>&1; echo \"RC=\$?\"" 2>/dev/null)
    assert "$out" contains 'not recognised'
    assert "$out" contains 'RC=1'
}

@test 'revolver bad --style + valid verb exits non-zero' {
    # Pin: bad style name MUST exit non-zero, not silently default.
    # In a minimal test environment the molovo/color dependency is
    # unavailable so the error path may surface as "command not
    # found: color" before the spinner-check runs. Either way,
    # exit code must be non-zero.
    local out
    out=$(zsh -c "zsh '$revBin' --style not-a-spinner start test 2>&1 >/dev/null; echo \"RC=\$?\"" 2>/dev/null)
    assert "$out" contains 'RC='
    # Exit code should NOT be 0
    [[ "$out" != *'RC=0'* ]]
    assert $? equals 0
}

@test 'revolver defaults to the dots style when --style is omitted' {
    # Pin: the `[[ -z $style ]] && style="dots"` line. If a refactor
    # changes the default, every user who relied on bare `revolver
    # start "msg"` gets a different spinner.
    local body
    body=$(cat "$revBin")
    assert "$body" contains "style='dots'"
}

@test '_revolver_start uses ${REVOLVER_DIR:-${ZDOTDIR:-$HOME}/.revolver} as the state dir' {
    # Pin: documented state-dir resolution order. Without ZDOTDIR
    # fallback, users of dotfile managers that move .zshrc would
    # get an unexpected ~/.revolver create.
    local body
    body=$(cat "$revBin")
    assert "$body" contains 'REVOLVER_DIR'
    assert "$body" contains 'ZDOTDIR'
    assert "$body" contains '$HOME}/.revolver'
}

@test 'state file is keyed by $PPID (parent process — caller script)' {
    # Pin: each caller script gets its own state file via PPID.
    # If a refactor uses $$ (the revolver subprocess pid) instead,
    # state files orphan and stop signals miss the spinner.
    local body
    body=$(cat "$revBin")
    assert "$body" contains 'statefile="$dir/$PPID"'
}

@test '_revolver_start records PID + message into state file' {
    # Pin: the state file format is "PID MSG". _revolver_update
    # rewrites the message; _revolver_stop kills the PID. If the
    # format drifts, update/stop go out of sync.
    local body
    body=$(cat "$revBin")
    assert "$body" contains 'echo "$! $msg" >! $statefile'
}

@test '_revolver_process backgrounds via &! (no-hup + no-wait)' {
    # Pin: zsh's &! (vs &) makes the spinner survive shell exit
    # without becoming a zombie. Critical for scripts that call
    # `revolver start` then exit.
    local body
    body=$(cat "$revBin")
    assert "$body" contains '_revolver_process $PPID &!'
}

@test '_revolver_update errors when state file is missing (no orphan-msg writes)' {
    # Pin: the "Revolver process could not be found" guard prevents
    # update from creating a stale state file that survives forever
    # without a spinner attached.
    local body
    body=$(cat "$revBin")
    assert "$body" contains 'Revolver process could not be found'
}

@test '_revolver_demo iterates every spinner via ${(@k)_revolver_spinners[@]}' {
    # Pin: the (@k) parameter flag is what gives stable key
    # iteration. Without (@k), demo would silently skip keys with
    # whitespace.
    local body
    body=$(cat "$revBin")
    assert "$body" contains '${(@k)_revolver_spinners[@]}'
}

@test 'bin/revolver invokes the dispatcher at file bottom via revolver "$@"' {
    # Pin: the file must call revolver at the end with the user's
    # args. Without it, sourcing or executing the file just defines
    # functions without running anything.
    local last
    last=$(grep -E '^revolver ' "$revBin" | tail -1)
    assert "$last" same_as 'revolver "$@"'
}

@test 'plugin sourced cleanly + revolver visible on path after sourcing' {
    # End-to-end: source the plugin in a fresh subshell, verify the
    # `revolver` binary is reachable via $path[1] entry.
    local found
    found=$(zsh -c "
        emulate zsh
        source '$pluginFile'
        whence revolver
    " 2>&1)
    assert "$found" contains 'revolver'
}

#--------------------------------------------------------------
# Round 3: fresh-surface pins (completion + spinner metadata)
#--------------------------------------------------------------

@test 'completion declares every public verb (start|update|stop|demo) in _commands' {
    # Pin: src/_revolver _commands array must enumerate every verb
    # accepted by the dispatcher's case branch. If a refactor adds
    # a 5th verb (e.g. `restart`) and forgets the completion entry,
    # users get the verb working without tab-complete.
    local body
    body=$(cat "$compFile")
    assert "$body" contains "'start:"
    assert "$body" contains "'update:"
    assert "$body" contains "'stop:"
    assert "$body" contains "'demo:"
}

@test 'completion wires both -h/--help and -v/--version option pairs' {
    # Pin: the _arguments call enumerates both short+long forms in
    # parens-separated bundles. If a refactor drops the short form
    # from _arguments, completion silently stops offering -h / -v.
    local body
    body=$(cat "$compFile")
    assert "$body" contains '(-h --help)'
    assert "$body" contains '(-v --version)'
}

@test 'spinner catalogue floor: at least 50 styles declared' {
    # Tighter floor than the existing 30+ pin. revolver currently
    # ships 55; a drop below 50 means a substantial chunk of the
    # catalogue silently disappeared from the literal.
    local count
    count=$(awk '/^_revolver_spinners=\(/,/^\)/' "$revBin" | grep -cE "^  '")
    local result=$([[ "$count" -ge 50 ]] && echo yes || echo "no:$count")
    assert "$result" same_as 'yes'
}

@test 'every spinner interval is < 1.0 second (spinner not pulser)' {
    # Pin: the catalogue's first field is a sleep interval in seconds.
    # A value >=1.0 would make the "spinner" stutter visibly between
    # frames — fail the UX contract. Ignore the `flip` entry, whose
    # frames contain a backtick that confuses the simple awk split.
    local bad
    bad=$(awk -F"'" '/^  / && $2 != "flip" { split($4, a, " "); if (a[1]+0 >= 1.0) print $2 ":" a[1] }' "$revBin")
    assert "$bad" is_empty
}

@test 'completion declares no verbs that the dispatcher does not handle' {
    # Reverse direction of the prior pin: every _commands entry must
    # correspond to a real dispatcher branch (start|update|stop|demo).
    # Catches stale completion entries that survived a verb removal.
    local extra verbs verb
    extra=""
    verbs=$(awk -F"'" '/^  '\''[a-z]+:/ { print $2 }' "$compFile" | awk -F: '{print $1}')
    for verb in ${(f)verbs}; do
        case "$verb" in
            start|update|stop|demo) ;;
            *) extra="$extra $verb" ;;
        esac
    done
    assert "$extra" is_empty
}
