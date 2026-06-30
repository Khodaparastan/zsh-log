# Security Policy

## Supported Versions

| Version         | Supported             |
|-----------------|-----------------------|
| `main` (latest) | ✅ Yes                 |
| Older tags      | ❌ No — please upgrade |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report security issues by emailing the maintainer directly. Include:

1. A description of the vulnerability and its potential impact.
2. A minimal reproduction script or proof-of-concept.
3. The Zsh version and OS where you reproduced it.

You will receive an acknowledgement within 48 hours and a resolution timeline within 7 days.

## Scope

`zlog` is a logging library. The primary security concerns are:

- **Log injection**: malicious content in log messages that could corrupt log files or mislead log parsers. All user-supplied strings are passed through `__z::json::escape` in JSON mode. Text mode does not sanitize newlines — callers should sanitize untrusted input before logging.
- **File permissions**: log files are created with the default `umask` of the calling process. If logging sensitive data, set a restrictive `umask` before calling `zlog::setup`.
- **Lock file races**: the rotation lock uses a best-effort file lock. It is not suitable as a security boundary — only as a coordination mechanism between cooperative processes owned by the same user.
- **Async FIFO**: the async logging FIFO is created in `$TMPDIR` with `mktemp`. It is readable only by the owning user.

## Out of Scope

- Vulnerabilities in Zsh itself.
- Issues that require the attacker to already have write access to the log file or the script being sourced.
