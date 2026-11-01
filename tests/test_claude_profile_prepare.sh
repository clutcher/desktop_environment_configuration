#!/bin/bash

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
prepare_command="${PREPARE_COMMAND_UNDER_TEST:-$repo_root/configs/bin/claude-profile-prepare}"
failures=0
original_path=$PATH

setup_sandbox() {
    sandbox=$(mktemp -d)
    export HOME="$sandbox/home"
    export CLAUDE_SHARED_DIR="$HOME/.claude-shared"
    export CLAUDE_PROFILES_HOME="$HOME"
    export CLAUDE_COMMAND="$sandbox/bin/claude"
    export CLAUDE_CALL_LOG="$sandbox/claude-calls.log"
    export FAKE_CLAUDE_EXIT=0
    mkdir -p "$HOME" "$CLAUDE_SHARED_DIR" "$sandbox/bin"
    cp "$repo_root/configs/claude/settings.json" "$CLAUDE_SHARED_DIR/settings.base.json"
    printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$CLAUDE_CONFIG_DIR" "$*" >> "$CLAUDE_CALL_LOG"\nexit "$FAKE_CLAUDE_EXIT"\n' > "$sandbox/bin/claude"
    chmod +x "$sandbox/bin/claude"
    export PATH="$sandbox/bin:$original_path"
    unset CLAUDE_CONFIG_DIR
    profile_dir="$HOME/.claude-work"
    mkdir -p "$profile_dir"
    mark_profile_for_linking work
}

mark_profile_for_linking() {
    mkdir -p "$CLAUDE_SHARED_DIR/.relink-markers"
    date +%Y%m%d%H%M%S > "$CLAUDE_SHARED_DIR/.relink-markers/$1"
}

prepare() {
    output=$("$prepare_command" "$@" < /dev/null 2>&1)
    status=$?
}

start_fake_claude_process() {
    local config_dir=$1
    mkdir -p "$sandbox/proc"
    cp "$(command -v sleep)" "$sandbox/proc/claude"
    if [[ -n "$config_dir" ]]; then
        CLAUDE_CONFIG_DIR="$config_dir" "$sandbox/proc/claude" 30 &
    else
        env -u CLAUDE_CONFIG_DIR "$sandbox/proc/claude" 30 &
    fi
    fake_claude_pid=$!
}

