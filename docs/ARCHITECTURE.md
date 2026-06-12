# Architecture

## Overview

zig-cli is organized into several modules, each handling a specific aspect of CLI development.
Source files are kept under an 800-line cap enforced by a pre-commit hook
(`scripts/check_file_size.sh`); larger concerns are split into subdirectory modules
re-exported from their parent file.

```text
src/
├── root.zig               # Public surface (re-exports everything below)
├── cli.zig                # CLI namespace (command/parser/help/completion)
│   └── cli/
│       ├── command.zig    # Command tree, hooks, flag groups, args validators
│       ├── context.zig    # Context, FlagSpec, FlagValue, StdioWriter, SecretPolicy
│       ├── parser.zig     # Argument parsing + run() lifecycle
│       │   └── parser/    # env.zig (env defaults), format.zig (error rendering)
│       ├── help.zig       # Help coordinator + templates
│       │   └── help/      # common.zig, text.zig, json.zig, man.zig, markdown.zig
│       └── completion/    # bash.zig, zsh.zig, fish.zig, powershell.zig
├── config.zig             # Configuration management (re-exports zig-config)
├── term.zig               # Terminal utilities (term/: tty, color, pager, progress, table, env)
├── util.zig               # General utilities (util/: errors, suggest, text, fs)
├── prompt.zig             # Interactive prompts (prompt/select.zig: select/multiSelect)
├── sanitize.zig           # Shared terminal-output sanitizer (named build module)
├── signal.zig             # Signal handling (flag-and-poll)
└── parallel.zig           # Optional spice-based parallelism
```

## Module Dependencies

```text
                    ┌─────────────┐
                    │   config    │ (external: zig-config)
                    │ yaml,toml,  │
                    │   json      │
                    └──────┬──────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
    ▼                      ▼                      ▼
┌───────┐            ┌───────────┐          ┌────────┐
│  cli  │◄───────────│  parser   │─────────►│  help  │
└───┬───┘            └───────────┘          └────────┘
    │                      │
    │                      ▼
    │               ┌─────────────┐
    │               │ completions │
    │               └─────────────┘
    │
    ▼
┌───────┐            ┌───────┐
│ term  │            │ util  │
└───────┘            └───────┘
```

## Core Components

### Command (`src/cli/command.zig`)

Defines the command structure:

```zig
pub const Command = struct {
    name: []const u8,
    summary: []const u8,
    long_help: []const u8 = "",
    examples: []const []const u8 = &.{},
    flags: []const FlagSpec = &.{},
    subcommands: []const *const Command = &.{},
    run: ?RunFn = null,
    pre_run: ?HookFn = null,
    post_run: ?HookFn = null,
    persistent_pre_run: ?HookFn = null,
    persistent_post_run: ?HookFn = null,
    aliases: []const []const u8 = &.{},
    hidden: bool = false,
    deprecated: ?[]const u8 = null,
    flag_groups: []const FlagGroup = &.{},
    args: ?ArgsValidator = null,
    group: []const u8 = "",
    version: []const u8 = "",
};
```

### Parser (`src/cli/parser.zig`, `src/cli/parser/`)

Handles argument parsing with support for:

- Short flags (`-v`)
- Long flags (`--verbose`)
- Flag values (`--config=file.toml` or `--config file.toml`)
- Positional arguments
- Subcommand dispatch
- `--` separator for raw arguments

`parse()` is decomposed into a phase pipeline (token handlers → finalize).
Two submodules carry the supporting concerns and are re-exported through
`parser.zig`: `parser/env.zig` (environment-variable flag defaults and env
parse-error tracking) and `parser/format.zig` (rendering `run()` parse
errors to stderr).

### Context (`src/cli/context.zig`)

Stores parsed values and provides typed access:

```zig
ctx.getBool("verbose")     // ?bool
ctx.getString("config")    // ?[]const u8
ctx.getInt("port")         // ?i64
ctx.getFloat("threshold")  // ?f64
```

Positional arguments are accessed via `ctx.positionals.items`.

`context.zig` is the canonical home of `Context`, `FlagSpec`, `FlagValue`,
`FlagType`, `SecretPolicy`, and `StdioWriter`; `command.zig` re-exports them
at their historical paths so the public API is unchanged.

### Help (`src/cli/help.zig`, `src/cli/help/`)

`help.zig` keeps the public entry points (`printHelp*`, `printVersion*`,
`HelpTemplate`, `HelpSection`) and delegates rendering to per-format
submodules: `help/text.zig` (plain/ANSI text), `help/json.zig`,
`help/man.zig` (roff), `help/markdown.zig`, with shared helpers in
`help/common.zig`. Each renderer owns its format-specific escaper by
design (the escapers are intentionally not unified -- see NS-060).

