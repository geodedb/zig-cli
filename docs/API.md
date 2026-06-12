# API Reference

This document provides a comprehensive reference for the zig-cli library.

All symbols are reached through the root module (import name `zig_cli` in the
examples below; use whatever name you registered in your `build.zig`):

```zig
const zig_cli = @import("zig_cli");

const cli = zig_cli.cli;        // command parsing and execution
const config = zig_cli.config;  // configuration (re-exports zig-config)
const term = zig_cli.term;      // terminal utilities (color, progress, table, pager, tty)
const util = zig_cli.util;      // general utilities (errors, suggest, text, fs)
const signal = zig_cli.signal;  // signal handling
const prompt = zig_cli.prompt;  // interactive prompts
const parallel = zig_cli.parallel; // optional spice-based parallelism
```

The root module also re-exports the most common symbols directly:
`Command`, `Context`, `FlagSpec`, `FlagType`, `SecretPolicy`, `ParseError`,
`run`, `generateCompletions`, `generateMan`, `Loader`, `LoadOptions`,
`Source`, `load`, `Color`, `Progress`, `ProgressBar`, `suggestClosest`,
`ExitCode`, `Signal`, `installSignalHandlers`, `wasInterrupted`,
`shouldShutdown`, `onCleanup`, `PromptError`, `InputConfig`, `promptInput`,
`promptPassword`, `promptFreeSecret`, `promptConfirm`, `promptSelect`,
`promptMultiSelect`, and `version` (the library version, single-sourced from
`build.zig.zon`).

## Modules