stop_fake_claude_process() {
    kill "$fake_claude_pid" 2> /dev/null
    wait "$fake_claude_pid" 2> /dev/null
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
lacks() { [[ "$1" != *"$2"* ]] && echo ok || echo no; }
verdict() { [[ "$1" == "$2" ]] && echo ok || echo no; }

settings_value() { jq -c "$1" "$profile_dir/settings.json"; }

start_profile_with_base_settings() {
    mkdir -p "$profile_dir"
    cp "$CLAUDE_SHARED_DIR/settings.base.json" "$profile_dir/settings.json"
    chmod 600 "$profile_dir/settings.json"
}

change_profile_settings() {
    jq -c "$1" "$profile_dir/settings.json" > "$sandbox/changed.json"
    mv "$sandbox/changed.json" "$profile_dir/settings.json"
}

installed_plugins_of() {
    mkdir -p "$profile_dir/plugins"
    jq -n --args '{version: 2, plugins: ($ARGS.positional | map({key: ., value: [{scope: "user"}]}) | from_entries)}' "$@" > "$profile_dir/plugins/installed_plugins.json"
}


shouldLinkEverySharedItemAndCreateSharedTargetsWhenProfileIsNew() {
    setup_sandbox
    prepare --no-plugins work
    local item broken=0
    for item in projects history.jsonl CLAUDE.md skills agents commands file-history paste-cache; do
        [[ "$(readlink "$profile_dir/$item")" == "$CLAUDE_SHARED_DIR/$item" ]] || broken=$((broken + 1))
    done
    check "${FUNCNAME[0]}" "$(verdict "$broken" 0)"
    check "shouldCreateSharedDirectories" "$(holds test -d "$CLAUDE_SHARED_DIR/skills" -a -d "$CLAUDE_SHARED_DIR/projects")"
    check "shouldCreateSharedHistoryFile" "$(holds test -f "$CLAUDE_SHARED_DIR/history.jsonl")"
    check "shouldNotCreateDeployedInstructionsFile" "$(holds test ! -e "$CLAUDE_SHARED_DIR/CLAUDE.md")"
}

shouldReplaceEmptyRealEntriesWithLinks() {
    setup_sandbox
    mkdir -p "$profile_dir/skills"
    : > "$profile_dir/history.jsonl"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(readlink "$profile_dir/skills")" "$CLAUDE_SHARED_DIR/skills")"
    check "shouldReplaceEmptyFile" "$(verdict "$(readlink "$profile_dir/history.jsonl")" "$CLAUDE_SHARED_DIR/history.jsonl")"
}

shouldKeepRealEntryWithContentAndWarnWhenNotLinked() {
    setup_sandbox
    mkdir -p "$profile_dir/projects/repo"
    echo session > "$profile_dir/projects/repo/s.jsonl"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$(holds test -f "$profile_dir/projects/repo/s.jsonl" -a ! -L "$profile_dir/projects")"
    check "shouldNameEntryAndMigration" "$(contains "$output" "not linked: $profile_dir/projects")"
    check "shouldNameMigration" "$(contains "$output" "run the migration")"
    check "shouldStillLinkOtherItems" "$(holds test -L "$profile_dir/skills")"
}

shouldKeepWrongLinkAndWarn() {
    setup_sandbox
    mkdir -p "$sandbox/elsewhere" "$profile_dir"
    ln -s "$sandbox/elsewhere" "$profile_dir/skills"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(readlink "$profile_dir/skills")" "$sandbox/elsewhere")"
    check "shouldWarnAboutWrongLink" "$(contains "$output" "not linked: $profile_dir/skills")"
}

shouldLeaveCorrectLinksUntouchedAndStaySilent() {
    setup_sandbox
    start_profile_with_base_settings
    prepare --no-plugins work
    local before
    before=$(stat -c %i "$profile_dir/skills")
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && "$(stat -c %i "$profile_dir/skills")" == "$before" ]] && echo ok || echo no)"
}

shouldNeverTouchPerProfileFiles() {
    setup_sandbox
    mkdir -p "$profile_dir/plugins" "$profile_dir/sessions"
    echo secret-login > "$profile_dir/.credentials.json"
    echo state > "$profile_dir/.claude.json"
    echo plugin > "$profile_dir/plugins/keep"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$([[ "$(cat "$profile_dir/.credentials.json")" == secret-login && "$(cat "$profile_dir/.claude.json")" == state && -f "$profile_dir/plugins/keep" && -d "$profile_dir/sessions" ]] && echo ok || echo no)"
}

shouldSeedSettingsFromBaseWithPrivateModeWhenProfileHasNone() {
    setup_sandbox
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$(holds cmp "$CLAUDE_SHARED_DIR/settings.base.json" "$profile_dir/settings.json")"
    check "shouldUseMode600" "$(verdict "$(stat -c %a "$profile_dir/settings.json")" 600)"
}

shouldReportNothingWhenSettingsMatchBase() {
    setup_sandbox
    start_profile_with_base_settings
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" ]] && echo ok || echo no)"
}

shouldReportDeviatingKeyPathWithoutValueWhenScalarDiffers() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet-secret-name"'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" == *"settings.json /model"* ]] && echo ok || echo no)"
    check "shouldNeverPrintValues" "$(lacks "$output" "sonnet-secret-name")"
    check "shouldNotChangeSettingsInCheckMode" "$(verdict "$(settings_value .model)" '"sonnet-secret-name"')"
}

shouldReportNestedKeyPathWhenNestedScalarDiffers() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.voice.mode = "tap"'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "settings.json /voice/mode")"
    check "shouldNotReportEqualSibling" "$(lacks "$output" "/voice/enabled")"
}

shouldReportMissingBaseKeyPath() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings 'del(.attribution)'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" == *"settings.json /attribution/"* ]] && echo ok || echo no)"
}

shouldAcceptExtraAllowEntriesAndExtraKeys() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.permissions.allow += ["Bash(git:*)"] | .env = {"LAMINAR_CONVENTION_HINTS": "off"} | .effortLevel = "high"'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" ]] && echo ok || echo no)"
}

shouldReportAllowListWhenBaseEntryIsMissing() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.permissions.allow -= ["Read"]'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" == *"settings.json /permissions/allow"* ]] && echo ok || echo no)"
}

