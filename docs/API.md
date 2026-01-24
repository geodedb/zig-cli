# API Reference

This document provides a comprehensive reference for the zig-cli library.

## Modules

- [cli](#cli-module) - Command parsing and execution
- [help](#help-module) - Help text generation and templates
- [completion](#completion-module) - Shell completion generation
- [config](#config-module) - Configuration management
- [term](#term-module) - Terminal utilities
- [progress](#progress-module) - Progress indicators
- [table](#table-module) - Table formatting
- [prompt](#prompt-module) - Interactive prompts
- [signal](#signal-module) - Signal handling
- [util](#util-module) - General utilities

---

## CLI Module

### Command

Defines a CLI command with flags, subcommands, and execution logic.

```zig
const cli = @import("cli");

const Command = struct {
    // Required
    name: []const u8,           // Command name
    summary: []const u8,        // One-line description

    // Help and documentation
    long_help: []const u8 = "",      // Extended help text
    examples: []const []const u8 = &.{},
    version: []const u8 = "",        // Version string

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
    args: ArgsSpec = .{},                // Positional argument config

    // Active help for completions
    active_help: []const []const u8 = &.{},
    active_help_fn: ?ActiveHelpFn = null,
};
```

### FlagSpec

Defines a command-line flag.

```zig
const FlagSpec = struct {
    name: []const u8,               // Long flag name (--name)
    short: ?u8 = null,              // Short flag (-n)
    help: []const u8 = "",          // Help text
    ftype: FlagType = .string,      // Value type
    required: bool = false,
    default_str: ?[]const u8 = null,
    env: ?[]const u8 = null,        // Environment variable name
    is_repeatable: bool = false,    // Can be specified multiple times
    is_deprecated: bool = false,
    secret: SecretPolicy = .none,   // Secret handling policy
    validator: ?ValidatorFn = null, // Custom validator
    completions: []const []const u8 = &.{}, // Static completion values
};
```

### FlagGroup

Defines relationships between flags.

```zig
const FlagGroup = struct {
    flags: []const []const u8,  // Flag names in this group
    rule: GroupRule,
};

const GroupRule = enum {
    mutually_exclusive,  // Only one flag can be set
    required_together,   // If one is set, all must be set
    one_required,        // At least one must be set
};
```

### ArgsSpec

Configures positional argument handling.

```zig
const ArgsSpec = struct {
    validator: ?ArgsValidator = null,  // Validate argument count/content
    names: []const []const u8 = &.{},  // Named positional args for help
};

// Built-in validators
const args = struct {
    fn exact(n: usize) ArgsValidator { ... }
    fn minimum(n: usize) ArgsValidator { ... }
    fn maximum(n: usize) ArgsValidator { ... }
    fn range(min: usize, max: usize) ArgsValidator { ... }
};
```

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

Execution context passed to command handlers.

```zig
const Context = struct {
    allocator: Allocator,
    stdout: Writer,
    stderr: Writer,
    is_tty_out: bool,
    is_tty_err: bool,
    quiet: bool,      // -q/--quiet
    json: bool,       // --json
    plain: bool,      // --plain
    no_color: bool,   // --no-color
    dry_run: bool,    // -n/--dry-run
    no_input: bool,   // --no-input

    // Methods
    fn getFlag(self, name) ?FlagValue
    fn getString(self, name) ?[]const u8
    fn getBool(self, name) bool
    fn getInt(self, name) ?i64
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
const result = try parser.parse(argv);
defer result.context.deinit();

if (result.help_requested) {
    cli.printHelp(result.command, &result.context);
}
```

### Helper Functions

```zig
// Run a command with arguments
fn run(root: *const Command, argv: [][]const u8, allocator: Allocator) !u8

// Generate shell completions
fn generateCompletions(shell: enum { bash, zsh, fish, powershell }, cmd: *const Command, allocator: Allocator) ![]const u8

// Generate man page
fn generateMan(cmd: *const Command, allocator: Allocator) ![]const u8

// Generate Markdown documentation
fn generateMarkdown(cmd: *const Command, allocator: Allocator) ![]const u8

// Print help
fn printHelp(cmd: *const Command, ctx: *Context) void

// Print help with custom template
fn printHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) void
```

---

## Help Module

Help text generation with customizable templates.

### HelpTemplate

```zig
const help = @import("cli").help;

const HelpTemplate = struct {
    // Section order
    sections: []const HelpSection = &.{ .header, .usage, .examples, .description, .commands, .flags, .footer },

    // Section headers
    usage_header: []const u8 = "Usage",
    examples_header: []const u8 = "Examples",
    description_header: []const u8 = "",
    commands_header: []const u8 = "Commands",
    flags_header: []const u8 = "Flags",

    // Display options
    show_global_flags: bool = true,
    show_footer: bool = true,
    footer_text: ?[]const u8 = null,

    // Formatting
    indent: u8 = 2,
    name_column_width: u8 = 20,

    // Custom renderer (optional)
    custom_renderer: ?CustomRendererFn = null,

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
    footer,      // Footer hints
};
```

### Functions

```zig
// Print help with default template
fn printHelp(cmd: *const Command, ctx: *Context) void

// Print help with custom template
fn printHelpWithTemplate(cmd: *const Command, ctx: *Context, template: *const HelpTemplate) void

// Generate man page in roff format
fn generateMan(cmd: *const Command, allocator: Allocator) ![]const u8

// Generate Markdown documentation
fn generateMarkdown(cmd: *const Command, allocator: Allocator) ![]const u8

// Print version information
fn printVersion(cmd: *const Command, ctx: *Context) void
```

---

## Completion Module

Shell completion script generation.

### Shell Types

```zig
const completion = @import("cli").completion;

const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,
};
```

### Generation

```zig
// Generate completion script
fn generate(
    shell: Shell,
    cmd: *const Command,
    allocator: Allocator,
    options: GenerateOptions,
) ![]const u8

const GenerateOptions = struct {
    active_help: bool = true,  // Include active help support
};
```

### Active Help

Active help provides dynamic hints during shell completion:

```zig
const cmd = Command{
    .name = "deploy",
    // Static hints
    .active_help = &.{
        "Tip: Use --dry-run to preview changes",
    },
    // Dynamic hints based on context
    .active_help_fn = struct {
        fn getHints(cmd: *const Command, args: []const []const u8) []const []const u8 {
            // Return context-aware hints
        }
    }.getHints,
};
```

Users can disable active help with environment variable:
```bash
export MYAPP_ACTIVE_HELP=0
```

---

## Config Module

Re-exports the external `zig-config` library.

### Format Detection

```zig
const Format = enum { yaml, toml, json };

const format = config.Format.fromExtension("config.yaml");  // .yaml
```

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

### Provenance Tracking

```zig
var tracker = config.ProvenanceTracker.init(allocator);
defer tracker.deinit();

try tracker.set("port", "8080", .system, "/etc/app/config.toml");
try tracker.set("port", "9000", .user, "~/.config/app/config.toml");

const val = tracker.get("port").?;
// val.value == "9000" (user overrides system)
// val.source == .user
```

### Source Precedence

```
flag > env > project > user > system > default
```

### XDG Directories

```zig
const config_dir = try config.xdg.getConfigDir("myapp", allocator);
const data_dir = try config.xdg.getDataDir("myapp", allocator);
const cache_dir = try config.xdg.getCacheDir("myapp", allocator);
const system_dir = try config.xdg.getSystemConfigDir("myapp", allocator);
```

### Validation

```zig
try config.validate.required(value);
try config.validate.url("https://example.com");
try config.validate.email("user@example.com");
try config.validate.port(8080);
```

### Secret Handling

```zig
const redacted = config.secret.redact("password123");
// "***REDACTED***"

var buffer = "secret".*;
config.secret.secureZero(&buffer);
// buffer is now all zeros
```

---

## Term Module

Terminal utilities with TTY detection and NO_COLOR compliance.

### Terminal Info

```zig
const info = term.getInfo();
// info.is_tty, info.width, info.height, info.color_supported
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
const color_ctx = term.ColorContext.init(force_color, no_color);
if (color_ctx.enabled) {
    // Use colors
}
```

### ANSI Stripping

```zig
const plain = try term.stripAnsi("\x1b[31mred\x1b[0m text", allocator);
// "red text"
```

---

## Progress Module

Progress indicators for long-running operations.

### Spinner

For operations with unknown duration:

```zig
const progress = @import("cli").progress;

var spinner = progress.Spinner.init(ctx.stdout, .{
    .message = "Loading...",
    .style = .dots,  // .dots, .line, .arrow, .pulse, .bounce
});

spinner.start();
defer spinner.stop();

// Update message during operation
spinner.setMessage("Processing...");

// Completion states
spinner.succeed("Done!");    // Green checkmark
spinner.fail("Failed");      // Red X
spinner.warn("Warning");     // Yellow warning
spinner.info("Info");        // Blue info
```

### Progress Bar

For operations with known total:

```zig
var bar = progress.ProgressBar.init(ctx.stdout, .{
    .total = 100,
    .width = 40,
    .format = "[{bar}] {percent}% ({current}/{total})",
    .filled_char = '=',
    .empty_char = ' ',
    .show_eta = true,
});

bar.start();
defer bar.finish();

// Update progress
bar.update(50);     // Set to 50
bar.increment(1);   // Add 1 to current
```

### Format Placeholders

```
{bar}     - Progress bar visualization
{percent} - Percentage complete
{current} - Current value
{total}   - Total value
{eta}     - Estimated time remaining
{message} - Custom message
```

---

## Table Module

Structured table output.

### Creating Tables

```zig
const table = @import("cli").table;

var t = table.Table.init(ctx.allocator, .{
    .style = .ascii,  // .ascii, .unicode, .unicode_double, .minimal, .none
    .striped = false,
    .padding = 1,
    .columns = &.{
        .{ .header = "ID", .alignment = .right, .min_width = 4 },
        .{ .header = "Name", .alignment = .left, .max_width = 20 },
        .{ .header = "Status", .alignment = .center },
    },
});
defer t.deinit();

try t.addRow(&.{ "1", "Alice", "Active" });
try t.addRow(&.{ "2", "Bob", "Inactive" });

try t.render(ctx.stdout);
```

### Column Options

```zig
const ColumnSpec = struct {
    header: []const u8 = "",
    alignment: Alignment = .left,
    min_width: ?usize = null,
    max_width: ?usize = null,
};

const Alignment = enum { left, center, right };
```

### Border Styles

```
.ascii          +----+---------+
                | ID | Name    |
                +----+---------+

.unicode        ┌────┬─────────┐
                │ ID │ Name    │
                ├────┼─────────┤

.unicode_double ╔════╦═════════╗
                ║ ID ║ Name    ║
                ╠════╬═════════╣

.minimal        ID  Name
                --  ----

.none           ID  Name
```

### Sorting

```zig
t.sortByColumn(0, .ascending);
t.sortByColumn(1, .descending);
```

---

## Util Module

### Exit Codes

```zig
const ExitCode = enum(u8) {
    success = 0,
    general_error = 1,
    usage_error = 2,
    // ...
};
```

### String Suggestions

```zig
const candidates = &[_][]const u8{ "start", "stop", "status" };
const suggestion = util.suggestClosest("strat", candidates, 2);
// suggestion == "start"
```

### Text Utilities

```zig
const truncated = try util.truncate("hello world", 8, allocator);
// "hello..."

const padded = try util.padRight("hi", 10, allocator);
// "hi        "
```

### Filesystem

```zig
util.exists("/path/to/file")
util.isDirectory("/path")
util.fs.isSafePath("/home/user/file.txt")  // true
util.fs.isSafePath("/etc/shadow")          // false
```

---

## Signal Module

Cross-platform signal handling for graceful shutdown.

### Installation

```zig
const signal = @import("cli").signal;

try signal.install(.{
    .handle_interrupt = true,   // SIGINT
    .handle_terminate = true,   // SIGTERM
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
```

### Cleanup Callbacks

```zig
try signal.onCleanup(fn() void {
    // Cleanup resources
});
```

---

## Prompt Module

Interactive prompts for CLI input.

### Text Input

```zig
const prompt = @import("cli").prompt;

const name = try prompt.input("Enter name", .{
    .default = "anonymous",
    .allow_empty = false,
    .max_length = 100,
}, allocator);
defer allocator.free(name);
```

### Password Input

```zig
const password = try prompt.password("Password: ", allocator);
defer allocator.free(password);
// Input is not echoed
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
// choice is 0, 1, or 2
```

### Multi-Select

```zig
const choices = try prompt.multiSelect("Select features:", &.{
    "Feature A",
    "Feature B",
    "Feature C",
}, allocator);
defer allocator.free(choices);
// choices is slice of indices
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

### ValidationError

```zig
const ValidationError = error{
    Required,
    TooShort,
    TooLong,
    OutOfRange,
    PatternMismatch,
};
```

---

## Built-in Validators

The library provides common validators for flag values.

### Network Validators

```zig
const validate = @import("cli").validate;

validate.hostname  // Valid hostname format
validate.port      // Valid port (1-65535)
validate.ip        // IPv4 or IPv6 address
validate.ipv4      // IPv4 address only
validate.ipv6      // IPv6 address only
validate.url       // Valid URL format
```

### Format Validators

```zig
validate.email     // Email address format
validate.uuid      // UUID format
```

### Path Validators

```zig
validate.file_exists  // File must exist
validate.dir_exists   // Directory must exist
validate.path_exists  // File or directory must exist
```

### Numeric Validators

```zig
validate.positive       // > 0
validate.non_negative   // >= 0
validate.range(1, 100)  // Within range (inclusive)
```

### Usage

```zig
const cmd = Command{
    .flags = &.{
        FlagSpec{
            .name = "port",
            .ftype = .int,
            .validator = validate.port,
        },
        FlagSpec{
            .name = "email",
            .ftype = .string,
            .validator = validate.email,
        },
    },
};
```

### Custom Validators

```zig
fn validateProjectName(value: []const u8) ?[]const u8 {
    if (value.len < 3) {
        return "Project name must be at least 3 characters";
    }
    if (!std.ascii.isAlphabetic(value[0])) {
        return "Project name must start with a letter";
    }
    return null;  // Valid
}

const cmd = Command{
    .flags = &.{
        FlagSpec{
            .name = "name",
            .validator = validateProjectName,
        },
    },
};
```
