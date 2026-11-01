#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
import time
from hashlib import sha256

CONVENTIONAL_TYPES = ("feat", "fix", "docs", "style", "refactor", "perf", "test", "build", "ci", "chore", "revert")
CONVENTIONAL_TITLE = re.compile(r"^(?P<type>[A-Za-z]+)(?P<scope>\([^()]*\))?(?P<breaking>!)?: (?P<description>.*)$")
MAXIMUM_TITLE_LENGTH = 100
MAXIMUM_BODY_LENGTH = 500
ATTRIBUTION_PATTERNS = (
    re.compile(r"co-authored-by\s*:", re.IGNORECASE),
    re.compile(r"claude-session\s*:", re.IGNORECASE),
    re.compile(r"generated\s+with\s+\[?claude\s+code", re.IGNORECASE),
    re.compile(r"claude\.ai/code", re.IGNORECASE),
)
SUBSTITUTED_HEREDOC = re.compile(r"\$\(\s*cat\s*<<-?\s*(['\"]?)(\w+)\1[ \t]*\n(.*?)\n[ \t]*\2[ \t]*\n?\s*\)", re.DOTALL)
STDIN_HEREDOC = re.compile(r"(?<!<)<<-?(?!<)[ \t]*(['\"]?)(\w+)\1([^\n]*)\n(.*?)\n[ \t]*\2[ \t]*(?=\n|$)", re.DOTALL)
PLACEHOLDER = re.compile(r"__COMMIT_HEREDOC_(\d+)__")
UNEXPANDED_SHELL_VALUE = re.compile(r"\$[A-Za-z_{(]|`")
COMMAND_SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
GIT_GLOBAL_OPTIONS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--config-env"}
COMMIT_LONG_OPTIONS_WITH_VALUE = {
    "--author", "--date", "--cleanup", "--template", "--trailer", "--pathspec-from-file",
    "--gpg-sign", "--untracked-files",
}
RETRY_STATE_FOLDER_NAME = "claude-commit-check"
RETRY_ENTRY_LIFETIME_SECONDS = 30 * 60
BODY_RUBRIC = (
    "This commit has a body. A body is worth keeping only when it tells a future reader WHY: a non-obvious root cause, "
    "a rejected alternative, an external constraint or a contract that forced the shape. It must not list what changed "
    "or narrate how the work went, and it must not state a why that is obvious from the title or the diff. "
    "Usually the title alone is right: drop the body and commit the title alone. "
    "If the body passes this test, run the identical commit again and it will be allowed."
)
MESSAGE_REUSE_OPTIONS = {"-C", "-c", "--reuse-message", "--reedit-message", "--fixup", "--squash", "--no-edit"}


class UndeterminedMessage(Exception):
    pass


class CommitInvocation:
    def __init__(self, working_folder):
        self.working_folder = working_folder
        self.message_paragraphs = []
        self.message_file = None
        self.trailer_values = []
        self.reuses_message = False
        self.stdin_body = None


def read_hook_input():
    return json.load(sys.stdin)


def replace_heredocs_with_placeholders(command):
    heredoc_bodies = []

    def keep_substituted_body(match):
        heredoc_bodies.append(match.group(3))
        return f"__COMMIT_HEREDOC_{len(heredoc_bodies) - 1}__"

    def keep_stdin_body(match):
        heredoc_bodies.append(match.group(4) + "\n")
        return f" __STDIN__ __COMMIT_HEREDOC_{len(heredoc_bodies) - 1}__ {match.group(3)}"

    command = SUBSTITUTED_HEREDOC.sub(keep_substituted_body, command)
    command = STDIN_HEREDOC.sub(keep_stdin_body, command)
    return command, heredoc_bodies


def replace_unquoted_newlines_with_separators(command):
    characters = []
    quote = None
    index = 0
    while index < len(command):
        character = command[index]
        if character == "\\" and quote != "'" and index + 1 < len(command):
            if command[index + 1] == "\n":
                index += 2
                continue
            characters.append(command[index:index + 2])
            index += 2
            continue
        if quote is None and character in "'\"":
            quote = character
        elif quote == character:
            quote = None
        if quote is None and character == "\n":
            characters.append(" ; ")
        else:
            characters.append(character)
        index += 1
    return "".join(characters)


