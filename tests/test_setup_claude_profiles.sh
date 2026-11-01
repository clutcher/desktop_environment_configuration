#!/bin/bash

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

setup_sandbox() {
    sandbox=$(mktemp -d)
    export HOME="$sandbox/home"
    mkdir -p "$HOME" "$sandbox/bin" "$sandbox/repo"
    cp -r "$repo_root/scripts" "$repo_root/configs" "$sandbox/repo/"
    find "$sandbox/repo" -name __pycache__ -o -name .pytest_cache | xargs rm -rf
    printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$GIT_CALL_LOG"\n' > "$sandbox/bin/git"
    chmod +x "$sandbox/bin/git"
    export GIT_CALL_LOG="$sandbox/git-calls.log"
    export PATH="$sandbox/bin:$PATH"
    shared_dir="$HOME/.claude-shared"
}

run_stage() {
    (cd "$sandbox/repo" && source scripts/setup_claude_profiles.sh "$@" < /dev/null)
}

settings_diff() {
    CLAUDE_SHARED_DIR="$shared_dir" CLAUDE_REPO_CONFIG_DIR="$sandbox/repo/configs/claude" "$sandbox/repo/configs/bin/claude-settings-diff" "$@"
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

holds() { "$@" > /dev/null 2>&1 && echo ok || echo no; }
contains() { [[ "$1" == *"$2"* ]] && echo ok || echo no; }
verdict() { [[ "$1" == "$2" ]] && echo ok || echo no; }

shouldDeployRepoSettingsAsBaseAndNotAsSettingsJson() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/repo/configs/claude/settings.json" "$shared_dir/settings.base.json")"
    check "shouldNotDeploySettingsJson" "$(holds test ! -e "$shared_dir/settings.json")"
}

shouldDeployHooksAndStatusLine() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/repo/configs/claude/hooks/commit-message-check.py" "$shared_dir/hooks/commit-message-check.py")"
    check "shouldKeepStatusLineExecutable" "$(holds test -x "$shared_dir/statusline-command.sh")"
    check "shouldNotDeployHookTests" "$(holds test ! -e "$shared_dir/hooks/test_commit_message_check.py")"
}

shouldOverwriteDeployedBaseAndHooksPlainly() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '{"edited": true}' > "$shared_dir/settings.base.json"
    echo '# edited' >> "$shared_dir/hooks/commit-message-check.py"
    output=$(run_stage deploy-files)
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/repo/configs/claude/settings.json" "$shared_dir/settings.base.json")"
    check "shouldOverwriteHook" "$(holds cmp "$sandbox/repo/configs/claude/hooks/commit-message-check.py" "$shared_dir/hooks/commit-message-check.py")"
    check "shouldNotMentionDrift" "$([[ "$output" != *drift* ]] && echo ok || echo no)"
}

shouldKeepPreviousBaseWhenRepoBaseChanges() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    cp "$shared_dir/settings.base.json" "$sandbox/first-base.json"
    jq -c '.model = "sonnet"' "$sandbox/repo/configs/claude/settings.json" > "$sandbox/changed.json"
    mv "$sandbox/changed.json" "$sandbox/repo/configs/claude/settings.json"
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/first-base.json" "$shared_dir/.deployed/settings.base.json")"
    check "shouldDeployNewBase" "$(verdict "$(jq -r .model "$shared_dir/settings.base.json")" sonnet)"
}

shouldKeepOlderPreviousBaseWhenRepoBaseIsUnchanged() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '{"older": true}' > "$shared_dir/.deployed/settings.base.json"
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(verdict "$(jq -c . "$shared_dir/.deployed/settings.base.json")" '{"older":true}')"
}

shouldWriteNoPreviousBaseOnFirstDeploy() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds test ! -e "$shared_dir/.deployed/settings.base.json")"
}

shouldDeployClaudeInstructionsWithSnapshot() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/repo/configs/claude/CLAUDE.md" "$shared_dir/CLAUDE.md")"
    check "shouldKeepSnapshot" "$(holds cmp "$sandbox/repo/configs/claude/CLAUDE.md" "$shared_dir/.deployed/CLAUDE.md")"
}

shouldOverwriteClaudeInstructionsSilentlyWhenOnlyRepoChanged() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '# repo change' >> "$sandbox/repo/configs/claude/CLAUDE.md"
    run_stage deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds cmp "$sandbox/repo/configs/claude/CLAUDE.md" "$shared_dir/CLAUDE.md")"
}

