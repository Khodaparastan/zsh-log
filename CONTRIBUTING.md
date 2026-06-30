# Contributing to zlog

Thank you for taking the time to contribute! This document explains how to report bugs, propose features, and submit code changes.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Reporting Bugs](#reporting-bugs)
3. [Requesting Features](#requesting-features)
4. [Development Setup](#development-setup)
5. [Making Changes](#making-changes)
6. [Code Style](#code-style)
7. [Testing](#testing)
8. [Submitting a Pull Request](#submitting-a-pull-request)
9. [Commit Message Format](#commit-message-format)

---

## Code of Conduct

Be respectful and constructive. Harassment of any kind will not be tolerated.

---

## Reporting Bugs

Before opening an issue, please:

1. Search existing issues to avoid duplicates.
2. Reproduce the bug on the latest `main` branch.
3. Include the following in your report:
   - Zsh version (`zsh --version`)
   - OS and terminal emulator
   - Minimal reproduction script (the shorter the better)
   - Actual vs. expected output

---

## Requesting Features

Open a GitHub issue with the label `enhancement`. Describe:

- The problem you are trying to solve (not just the solution).
- How you would expect the API to look.
- Whether you are willing to implement it yourself.

---

## Development Setup

`zlog` has **no external dependencies** beyond a standard Zsh 5.8+ installation.

```zsh
# Clone the repo
git clone https://github.com/khodaparastan/zsh-log.git
cd zlog

# Verify Zsh version (5.8+ required)
zsh --version

# Source the library in a test shell
zsh -c 'source ./zlog; zlog::info "hello"'
```

Optional tools used in tests:

| Tool            | Purpose                                    |
|-----------------|--------------------------------------------|
| `zsh` 5.8+      | Required                                   |
| `date` / `stat` | Used internally; standard on all platforms |
| `mktemp`        | Used by test scripts                       |

---

## Making Changes

1. Fork the repository and create a branch from `main`:
   ```
   git checkout -b fix/rotation-lock-timeout
   ```

2. Make your changes in `zlog`. The file is organized into clearly labeled sections — find the right section before adding code.

3. Follow the [Code Style](#code-style) rules below.

4. Add or update tests in `tests/` (see [Testing](#testing)).

5. Update `CHANGELOG.md` under `[Unreleased]` with a brief description of your change.

6. If you changed the public API, update `docs/api.md` accordingly.

---

## Code Style

`zlog` has a strict internal style. Please match it exactly.

### General rules

- Every function starts with `emulate -L zsh` and `setopt localoptions`.
- Local variables are declared with `local` at the top of the function.
- Functions that return a single value set `REPLY=` instead of using a subshell.
- All internal functions are prefixed `__zlog::`. Public API functions are prefixed `zlog::`.
- No global side-effects outside of the `_zlog_*` namespaced variables.
- Error messages go to `>&2`.

### Naming

| Kind              | Convention                               | Example               |
|-------------------|------------------------------------------|-----------------------|
| Public function   | `zlog::<name>`                         | `zlog::info`        |
| Internal function | `__zlog::<name>`                       | `__zlog::engine`    |
| Global config     | `_zlog_config[<key>]`                    | `_zlog_config[level]` |
| Global state      | `_zlog_state[<key>]`                     | `_zlog_state[depth]`  |
| Constants         | `_ZLOG_<NAME>` (readonly integer/string) | `_ZLOG_LEVEL_ERROR`   |

### Comments

- Section headers use the `###...###` banner style already present in the file.
- Inline comments explain *why*, not *what*.
- Do not add comments that merely restate the code.

---

## Testing

Tests live in `tests/`. Run the unit and integration tests:

```zsh
zsh tests/test-zlog-unit.zsh
zsh tests/test-zlog-integration.zsh
```

Run benchmarks:

```zsh
zsh tests/benchmark-zlog.zsh
zsh tests/benchmark-zlog-detailed.zsh
```

### Writing tests

- Each test file sources `zlog` at the top.
- Use a temporary file for log output (`mktemp`) and clean it up in a trap.
- Assert both the return code and the log output content.
- Test edge cases: empty messages, invalid levels, very long strings, concurrent writes.

Example test skeleton:

```zsh
#!/usr/bin/env zsh
source "${0:A:h}/../zlog"

local tmplog=$(mktemp)
trap "rm -f $tmplog" EXIT

zlog::setup "$tmplog" info text

zlog::info "hello world"

if grep -q "hello world" "$tmplog"; then
  print "PASS: basic info log"
else
  print "FAIL: basic info log"
  exit 1
fi
```

---

## Submitting a Pull Request

1. Ensure all tests pass locally.
2. Keep the PR focused — one logical change per PR.
3. Fill in the PR template completely.
4. Reference any related issues with `Fixes #123` or `Closes #123`.
5. Be prepared to iterate based on review feedback.

---

## Commit Message Format

Use the [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <short summary>

[optional body]

[optional footer]
```

| Type       | When to use                                |
|------------|--------------------------------------------|
| `feat`     | New feature or public API addition         |
| `fix`      | Bug fix                                    |
| `perf`     | Performance improvement                    |
| `refactor` | Internal restructuring, no behavior change |
| `test`     | Adding or fixing tests                     |
| `docs`     | Documentation only                         |
| `chore`    | Build, CI, tooling changes                 |

**Examples:**

```
feat(rotation): add configurable lock timeout
fix(buffer): flush buffer before exit on SIGTERM
perf(engine): skip format call when no output targets active
docs(api): document zlog::rate_limit parameters
```