def split_into_simple_commands(command):
    lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
    lexer.whitespace_split = True
    lexer.commenters = ""
    simple_commands = [[]]
    for token in lexer:
        if token in COMMAND_SEPARATORS:
            simple_commands.append([])
        else:
            simple_commands[-1].append(token)
    return [words for words in simple_commands if words]


def resolve_placeholders(value, heredoc_bodies):
    return PLACEHOLDER.sub(lambda match: heredoc_bodies[int(match.group(1))], value)


def literal_value(value, heredoc_bodies):
    if UNEXPANDED_SHELL_VALUE.search(PLACEHOLDER.sub("", value)):
        raise UndeterminedMessage()
    return resolve_placeholders(value, heredoc_bodies)


def commit_arguments_after_git(words):
    position = 1
    git_folder = None
    while position < len(words):
        word = words[position]
        if word in GIT_GLOBAL_OPTIONS_WITH_VALUE and position + 1 < len(words):
            if word == "-C":
                git_folder = words[position + 1]
            position += 2
        elif word.startswith("-"):
            position += 1
        else:
            break
    if position < len(words) and words[position] == "commit":
        return words[position + 1:], git_folder
    return None, git_folder


def read_short_option_cluster(cluster, following_words, invocation, heredoc_bodies):
    consumed_following = 0
    for offset, letter in enumerate(cluster[1:], start=1):
        attached_value = cluster[offset + 1:]
        if letter in "mFCc":
            if attached_value:
                value = attached_value
            elif following_words:
                value = following_words[0]
                consumed_following = 1
            else:
                raise UndeterminedMessage()
            if letter == "m":
                invocation.message_paragraphs.append(literal_value(value, heredoc_bodies))
            elif letter == "F":
                invocation.message_file = value
            else:
                invocation.reuses_message = True
            return consumed_following
        if letter in "Sut":
            if letter == "t" and not attached_value and following_words:
                consumed_following = 1
            return consumed_following
    return consumed_following


def read_long_option(word, following_words, invocation, heredoc_bodies):
    name, has_attached_value, attached_value = word.partition("=")
    if name in MESSAGE_REUSE_OPTIONS:
        invocation.reuses_message = True
    if name in ("--message", "--file", "--trailer", "--reuse-message", "--reedit-message", "--fixup", "--squash") or name in COMMIT_LONG_OPTIONS_WITH_VALUE:
        if name in ("--gpg-sign", "--untracked-files") and not has_attached_value:
            return 0
        if has_attached_value:
            value, consumed_following = attached_value, 0
        elif following_words:
            value, consumed_following = following_words[0], 1
        else:
            raise UndeterminedMessage()
        if name == "--message":
            invocation.message_paragraphs.append(literal_value(value, heredoc_bodies))
        elif name == "--file":
            invocation.message_file = value
        elif name == "--trailer":
            invocation.trailer_values.append(resolve_placeholders(value, heredoc_bodies))
        return consumed_following
    return 0


def read_commit_invocation(arguments, working_folder, stdin_body, heredoc_bodies):
    invocation = CommitInvocation(working_folder)
    invocation.stdin_body = stdin_body
    position = 0
    while position < len(arguments):
        word = arguments[position]
        following_words = arguments[position + 1:]
        if word == "--":
            break
        if word.startswith("--"):
            position += 1 + read_long_option(word, following_words, invocation, heredoc_bodies)
        elif word.startswith("-") and len(word) > 1:
            position += 1 + read_short_option_cluster(word, following_words, invocation, heredoc_bodies)
        else:
            position += 1
    return invocation


def stdin_body_of(words, heredoc_bodies):
    for index, word in enumerate(words):
        if word == "__STDIN__" and index + 1 < len(words):
            return resolve_placeholders(words[index + 1], heredoc_bodies)
        if word == "<<<" and index + 1 < len(words):
            return literal_value(words[index + 1], heredoc_bodies) + "\n"
    return None