shouldReportHooksWhenTheyDiffer() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.hooks.PreToolUse[0].hooks[0].timeout = 99'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "settings.json /hooks/PreToolUse")"
}

shouldNotReportWhenOnlyKeyOrderDiffers() {
    setup_sandbox
    start_profile_with_base_settings
    jq -c 'to_entries | reverse | from_entries | .hooks.PreToolUse[0] |= (to_entries | reverse | from_entries)' "$CLAUDE_SHARED_DIR/settings.base.json" > "$profile_dir/settings.json"
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" ]] && echo ok || echo no)"
}

shouldSkipIgnoredKeyPathsAndTheirChildren() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet" | .voice.mode = "tap" | .effortLevel = "low"'
    printf '/model\n/voice\n' > "$profile_dir/shared-settings.ignore"
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" != *"model"* && "$output" != *"voice"* && "$output" == *"effortLevel"* ]] && echo ok || echo no)"
}

shouldFixOnlyDeviatingPathsAndKeepEverythingElse() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet" | .env = {"AWS_REGION": "eu-west-1"} | .permissions.allow = ["Bash(git:*)"] | .voice.mode = "tap"'
    chmod 644 "$profile_dir/settings.json"
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value '.model')" '"opus"')"
    check "shouldKeepExtraKeys" "$(verdict "$(settings_value '.env')" '{"AWS_REGION":"eu-west-1"}')"
    check "shouldKeepExtraAllowEntryAndAddBaseOnes" "$(verdict "$(settings_value '(.permissions.allow | index("Bash(git:*)") != null) and (.permissions.allow | index("Read") != null)')" true)"
    check "shouldFixNestedPathOnly" "$(verdict "$(settings_value '.voice')" '{"enabled":true,"mode":"hold"}')"
    check "shouldKeepMode600" "$(verdict "$(stat -c %a "$profile_dir/settings.json")" 600)"
    check "shouldReportFixedPaths" "$(contains "$output" "fixed settings.json: /model")"
    check "shouldExitZeroAfterFix" "$(verdict "$status" 0)"
    check "shouldLeaveNoTemporaryFile" "$(verdict "$(find "$profile_dir" -maxdepth 1 -name '.settings.json.*' | wc -l)" 0)"
}

shouldNotFixIgnoredKeyPath() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet" | .effortLevel = "low"'
    echo /model > "$profile_dir/shared-settings.ignore"
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$([[ "$(settings_value .model)" == '"sonnet"' && "$(settings_value .effortLevel)" == '"high"' ]] && echo ok || echo no)"
}

shouldReportMalformedSettingsAndNeverOverwriteThem() {
    setup_sandbox
    mkdir -p "$profile_dir"
    echo '{ not json' > "$profile_dir/settings.json"
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$([[ "$(cat "$profile_dir/settings.json")" == '{ not json' && "$output" == *malformed* && $status -eq 1 ]] && echo ok || echo no)"
}




shouldReportMissingPluginsFromBaseEnabledPlugins() {
    setup_sandbox
    start_profile_with_base_settings
    installed_plugins_of plugin-dev@claude-plugins-official
    prepare --check --verbose work
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" == *"missing plugin: laminar@laminar-skills"* && "$output" != *"missing plugin: plugin-dev"* ]] && echo ok || echo no)"
    check "shouldRunNoClaudeCommandInCheckMode" "$(holds test ! -e "$CLAUDE_CALL_LOG")"
}

shouldSkipPluginCheckWhenNoPluginsFlagGiven() {
    setup_sandbox
    start_profile_with_base_settings
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$status" 0)"
}