### Config (`src/config.zig`)

Re-exports the external `zig-config` library providing:

- Multi-format parsing (YAML, TOML, JSON)
- XDG Base Directory support
- Precedence chain: flags > env > project > user > system > defaults
- Provenance tracking (where each value came from)
- Secret handling (file/stdin only, not flags/env)

### Terminal (`src/term.zig`)

Terminal utilities:

- ANSI color codes with NO_COLOR support
- Terminal size detection
- Cursor manipulation
- ANSI sequence stripping

### Completions (`src/cli/completion/{bash,zsh,fish,powershell}.zig`)

Generates shell completions, exposed via `cli.generateCompletions`
(`src/cli.zig`), for:

- Bash
- Zsh
- Fish
- PowerShell

Each generator emits a different shell language and therefore keeps its own
tree walk and escaper; the shared sanitizer policy lives in `src/sanitize.zig`.

### Sanitize (`src/sanitize.zig`)

Single source of truth for terminal-output sanitization
(`writeControlFiltered`, `stripControlChars`, `utf8FloorIndex`). It is wired
in `build.zig` as a named module (`@import("sanitize")`) so `cli`, `term`,
`util`, and the test modules all share one implementation instead of the
three mirrored copies that predated it.

### Prompts (`src/prompt.zig`, `src/prompt/select.zig`)

Interactive prompts (input, password, confirm). The `select`/`multiSelect`
implementations live in `prompt/select.zig` and are re-exported from
`prompt.zig`, so the public API is unchanged.

## Configuration Precedence

Values are resolved in this order (lowest to highest priority):

1. **Default** - Hardcoded defaults in FlagSpec
2. **System** - `/etc/appname/config.toml`
3. **User** - `~/.config/appname/config.toml`
4. **Project** - `./.appname.toml` or `./appname.toml`
5. **Environment** - `APPNAME_FLAGNAME`
6. **Flags** - Command-line arguments

## Error Handling

The library uses Zig's error unions throughout:

```zig
pub const ParseError = error{
    UnknownFlag,
    MissingValue,
    InvalidValue,
    UnknownCommand,
    MissingRequired,
    // ...
};
```

Errors include context for helpful messages:

- Which flag/command caused the error
- Expected types/values

Typo-suggestion helpers (`util.suggestClosest`, Levenshtein distance, and the
sanitized `util.errors.formatUnknownCommand`) are provided for consumers to
build "did you mean" messages in their own error handling; the parser does
not auto-suggest.

## Thread Safety

### Concurrency Model

The CLI library is **single-threaded by design**. Command parsing, help
generation, and completion output all run on the calling thread. The only
concurrent contexts are signal handlers (which set atomic flags) and the
optional spice thread pool (for parallel batch operations).

### Module Thread-Safety Status

| Module | Thread-Safe | Notes |
|--------|-------------|-------|
| `command` | Partial | `Command` and `FlagSpec` are compile-time constants (safe). `Context` is NOT safe (stateful parsing). |
| `parser` | No | Stateful parsing; single-threaded only. |
| `help` | No | Writes to a single output stream. |
| `completion` | No | Generates output to a single stream. |
| `config` | No | Config loading is not synchronized. Use external locking if shared. |
| `signal` | **Yes** | Atomic flags with acquire/release ordering. Callback registration is mutex-protected. Callbacks run in normal context via `pollSignals()`. |
| `progress` | Partial | `ProgressBar` is thread-safe (atomic counter + render mutex). `Progress` (spinner) is NOT safe. |
| `pager` | No | Spawns and waits on a child process synchronously. |
| `prompt` | No | Reads stdin interactively; not shareable. |
| `parallel` | **Yes** | Spice thread pool manages all synchronization. Results written to caller-owned slices. |
| `util` | **Yes** | Pure functions with no shared state. |

### Signal Handling

Signal handlers use the **flag-and-poll pattern**: POSIX/Windows handlers
only set atomic flags. Cleanup callbacks run in normal execution context
via `pollSignals()`, which means callbacks can safely allocate, lock, and
perform I/O.

### Parallel Operations

The `parallel` module provides optional spice-based fork/join parallelism
(enabled with `-Dspice=true`, the default). When disabled, all operations
fall back to sequential execution transparently. See `src/parallel.zig`
for the API.

## Memory Management

- Uses Zig allocators throughout
- Context owns all parsed string values
- Call `context.deinit()` to free all resources
- Config values use arena allocation for efficient cleanup
