#!/bin/bash

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

setup_sandbox() {
    sandbox=$(mktemp -d)
    export HOME="$sandbox/home"
    mkdir -p "$HOME" "$sandbox/bin"
    cat > "$sandbox/bin/claude" <<'FAKE'
#!/bin/bash
printf 'config_dir=%s\n' "$CLAUDE_CONFIG_DIR"
printf 'profile_marker=%s\n' "$PROFILE_MARKER"
printf 'args=%s\n' "$*"
exit "${FAKE_CLAUDE_EXIT:-0}"
FAKE
    chmod +x "$sandbox/bin/claude"
    export PATH="$sandbox/bin:$PATH"
    unset CLAUDE_CONFIG_DIR PROFILE_MARKER FAKE_CLAUDE_EXIT
    source "$repo_root/dotfiles/bash/.bash_claude"
}

check() {
    local name=$1 condition_result=$2
    if [[ "$condition_result" == "ok" ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        failures=$((failures + 1))
    fi
}

contains() { [[ "$1" == *"$2"* ]] && echo ok || echo no; }

shouldUsePersonalProfileWhenNoProfileGiven() {
    setup_sandbox
    local output
    output=$(claude --version)
    check "${FUNCNAME[0]}" "$(contains "$output" "config_dir=$HOME/.claude-personal")"
}

shouldUseWorkProfileWhenProfileFlagGiven() {
    setup_sandbox
    local output
    output=$(claude -pf work --version)
    check "${FUNCNAME[0]}" "$(contains "$output" "config_dir=$HOME/.claude-work")"
}

shouldExposeProfileEnvToClaudeOnlyWhenProfileEnvExists() {
    setup_sandbox
    mkdir -p "$HOME/.claude-sample"
    echo 'PROFILE_MARKER=from-profile-env' > "$HOME/.claude-sample/profile.env"
    local output
    output=$(claude -pf sample)
    claude -pf sample > /dev/null
    local leaked="${PROFILE_MARKER:-absent}"
    check "${FUNCNAME[0]}" "$(contains "$output" "profile_marker=from-profile-env")"
    check "shouldKeepProfileEnvOutOfCallingShell" "$([[ "$leaked" == absent ]] && echo ok || echo no)"
}

shouldNotLaunchClaudeWhenProfileEnvIsBroken() {
    setup_sandbox
    mkdir -p "$HOME/.claude-sample"
    echo 'false' > "$HOME/.claude-sample/profile.env"
    local output status
    output=$(claude -pf sample)
    status=$?
    check "${FUNCNAME[0]}" "$([[ $status -ne 0 && "$output" != *config_dir* ]] && echo ok || echo no)"
}

shouldRejectProfileNameWhenItHasForbiddenCharacters() {
    setup_sandbox
    local output status
    output=$(claude -pf '../evil' 2>&1)
    status=$?
    check "${FUNCNAME[0]}" "$([[ $status -ne 0 && "$output" != *config_dir* ]] && echo ok || echo no)"
}

shouldPassClaudeExitStatusThrough() {
    setup_sandbox
    export FAKE_CLAUDE_EXIT=7
    claude -pf work > /dev/null
    local status=$?
    check "${FUNCNAME[0]}" "$([[ $status -eq 7 ]] && echo ok || echo no)"
}

shouldRunHelpThroughTheSameProfileEnvironment() {
    setup_sandbox
    mkdir -p "$HOME/.claude-sample"
    echo 'PROFILE_MARKER=from-profile-env' > "$HOME/.claude-sample/profile.env"
    local output
    output=$(claude -pf sample --help)
    check "${FUNCNAME[0]}" "$(contains "$output" "profile_marker=from-profile-env")"
}

install_fake_prepare() {
    cat > "$sandbox/bin/claude-profile-prepare" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$PREPARE_LOG"
exit "${FAKE_PREPARE_EXIT:-0}"
FAKE
    chmod +x "$sandbox/bin/claude-profile-prepare"
    export PREPARE_LOG="$sandbox/prepare.log"
}

shouldCheckSelectedProfileWithoutPluginsBeforeLaunching() {
    setup_sandbox
    install_fake_prepare
    claude -pf work --version > /dev/null
    check "${FUNCNAME[0]}" "$([[ "$(cat "$PREPARE_LOG")" == "--check --no-plugins work" ]] && echo ok || echo no)"
}

shouldCheckPersonalProfileWhenNoProfileGiven() {
    setup_sandbox
    install_fake_prepare
    claude --version > /dev/null
    check "${FUNCNAME[0]}" "$([[ "$(cat "$PREPARE_LOG")" == "--check --no-plugins personal" ]] && echo ok || echo no)"
}

shouldLaunchClaudeWhenPrepareFails() {
    setup_sandbox
    install_fake_prepare
    export FAKE_PREPARE_EXIT=1
    local output
    output=$(claude -pf work)
    check "${FUNCNAME[0]}" "$(contains "$output" "config_dir=$HOME/.claude-work")"
}

shouldLaunchClaudeWhenPrepareIsAbsent() {
    setup_sandbox
    local output
    output=$(claude -pf work)
    check "${FUNCNAME[0]}" "$(contains "$output" "config_dir=$HOME/.claude-work")"
}

shouldNotPrepareWhenProfileNameIsInvalid() {
    setup_sandbox
    install_fake_prepare
    claude -pf '../evil' > /dev/null 2>&1
    check "${FUNCNAME[0]}" "$([[ ! -e "$PREPARE_LOG" ]] && echo ok || echo no)"
}

shouldNotPrepareWhenShowingHelp() {
    setup_sandbox
    install_fake_prepare
    claude -pf work --help > /dev/null
    check "${FUNCNAME[0]}" "$([[ ! -e "$PREPARE_LOG" ]] && echo ok || echo no)"
}

shouldUsePersonalProfileWhenNoProfileGiven
shouldCheckSelectedProfileWithoutPluginsBeforeLaunching
shouldCheckPersonalProfileWhenNoProfileGiven
shouldLaunchClaudeWhenPrepareFails
shouldLaunchClaudeWhenPrepareIsAbsent
shouldNotPrepareWhenProfileNameIsInvalid
shouldNotPrepareWhenShowingHelp
shouldUseWorkProfileWhenProfileFlagGiven
shouldExposeProfileEnvToClaudeOnlyWhenProfileEnvExists
shouldNotLaunchClaudeWhenProfileEnvIsBroken
shouldRejectProfileNameWhenItHasForbiddenCharacters
shouldPassClaudeExitStatusThrough
shouldRunHelpThroughTheSameProfileEnvironment

exit "$failures"