shouldInstallMissingPluginsAndMarketplacesIntoProfileDirectory() {
    setup_sandbox
    start_profile_with_base_settings
    mkdir -p "$profile_dir/plugins"
    echo '{"claude-plugins-official": {}}' > "$profile_dir/plugins/known_marketplaces.json"
    installed_plugins_of plugin-dev@claude-plugins-official
    prepare --fix work
    local calls
    calls=$(cat "$CLAUDE_CALL_LOG")
    check "${FUNCNAME[0]}" "$(contains "$calls" "$profile_dir|plugin install laminar@laminar-skills --scope user")"
    check "shouldInstallSecondMissingPlugin" "$(contains "$calls" "$profile_dir|plugin install skill-creator@claude-plugins-official --scope user")"
    check "shouldAddMissingMarketplace" "$(contains "$calls" "$profile_dir|plugin marketplace add clutcher/laminar-skills")"
    check "shouldNotAddKnownMarketplace" "$(lacks "$calls" "marketplace add anthropics/claude-plugins-official")"
    check "shouldNotReinstallPresentPlugin" "$(lacks "$calls" "install plugin-dev@")"
    check "shouldTargetOnlyProfileDirectory" "$([[ -z "$(cut -d'|' -f1 "$CLAUDE_CALL_LOG" | grep -vx "$profile_dir")" ]] && echo ok || echo no)"
}

shouldRunNoPluginCommandWhenAllPluginsInstalled() {
    setup_sandbox
    start_profile_with_base_settings
    installed_plugins_of plugin-dev@claude-plugins-official skill-creator@claude-plugins-official laminar@laminar-skills
    prepare --fix work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && ! -e "$CLAUDE_CALL_LOG" ]] && echo ok || echo no)"
}


shouldReportFailedPluginInstall() {
    setup_sandbox
    start_profile_with_base_settings
    export FAKE_CLAUDE_EXIT=1
    prepare --fix work
    local fix_status=$status
    check "${FUNCNAME[0]}" "$([[ "$output" == *"could not install plugin laminar@laminar-skills"* && $fix_status -eq 1 ]] && echo ok || echo no)"
}


shouldRejectInvalidAndReservedProfileNames() {
    setup_sandbox
    local rejected=0 name
    for name in "../x" "Upper" "a b" shared ""; do
        prepare "$name"
        [[ $status -eq 2 ]] && rejected=$((rejected + 1))
    done
    check "${FUNCNAME[0]}" "$([[ $rejected -eq 5 && ! -e "$HOME/.claude-shared/../x" && ! -e "$HOME/.claude-shared-profile" ]] && echo ok || echo no)"
}

shouldRejectUnknownOption() {
    setup_sandbox
    prepare --bogus work
    check "${FUNCNAME[0]}" "$(verdict "$status" 2)"
}

shouldDoNothingWhenProfileFolderDoesNotExist() {
    setup_sandbox
    rmdir "$profile_dir"
    rm -r "$CLAUDE_SHARED_DIR/.relink-markers"
    prepare work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && ! -e "$profile_dir" && ! -e "$CLAUDE_SHARED_DIR/.relink-markers" ]] && echo ok || echo no)"
    prepare --fix work
    check "shouldNotCreateFolderInFixMode" "$([[ $status -eq 0 && ! -e "$profile_dir" ]] && echo ok || echo no)"
}

shouldLeaveUnmarkedExistingProfileUntouchedByLaunchCheck() {
    setup_sandbox
    rm "$CLAUDE_SHARED_DIR/.relink-markers/work"
    mkdir -p "$profile_dir/projects/repo"
    echo session > "$profile_dir/projects/repo/s.jsonl"
    cp "$CLAUDE_SHARED_DIR/settings.base.json" "$profile_dir/settings.json"
    prepare --check --no-plugins work
    local entries
    entries=$(cd "$profile_dir" && find . | sort | tr '\n' ' ')
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && "$entries" == ". ./projects ./projects/repo ./projects/repo/s.jsonl ./settings.json " && ! -e "$CLAUDE_SHARED_DIR/projects" ]] && echo ok || echo no)"
}

shouldNeverCreateLinksOrMarkerOrSharedTargetsForUnmarkedProfileInFixMode() {
    setup_sandbox
    rm "$CLAUDE_SHARED_DIR/.relink-markers/work"
    cp "$CLAUDE_SHARED_DIR/settings.base.json" "$profile_dir/settings.json"
    change_profile_settings '.model = "sonnet"'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$([[ "$(settings_value .model)" == '"opus"' && -z "$(find "$profile_dir" -type l)" && ! -e "$CLAUDE_SHARED_DIR/.relink-markers/work" && ! -e "$CLAUDE_SHARED_DIR/skills" ]] && echo ok || echo no)"
}

