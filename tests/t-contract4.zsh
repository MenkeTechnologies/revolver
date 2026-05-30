#!/usr/bin/env zunit
#{{{                    MARK:Header
##### Purpose: revolver — fourth-tier contracts.
#####          Pins for spinner-index advancement direction (FORWARD
#####          only, no reverse mode), unknown-spinner-name validation
#####          path, REVOLVER_DIR override surface, and the canonical
#####          ZSH-array offset hack at spinner_index==0.
#}}}***********************************************************

@setup {
    0="${${0:#$ZSH_ARGZERO}:-${(%):-%N}}"
    0="${${(M)0:#/*}:-$PWD/$0}"
    pluginDir="${0:h:A}"
    binFile="$pluginDir/bin/revolver"
}

@test 'spinner_index advances FORWARD via modulo (no reverse direction)' {
    # Pin: `spinner_index=$(( $(( $spinner_index + 1 )) % $(( ${#frames} + 1 )) ))`.
    # The wrap uses (idx+1)%(N+1) so it counts 1,2,...,N,0,1,... — no
    # decrement path. A "--reverse" flag would require subtracting from
    # ${#frames} instead. Pin the absence of a decrement.
    grep -qE 'spinner_index=\$\(\( \$\(\( \$spinner_index \+ 1 \)\) %' "$binFile"
    local has_inc=$?
    ! grep -qE 'spinner_index=\$\(\( \$spinner_index - 1' "$binFile"
    local no_dec=$?
    assert $(( has_inc + no_dec )) equals 0
}

@test 'unknown spinner style is rejected with a colored error and exit 1' {
    # Pin: `if [[ -z $_revolver_spinners[$style] ]]; then echo ...; exit 1`.
    # Removing the guard would let an unknown style propagate to the
    # subscript expansion `frames=(${(@z)_revolver_spinners[$style]})`
    # which would silently yield no frames (and an infinite loop).
    grep -qE 'if \[\[ -z \$_revolver_spinners\[\$style\] \]\]; then' "$binFile"
    local guard=$?
    awk '/if \[\[ -z \$_revolver_spinners\[\$style\] \]\]/,/^[[:space:]]+fi/' "$binFile" | grep -qE 'exit 1'
    local ex=$?
    assert $(( guard + ex )) equals 0
}

@test 'REVOLVER_DIR override falls back to ${ZDOTDIR:-$HOME}/.revolver' {
    # Pin: 4 helper fns (_revolver_process, _revolver_stop,
    # _revolver_update, _revolver_start) all read the same expansion
    # `${REVOLVER_DIR:-"${ZDOTDIR:-$HOME}/.revolver"}`. Drifting any
    # one to a different default would put state files in two places
    # and the stop/update helpers would not find what start created.
    local count
    count=$(grep -cF 'dir=${REVOLVER_DIR:-"${ZDOTDIR:-$HOME}/.revolver"}' "$binFile")
    assert "$count" same_as '4'
}

@test 'spinner_index 0->1 bump is the ZSH-array 1-based offset hack' {
    # Pin: `if [[ $spinner_index -eq 0 ]]; then spinner_index+=1`.
    # The initial value is 0 (from `local ... spinner_index=0`) but
    # `frames[$spinner_index]` uses zsh 1-based indexing. Without the
    # bump, the first frame would be missed and the spinner would
    # start from frame 2 then wrap back to 0=empty on the first cycle.
    grep -qE 'if \[\[ \$spinner_index -eq 0 \]\]; then' "$binFile"
    local guard=$?
    grep -qE '^[[:space:]]+spinner_index\+=1' "$binFile"
    local bump=$?
    assert $(( guard + bump )) equals 0
}

@test 'demo subcommand iterates spinner-key array via (@k) (no key-flatten)' {
    # Pin: `for style in "${(@k)_revolver_spinners[@]}"; do`. The
    # `(@k)` flag enumerates ASSOCIATIVE-array keys; dropping `k`
    # would iterate values (the literal frame strings) instead, and
    # `revolver --style $style start $style` would error on each.
    grep -qF 'for style in "${(@k)_revolver_spinners[@]}"' "$binFile"
    assert $? equals 0
}