def without_redirections(words):
    kept_words = []
    skip_next = False
    for index, word in enumerate(words):
        if skip_next:
            skip_next = False
            continue
        if word == "__STDIN__":
            skip_next = True
            continue
        if word in ("<<<", "<", ">", ">>", "2>", "2>>", "&>"):
            skip_next = True
            continue
        kept_words.append(word)
    return kept_words


def find_commit_invocations(command, session_folder):
    command, heredoc_bodies = replace_heredocs_with_placeholders(command)
    command = replace_unquoted_newlines_with_separators(command)
    working_folder = session_folder
    invocations = []
    for words in split_into_simple_commands(command):
        while words and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", words[0]):
            words = words[1:]
        if not words:
            continue
        if words[0] == "cd" and len(words) > 1:
            working_folder = os.path.join(working_folder, os.path.expanduser(words[1]))
            continue
        if words[0] != "git":
            continue
        stdin_body = stdin_body_of(words, heredoc_bodies)
        commit_arguments, git_folder = commit_arguments_after_git(without_redirections(words))
        if commit_arguments is None:
            continue
        folder = os.path.join(working_folder, git_folder) if git_folder else working_folder
        invocations.append(read_commit_invocation(commit_arguments, folder, stdin_body, heredoc_bodies))
    return invocations


def message_text_of(invocation):
    if invocation.message_paragraphs:
        return "\n\n".join(invocation.message_paragraphs)
    if invocation.message_file is not None:
        if invocation.message_file == "-":
            if invocation.stdin_body is None:
                raise UndeterminedMessage()
            return invocation.stdin_body
        path = os.path.join(invocation.working_folder, os.path.expanduser(invocation.message_file))
        try:
            with open(path, encoding="utf-8") as message_file:
                return message_file.read()
        except OSError:
            raise UndeterminedMessage()
    raise UndeterminedMessage()


def cleaned_like_git(message):
    lines = [line.rstrip() for line in message.split("\n")]
    cleaned_lines = []
    for line in lines:
        if line == "" and (not cleaned_lines or cleaned_lines[-1] == ""):
            continue
        cleaned_lines.append(line)
    while cleaned_lines and cleaned_lines[-1] == "":
        cleaned_lines.pop()
    return cleaned_lines


def title_problem(title):
    match = CONVENTIONAL_TITLE.match(title)
    if not match:
        return (
            f'The title "{title}" is not a Conventional Commits title. Write it as "<type>(<optional scope>)!: <description>", '
            f'for example "fix(parser): reject empty input" or "feat(#123): export the order list", with type one of {", ".join(CONVENTIONAL_TYPES)}.'
        )
    if match.group("type") not in CONVENTIONAL_TYPES:
        return (
            f'The type "{match.group("type")}" is not allowed. Use one of {", ".join(CONVENTIONAL_TYPES)}, in lower case, '
            f'for example "fix: {match.group("description")}".'
        )
    if match.group("scope") == "()":
        return 'The scope is empty. Remove the "()" or put a scope inside it, for example "fix(api): ...".'
    description = match.group("description")
    if not description.strip():
        return 'The description after "<type>: " is empty. Say what is now true, for example "fix: reject an empty order".'
    if description != description.strip():
        return 'The description has extra spaces. Write exactly one space after the colon and none at the end.'
    if description.endswith("."):
        return f'The title ends with a period. Remove it: "{title[:-1]}".'
    if len(title) > MAXIMUM_TITLE_LENGTH:
        return f"The title is {len(title)} characters long. Shorten it to {MAXIMUM_TITLE_LENGTH} characters or fewer and move the reason, if any, into the body."
    return None


