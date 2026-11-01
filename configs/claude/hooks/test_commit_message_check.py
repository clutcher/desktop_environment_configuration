import importlib.util
import json
import os
import subprocess
import sys
import threading
import time
from pathlib import Path

import pytest

HOOK_PATH = Path(__file__).parent / "commit-message-check.py"
specification = importlib.util.spec_from_file_location("commit_message_check", HOOK_PATH)
commit_message_check = importlib.util.module_from_spec(specification)
specification.loader.exec_module(commit_message_check)

TITLE = "fix(parser): reject empty input"
BODY = "The upstream tokenizer returns an empty list instead of failing, so callers crash later."
MINUTES = 60


@pytest.fixture
def repository(tmp_path):
    folder = tmp_path / "repository"
    (folder / "service").mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(folder)], check=True)
    return folder


@pytest.fixture
def runtime_folder(tmp_path):
    folder = tmp_path / "runtime"
    folder.mkdir()
    return folder


def run_review(command, working_folder, runtime_folder, clock=time.time):
    hook_input = {"tool_input": {"command": command}, "cwd": str(working_folder)}
    environment = {"XDG_RUNTIME_DIR": str(runtime_folder)} if runtime_folder else {}
    return commit_message_check.review(hook_input, environment, clock)


def heredoc_commit(message):
    return f"git commit -m \"$(cat <<'EOF'\n{message}\nEOF\n)\""


def test_shouldAllowWhenCommandIsNotACommit(repository, runtime_folder):
    assert run_review("git status && ls -la", repository, runtime_folder) is None
    assert run_review("echo 'git commit -m bad title'", repository, runtime_folder) is None


def test_shouldAllowWhenMessageIsOnlyATitle(repository, runtime_folder):
    assert run_review(f'git commit -m "{TITLE}"', repository, runtime_folder) is None
    assert run_review(f'git commit -m "{TITLE}"', repository, runtime_folder) is None


def test_shouldDenyWhenTitleIsNotConventional(repository, runtime_folder):
    reason = run_review('git commit -m "Updated the parser."', repository, runtime_folder)

    assert "not a Conventional Commits title" in reason


def test_shouldDenyWhenTitleIsLongerThanLimit(repository, runtime_folder):
    long_title = "feat: " + "x" * 100

    reason = run_review(f'git commit -m "{long_title}"', repository, runtime_folder)

    assert "characters long" in reason


def test_shouldDenyWhenBodyIsLongerThanLimit(repository, runtime_folder):
    long_body = "y" * 501

    reason = run_review(f'git commit -m "{TITLE}" -m "{long_body}"', repository, runtime_folder)

    assert "The body is 501 characters long" in reason


@pytest.mark.parametrize("trailer", [
    "Co-Authored-By: Someone <someone@example.com>",
    "Claude-Session: abc123",
    "Generated with Claude Code",
    "https://claude.ai/code/session_1",
])
def test_shouldDenyWhenMessageCarriesAttribution(repository, runtime_folder, trailer):
    reason = run_review(heredoc_commit(f"{TITLE}\n\n{trailer}"), repository, runtime_folder)

    assert "attribution trailer" in reason


def test_shouldDenyWhenTrailerOptionCarriesAttribution(repository, runtime_folder):
    command = f'git commit -m "{TITLE}" --trailer "Co-Authored-By: Someone <s@example.com>"'

    assert "attribution trailer" in run_review(command, repository, runtime_folder)


def test_shouldBlockFirstAttemptWhenMessageHasBodyViaMultipleMessageOptions(repository, runtime_folder):
    command = f'git commit -m "{TITLE}" -m "{BODY}"'

    first_attempt = run_review(command, repository, runtime_folder)
    retry = run_review(command, repository, runtime_folder)

    assert "WHY" in first_attempt
    assert "title alone" in first_attempt
    assert retry is None


def test_shouldBlockFirstAttemptWhenMessageHasBodyViaHeredoc(repository, runtime_folder):
    command = heredoc_commit(f"{TITLE}\n\n{BODY}")

    first_attempt = run_review(command, repository, runtime_folder)
    retry = run_review(command, repository, runtime_folder)

    assert "WHY" in first_attempt
    assert retry is None


def test_shouldBlockAgainWhenRetryMessageDiffers(repository, runtime_folder):
    run_review(f'git commit -m "{TITLE}" -m "{BODY}"', repository, runtime_folder)

    reworded = run_review(f'git commit -m "{TITLE}" -m "{BODY} Reworded."', repository, runtime_folder)

    assert "WHY" in reworded


