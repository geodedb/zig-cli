# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do not** open a public issue
2. Email security concerns to: <security@codepros.dev>
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We will acknowledge receipt within 48 hours and provide a detailed response within 7 days.

## Security Measures

This project implements the following security measures:

### CI/CD Security Scanning

- **SAST**: Static Application Security Testing via GitLab
- **Secret Detection**: Automated scanning for hardcoded secrets
- **License Scanning**: Compliance verification for dependencies
- **Gitleaks**: Enhanced secrets detection

### Code Security

- Memory-safe Zig implementation
- No external C dependencies (stdlib only)
- Compile-time safety checks enabled
- **Coverage-guided fuzz testing** via `zig build test --fuzz`
  - Integrated into CI on scheduled and manual pipelines
  - Crash artifacts are collected and triaged as security issues
  - Note: fuzz testing exercises Zig's built-in fuzzer on the test suite; dedicated fuzz harnesses for specific parser inputs are not yet implemented

### Release Security

- All releases are tagged and signed
- SPDX license identifiers in all source files
- Apache-2.0 license

## Command metadata trust model

Command and flag metadata (`name`, `summary`, `help`, `examples`, ...) is
normally authored by the application developer at compile time and is
treated as trusted for layout purposes. As defense in depth, all help,
table, progress, and error output strips terminal control bytes
(C0 controls except `\n`/`\t`, and DEL), so escape-sequence injection
(CWE-150) is neutralized even when metadata originates from untrusted
sources (plugin manifests, registries). Markdown, roff, JSON, and shell
completion generators apply context-specific escaping. If you render
untrusted strings through other output paths, sanitize them with
`util.text.stripControlChars`.

## Security Updates

Security updates will be released as patch versions. Subscribe to releases to be notified.
