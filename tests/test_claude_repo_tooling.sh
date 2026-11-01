#!/bin/bash

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
failures=0

check() {
    local name=$1 condition_result=$2
    if [[ "$condition_result" == "ok" ]]; then
        printf 'PASS %s\n' "$name"
    else
        printf 'FAIL %s\n' "$name"
        failures=$((failures + 1))
    fi
}

setup_throwaway_repository() {
    sandbox=$(mktemp -d)
    git init -q "$sandbox/repo"
    mkdir -p "$sandbox/repo/.githooks" "$sandbox/repo/docs" "$sandbox/bin"
    cp "$repo_root/.githooks/pre-commit" "$sandbox/repo/.githooks/pre-commit"
    mkdir -p "$sandbox/repo/configs/bin" "$sandbox/repo/configs/claude"
    cp "$repo_root/configs/bin/claude-settings-diff" "$sandbox/repo/configs/bin/claude-settings-diff"
    git -C "$sandbox/repo" config core.hooksPath .githooks
    git -C "$sandbox/repo" config user.email test@example.com
    git -C "$sandbox/repo" config user.name test
    printf '#!/bin/bash\nexit 0\n' > "$sandbox/bin/gitleaks"
    chmod +x "$sandbox/bin/gitleaks"
}

commit_status_of() {
    (cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" git commit -q -m "chore: test" > /dev/null 2>&1; echo $?)
}

fake_authorization_header_line() {
    printf 'curl -H "%s: %s %s" https://example.com\n' "Authori""zation" "Bear""er" "abcdefghijklmnopqrstuvwx"
}

shouldBlockCommitWhenFileOutsideClaudeConfigsHoldsBearerToken() {
    setup_throwaway_repository
    fake_authorization_header_line > "$sandbox/repo/docs/notes.md"
    git -C "$sandbox/repo" add docs/notes.md
    check "${FUNCNAME[0]}" "$([[ "$(commit_status_of)" != 0 ]] && echo ok || echo no)"
}

shouldAllowCommitWhenStagedFilesHoldNoSecret() {
    setup_throwaway_repository
    echo 'plain notes' > "$sandbox/repo/docs/notes.md"
    git -C "$sandbox/repo" add docs/notes.md
    check "${FUNCNAME[0]}" "$([[ "$(commit_status_of)" == 0 ]] && echo ok || echo no)"
}

shouldBlockCommitWhenGitleaksReportsLeak() {
    setup_throwaway_repository
    printf '#!/bin/bash\nexit 1\n' > "$sandbox/bin/gitleaks"
    echo 'plain notes' > "$sandbox/repo/docs/notes.md"
    git -C "$sandbox/repo" add docs/notes.md
    check "${FUNCNAME[0]}" "$([[ "$(commit_status_of)" != 0 ]] && echo ok || echo no)"
}

shouldWarnAndStillScanWhenGitleaksIsMissing() {
    setup_throwaway_repository
    rm "$sandbox/bin/gitleaks"
    if PATH="$sandbox/bin:$PATH" command -v gitleaks > /dev/null 2>&1; then
        check "${FUNCNAME[0]}" ok
        return
    fi
    echo 'plain notes' > "$sandbox/repo/docs/notes.md"
    git -C "$sandbox/repo" add docs/notes.md
    local clean_output
    clean_output=$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" git commit -q -m "chore: test" 2>&1)
    local clean_status=$?
    fake_authorization_header_line > "$sandbox/repo/docs/leak.md"
    git -C "$sandbox/repo" add docs/leak.md
    (cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" git commit -q -m "chore: leak" > /dev/null 2>&1)
    local leak_status=$?
    local verdict=no
    if [[ "$clean_status" == 0 && "$clean_output" == *"gitleaks is not installed"* && "$leak_status" != 0 ]]; then
        verdict=ok
    fi
    check "${FUNCNAME[0]}" "$verdict"
}

shouldBlockCommitWhenStagedSharedSettingsHoldBedrockEnv() {
    setup_throwaway_repository
    echo '{"env": {"CLAUDE_CODE_USE_BEDROCK": "1", "AWS_REGION": "eu-west-1"}}' > "$sandbox/repo/configs/claude/settings.json"
    git -C "$sandbox/repo" add configs/claude/settings.json
    local output
    output=$(cd "$sandbox/repo" && PATH="$sandbox/bin:$PATH" git commit -q -m "chore: test" 2>&1)
    check "${FUNCNAME[0]}" "$([[ $? -ne 0 && "$output" == *"env.CLAUDE_CODE_USE_BEDROCK"* && "$output" == *"env.AWS_REGION"* && "$output" != *eu-west-1* ]] && echo ok || echo no)"
}

shouldAllowCommitWhenStagedSharedSettingsHoldOtherEnv() {
    setup_throwaway_repository
    echo '{"env": {"LAMINAR_CONVENTION_HINTS": "off"}}' > "$sandbox/repo/configs/claude/settings.json"
    git -C "$sandbox/repo" add configs/claude/settings.json
    check "${FUNCNAME[0]}" "$([[ "$(commit_status_of)" == 0 ]] && echo ok || echo no)"
}

shouldPrintSameStatusLineAsRecordedOutput() {
    local sandbox_home
    sandbox_home=$(mktemp -d)
    mkdir -p "$sandbox_home/bin"
    printf '#!/bin/bash\necho "{\\"email\\":\\"a@b.c\\"}"\n' > "$sandbox_home/bin/claude"
    chmod +x "$sandbox_home/bin/claude"
    local session="statusline-test-$$"
    local output
    output=$(printf '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"cost":{"total_cost_usd":1.23456},"context_window":{"used_percentage":42.4},"session_id":"%s","workspace":{"current_dir":"/tmp","project_dir":"/tmp/proj"}}' "$session" \
        | PATH="$sandbox_home/bin:$PATH" bash "$repo_root/configs/claude/statusline-command.sh")
    rm -f "/tmp/statusline-git-$session" "/tmp/statusline-email-$session"
    check "${FUNCNAME[0]}" "$([[ "$output" == *"proj"* && "$output" == *"a@b.c"* && "$output" == *'$1.2346'* && "$output" == *"ctx 42%"* ]] && echo ok || echo no)"
}

shouldContainNoCommentLinesInStatusLineScript() {
    local comment_lines
    comment_lines=$(grep -c '^[[:space:]]*#[^!]' "$repo_root/configs/claude/statusline-command.sh")
    check "${FUNCNAME[0]}" "$([[ $comment_lines -eq 0 ]] && echo ok || echo no)"
}

shouldBlockCommitWhenFileOutsideClaudeConfigsHoldsBearerToken
shouldAllowCommitWhenStagedFilesHoldNoSecret
shouldBlockCommitWhenGitleaksReportsLeak
shouldWarnAndStillScanWhenGitleaksIsMissing
shouldBlockCommitWhenStagedSharedSettingsHoldBedrockEnv
shouldAllowCommitWhenStagedSharedSettingsHoldOtherEnv
shouldPrintSameStatusLineAsRecordedOutput
shouldContainNoCommentLinesInStatusLineScript

exit "$failures"