shouldStillSeedAbsentSettingsForUnmarkedProfile() {
    setup_sandbox
    rm "$CLAUDE_SHARED_DIR/.relink-markers/work"
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$([[ -f "$profile_dir/settings.json" && -z "$(find "$profile_dir" -type l)" ]] && echo ok || echo no)"
}

shouldLinkMissingItemsOnlyAfterMarkerAppears() {
    setup_sandbox
    rm "$CLAUDE_SHARED_DIR/.relink-markers/work"
    prepare --check --no-plugins work
    local links_before
    links_before=$(find "$profile_dir" -type l | wc -l)
    mark_profile_for_linking work
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $links_before -eq 0 && -L "$profile_dir/file-history" ]] && echo ok || echo no)"
}

shouldDoNothingWhenMarkerExistsButProfileHasNoSharedMarkerFile() {
    setup_sandbox
    touch "$profile_dir/.no-shared"
    prepare --fix work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && -z "$(find "$profile_dir" -type l)" && ! -e "$profile_dir/settings.json" ]] && echo ok || echo no)"
}

shouldReplaceWholeMarketplaceSourceWhenSourceKindDiffers() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.extraKnownMarketplaces["laminar-skills"].source = {"source": "directory", "path": "/local/laminar"} | .extraKnownMarketplaces["mine"] = {"source": {"source": "directory", "path": "/mine"}}'
    prepare --check --verbose --no-plugins work
    local check_output=$output
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value '.extraKnownMarketplaces["laminar-skills"].source')" '{"source":"github","repo":"clutcher/laminar-skills"}')"
    check "shouldReportSourcePointerOnce" "$(verdict "$(grep -c 'settings.json /extraKnownMarketplaces/laminar-skills' <<< "$check_output")" 1)"
    check "shouldReportWholeSourceObject" "$(contains "$check_output" "settings.json /extraKnownMarketplaces/laminar-skills/source")"
    check "shouldKeepExtraMarketplace" "$(verdict "$(settings_value '.extraKnownMarketplaces.mine')" '{"source":{"source":"directory","path":"/mine"}}')"
}

shouldKeepLeafWiseMergeWhenMarketplaceSourceKindMatches() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.extraKnownMarketplaces["laminar-skills"].source = {"source": "github", "repo": "someone/fork", "ref": "main"}'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value '.extraKnownMarketplaces["laminar-skills"].source')" '{"source":"github","repo":"clutcher/laminar-skills","ref":"main"}')"
}

shouldDoNothingWhenSharedStoreDoesNotExist() {
    setup_sandbox
    rm -rf "$CLAUDE_SHARED_DIR"
    prepare work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && ! -e "$CLAUDE_SHARED_DIR" && -z "$(ls -A "$profile_dir")" ]] && echo ok || echo no)"
}

shouldSkipOnlySettingsAndPluginsWhenBaseIsMissing() {
    setup_sandbox
    rm "$CLAUDE_SHARED_DIR/settings.base.json"
    prepare work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -L "$profile_dir/skills" && ! -e "$profile_dir/settings.json" && "$output" == *"settings.base.json is missing"* && ! -e "$CLAUDE_CALL_LOG" ]] && echo ok || echo no)"
}

shouldDoNothingWhenProfileHasNoSharedMarker() {
    setup_sandbox
    mkdir -p "$profile_dir"
    touch "$profile_dir/.no-shared"
    echo '{"model":"sonnet"}' > "$profile_dir/settings.json"
    prepare --fix work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" && ! -L "$profile_dir/skills" && "$(cat "$profile_dir/settings.json")" == '{"model":"sonnet"}' && ! -e "$CLAUDE_CALL_LOG" ]] && echo ok || echo no)"
}

shouldKeepSharedHistoryContentWhenLinking() {
    setup_sandbox
    echo line > "$CLAUDE_SHARED_DIR/history.jsonl"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(cat "$CLAUDE_SHARED_DIR/history.jsonl")" line)"
}


shouldPrintOneSummaryLineWhenSettingsDeviate() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet" | .effortLevel = "low"'
    installed_plugins_of plugin-dev@claude-plugins-official skill-creator@claude-plugins-official
    prepare work
    check "${FUNCNAME[0]}" "$(verdict "$output" "settings deviate from base at 2 paths, missing plugins: 1; run claude-profile-prepare --fix work")"
    check "shouldNotAskOrInstallInDefaultMode" "$([[ $status -eq 1 && ! -e "$CLAUDE_CALL_LOG" && "$(settings_value .model)" == '"sonnet"' ]] && echo ok || echo no)"
}