- [cli](#cli-module) - Command parsing and execution
- [help](#help-module) - Help text generation and templates
- [completion](#completion-module) - Shell completion generation
- [config](#config-module) - Configuration management
- [term](#term-module) - Terminal utilities
- [progress](#progress-module) - Progress indicators (`term.Progress` / `term.ProgressBar`)
- [table](#table-module) - Table formatting (`term.Table`)
- [prompt](#prompt-module) - Interactive prompts
- [signal](#signal-module) - Signal handling
- [util](#util-module) - General utilities

---

## CLI Module

### Command

Defines a CLI command with flags, subcommands, and execution logic.

```zig
const cli = @import("zig_cli").cli;

const Command = struct {
    // Required
    name: []const u8,           // Command name
    summary: []const u8,        // One-line description

    // Help and documentation
    long_help: []const u8 = "",      // Extended help text
    examples: []const []const u8 = &.{},
    version: []const u8 = "",        // Version string
    author: []const u8 = "",         // Author for man page generation

    // Flags and subcommands
    flags: []const FlagSpec = &.{},
    subcommands: []const *const Command = &.{},
    flag_groups: []const FlagGroup = &.{},  // Flag group constraints

    // Execution hooks
    run: ?RunFn = null,                  // Main execution function
    pre_run: ?HookFn = null,             // Called before run
    post_run: ?HookFn = null,            // Called after run
    persistent_pre_run: ?HookFn = null,  // Runs before this and subcommands
    persistent_post_run: ?HookFn = null, // Runs after this and subcommands

    // Display options
    aliases: []const []const u8 = &.{},
    group: []const u8 = "",              // Group name for help organization
    hidden: bool = false,                // Hide from help
    deprecated: ?[]const u8 = null,      // Deprecation message

    // Positional arguments
    args: ?ArgsValidator = null,         // Positional argument config

    // Active help for completions
    active_help: []const []const u8 = &.{},
    active_help_fn: ?*const fn (*const Command, []const []const u8) []const []const u8 = null,
};
```

Hook and run function types:

```zig
const RunFn = *const fn (*Context) anyerror!void;
const HookFn = *const fn (*Context) anyerror!void;
```

### FlagSpec

Defines a command-line flag. `help` and `ftype` are required fields (no
defaults).

```zig
const FlagSpec = struct {
    name: []const u8,               // Long flag name (--name)
    short: ?u8 = null,              // Short flag (-n)
    help: []const u8,               // Help text (required)
    ftype: FlagType,                // Value type (required)
    required: bool = false,
    default_str: ?[]const u8 = null,
    env: ?[]const u8 = null,        // Environment variable name
    is_repeatable: bool = false,    // Can be specified multiple times
    is_deprecated: bool = false,
    secret: SecretPolicy = .none,   // Secret handling policy
    validator: ?*const fn ([]const u8) bool = null, // Custom validator
    completions: []const []const u8 = &.{}, // Static completion values
    complete_fn: ?*const fn ([]const u8) []const []const u8 = null, // Dynamic completions
};
```

### FlagGroup

Defines relationships between flags.

```zig
const FlagGroup = struct {
    group_type: FlagGroupType,          // Type of validation
    flags: []const []const u8,          // Flag names in this group
};

const FlagGroupType = enum {
    mutually_exclusive,  // Only one flag can be set
    required_together,   // If one is set, all must be set
    one_required,        // At least one must be set
};
```

### ArgsValidator

Validates positional arguments. Set as the `args` field on a `Command`.

```zig
const ArgsValidator = union(enum) {
    none: void,                 // No arguments allowed
    arbitrary: void,            // Any number of arguments
    exact: usize,               // Exactly N arguments
    minimum: usize,             // At least N arguments
    maximum: usize,             // At most N arguments
    range: struct { min: usize, max: usize }, // Between min and max
    only_valid: []const []const u8,  // Only values from this list
};
```

Note: `.only_valid` accepts empty positional args (it only rejects
individual values not in the list); combine with `.minimum` if at least
one argument is required.

### FlagType

```zig
const FlagType = enum {
    bool,           // Boolean flag (no value required)
    int,            // Integer value
    float,          // Floating-point value
    string,         // String value
    path,           // File path (enables file completion)
    string_array,   // Multiple string values
};
```

### Context

Execution context passed to command handlers. Defined in
`src/cli/context.zig` and re-exported as `cli.Context`.

```zig
const Context = struct {
    allocator: Allocator,
    stdout: StdioWriter,   // print/writeAll/writeByte wrapper over stdout
    stderr: StdioWriter,
    is_tty_out: bool,
    is_tty_err: bool,
    quiet: bool,      // -q/--quiet
    json: bool,       // --json
    plain: bool,      // --plain
    no_color: bool,   // --no-color
    dry_run: bool,    // -n/--dry-run
    no_input: bool,   // --no-input
    env_prefix: []const u8,                    // Env var prefix for flag defaults
    flags: std.StringHashMap(FlagValue),       // Parsed flag values
    positionals: std.ArrayList([]const u8),    // Positional arguments
    command_path: std.ArrayList([]const u8),   // e.g. ["kv", "get"]

    // Lifecycle
    fn init(allocator: Allocator) Context
    fn deinit(self: *Context) void

    // Methods
    fn getFlag(self, name) ?FlagValue
    fn getString(self, name) ?[]const u8
    fn getBool(self, name) bool          // absent collapses to false
    fn getBoolOpt(self, name) ?bool      // distinguishes absent from false
    fn getInt(self, name) ?i64
    fn getFloat(self, name) ?f64
    fn getStringArray(self, name) ?[]const []const u8
    fn print(self, fmt, args) !void      // Respects quiet mode
    fn err(self, fmt, args) !void        // Always writes to stderr
    fn useColor(self) bool               // Check if color should be used
};
```

### Parser

Parses command-line arguments.

```zig
var parser = cli.Parser.init(allocator, &root_cmd, "1.0.0", "PREFIX_");
var result = try parser.parse(argv); // argv: []const []const u8
// The allocator argument is accepted for backward compatibility but
// ignored; ParseResult stores its own allocator.
defer result.deinit(allocator);

if (result.help_requested) {
    cli.printHelp(result.command, &result.context);
}
```

`ParseResult` fields: `command: *const Command`, `context: Context`,
`help_requested: bool`, `version_requested: bool`, and the command chain
used for persistent hooks.

### Helper Functions

```zig
// Run a command with arguments (parse, env/defaults, validation, hooks, dispatch)
fn run(root: *const Command, argv: []const []const u8, allocator: Allocator) !u8

// Generate shell completions (Shell = enum { bash, zsh, fish, powershell })
fn generateCompletions(shell: Shell, cmd: *const Command, allocator: Allocator) ![]const u8

// Generate man page
fn generateMan(cmd: *const Command, allocator: Allocator) ![]const u8

// Generate Markdown documentation
fn generateMarkdown(cmd: *const Command, allocator: Allocator) ![]const u8

// Print help (write errors are swallowed for CLI robustness)
fn printHelp(cmd: *const Command, ctx: *Context) void

// Print help with custom template
fn printHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) void
```

---

## Help Module

Help text generation with customizable templates (`cli.help`).

### HelpTemplate

```zig
const help = @import("zig_cli").cli.help;

const HelpTemplate = struct {
    // Section order
    sections: []const HelpSection = &.{ .header, .usage, .examples, .description, .commands, .flags, .footer },

    // Section headers
    usage_header: []const u8 = "Usage",
    examples_header: []const u8 = "Examples",
    description_header: []const u8 = "",
    commands_header: []const u8 = "Commands",
    flags_header: []const u8 = "Flags",
    env_header: []const u8 = "Environment Variables",

    // Display options
    show_global_flags: bool = true,
    show_env_section: bool = false,
    show_standard_env_vars: bool = true,
    show_footer: bool = true,
    footer_text: ?[]const u8 = null,

    // Formatting
    indent: u8 = 2,
    name_column_width: u8 = 20,

    // Custom section renderer (optional); return true if the section was handled
    custom_renderer: ?*const fn (*const Command, *Context, HelpSection, *const HelpTemplate) bool = null,

    // Presets
    pub const default = HelpTemplate{};
    pub const minimal = HelpTemplate{ .sections = &.{ .usage, .flags }, ... };
    pub const verbose = HelpTemplate{ ... };
    pub const manpage = HelpTemplate{ ... };
};

const HelpSection = enum {
    header,      // Command name and summary
    usage,       // Usage line
    examples,    // Usage examples
    description, // Long description
    commands,    // Subcommands list
    flags,       // Flags list
    env_vars,    // Environment variables
    footer,      // Footer hints
};
```

### Functions

```zig
// Print help with default template (write errors silently ignored)
fn printHelp(cmd: *const Command, ctx: *Context) void

// Print help with custom template
fn printHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) void

// Error-propagating variants for callers that want to handle write errors
fn printHelpReturningError(cmd: *const Command, ctx: *Context) !void
fn printHelpWithTemplateReturningError(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) !void

// Generate man page in roff format
fn generateMan(cmd: *const Command, allocator: Allocator) ![]const u8

// Generate Markdown documentation
fn generateMarkdown(cmd: *const Command, allocator: Allocator) ![]const u8

// Print version information (and error-propagating variant)
fn printVersion(cmd: *const Command, ctx: *Context) void
fn printVersionReturningError(cmd: *const Command, ctx: *Context) !void
```

---

## Completion Module

Shell completion script generation. The convenience entry point lives on
the `cli` namespace:

```zig
const cli = @import("zig_cli").cli;

// Shell = enum { bash, zsh, fish, powershell }
const script = try cli.generateCompletions(.zsh, &root_cmd, allocator);
defer allocator.free(script);
```

The per-shell generators are also available directly as
`cli.completion.{bash,zsh,fish,powershell}`, each exposing:

```zig
fn generate(cmd: *const Command, allocator: Allocator) ![]const u8
```

### Active Help

Active help provides dynamic hints during shell completion:

```zig
const cmd = Command{
    .name = "deploy",
    .summary = "Deploy the app",
    // Static hints
    .active_help = &.{
        "Tip: Use --dry-run to preview changes",
    },
    // Dynamic hints based on context
    .active_help_fn = struct {
        fn getHints(c: *const Command, args: []const []const u8) []const []const u8 {
            _ = c;
            _ = args;
            return &.{}; // Return context-aware hints
        }
    }.getHints,
};
```

Users can disable active help with an environment variable derived from the
command name:

```bash
export MYAPP_ACTIVE_HELP=0
```

---

## Config Module

Re-exports the external `zig-config` library (`zig_cli.config`). The
authoritative reference for these symbols is the zig-config documentation;
the shim re-exports the following.

Sub-modules: `yaml`, `toml`, `json`, `loader`, `provenance`, `xdg`,
`dotenv`, `secret`, `validate`.

Common types and functions: `Loader`, `LoadError`, `LoadOptions`, `Format`,
`load`, `Source`, `TrackedValue`, `ProvenanceTracker`, `XdgPaths`,
`getPaths`, `getConfigDir`, `getDataDir`, `getCacheDir`, `SecretError`,
`readFromFile`, `readFromStdin`, `ValidationError`, `Value`, `ValueType`,
`MapEntry`, `parseContent`, `parseFile`.

### Parsing

```zig
// Parse from file (auto-detects format)
var value = try config.parseFile(allocator, "config.yaml");
defer value.deinit();

// Parse from content
var value = try config.parseContent(allocator, content, .yaml);
defer value.deinit();

// Access values
const host = value.getString("server.host") orelse "localhost";
const port = value.getInt("server.port") orelse 8080;
```

### Source Precedence

```text
flag > env > project > user > system > default
```

### XDG Directories

```zig
const config_dir = try config.getConfigDir("myapp", allocator);
const data_dir = try config.getDataDir("myapp", allocator);
const cache_dir = try config.getCacheDir("myapp", allocator);
```

### Secret Handling

Secrets are read from file or stdin only (never flags/env); see
`config.secret` (`readFromFile`, `readFromStdin`) and the `SecretPolicy`
flag policy in the CLI module.

---

## Term Module

Terminal utilities with TTY detection and NO_COLOR compliance
(`zig_cli.term`).

### Terminal Info

```zig
const info = term.getInfo();
// info.is_tty, info.width, info.height, info.term_type,
// info.color_supported, info.unicode_supported
// Always succeeds; falls back to 80x24 when stdout is not a TTY.
```

### Terminal Size

```zig
if (term.getTermSize()) |size| {
    // size.cols, size.rows
}
```

### TTY Detection

```zig
term.isStdoutTty()
term.isStderrTty()
term.isStdinTty()
```

### Color Context

```zig
// force_color: ?bool (null = auto-detect), no_color: bool
const color_ctx = term.ColorContext.init(null, false);
if (color_ctx.enabled) {
    // Use colors
}

// Writer-based helpers (output is control-byte sanitized):
try color_ctx.writeColored(writer, "text", .green);
try color_ctx.writeStyled(writer, "text", .bold);
```

### ANSI Stripping

```zig
const plain = try term.stripAnsi("\x1b[31mred\x1b[0m text", allocator);
// "red text"
```

---

## Progress Module

Progress indicators for long-running operations, in `zig_cli.term`
(`term.Progress`, `term.ProgressBar`; also re-exported from the root as
`Progress`/`ProgressBar`). Both are TTY-aware: when stdout is not a TTY
they produce no output.

### Spinner (`term.Progress`)

For operations with unknown duration:

```zig
const term = @import("zig_cli").term;

var spinner = term.Progress.start("Loading...");
defer spinner.stop();

// Or only when attached to a TTY:
var spinner2 = term.Progress.startIfTty(ctx.is_tty_out, "Loading...");

spinner.update("Processing...");  // Update message
spinner.tick();                   // Advance the spinner frame
spinner.stopWithMessage("Done!"); // Stop with a final message
```

Spinner styles (`spinner_style` field):

```zig
const SpinnerStyle = enum { dots, line, arrow, pulse };
```

### Progress Bar (`term.ProgressBar`)

For operations with known total. The bar width is derived from the
terminal width automatically; rendering is thread-safe.

```zig
var bar = term.ProgressBar.init(100, "Downloading");

bar.update(50);          // Set absolute progress (clamped to total)
bar.increment();         // Add 1 to current
const n = bar.getCurrent();
bar.finish();            // Complete and end the line
```

---

## Table Module

Structured table output, in `zig_cli.term` (`term.Table`).

### Creating Tables

```zig
const term = @import("zig_cli").term;

var t = term.Table.initWithConfig(ctx.allocator, .{
    .border = .unicode,  // .none, .ascii, .unicode, .markdown
    .padding = 1,
    .show_header = true,
    .header_separator = true,
    .use_color = false,
});
defer t.deinit();

try t.addColumn(.{ .header = "ID", .alignment = .right, .min_width = 4 });
try t.addColumn(.{ .header = "Name", .alignment = .left, .max_width = 20 });
try t.addColumn(.{ .header = "Status", .alignment = .center });
// Or: try t.addColumns(&.{ "ID", "Name", "Status" });

try t.addRow(&.{ "1", "Alice", "Active" });
try t.addRow(&.{ "2", "Bob", "Inactive" });

// Render to an allocated string...
const out = try t.render();
defer ctx.allocator.free(out);

// ...or directly to a writer
try t.renderTo(writer);
```

`Table.init(allocator)` creates a table with the default configuration.

### Column Options

```zig
const Column = struct {
    header: []const u8,
    min_width: usize = 0,        // 0 = auto
    max_width: usize = 0,        // 0 = unlimited; cells are truncated UTF-8-safely
    alignment: Alignment = .left,
};

const Alignment = enum { left, center, right };
```

### Border Styles

```text
.ascii          +----+---------+
                | ID | Name    |
                +----+---------+

.unicode        ┌────┬─────────┐
                │ ID │ Name    │
                ├────┼─────────┤

.markdown       | ID | Name    |
                | -- | ------- |

.none           ID  Name
```

---

## Util Module

General utilities (`zig_cli.util`).

### Exit Codes

```zig
const ExitCode = enum(u8) {
    success = 0,
    general_error = 1,
    usage_error = 2,
    io_error = 74,
    permission_denied = 77,
    config_error = 78,

    fn toInt(self: ExitCode) u8
};
```

### String Suggestions

```zig
const candidates = &[_][]const u8{ "start", "stop", "status" };
const suggestion = util.suggestClosest("strat", candidates, 2);
// suggestion == "start" (?[]const u8; null when nothing is close enough)

const d = util.levenshteinDistance("kitten", "sitting"); // 3
```

For building "did you mean" errors there is also
`util.errors.formatUnknownCommand(input, suggestion, allocator)`, which
returns a `FormattedError` with the echoed input sanitized of terminal
control bytes.

### Text Utilities

```zig
const truncated = try util.truncate("hello world", 8, allocator);
// "hello..." (UTF-8 codepoint-safe)

const padded = try util.padRight("hi", 10, allocator);
// "hi        "

// Also: util.padLeft, util.wordWrap, util.indent
```

### Filesystem

```zig
util.exists("/path/to/file")
util.isDirectory("/path")
util.isFile("/path/to/file")
util.fs.isSafePath("/home/user/file.txt")  // true
util.fs.isSafePath("/etc/shadow")          // false
```

Note: `isSafePath` is a best-effort denylist of obviously sensitive paths
(plus `..` traversal rejection), NOT a security boundary -- it does not
canonicalize or resolve symlinks. Callers needing a real guarantee must
canonicalize (e.g. `util.fs.absolutePath`) and validate against an
allowlisted root.

---

## Signal Module

Cross-platform signal handling for graceful shutdown (`zig_cli.signal`).
Handlers only set atomic flags; cleanup callbacks run in normal execution
context via `pollSignals()` (flag-and-poll pattern).

### Installation

```zig
const signal = @import("zig_cli").signal;

try signal.install(.{
    .handle_interrupt = true,   // SIGINT (default: true)
    .handle_terminate = true,   // SIGTERM (default: true)
    .handle_hangup = false,     // SIGHUP
    .handle_quit = false,       // SIGQUIT
});
defer signal.uninstall();
```

### Checking Status

```zig
if (signal.wasInterrupted()) {
    // Ctrl+C was pressed
}

if (signal.wasTerminated()) {
    // SIGTERM received
}

if (signal.shouldShutdown()) {
    // Either SIGINT or SIGTERM
}

// Run registered cleanup callbacks if a signal was received.
// Call periodically from your main loop.
_ = signal.pollSignals();
```

### Cleanup Callbacks

```zig
fn cleanup() void {
    // Cleanup resources (runs in normal context via pollSignals(),
    // so it may allocate, lock, and perform I/O)
}

try signal.onCleanup(&cleanup);
```

---

## Prompt Module

Interactive prompts for CLI input (`zig_cli.prompt`). All prompt functions
return `PromptError.NotInteractive` when stdin is not a TTY.

### Text Input

```zig
const prompt = @import("zig_cli").prompt;

const name = try prompt.input("Enter name", .{
    .default = "anonymous",
    .allow_empty = true,        // default: true
    .max_length = 100,          // default: 1024
    .validator = null,          // ?*const fn ([]const u8) bool
    .validation_error = "Invalid input",
}, allocator);
defer allocator.free(name);
```

### Password Input

```zig
const password = try prompt.password("Password: ", allocator);
defer prompt.freeSecret(allocator, password);
// Input is not echoed; freeSecret zeroes the buffer before freeing
```

### Confirmation

```zig
if (try prompt.confirm("Delete all files?", false)) {
    // User confirmed
}
```

### Select

```zig
const choice = try prompt.select("Choose option:", &.{
    "Option A",
    "Option B",
    "Option C",
});
// choice: usize (0, 1, or 2)
```

### Multi-Select

```zig
const choices = try prompt.multiSelect("Select features:", &.{
    "Feature A",
    "Feature B",
    "Feature C",
}, allocator);
defer allocator.free(choices);
// choices: []usize (selected indices)
```

---

## Error Types

### ParseError

```zig
const ParseError = error{
    UnknownFlag,
    UnknownCommand,
    MissingValue,
    InvalidValue,
    MissingRequired,
    SecretInFlagOrEnv,
    HelpRequested,
    VersionRequested,
    OutOfMemory,
    MutuallyExclusiveFlags,
    RequiredTogetherFlags,
    OneRequiredFlags,
    InvalidArgs,
};
```

### PromptError

```zig
const PromptError = error{
    Cancelled,
    NotInteractive,
    ReadError,
    InvalidInput,
    OutOfMemory,
};
```

### ArgsValidationError

Returned by `ArgsValidator.validate`; surfaced through `run()` as
`ParseError.InvalidArgs` with a descriptive message.

```zig
const ArgsValidationError = error{
    NoArgsExpected,
    ExactArgsMismatch,
    TooFewArgs,
    TooManyArgs,
    RangeArgsMismatch,
    InvalidArg,
};
```

`config.ValidationError` (from the external zig-config library) is separate
and applies to configuration validation.

---

## Flag Validators

Flag values are validated with a custom function on the `FlagSpec`. The
validator receives the raw string value and returns `true` when valid:

```zig
fn validateProjectName(value: []const u8) bool {
    if (value.len < 3) return false;
    if (!std.ascii.isAlphabetic(value[0])) return false;
    return true;
}

const cmd = Command{
    .name = "new",
    .summary = "Create a project",
    .flags = &.{
        .{
            .name = "name",
            .help = "Project name",
            .ftype = .string,
            .validator = &validateProjectName,
        },
    },
};
```

When a validator returns `false`, parsing fails with
`ParseError.InvalidValue`.

For configuration-value validation (URLs, emails, ports, ...), see the
external zig-config library's validation module, re-exported as
`config.validate`.