def test_shouldBlockAgainWhenSameMessageIsCommittedInAnotherRepository(repository, runtime_folder, tmp_path):
    other_repository = tmp_path / "other"
    other_repository.mkdir()
    subprocess.run(["git", "init", "-q", str(other_repository)], check=True)
    command = f'git commit -m "{TITLE}" -m "{BODY}"'
    run_review(command, repository, runtime_folder)

    assert "WHY" in run_review(command, other_repository, runtime_folder)


def test_shouldAllowRetryFromSubfolderOfSameRepository(repository, runtime_folder):
    command = f'git commit -m "{TITLE}" -m "{BODY}"'
    run_review(command, repository, runtime_folder)

    assert run_review(command, repository / "service", runtime_folder) is None


def test_shouldBlockBodyWhenCommitUsesGitFolderOption(repository, runtime_folder, tmp_path):
    command = f'git -C {repository} commit -m "{TITLE}" -m "{BODY}"'

    first_attempt = run_review(command, tmp_path, runtime_folder)
    retry = run_review(command, tmp_path, runtime_folder)

    assert "WHY" in first_attempt
    assert retry is None


def test_shouldBlockBodyWhenCommitFollowsChangeDirectory(repository, runtime_folder, tmp_path):
    command = f'cd {repository}/service && git commit -m "{TITLE}" -m "{BODY}"'

    first_attempt = run_review(command, tmp_path, runtime_folder)
    retry = run_review(command, tmp_path, runtime_folder)

    assert "WHY" in first_attempt
    assert retry is None


def test_shouldCheckFormatWhenCommitFollowsChangeDirectory(repository, runtime_folder):
    reason = run_review('cd service && git commit -m "oops."', repository, runtime_folder)

    assert "not a Conventional Commits title" in reason


def test_shouldCheckFormatWhenCommitUsesGitFolderOption(repository, runtime_folder):
    reason = run_review('git -C service commit -m "oops."', repository, runtime_folder)

    assert "not a Conventional Commits title" in reason


def test_shouldBlockAgainWhenEntryIsOlderThanThirtyMinutes(repository, runtime_folder):
    command = f'git commit -m "{TITLE}" -m "{BODY}"'
    run_review(command, repository, runtime_folder)
    thirty_one_minutes_later = lambda: time.time() + 31 * MINUTES

    after_expiry = run_review(command, repository, runtime_folder, thirty_one_minutes_later)

    assert "WHY" in after_expiry


def test_shouldAllowRetryWhenEntryIsYoungerThanThirtyMinutes(repository, runtime_folder):
    command = f'git commit -m "{TITLE}" -m "{BODY}"'
    run_review(command, repository, runtime_folder)
    twenty_nine_minutes_later = lambda: time.time() + 29 * MINUTES

    assert run_review(command, repository, runtime_folder, twenty_nine_minutes_later) is None


def test_shouldRemoveExpiredEntriesWhenAnyBodyIsChecked(repository, runtime_folder):
    run_review(f'git commit -m "{TITLE}" -m "{BODY}"', repository, runtime_folder)
    state_folder = runtime_folder / "claude-commit-check"
    assert len(list(state_folder.iterdir())) == 1
    thirty_one_minutes_later = lambda: time.time() + 31 * MINUTES

    run_review(f'git commit -m "{TITLE}" -m "Another reason."', repository, runtime_folder, thirty_one_minutes_later)

    assert len(list(state_folder.iterdir())) == 1


def test_shouldLetExactlyOneOfConcurrentAttemptsCreateTheEntry(runtime_folder):
    store = commit_message_check.RetryStore(str(runtime_folder / "claude-commit-check"), time.time)
    attempts = 16
    barrier = threading.Barrier(attempts)
    outcomes = []

    def claim():
        barrier.wait()
        outcomes.append(store.claim_first_attempt("same-key"))

    threads = [threading.Thread(target=claim) for _ in range(attempts)]
    [thread.start() for thread in threads]
    [thread.join() for thread in threads]

    assert outcomes.count(True) == 1


def test_shouldBlockBodyOnceWhenMessageFileIsReadable(repository, runtime_folder):
    (repository / "message.txt").write_text(f"{TITLE}\n\n{BODY}\n")

    first_attempt = run_review("git commit -F message.txt", repository, runtime_folder)
    retry = run_review("git commit -F message.txt", repository, runtime_folder)

    assert "WHY" in first_attempt
    assert retry is None


def test_shouldAllowWhenMessageFileCannotBeRead(repository, runtime_folder):
    assert run_review("git commit -F missing.txt", repository, runtime_folder) is None