shouldMentionNoPluginsInSummaryWhenPluginCheckIsOff() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet"'
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$output" "settings deviate from base at 1 paths; run claude-profile-prepare --fix work")"
}


shouldKeepExtraObjectKeysByteEqualWhenFixingNestedBaseKey() {
    setup_sandbox
    jq -c '. + {env: {FOO: "base"}}' "$CLAUDE_SHARED_DIR/settings.base.json" > "$sandbox/base.json"
    mv "$sandbox/base.json" "$CLAUDE_SHARED_DIR/settings.base.json"
    start_profile_with_base_settings
    change_profile_settings '.env = {"FOO": "stale", "ANTHROPIC_AUTH_TOKEN": "sk''-fake-token-1234567890", "NESTED": {"deep": [1, 2]}}'
    local extras_before
    extras_before=$(settings_value '.env | del(.FOO)')
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value .env.FOO)" '"base"')"
    check "shouldKeepFakeTokenAndNestedKeys" "$(verdict "$(settings_value '.env | del(.FOO)')" "$extras_before")"
    check "shouldNotPrintTokenInOutput" "$(lacks "$output" sk-fake-token)"
    check "shouldReportOnlyTheLeafPointer" "$(contains "$output" "fixed settings.json: /env/FOO")"
}

shouldAddMissingBaseKeyInsideExistingObjectWithoutTouchingSiblings() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.voice = {"extra": "kept"}'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value .voice)" '{"extra":"kept","enabled":true,"mode":"hold"}')"
}

shouldBuildObjectPathWhenProfileHasScalarWhereBaseHasObject() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.voice = "off"'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value .voice)" '{"enabled":true,"mode":"hold"}')"
}

shouldEscapeSlashAndTildeInPointers() {
    setup_sandbox
    jq -c '. + {"a/b": {"c~d": 1}}' "$CLAUDE_SHARED_DIR/settings.base.json" > "$sandbox/base.json"
    mv "$sandbox/base.json" "$CLAUDE_SHARED_DIR/settings.base.json"
    start_profile_with_base_settings
    jq -c 'del(."a/b")' "$profile_dir/settings.json" > "$sandbox/changed.json"
    mv "$sandbox/changed.json" "$profile_dir/settings.json"
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "settings.json /a~1b/c~0d")"
}

shouldKeepPerProfileHookWhenBaseHookIsPresent() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.hooks.PreToolUse += [{"matcher": "Edit", "hooks": []}]'
    prepare --check --verbose --no-plugins work
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && -z "$output" ]] && echo ok || echo no)"
}

shouldAppendBaseHookWhenProfileLacksIt() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.hooks.PreToolUse = [{"matcher": "Edit", "hooks": []}]'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value '.hooks.PreToolUse | length')" 2)"
    check "shouldKeepProfileHook" "$(verdict "$(settings_value '.hooks.PreToolUse[0].matcher')" '"Edit"')"
}

shouldRemoveValuesDroppedFromBaseWhenProfileStillHoldsTheOldOnes() {
    setup_sandbox
    start_profile_with_base_settings
    mkdir -p "$CLAUDE_SHARED_DIR/.deployed"
    jq -c '.permissions.allow += ["Bash(old:*)", "Bash(kept:*)"] | .legacyFlag = true | .legacyChoice = "old"' "$CLAUDE_SHARED_DIR/settings.base.json" > "$CLAUDE_SHARED_DIR/.deployed/settings.base.json"
    change_profile_settings '.permissions.allow += ["Bash(old:*)", "Bash(mine:*)"] | .legacyFlag = true | .legacyChoice = "changed-by-user"'
    prepare --check --verbose --no-plugins work
    local check_output=$output
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value '.permissions.allow | index("Bash(old:*)")')" null)"
    check "shouldKeepProfileOwnEntry" "$(verdict "$(settings_value '.permissions.allow | index("Bash(mine:*)") != null')" true)"
    check "shouldRemoveDroppedKeyWithOldValue" "$(verdict "$(settings_value 'has("legacyFlag")')" false)"
    check "shouldKeepDroppedKeyThatUserChanged" "$(verdict "$(settings_value .legacyChoice)" '"changed-by-user"')"
    check "shouldReportRemovedFromBase" "$(contains "$output" "removed from base: settings.json /legacyFlag")"
    check "shouldListRemovalsInCheckMode" "$(contains "$check_output" "removed from base: settings.json /legacyFlag")"
}

