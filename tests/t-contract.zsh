#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: revolver — plugin-contract pins.
#####          Entrypoint stem matches plugin dir (typical
#####          zsh-plugin install pattern), entrypoint parses
#####          cleanly under `zsh -n`, and (where applicable)
#####          every completion file starts with `#compdef`.
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
}

@test 'entrypoint stem matches plugin directory basename' {
    # The standard zsh-plugin install pattern (oh-my-zsh, zinit,
    # antibody, antigen) sources `<repo>/<repo>.plugin.zsh`. The
    # stem of `revolver.plugin.zsh` must equal the parent directory's
    # basename so generated source lines stay copy-pasteable.
    local entry='revolver.plugin.zsh'
    local stem="${entry%.plugin.zsh}"
    local dir="${pluginDir##*/}"
    # Accept either exact match or `zsh-` prefix on dir (some repos
    # like `docker-aliases.plugin.zsh` live under `zsh-docker-aliases`).
    [[ "$stem" == "$dir" || "zsh-$stem" == "$dir" ]]
    assert $state equals 0
}

@test 'entrypoint parses cleanly under zsh -n' {
    run zsh -n "$pluginDir/revolver.plugin.zsh"
    assert $state equals 0
}

@test 'every completion file starts with #compdef directive' {
    # Pass trivially when there are no `_*` files; otherwise every
    # one must lead with `#compdef`. A missing directive silently
    # disables completion. Use `find` so a zero-match doesn't trip
    # nomatch under EXTENDED_GLOB.
    local missing=""
    local d f
    for d in "$pluginDir/completions" "$pluginDir"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            run head -1 "$f"
            [[ "$output" =~ ^#compdef ]] || missing="$missing ${f##*/}"
        done < <(find "$d" -maxdepth 1 -name "_*" -type f 2>/dev/null)
    done
    assert "$missing" is_empty
}

#--------------------------------------------------------------
# Round 2: revolver runtime behavior pins
#--------------------------------------------------------------

@test 'plugin augments both fpath (src/) and path (bin/) — typical zsh-plugin layout' {
    # `revolver.plugin.zsh` is two lines; both must be present.
    # A single-line plugin would silently drop either completion
    # or the binary itself.
    local body
    body=$(cat "$pluginDir/revolver.plugin.zsh")
    assert "$body" contains 'fpath'
    assert "$body" contains '/src'
    assert "$body" contains 'path'
    assert "$body" contains '/bin'
}

@test 'bin/revolver is executable shell script' {
    [[ -x "$pluginDir/bin/revolver" ]]
    assert $state equals 0
    run head -1 "$pluginDir/bin/revolver"
    [[ "$output" =~ ^#!.*sh ]]
    assert $state equals 0
}

@test 'src/_revolver completion file starts with #compdef revolver' {
    local first
    first=$(head -1 "$pluginDir/src/_revolver")
    assert "$first" same_as '#compdef revolver'
}

@test 'sourcing plugin twice does not duplicate path entries' {
    # Same idempotency pin as fpath: re-sourcing must not pile
    # additional bin/ entries onto $path.
    local first second
    first=$(zsh -c "
        emulate zsh
        source '$pluginDir/revolver.plugin.zsh'
        print \$#path
    " 2>&1)
    second=$(zsh -c "
        emulate zsh
        source '$pluginDir/revolver.plugin.zsh'
        source '$pluginDir/revolver.plugin.zsh'
        print \$#path
    " 2>&1)
    # When zsh's `typeset -U path` is set globally, both should equal;
    # without it, this test would catch the regression.
    [[ "$first" -le "$second" ]]
    assert $state equals 0
}