def test_shouldDenyFormatWhenMessageFileHasBadTitle(repository, runtime_folder):
    (repository / "message.txt").write_text("bad title\n")

    assert "not a Conventional Commits title" in run_review("git commit -F message.txt", repository, runtime_folder)


def test_shouldAllowWhenAmendKeepsMessage(repository, runtime_folder):
    assert run_review("git commit --amend --no-edit", repository, runtime_folder) is None


def test_shouldAllowWhenEditorWritesMessage(repository, runtime_folder):
    assert run_review("git commit", repository, runtime_folder) is None


def test_shouldAllowWhenMessageUsesUnexpandedShellValue(repository, runtime_folder):
    assert run_review('git commit -m "$MESSAGE"', repository, runtime_folder) is None


def test_shouldAllowWhenHeredocIsNotCommandSubstitution(repository, runtime_folder):
    command = "cat <<'EOF' > notes.txt\nsome notes\nEOF\ngit commit"

    assert run_review(command, repository, runtime_folder) is None


def test_shouldReadMessageFromStdinHeredoc(repository, runtime_folder):
    command = f"git commit -F - <<'EOF'\n{TITLE}\n\n{BODY}\nEOF"

    first_attempt = run_review(command, repository, runtime_folder)

    assert "WHY" in first_attempt


def test_shouldSkipRubricButKeepFormatChecksWhenRuntimeFolderIsUnset(repository):
    with_body = f'git commit -m "{TITLE}" -m "{BODY}"'

    assert run_review(with_body, repository, None) is None
    assert "not a Conventional Commits title" in run_review('git commit -m "bad."', repository, None)


def test_shouldSkipRubricWhenRuntimeFolderIsNotWritable(repository, tmp_path):
    not_a_folder = tmp_path / "file"
    not_a_folder.write_text("")

    assert run_review(f'git commit -m "{TITLE}" -m "{BODY}"', repository, not_a_folder) is None


def run_hook_process(command, working_folder, environment):
    hook_input = json.dumps({"tool_input": {"command": command}, "cwd": str(working_folder)})
    return subprocess.run(
        [sys.executable, str(HOOK_PATH)], input=hook_input, capture_output=True, text=True,
        env=environment, check=False,
    )


def test_shouldPrintDenyDecisionAndExitZeroWhenBodyIsBlocked(repository, runtime_folder):
    environment = {**os.environ, "XDG_RUNTIME_DIR": str(runtime_folder)}

    result = run_hook_process(f'git commit -m "{TITLE}" -m "{BODY}"', repository, environment)

    decision = json.loads(result.stdout)["hookSpecificOutput"]
    assert result.returncode == 0
    assert decision["hookEventName"] == "PreToolUse"
    assert decision["permissionDecision"] == "deny"
    assert decision["permissionDecisionReason"].startswith("Commit message rule: ")


def test_shouldPrintNothingAndExitZeroWhenRuntimeFolderIsUnsetInProcess(repository):
    environment = {name: value for name, value in os.environ.items() if name != "XDG_RUNTIME_DIR"}

    result = run_hook_process(f'git commit -m "{TITLE}" -m "{BODY}"', repository, environment)

    assert result.returncode == 0
    assert result.stdout == ""


def run_hook_with_raw_stdin(stdin_text, tmp_path):
    return subprocess.run(
        [sys.executable, str(HOOK_PATH)],
        input=stdin_text, capture_output=True, text=True,
        env={**os.environ, "XDG_RUNTIME_DIR": str(tmp_path)},
    )


def test_shouldExitSuccessfullyWithoutDecisionWhenStdinIsNotJson(tmp_path):
    result = run_hook_with_raw_stdin("not json", tmp_path)

    assert result.returncode == 0
    assert result.stdout == ""


def test_shouldExitSuccessfullyWithoutDecisionWhenReviewFailsUnexpectedly(tmp_path, monkeypatch):
    def fail(*_):
        raise RuntimeError("git exploded")

    monkeypatch.setattr(commit_message_check, "review", fail)
    monkeypatch.setattr(commit_message_check, "read_hook_input", lambda: {})

    commit_message_check.main()


def test_shouldPrintDenyDecisionAndExitSuccessfullyWhenTitleIsNotConventional(tmp_path):
    hook_input = {"tool_input": {"command": 'git commit -m "wip"'}, "cwd": str(tmp_path)}

    result = run_hook_with_raw_stdin(json.dumps(hook_input), tmp_path)

    assert result.returncode == 0
    assert json.loads(result.stdout)["hookSpecificOutput"]["permissionDecision"] == "deny"