shouldRemoveNothingWhenNoPreviousBaseExists() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.legacyFlag = true'
    prepare --fix --no-plugins work
    check "${FUNCNAME[0]}" "$(verdict "$(settings_value .legacyFlag)" true)"
}

shouldNoteRemoteSettingsOverridesAsKeyPathsOnly() {
    setup_sandbox
    start_profile_with_base_settings
    echo '{"model": "secret-model-name", "voice": {"mode": "tap"}}' > "$profile_dir/remote-settings.json"
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "overridden by remote-settings: /model, /voice/mode")"
    check "shouldNeverPrintRemoteValues" "$(lacks "$output" secret-model-name)"
}

shouldWarnWhenRemoteSettingsAllowOnlyManagedHooks() {
    setup_sandbox
    start_profile_with_base_settings
    echo '{"allowManagedHooksOnly": true}' > "$profile_dir/remote-settings.json"
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "allowManagedHooksOnly")"
}

shouldRefuseFixWhileClaudeRunsInSameProfile() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet"'
    start_fake_claude_process "$profile_dir"
    prepare --fix work
    stop_fake_claude_process
    check "${FUNCNAME[0]}" "$([[ $status -eq 1 && "$output" == *"fix skipped: a claude process of profile work is running"* && "$(settings_value .model)" == '"sonnet"' && ! -e "$CLAUDE_CALL_LOG" ]] && echo ok || echo no)"
}

shouldFixWhileClaudeRunsInAnotherProfile() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet"'
    start_fake_claude_process "$HOME/.claude-sample"
    prepare --fix --no-plugins work
    stop_fake_claude_process
    check "${FUNCNAME[0]}" "$([[ $status -eq 0 && "$(settings_value .model)" == '"opus"' ]] && echo ok || echo no)"
}

shouldTreatClaudeWithoutConfigDirAsPersonalProfile() {
    setup_sandbox
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet"'
    profile_dir="$HOME/.claude-personal"
    start_profile_with_base_settings
    change_profile_settings '.model = "sonnet"'
    start_fake_claude_process ""
    prepare --fix --no-plugins personal
    local personal_output=$output personal_status=$status
    prepare --fix --no-plugins work
    stop_fake_claude_process
    check "${FUNCNAME[0]}" "$([[ $personal_status -eq 1 && "$personal_output" == *"fix skipped"* && "$output" == "fixed settings.json: /model" ]] && echo ok || echo no)"
}

shouldNeverSeedOverMalformedSettings() {
    setup_sandbox
    mkdir -p "$profile_dir"
    printf '{"model": ' > "$profile_dir/settings.json"
    prepare --no-plugins work
    check "${FUNCNAME[0]}" "$([[ "$(cat "$profile_dir/settings.json")" == '{"model": ' && "$output" == *malformed* ]] && echo ok || echo no)"
}

shouldSeedOnceWhenLaunchesRunSimultaneously() {
    setup_sandbox
    mkdir -p "$profile_dir"
    local run
    for run in 1 2 3 4 5 6; do
        "$prepare_command" --check --no-plugins work > "$sandbox/run-$run.log" 2>&1 < /dev/null &
    done
    wait
    local seeded
    seeded=$(cat "$sandbox"/run-*.log | grep -c "^seeded settings.json")
    check "${FUNCNAME[0]}" "$([[ $seeded -eq 1 ]] && cmp -s "$CLAUDE_SHARED_DIR/settings.base.json" "$profile_dir/settings.json" && [[ -z "$(find "$profile_dir" -maxdepth 1 -name '.settings.json.*')" ]] && echo ok || echo no)"
}

shouldAcceptLinkCreatedByCompetingLaunch() {
    setup_sandbox
    printf '#!/bin/bash\n/usr/bin/ln "$@"\nexit 1\n' > "$sandbox/bin/ln"
    chmod +x "$sandbox/bin/ln"
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$(lacks "$output" "not linked")"
}