shouldKeepClaudeInstructionsAndReportDriftWhenOnlyDeployedChanged() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '# claude edit' >> "$shared_dir/CLAUDE.md"
    output=$(run_stage deploy-files)
    check "${FUNCNAME[0]}" "$(contains "$output" "drift    CLAUDE.md")"
    check "shouldNotTouchDriftedFile" "$(holds grep -q 'claude edit' "$shared_dir/CLAUDE.md")"
}

shouldKeepDeployedClaudeInstructionsAndShowBothDiffsWhenBothChangedWithoutTerminal() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '# claude edit' >> "$shared_dir/CLAUDE.md"
    echo '# repo edit' >> "$sandbox/repo/configs/claude/CLAUDE.md"
    output=$(run_stage deploy-files)
    check "${FUNCNAME[0]}" "$(contains "$output" "+# claude edit")"
    check "shouldShowRepoDiffToo" "$(contains "$output" "+# repo edit")"
    check "shouldKeepDeployedCopyWithoutTerminal" "$(holds grep -q 'claude edit' "$shared_dir/CLAUDE.md")"
}

shouldDeployFilesDryRunWithoutWriting() {
    setup_sandbox
    run_stage --dry-run deploy-files > /dev/null
    check "${FUNCNAME[0]}" "$(holds test ! -e "$shared_dir/settings.base.json")"
}

shouldInstallBothToolsAndSetHooksPath() {
    setup_sandbox
    run_stage install-tooling > /dev/null
    check "${FUNCNAME[0]}" "$(holds test -x "$HOME/.local/bin/claude-profile-prepare" -a -x "$HOME/.local/bin/claude-settings-diff")"
    check "shouldSetHooksPath" "$(verdict "$(cat "$GIT_CALL_LOG")" "config core.hooksPath .githooks")"
}

shouldRejectRemovedPhases() {
    setup_sandbox
    local rejected=0 phase
    for phase in link-profile install-plugins new-profile; do
        run_stage "$phase" work > /dev/null 2>&1 || rejected=$((rejected + 1))
    done
    check "${FUNCNAME[0]}" "$(verdict "$rejected" 3)"
    check "shouldCreateNoProfile" "$(holds test ! -e "$HOME/.claude-work")"
}

shouldListOnlyCurrentPhasesInUsage() {
    setup_sandbox
    output=$(run_stage 2>&1)
    check "${FUNCNAME[0]}" "$(verdict "$(grep '^Phases:' <<< "$output")" "Phases: deploy-files, install-tooling")"
}

shouldReportDriftOfClaudeInstructionsOnly() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '# claude edit' >> "$shared_dir/CLAUDE.md"
    output=$(settings_diff)
    check "${FUNCNAME[0]}" "$(contains "$output" "deployed-drift   CLAUDE.md")"
    check "shouldCompareSettingsBaseHooksAndStatusLinePlainly" "$(contains "$output" "in-sync          settings.base.json")"
}

shouldReportPlainDifferenceOfDeployedBase() {
    setup_sandbox
    run_stage deploy-files > /dev/null
    echo '{"edited": true}' > "$shared_dir/settings.base.json"
    output=$(settings_diff -d)
    check "${FUNCNAME[0]}" "$(contains "$output" "differs          settings.base.json")"
    check "shouldShowDiff" "$(contains "$output" '+++ ')"
}

shouldDeployFilesWithoutEnvInBaseSettings() {
    check "${FUNCNAME[0]}" "$(holds jq -e 'has("env") | not' "$repo_root/configs/claude/settings.json")"
}

shouldDeployRepoSettingsAsBaseAndNotAsSettingsJson
shouldDeployHooksAndStatusLine
shouldOverwriteDeployedBaseAndHooksPlainly
shouldKeepPreviousBaseWhenRepoBaseChanges
shouldKeepOlderPreviousBaseWhenRepoBaseIsUnchanged
shouldWriteNoPreviousBaseOnFirstDeploy
shouldDeployClaudeInstructionsWithSnapshot
shouldOverwriteClaudeInstructionsSilentlyWhenOnlyRepoChanged
shouldKeepClaudeInstructionsAndReportDriftWhenOnlyDeployedChanged
shouldKeepDeployedClaudeInstructionsAndShowBothDiffsWhenBothChangedWithoutTerminal
shouldDeployFilesDryRunWithoutWriting
shouldInstallBothToolsAndSetHooksPath
shouldRejectRemovedPhases
shouldListOnlyCurrentPhasesInUsage
shouldReportDriftOfClaudeInstructionsOnly
shouldReportPlainDifferenceOfDeployedBase
shouldDeployFilesWithoutEnvInBaseSettings

exit "$failures"