def shape_problem(cleaned_lines):
    if len(cleaned_lines) == 1:
        return None
    if cleaned_lines[1] != "":
        return (
            "The title is followed directly by text on the next line. Put exactly one blank line between the title and the body, "
            "or make the message a single title line."
        )
    body = "\n".join(cleaned_lines[2:])
    if len(body) > MAXIMUM_BODY_LENGTH:
        return (
            f"The body is {len(body)} characters long; the limit is {MAXIMUM_BODY_LENGTH}. Keep only the reason a reader cannot get "
            "from the title or the diff: the root cause, the constraint or the rejected alternative. Drop any list of what changed."
        )
    return None


def attribution_problem(message, trailer_values):
    for text in [message, *trailer_values]:
        for pattern in ATTRIBUTION_PATTERNS:
            if pattern.search(text):
                return (
                    "The commit carries an attribution trailer or link. Remove every Co-Authored-By, Claude-Session, "
                    "Generated with Claude Code line and claude.ai/code link; the message holds only the title and the why."
                )
    return None


class RetryStore:
    def __init__(self, folder, clock):
        self.folder = folder
        self.clock = clock

    def claim_first_attempt(self, key):
        os.makedirs(self.folder, mode=0o700, exist_ok=True)
        self.remove_expired_entries()
        try:
            descriptor = os.open(os.path.join(self.folder, key), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError:
            return False
        os.close(descriptor)
        return True

    def remove_expired_entries(self):
        for entry_name in os.listdir(self.folder):
            entry_path = os.path.join(self.folder, entry_name)
            try:
                age_seconds = self.clock() - os.stat(entry_path).st_mtime
                if age_seconds > RETRY_ENTRY_LIFETIME_SECONDS:
                    os.remove(entry_path)
            except FileNotFoundError:
                continue


def cleaned_message_lines_of(invocation):
    if invocation.reuses_message and not invocation.message_paragraphs and invocation.message_file is None:
        return None
    try:
        message = message_text_of(invocation)
    except UndeterminedMessage:
        return None
    return cleaned_like_git(message) or None


def format_problem_of(invocation, cleaned_lines):
    return (
        attribution_problem("\n".join(cleaned_lines), invocation.trailer_values)
        or title_problem(cleaned_lines[0])
        or shape_problem(cleaned_lines)
    )


def repository_toplevel_of(working_folder):
    result = subprocess.run(
        ["git", "-C", working_folder, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        return os.path.normpath(working_folder)
    return result.stdout.strip()


def retry_key_of(invocation, cleaned_lines):
    identity = repository_toplevel_of(invocation.working_folder) + "\0" + "\n".join(cleaned_lines)
    return sha256(identity.encode("utf-8")).hexdigest()


def body_rubric_problem(invocation, cleaned_lines, retry_store):
    if len(cleaned_lines) == 1 or retry_store is None:
        return None
    try:
        first_attempt = retry_store.claim_first_attempt(retry_key_of(invocation, cleaned_lines))
    except OSError:
        return None
    return BODY_RUBRIC if first_attempt else None


def retry_store_from(environment, clock):
    runtime_folder = environment.get("XDG_RUNTIME_DIR")
    if not runtime_folder:
        return None
    return RetryStore(os.path.join(runtime_folder, RETRY_STATE_FOLDER_NAME), clock)


def review(hook_input, environment, clock=time.time):
    command = (hook_input.get("tool_input") or {}).get("command") or ""
    session_folder = hook_input.get("cwd") or os.getcwd()
    try:
        invocations = find_commit_invocations(command, session_folder)
    except (ValueError, UndeterminedMessage):
        return None
    messages = [(invocation, cleaned_message_lines_of(invocation)) for invocation in invocations]
    messages = [(invocation, lines) for invocation, lines in messages if lines]
    for invocation, cleaned_lines in messages:
        problem = format_problem_of(invocation, cleaned_lines)
        if problem:
            return problem
    retry_store = retry_store_from(environment, clock)
    for invocation, cleaned_lines in messages:
        problem = body_rubric_problem(invocation, cleaned_lines, retry_store)
        if problem:
            return problem
    return None


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Commit message rule: " + reason,
        }
    }))


def main():
    try:
        reason = review(read_hook_input(), os.environ)
    except Exception:
        return
    if reason:
        deny(reason)


if __name__ == "__main__":
    main()