shouldWarnWhenLinkCannotBeCreatedAndNothingExists() {
    setup_sandbox
    printf '#!/bin/bash\nexit 1\n' > "$sandbox/bin/ln"
    chmod +x "$sandbox/bin/ln"
    prepare --check --no-plugins work
    check "${FUNCNAME[0]}" "$(contains "$output" "not linked: $profile_dir/projects could not be linked")"
}

shouldLinkEverySharedItemAndCreateSharedTargetsWhenProfileIsNew
shouldReplaceEmptyRealEntriesWithLinks
shouldKeepRealEntryWithContentAndWarnWhenNotLinked
shouldKeepWrongLinkAndWarn
shouldLeaveCorrectLinksUntouchedAndStaySilent
shouldNeverTouchPerProfileFiles
shouldSeedSettingsFromBaseWithPrivateModeWhenProfileHasNone
shouldReportNothingWhenSettingsMatchBase
shouldReportDeviatingKeyPathWithoutValueWhenScalarDiffers
shouldReportNestedKeyPathWhenNestedScalarDiffers
shouldReportMissingBaseKeyPath
shouldAcceptExtraAllowEntriesAndExtraKeys
shouldReportAllowListWhenBaseEntryIsMissing
shouldReportHooksWhenTheyDiffer
shouldNotReportWhenOnlyKeyOrderDiffers
shouldSkipIgnoredKeyPathsAndTheirChildren
shouldFixOnlyDeviatingPathsAndKeepEverythingElse
shouldNotFixIgnoredKeyPath
shouldReportMalformedSettingsAndNeverOverwriteThem
shouldReportMissingPluginsFromBaseEnabledPlugins
shouldSkipPluginCheckWhenNoPluginsFlagGiven
shouldInstallMissingPluginsAndMarketplacesIntoProfileDirectory
shouldRunNoPluginCommandWhenAllPluginsInstalled
shouldReportFailedPluginInstall
shouldRejectInvalidAndReservedProfileNames
shouldRejectUnknownOption
shouldDoNothingWhenSharedStoreDoesNotExist
shouldSkipOnlySettingsAndPluginsWhenBaseIsMissing
shouldDoNothingWhenProfileHasNoSharedMarker
shouldKeepSharedHistoryContentWhenLinking

shouldPrintOneSummaryLineWhenSettingsDeviate
shouldMentionNoPluginsInSummaryWhenPluginCheckIsOff
shouldKeepExtraObjectKeysByteEqualWhenFixingNestedBaseKey
shouldAddMissingBaseKeyInsideExistingObjectWithoutTouchingSiblings
shouldBuildObjectPathWhenProfileHasScalarWhereBaseHasObject
shouldEscapeSlashAndTildeInPointers
shouldKeepPerProfileHookWhenBaseHookIsPresent
shouldAppendBaseHookWhenProfileLacksIt
shouldRemoveValuesDroppedFromBaseWhenProfileStillHoldsTheOldOnes
shouldRemoveNothingWhenNoPreviousBaseExists
shouldNoteRemoteSettingsOverridesAsKeyPathsOnly
shouldWarnWhenRemoteSettingsAllowOnlyManagedHooks
shouldRefuseFixWhileClaudeRunsInSameProfile
shouldFixWhileClaudeRunsInAnotherProfile
shouldTreatClaudeWithoutConfigDirAsPersonalProfile
shouldNeverSeedOverMalformedSettings
shouldSeedOnceWhenLaunchesRunSimultaneously
shouldAcceptLinkCreatedByCompetingLaunch
shouldWarnWhenLinkCannotBeCreatedAndNothingExists

shouldDoNothingWhenProfileFolderDoesNotExist
shouldLeaveUnmarkedExistingProfileUntouchedByLaunchCheck
shouldNeverCreateLinksOrMarkerOrSharedTargetsForUnmarkedProfileInFixMode
shouldStillSeedAbsentSettingsForUnmarkedProfile
shouldLinkMissingItemsOnlyAfterMarkerAppears
shouldDoNothingWhenMarkerExistsButProfileHasNoSharedMarkerFile

shouldReplaceWholeMarketplaceSourceWhenSourceKindDiffers
shouldKeepLeafWiseMergeWhenMarketplaceSourceKindMatches

exit "$failures"
