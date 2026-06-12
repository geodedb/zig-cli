# Audit Iteration 1 Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every actionable security/perf/quality/gap finding from the 2026-06-11 codepros audit + appsec review (GitLab issues #39, #40, #94, #106, #124–#142 minus #34) with TDD fixes.

**Architecture:** Targeted fixes within the existing module layout (cli / term / util / parallel / prompt modules, all rooted at `src/`). A new shared control-character sanitizer lives in `src/util/text.zig` and is imported by cli and term files via in-tree relative imports (all these files share the `src/` module root within each module, e.g. `@import("../util/text.zig")` from `src/cli/help.zig`, `@import("../util/text.zig")` from `src/term/table.zig`). No public API removals; one additive API (`getBoolOpt`, `freeSecret`), one behavioral break documented in CHANGELOG (invalid `default_str` now errors).

**Tech Stack:** Zig 0.16.0. Build/test: `zig build test --summary all`, `zig build test-integration --summary all`, `zig fmt`, `pre-commit run --all-files`.

**Branch:** work on `fix/audit-iter1` (created from `main` before Task 1).

**Issue map:** T1–T3→#128(NS-056); T4→#131(NS-060)+#136; T5→#132(NS-061); T6→#140(NQ-NEW-009); T7→#129(NS-058)+#126(NP-031); T8→#127(NP-032); T9→#133(NS-062); T10→#124(NP-029); T11→#125(NP-030)+#139; T12→#39(GAP-0097)+#140(NQ-NEW-011/013); T13→#130(NS-059)+#40(GAP-0099); T14→#137; T15→#106+#135+#138; T16→docs(F-02/F-07/F-08/NQ-NEW-018/#141)+NP-033; T17→#134.

**General rules for every task:**

- Run `zig fmt src/ tests/ build.zig` before each commit.
- Run `zig build test --summary all` (expect 803+ pass, count grows as tests are added) before each commit.
- Commit messages follow conventional commits, reference the GitLab issue (`Refs: #NNN`).
- Tests live as inline `test ""` blocks in the file under change (repo convention).

---

## Tasks

### Task 1: Control-character sanitizer in util/text.zig (NS-056 foundation, #128)

**Files:**

- Modify: `src/util/text.zig` (append after `splitWhitespace`, before Tests section)

- [ ] **Step 1: Write failing tests** — append to the Tests section of `src/util/text.zig`:

```zig
test "writeControlFiltered strips ESC and C0 controls, keeps \\n and \\t" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "a\x1b[2Jb\x07c\nd\te\x7ff");
    try std.testing.expectEqualStrings("a[2Jbc\nd\tef", w.buffered());
}

test "writeControlFiltered passes plain text through unchanged" {
    var buf: [64]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    try writeControlFiltered(&w, "hello world");
    try std.testing.expectEqualStrings("hello world", w.buffered());
}

test "stripControlChars allocating variant" {
    const out = try stripControlChars("x\x1b]0;evil\x07y", std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("x]0;evily", out);
}
```

Note: `\x1b[2J` keeps `[2J` after stripping only the ESC byte — that is intentional (the sequence is neutralized once ESC is removed; remaining bytes are printable).

- [ ] **Step 2: Run `zig build test --summary all` — expect FAIL (undefined identifiers).**

- [ ] **Step 3: Implement** (append after `splitWhitespace`):

```zig
/// Write `text` to `w`, removing bytes that can alter terminal state:
/// C0 controls (0x00-0x08, 0x0B-0x1F), DEL (0x7F). Newline (0x0A) and
/// tab (0x09) are preserved. Removing ESC (0x1B) neutralizes ANSI/OSC
/// escape sequences (CWE-150); the remaining printable bytes are kept.
pub fn writeControlFiltered(w: anytype, text: []const u8) !void {
    var start: usize = 0;
    for (text, 0..) |c, idx| {
        const is_control = (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
        if (is_control) {
            if (idx > start) try w.writeAll(text[start..idx]);
            start = idx + 1;
        }
    }
    if (start < text.len) try w.writeAll(text[start..]);
}

/// Allocating variant of `writeControlFiltered`. Caller owns the result.
pub fn stripControlChars(text: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    var start: usize = 0;
    for (text, 0..) |c, idx| {
        const is_control = (c < 0x20 and c != '\n' and c != '\t') or c == 0x7f;
        if (is_control) {
            if (idx > start) try result.appendSlice(allocator, text[start..idx]);
            start = idx + 1;
        }
    }
    if (start < text.len) try result.appendSlice(allocator, text[start..]);
    return result.toOwnedSlice(allocator);
}
```

- [ ] **Step 4: Run `zig build test --summary all` — expect PASS.**
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat(util): add control-character sanitizer for terminal output

Refs: #128"`

---

### Task 2: Apply control filtering in cli module — help text + unknown-command error (#128)

**Files:**

- Modify: `src/cli/help.zig` (plain-text help emission), `src/util/errors.zig:102-119`

**Context:** `src/cli/help.zig` is part of the `cli` module whose root source is `src/cli.zig`, so module root dir is `src/` — import the sanitizer as `const textutil = @import("../util/text.zig");` (verify: other files may already do similar cross-dir imports; if the import path fails to compile, the module root differs — then use the path that works, e.g. `@import("util/text.zig")` won't work from `src/cli/`, the correct relative form is `../util/text.zig`).

- [ ] **Step 1: Write failing tests** in `src/cli/help.zig` tests section:

```zig
test "help: text output strips terminal escape bytes from metadata" {
    const cmd = Command{
        .name = "esc",
        .summary = "s\x1b[2Jummary",
        .flags = &.{
            .{ .name = "bad", .help = "h\x1b]0;evil\x07elp", .ftype = .bool },
        },
    };
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try printTextHelpToWriter(&buf.writer, &cmd); // use the existing internal text-help entry point; locate the function that printTextHelpWithTemplate delegates to and call it with the default template
    const out = buf.written();
    try std.testing.expect(std.mem.indexOfScalar(u8, out, 0x1b) == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, out, 0x07) == null);
}
```

Adapt the call to the actual internal API: read `printTextHelpWithTemplate` (around `help.zig:183`) — it builds the output in a `std.Io.Writer.Allocating`; factor the inner "render to writer" part into a testable function if one does not already exist (keep the public functions' signatures unchanged).

- [ ] **Step 2: Run `zig build test` — expect FAIL (escape byte present).**

- [ ] **Step 3: Implement.** In the plain-text help path (the template renderer and its helpers: command name/summary/long_help, flag name/help/default_str/env, subcommand name/summary, examples, group names), replace direct `{s}` emission of these *metadata strings* with `try textutil.writeControlFiltered(w, value)`. Pattern:

```zig
// before:
try w.print("  {s}\n", .{cmd.summary});
// after:
try w.writeAll("  ");
try textutil.writeControlFiltered(w, cmd.summary);
try w.writeAll("\n");
```

Do NOT filter: literal format strings, the roff/JSON/markdown generators (they have their own escapers; roff and JSON are already complete; markdown is fixed in Task 4). DO also filter the env-var section and active-help strings if they are emitted in plain-text help.

- [ ] **Step 4: In `src/util/errors.zig` `formatUnknownCommand` (line 102), sanitize the echoed argv:**

```zig
const text = @import("text.zig");

pub fn formatUnknownCommand(
    input: []const u8,
    suggestion: ?[]const u8,
    allocator: std.mem.Allocator,
) !FormattedError {
    const safe_input = try text.stripControlChars(input, allocator);
    const message = try std.fmt.allocPrint(allocator, "'{s}' is not a command", .{safe_input});
    allocator.free(safe_input);
    ...
}
```

Add test in `errors.zig`:

```zig
test "formatUnknownCommand strips control bytes from input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const fe = try formatUnknownCommand("de\x1b[2Jploy", null, arena.allocator());
    try std.testing.expect(std.mem.indexOfScalar(u8, fe.message, 0x1b) == null);
}
```

- [ ] **Step 5: Run `zig build test --summary all` and `zig build test-integration --summary all` — expect PASS.**
- [ ] **Step 6: Commit:** `fix(cli): strip terminal control bytes from help and error output (CWE-150)` + `Refs: #128`

---

### Task 3: Apply control filtering in term module — color, progress, table (#128)

**Files:**

- Modify: `src/term/color.zig:90-105`, `src/term/progress.zig:127-142`, `src/term/table.zig:242-267` (writeAligned) and header emission at `:189`

**Import:** `const textutil = @import("../util/text.zig");` (term module root is `src/`, same pattern as Task 2).

- [ ] **Step 1: Write failing tests:**

In `color.zig`:

```zig
test "writeColored strips control bytes from text" {
    var buf: [128]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    const c = Colorizer{ .enabled = true };  // match the actual struct name/init in this file
    try c.writeColored(&w, "a\x1b[31mb", .red);
    // exactly one ESC pair from our own wrapping, none from payload:
    try std.testing.expectEqualStrings("\x1b[31ma[31mb\x1b[0m", w.buffered());
}
```

(Adjust construction to the real type — read the struct definition at the top of color.zig; `Self` has field `enabled`.)

In `table.zig`:

```zig
test "table cells are control-filtered" {
    var t = Table.init(std.testing.allocator, .{});
    defer t.deinit();
    try t.addColumn(.{ .header = "h" });
    try t.addRow(&.{"a\x1b[2Jb"});
    const out = try t.render();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOfScalar(u8, out, 0x1b) == null);
}
```

(Match `Table.init`/`addColumn` signatures from the file; the existing tests in table.zig show the exact construction idiom — copy it.)

In `progress.zig` — `render` writes to stderr (not capturable); instead filter at the source: test the helper directly if one is extracted, or skip a unit test and rely on the filtered-write helper's own tests. Minimum: change + comment.

- [ ] **Step 2: Run `zig build test` — expect FAIL for color/table tests.**

- [ ] **Step 3: Implement:**

`color.zig` (both `writeColored` and `writeStyled`):

```zig
pub fn writeColored(self: Self, writer: anytype, text: []const u8, color: Color) !void {
    if (self.enabled) {
        try writer.print("\x1b[{d}m", .{@intFromEnum(color)});
        try textutil.writeControlFiltered(writer, text);
        try writer.writeAll("\x1b[0m");
    } else {
        try textutil.writeControlFiltered(writer, text);
    }
}
```

`table.zig` `writeAligned`: replace each `try writer.writeAll(text...)` of cell/header content with `try textutil.writeControlFiltered(writer, ...)` — note the width math still uses byte `.len` (UTF-8 width handled in Task 9; here only filter). Important: filtering changes emitted length if controls present; that is acceptable (alignment of malicious content is not a goal).

`progress.zig`: in `render` (line 141) and `stopWithMessage` (130/132), pre-filter the message. Since these print via `stderrPrint`, simplest is to filter into a stack buffer:

```zig
fn render(self: *Self) !void {
    const frames = self.spinner_style.frames();
    const frame = frames[self.frame_index];
    var mbuf: [256]u8 = undefined;
    var mw = std.Io.Writer.fixed(&mbuf);
    textutil.writeControlFiltered(&mw, self.message) catch {}; // truncates >256B messages; fine for a spinner line
    try stderrPrint("\r\x1b[K{s} {s}", .{ frame, mw.buffered() });
}
```

Apply the same pattern in `stopWithMessage` for `message`, and in `ProgressBar.render` for `self.message` (read the ProgressBar render code first and mirror).

- [ ] **Step 4: Run `zig build test --summary all` — expect PASS.**
- [ ] **Step 5: Commit:** `fix(term): strip terminal control bytes from colored text, progress messages, table cells` + `Refs: #128`

---

### Task 4: Markdown generator — escape headings, prose, fences, newlines (#131 NS-060, #136 NQ-NEW-008)

**Files:**

- Modify: `src/cli/help.zig:779-900` (writeMarkdownEscaped + generateMarkdownCommand)

- [ ] **Step 1: Write failing tests** in help.zig tests section:

```zig
test "markdown: headings and prose are escaped" {
    const cmd = Command{
        .name = "x<script>",
        .summary = "<img src=x onerror=1>",
        .long_help = "# fake heading\n<b>bold</b>",
        .flags = &.{},
    };
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try generateMarkdownCommand(&buf.writer, &cmd, 1);
    const out = buf.written();
    try std.testing.expect(std.mem.indexOf(u8, out, "<script>") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<img") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "\n# fake") == null); // leading # neutralized
}

test "markdown: code fence content cannot break out" {
    const cmd = Command{
        .name = "y",
        .summary = "s",
        .examples = &.{"a\n```\nevil"},
        .flags = &.{},
    };
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try generateMarkdownCommand(&buf.writer, &cmd, 1);
    // No line inside our fence may itself start with ```
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\n```\nevil") == null);
}

test "markdown: table cell newlines become <br>" {
    const cmd = Command{
        .name = "z",
        .summary = "s",
        .flags = &.{.{ .name = "f", .help = "line1\nline2", .ftype = .bool }},
    };
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    try generateMarkdownCommand(&buf.writer, &cmd, 1);
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "line1<br>line2") != null);
}
```

(Check `Command` field defaults — `examples`, `long_help` exist with `&.{}`/`""` defaults; copy construction style from neighboring tests. If `generateMarkdownCommand` is not pub, tests in the same file can still call it.)

- [ ] **Step 2: Run — expect FAIL.**

- [ ] **Step 3: Implement three context-specific helpers and use them:**

```zig
/// Escape for Markdown table cells: existing rules + newlines -> <br>.
fn writeMarkdownEscaped(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '|' => "\\|",
            '`' => "\\`",
            '<' => "&lt;",
            '>' => "&gt;",
            '\n' => "<br>",
            '\r' => "",
            else => null,
        };
        if (esc) |escape_seq| {
            if (idx > start) try w.writeAll(s[start..idx]);
            try w.writeAll(escape_seq);
            start = idx + 1;
        }
    }
    if (start < s.len) try w.writeAll(s[start..]);
}

/// Escape for Markdown inline/heading text: HTML-escape angle brackets,
/// escape backticks, and collapse newlines to spaces (headings are single-line).
fn writeMarkdownHeading(w: anytype, s: []const u8) !void {
    var start: usize = 0;
    for (s, 0..) |c, idx| {
        const esc: ?[]const u8 = switch (c) {
            '<' => "&lt;",
            '>' => "&gt;",
            '`' => "\\`",
            '\n', '\r' => " ",
            else => null,
        };
        if (esc) |escape_seq| {
            if (idx > start) try w.writeAll(s[start..idx]);
            try w.writeAll(escape_seq);
            start = idx + 1;
        }
    }
    if (start < s.len) try w.writeAll(s[start..]);
}

/// Escape for Markdown prose blocks: HTML-escape angle brackets and
/// neutralize line-leading '#' so injected text cannot create headings.
fn writeMarkdownProse(w: anytype, s: []const u8) !void {
    var at_line_start = true;
    for (s) |c| {
        if (at_line_start and c == '#') {
            try w.writeAll("\\#");
            at_line_start = false;
            continue;
        }
        switch (c) {
            '<' => try w.writeAll("&lt;"),
            '>' => try w.writeAll("&gt;"),
            '\n' => {
                try w.writeAll("\n");
                at_line_start = true;
                continue;
            },
            else => try w.writeByte(c),
        }
        at_line_start = false;
    }
}

/// Write example content inside a code fence, indenting any line that
/// starts with ``` so it cannot close the fence.
fn writeFenceSafe(w: anytype, s: []const u8) !void {
    var lines = std.mem.splitScalar(u8, s, '\n');
    var first = true;
    while (lines.next()) |line| {
        if (!first) try w.writeAll("\n");
        first = false;
        if (std.mem.startsWith(u8, std.mem.trimLeft(u8, line, " \t"), "```")) {
            try w.writeAll(" "); // leading space breaks fence-close semantics
        }
        try w.writeAll(line);
    }
}
```

Then in `generateMarkdownCommand` replace the raw prints: `:807` cmd.name → `writeMarkdownHeading`; `:810` cmd.summary and `:823` cmd.long_help → `writeMarkdownProse`; `:814` synopsis `cmd.name` inside the fence → `writeFenceSafe`; `:830` examples → `writeFenceSafe`; `:882` group_name → `writeMarkdownHeading`. Check the rest of the markdown generator (below line 894 — subcommand recursion, env-var section if present) and apply the same helpers to any other raw `{s}` of metadata.

- [ ] **Step 4: Run `zig build test --summary all` — expect PASS (also confirm pre-existing writeMarkdownEscaped tests still pass — update any that asserted newline passthrough).**
- [ ] **Step 5: Commit:** `fix(cli): context-aware markdown escaping for headings, prose, fences, and cell newlines` + `Refs: #131 #136`

---

### Task 5: Completion generator hardening — powershell, zsh, fish (#132 NS-061)

**Files:**

- Modify: `src/cli/completion/powershell.zig:33`, `src/cli/completion/zsh.zig` (function names + case labels), `src/cli/completion/fish.zig:166-181`

- [ ] **Step 1: Write failing tests** (one per file, in each file's tests section — copy the construction idiom from existing tests in the same files):

powershell.zig:

```zig
test "powershell: CommandName is escaped" {
    const cmd = Command{ .name = "app'b", .summary = "s", .flags = &.{} };
    const out = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "-CommandName 'app''b'") != null);
}
```

zsh.zig:

```zig
test "zsh: subcommand names are quoted in case labels and function names sanitized" {
    const sub = Command{ .name = "x);evil", .summary = "s", .flags = &.{} };
    const cmd = Command{ .name = "app", .summary = "s", .flags = &.{}, .subcommands = &.{sub} };
    const out = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(out);
    // case label must be single-quoted with internal quote-escaping
    try std.testing.expect(std.mem.indexOf(u8, out, "'x);evil')") != null);
    // function identifier must contain no shell metacharacters
    try std.testing.expect(std.mem.indexOf(u8, out, "_app_x__evil") != null);
}
```

(Adjust expected sanitized identifier to the implementation: every non-[a-zA-Z0-9_] byte → `_`, so `x);evil` → `x__evil` is 7 chars: x ) ; e v i l → `x__evil`. Verify in test after implementing — the assertion is on "no raw `);` in a function name" — alternatively assert `std.mem.indexOf(u8, out, "_app_x);evil") == null`.)

fish.zig:

```zig
test "fish: nesting deeper than 16 levels is capped gracefully" {
    // Build a 18-deep chain of commands.
    var cmds: [18]Command = undefined;
    cmds[17] = Command{ .name = "leaf", .summary = "s", .flags = &.{} };
    var i: usize = 17;
    while (i > 0) {
        i -= 1;
        cmds[i] = Command{ .name = "n", .summary = "s", .flags = &.{}, .subcommands = cmds[i + 1 .. i + 2] };
    }
    const out = try generate(&cmds[0], std.testing.allocator);
    defer std.testing.allocator.free(out);
    // Must not crash; deepest levels simply absent.
    try std.testing.expect(out.len > 0);
}
```

(If `Command.subcommands` requires `[]const Command` vs slice-of-array adjust accordingly; existing tests show the idiom. The key assertion is "does not panic/OOB".)

- [ ] **Step 2: Run — expect FAIL (powershell/zsh asserts; fish test panics in Debug).**

- [ ] **Step 3: Implement:**

powershell.zig:33:

```zig
const esc_cmd_name = try escapePowerShellString(esc_alloc, cmd.name);
try w.print("Register-ArgumentCompleter -Native -CommandName '{s}' -ScriptBlock {{\n", .{esc_cmd_name});
```

zsh.zig — add (mirroring bash.zig:88):

```zig
/// Sanitize a name for use as a zsh function identifier.
/// Replaces any character that is not [a-zA-Z0-9_] with an underscore.
fn sanitizeZshIdentifier(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const buf = try allocator.alloc(u8, name.len);
    for (name, 0..) |c, idx| {
        buf[idx] = if (std.ascii.isAlphanumeric(c) or c == '_') c else '_';
    }
    return buf;
}
```

Apply: wherever `prefix`/`subprefix` is built or used as a function name (`zsh.zig:174` `_{s}() {{`, `:217` subprefix bufPrint, `:219` `_{s}` call), sanitize the *name component* before composing. At `:218` quote the case label using the existing `escapeZshSingleQuote`:

```zig
const esc_label = try escapeZshSingleQuote(esc_alloc, subcmd.name);
try w.print("                '{s}')\n", .{esc_label});
```

Also check the top-level `generate` where the root function name comes from `cmd.name` (and the active-help function at `:161` `_{s}_active_help` which uses raw `cmd.name`) — sanitize those identifiers too.

fish.zig:166-181 — guard before the copy loop:

```zig
for (cmd.subcommands) |subcmd| {
    if (!subcmd.hidden) {
        // Depth cap: completions are generated at most 16 levels deep
        // (documented limit). Deeper trees are skipped, never OOB.
        if (path.len >= 16) break;
        var new_path: [16][]const u8 = undefined;
        ...
```

- [ ] **Step 4: Run `zig build test --summary all` — expect PASS.**
- [ ] **Step 5: Commit:** `fix(completion): escape powershell CommandName, sanitize zsh identifiers/case labels, cap fish nesting depth` + `Refs: #132`

---

### Task 6: JSON help — escape short-flag char (#140 NQ-NEW-009)

**Files:**

- Modify: `src/cli/help.zig:596-599`

- [ ] **Step 1: Failing test** (help.zig):

```zig
test "help: json short flag with quote char is escaped" {
    var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer buf.deinit();
    const flag = FlagSpec{ .name = "f", .short = '"', .help = "h", .ftype = .bool };
    try writeJsonFlag(&buf.writer, &flag); // call whatever function contains line 591-606; make it file-private-callable
    try std.testing.expect(std.mem.indexOf(u8, buf.written(), "\"short\":\"\\\"\"") != null);
}
```

(Locate the enclosing function of lines 591–606 — name the test target accordingly.)

- [ ] **Step 2: Run — expect FAIL (invalid JSON emitted raw).**
- [ ] **Step 3: Implement** at `:596`:

```zig
if (flag.short) |s| {
    try w.writeAll("\"short\":");
    try writeJsonEscapedString(w, &[_]u8{s});
    try w.writeAll(",");
} else {
    try w.print("\"short\":null,", .{});
}
```

Check the other `flag.short` JSON emissions (`:705`, `:841` regions) and fix identically if they also emit `{c}` into JSON.

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit:** `fix(cli): JSON-escape short flag character in help output` + `Refs: #140`

---

### Task 7: Progress — u16 underflow fix + spinner batched writes (#129 NS-058, #126 NP-031)

**Files:**

- Modify: `src/term/progress.zig:77-78, 94-95, 136-142, 173-184`

- [ ] **Step 1: Failing test** (progress.zig):

```zig
test "ProgressBar.init does not underflow on narrow terminals" {
    // Simulate the width computation with a narrow width.
    const w = barWidthForTerminal(10);
    try std.testing.expect(w <= 50);
    const w2 = barWidthForTerminal(0);
    try std.testing.expect(w2 >= 1);
}
```

- [ ] **Step 2: Run — FAIL (function undefined).**
- [ ] **Step 3: Implement.** Extract the width computation:

```zig
/// Compute the bar width for a terminal of `term_width` columns.
/// Saturating: never underflows on narrow terminals; minimum 1 column.
fn barWidthForTerminal(term_width: u16) u16 {
    return @max(@min(term_width -| 20, 50), 1);
}
```

and in `init` (line 179): `.width = barWidthForTerminal(term_info.width),`.

Spinner batching — replace the two-write start sequence (lines 77-78 and 94-95):

```zig
if (self.enabled) {
    // Hide cursor + first render in a single write
    self.renderWithPrefix("\x1b[?25l") catch {};
}
```

and refactor `render`:

```zig
fn render(self: *Self) !void {
    return self.renderWithPrefix("");
}

fn renderWithPrefix(self: *Self, prefix: []const u8) !void {
    const frames = self.spinner_style.frames();
    const frame = frames[self.frame_index];
    var mbuf: [256]u8 = undefined;
    var mw = std.Io.Writer.fixed(&mbuf);
    textutil.writeControlFiltered(&mw, self.message) catch {};
    try stderrPrint("{s}\r\x1b[K{s} {s}", .{ prefix, frame, mw.buffered() });
}
```

(If Task 3 already introduced message filtering in `render`, merge with that code — keep one implementation.)

- [ ] **Step 4: Run `zig build test --summary all` — PASS.**
- [ ] **Step 5: Commit:** `fix(term): saturating progress-bar width on narrow terminals; batch spinner start writes` + `Refs: #129 #126`

---

### Task 8: Table — min_width correctness + border splat (#127 NP-032)

**Files:**

- Modify: `src/term/table.zig:127-148` (addRow width update), `:269-283` (writeHorizontalBorder); check `addColumn` seeds widths

- [ ] **Step 1: Failing test:**

```zig
test "table: min_width is honored even when all cells are short" {
    var t = Table.init(std.testing.allocator, .{});
    defer t.deinit();
    try t.addColumn(.{ .header = "h", .min_width = 10 });
    try t.addRow(&.{"ab"});
    try std.testing.expectEqual(@as(usize, 10), t.column_widths.items[0]);
}
```

(Match `addColumn` Column struct field names from the file.)

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** — replace the width-update block at `:128-148`:

```zig
for (cells, 0..) |cell, i| {
    const current_width = self.column_widths.items[i];
    const col = self.columns.items[i];

    var cell_width = cell.len;
    if (col.max_width > 0 and cell_width > col.max_width) {
        cell_width = col.max_width;
    }
    if (col.min_width > 0 and cell_width < col.min_width) {
        cell_width = col.min_width;
    }
    if (cell_width > current_width) {
        self.column_widths.items[i] = cell_width;
    }
}
```

Also check `addColumn`: if it seeds `column_widths` with `header.len` only, seed with `@max(header.len, col.min_width)` so empty tables honor min_width too (add a quick test if changed).

Border splat: in `writeHorizontalBorder` replace the per-char loop:

```zig
const total_width = width + (pad * 2);
if (horiz.len == 1) {
    try writer.splatByteAll(horiz[0], total_width);
} else {
    for (0..total_width) |_| try writer.writeAll(horiz);
}
```

(If `std.Io.Writer` in Zig 0.16 has `splatBytesAll(bytes, n)`, use it for the multibyte branch instead of the loop — check `zig std` docs or grep the std source under the toolchain; if unsure keep the loop for multibyte.)

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit:** `fix(term): honor table min_width for short cells; batch single-byte border writes` + `Refs: #127`

---

### Task 9: UTF-8-safe truncation (#133 NS-062)

**Files:**

- Modify: `src/util/text.zig:104-114` (truncate), `src/term/table.zig:221-226` (display_cell), `:242-247` (writeAligned)

- [ ] **Step 1: Failing tests:**

text.zig:

```zig
test "truncate does not split multibyte UTF-8 sequences" {
    // "héllo wörld" — é is 2 bytes (0xC3 0xA9)
    const out = try truncate("héllo wörld", 5, std.testing.allocator);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out));
}
```

table.zig:

```zig
test "table max_width truncation does not split multibyte UTF-8" {
    var t = Table.init(std.testing.allocator, .{});
    defer t.deinit();
    try t.addColumn(.{ .header = "h", .max_width = 3 });
    try t.addRow(&.{"ab\xc3\xa9"}); // "abé": byte 3 splits é
    const out = try t.render();
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.unicode.utf8ValidateSlice(out));
}
```

- [ ] **Step 2: Run — FAIL (invalid UTF-8 in output).**
- [ ] **Step 3: Implement.** Add to `src/util/text.zig`:

```zig
/// Largest index <= max_len that does not split a UTF-8 sequence.
/// Backs off over continuation bytes (0b10xxxxxx). Invalid UTF-8 input
/// degrades gracefully (worst case backs off up to 3 bytes).
pub fn utf8FloorIndex(text: []const u8, max_len: usize) usize {
    if (max_len >= text.len) return text.len;
    var idx = max_len;
    while (idx > 0 and (text[idx] & 0xC0) == 0x80) idx -= 1;
    return idx;
}
```

Use it in `truncate`:

```zig
pub fn truncate(text: []const u8, max_len: usize, allocator: std.mem.Allocator) ![]const u8 {
    if (text.len <= max_len) return text;
    if (max_len <= 3) return text[0..utf8FloorIndex(text, max_len)];

    var result: std.ArrayList(u8) = .empty;
    try result.appendSlice(allocator, text[0..utf8FloorIndex(text, max_len - 3)]);
    try result.appendSlice(allocator, "...");
    return result.toOwnedSlice(allocator);
}
```

In `table.zig`, import textutil (already imported in Task 3) and use `textutil.utf8FloorIndex` at both slice points:

```zig
// :223
if (col.max_width > 0 and cell.len > col.max_width) {
    display_cell = cell[0..textutil.utf8FloorIndex(cell, col.max_width)];
}
// writeAligned :244
if (text.len >= width) {
    try textutil.writeControlFiltered(writer, text[0..textutil.utf8FloorIndex(text, width)]);
    return;
}
```

Add a doc comment on `Table` noting widths are byte-oriented; multibyte content is never split but display alignment of wide glyphs is not wcwidth-aware (documented limitation).

- [ ] **Step 4: Run tests — PASS.**
- [ ] **Step 5: Commit:** `fix(util,term): never split multibyte UTF-8 in truncation or table cell clipping` + `Refs: #133`

---

### Task 10: Bash completion — emit global flags once (#124 NP-029)

**Files:**

- Modify: `src/cli/completion/bash.zig:106-139` (generateWithActiveHelp), `:194-204` (generateCommandFunction)

- [ ] **Step 1: Failing test** (bash.zig):

```zig
test "bash: global flags emitted once, referenced per function" {
    const sub = Command{ .name = "sub", .summary = "s", .flags = &.{} };
    const cmd = Command{ .name = "app", .summary = "s", .flags = &.{}, .subcommands = &.{sub} };
    const out = try generate(&cmd, std.testing.allocator);
    defer std.testing.allocator.free(out);
    // The literal global flag list appears exactly once (in the shared variable)
    const first = std.mem.indexOf(u8, out, "_app_global_flags=").?;
    try std.testing.expect(std.mem.indexOfPos(u8, out, first + 1, "_app_global_flags=") == null);
    // Functions reference the shared variable
    try std.testing.expect(std.mem.indexOf(u8, out, "local global_flags=\"${_app_global_flags}\"") != null);
}
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.** In `generateWithActiveHelp` after computing `safe_name` (line 123), emit the shared variable once:

```zig
// Global flags shared by all completion functions (emitted once; NP-029)
try w.print("_{s}_global_flags=\"", .{safe_name});
for (command.global_flags, 0..) |*gflag, gi| {
    if (gi > 0) try w.writeAll(" ");
    const esc_gname = try escapeBashDoubleQuote(esc_alloc, gflag.name);
    try w.print("--{s}", .{esc_gname});
    if (gflag.short) |s| {
        try w.print(" -{c}", .{s});
    }
}
try w.writeAll("\"\n\n");
```

In `generateCommandFunction`, replace lines 194-204 with:

```zig
// Global flags: reference the shared variable emitted once at top level
try w.print("    local global_flags=\"${{_{s}_global_flags}}\"\n", .{root_name});
```

(`root_name` is already the sanitized identifier — verify it's `safe_name` passed through recursion; it is, per line 126.)

- [ ] **Step 4: Run `zig build test --summary all`; also run `zig build scale-bench` if quick and note bash completion output size drop in the commit body (expected ~1.9x → ~1.0x vs zsh at 128 subcmds).**
- [ ] **Step 5: Commit:** `perf(completion): emit bash global flags once instead of per-subcommand` + `Refs: #124`

---

### Task 11: parallel — worker-aware chunking + atomic pool_started (#125 NP-030, #139 NQ-NEW-016)

**Files:**

- Modify: `src/parallel.zig:71-97, 144-198`

- [ ] **Step 1: Failing test** (parallel.zig):

```zig
test "chunk count is bounded by worker count, not item count" {
    try std.testing.expectEqual(@as(usize, 1), computeNumChunks(8, 1));
    try std.testing.expectEqual(@as(usize, 8), computeNumChunks(64, 4));   // 4 workers * 2 = 8 chunks
    try std.testing.expectEqual(@as(usize, 16), computeNumChunks(16, 32)); // never more chunks than items
    try std.testing.expectEqual(@as(usize, 64), computeNumChunks(10_000, 64)); // MAX_CHUNKS cap
}
```

- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement:**

```zig
var pool_workers: usize = 1;
var pool_started: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub fn initPool(config: PoolConfig) void {
    if (!tp_enabled) return;
    if (pool_started.load(.acquire)) return;

    const max: usize = if (config.worker_count) |n| n else 0;
    pool = tp.ThreadPool.init(std.heap.page_allocator, .{
        .max_threads = max,
    }) catch @panic("thread-pool: init failed");
    pool_workers = if (max > 0) max else (std.Thread.getCpuCount() catch 1);
    pool_started.store(true, .release);
}

pub fn deinitPool() void {
    if (!tp_enabled) return;
    if (!pool_started.load(.acquire)) return;
    pool_started.store(false, .release);
    pool.deinit();
}

/// Number of chunks: ~2 chunks per worker for load balancing, never more
/// than items or MAX_CHUNKS, never zero.
fn computeNumChunks(item_count: usize, workers: usize) usize {
    const by_workers = @max(workers, 1) * 2;
    return @max(@min(@min(item_count, MAX_CHUNKS), by_workers), 1);
}
```

Update `forEach` line 124 to `pool_started.load(.acquire)` and `tpForEach` line 153 to:

```zig
const num_chunks = computeNumChunks(items.len, pool_workers);
```

(Keep `MAX_CHUNKS`-sized stack arrays — num_chunks ≤ MAX_CHUNKS holds.)

- [ ] **Step 4: Run `zig build test --summary all` — PASS (parallel tests exercise forEach).**
- [ ] **Step 5: Commit:** `perf(parallel): bound forEach chunk count by worker count; make pool_started atomic` + `Refs: #125 #139`

---

### Task 12: Parser error-handling — OOM propagation, invalid defaults, env error cap, state reset (#39 GAP-0097, #140 NQ-NEW-011/013)

**Files:**

- Modify: `src/cli/parser.zig:474-507` (applyEnvDefaultsForCommand), `:540-551` (applyDefaultsForCommand), env_parse_errors struct fields, `parse()` entry point

- [ ] **Step 1: Failing tests** (parser.zig — find existing env-default tests and copy the harness idiom, e.g. how they inject env or skip if not injectable; if env injection isn't testable, test `applyDefaultsForCommand` instead and cover env paths by signature change compile-success):

```zig
test "parser: invalid default_str surfaces InvalidValue with flag name" {
    const cmd = Command{
        .name = "t",
        .summary = "s",
        .flags = &.{.{ .name = "n", .help = "h", .ftype = .int, .default_str = "not-a-number" }},
    };
    var parser = Parser.init(&cmd, std.testing.allocator); // match the real Parser construction from neighboring tests
    defer parser.deinit();
    const result = parser.parse(&.{});
    try std.testing.expectError(ParseError.InvalidValue, result);
    try std.testing.expectEqualStrings("n", parser.invalid_default_flag.?);
}

test "parser: error state is reset between parse calls" {
    // First parse sets error state; second parse on valid input must succeed
    // and expose no stale error fields.
    const cmd = Command{
        .name = "t",
        .summary = "s",
        .flags = &.{.{ .name = "x", .help = "h", .ftype = .int }},
    };
    var parser = Parser.init(&cmd, std.testing.allocator);
    defer parser.deinit();
    _ = parser.parse(&.{ "--x", "bad" }) catch {};
    var ctx = try parser.parse(&.{ "--x", "1" });
    defer ctx.deinit();
    try std.testing.expectEqual(@as(usize, 0), parser.env_parse_error_count);
    try std.testing.expect(parser.missing_required_flag == null);
    try std.testing.expect(parser.invalid_default_flag == null);
}
```

(Adapt construction/parse signatures to the file's real API — read the top of parser.zig and existing tests first. The behavioral assertions are the contract.)

- [ ] **Step 2: Run — FAIL (field undefined / wrong behavior).**
- [ ] **Step 3: Implement:**

1. Add field `invalid_default_flag: ?[]const u8 = null` and `env_parse_errors_dropped: usize = 0` next to the existing error-state fields (find `missing_required_flag` declaration).
2. `applyDefaultsForCommand` line 547:

    ```zig
    const fval = self.parseValue(flag.ftype, def) catch {
        // An unparseable default is a programmer error in the command
        // definition: fail loudly instead of silently skipping (GAP-0097).
        self.invalid_default_flag = flag.name;
        return ParseError.InvalidValue;
    };
    ```

3. `applyEnvDefaultsForCommand`: change return type to `ParseError!void`; line 503 becomes `try self.setFlagValue(ctx, flag.name, fval);` (OOM now propagates); in the env-parse-failure branch, when the array is full increment `self.env_parse_errors_dropped += 1;`. Update both call sites (line 474 and the subcommand-resolution call near line 261) to `try`.
4. Add a private `resetErrorState`:

    ```zig
    fn resetErrorState(self: *Self) void {
        self.env_parse_error_count = 0;
        self.env_parse_errors_dropped = 0;
        self.missing_required_flag = null;
        self.invalid_default_flag = null;
        // reset any other per-parse error fields found adjacent to these
    }
    ```

    and call it first thing in the public `parse()` entry point. Grep parser.zig for ALL mutable per-parse diagnostic fields (e.g. unknown-flag name capture) and include them.
5. Wherever env parse errors are rendered to the user (search for use of `env_parse_errors`), append `(+{d} more)` when `env_parse_errors_dropped > 0`.

- [ ] **Step 4: Run `zig build test --summary all` + `zig build test-integration --summary all` — PASS. (If any existing test relied on bad defaults being skipped, fix the test's command definition — a bad default is now an error by design; note it in CHANGELOG in Task 15.)**
- [ ] **Step 5: Commit:** `fix(parser): propagate OOM from env defaults, error on invalid default_str, cap-count env errors, reset error state per parse` + `Refs: #39 #140`

---

### Task 13: Prompt — Windows no-echo guarantee + freeSecret helper (#130 NS-059, #40 GAP-0099)

**Files:**

- Modify: `src/prompt.zig:222-258` (password Windows branch), new helper + doc update near line 188

- [ ] **Step 1: Failing test** (POSIX-runnable part only — the Windows branch is comptime-gated; test the helper):

```zig
test "freeSecret zeroes before freeing" {
    const allocator = std.testing.allocator;
    const secret = try allocator.dupe(u8, "hunter2");
    // capture the pointer before free to verify zeroing happened first is not
    // observable after free; instead verify via a wrapper allocation pattern:
    // freeSecret must compile with []const u8 and not leak (testing.allocator
    // fails the test on leaks).
    freeSecret(allocator, secret);
}
```

- [ ] **Step 2: Run — FAIL (undefined).**
- [ ] **Step 3: Implement:**

freeSecret (after `password`):

```zig
/// Zero a secret buffer returned by `password()` (or any secret slice you
/// own) and free it. Zeroing uses a volatile pointer write pattern via
/// `std.crypto.secureZero` so the compiler cannot elide it.
pub fn freeSecret(allocator: std.mem.Allocator, secret: []const u8) void {
    const mutable = @constCast(secret);
    std.crypto.secureZero(u8, mutable);
    allocator.free(mutable);
}
```

(Verify `std.crypto.secureZero` exists in 0.16 — it does as `std.crypto.secureZero(comptime T, slice)`; if signature differs use `std.crypto.utils.secureZero` per the toolchain's std.)

Windows branch — replace the echoed fallback at lines 237-240:

```zig
} else {
    // GetConsoleMode failed: we cannot guarantee echo suppression.
    // Refuse rather than silently echoing the password (NS-059).
    return PromptError.NotInteractive;
}
```

Update the `password` doc comment (lines 188-197) to recommend `freeSecret`:

```zig
/// The returned slice is heap-allocated. Free it with `freeSecret()` to
/// guarantee the password is zeroed before the memory is released:
///
///     const pw = try prompt.password("Password: ", allocator);
///     defer prompt.freeSecret(allocator, pw);
```

- [ ] **Step 4: Run `zig build test --summary all` — PASS.**
- [ ] **Step 5: Commit:** `fix(prompt): refuse echoed Windows password fallback; add freeSecret zeroing helper` + `Refs: #130 #40`

---

### Task 14: Pager — fall back to direct output instead of losing content (#137 NQ-NEW-017)

**Files:**

- Modify: `src/term/pager.zig:92-111`

- [ ] **Step 1: Failing test.** The page function hits real TTY/subprocess paths; test the fallback decision via a refactor: extract the direct-write into `writeDirect(content) PageError!void` (it already exists inline 3 times — DRY it), and make the spawn-failure path call it. Add a test that an invalid pager binary falls back (runnable in CI without TTY only if line_count check passes — looking at line 50, non-TTY heights make content fit and short-circuit; so unit-test only the helper extraction compiles, and add the behavioral test for the tokenizer-empty path which already falls back):

```zig
test "page: empty PAGER value falls back to direct write (no error)" {
    // Existing behavior at :84-90 — keep as regression anchor if a test
    // doesn't already exist; otherwise extend it.
}
```

Primary verification for this task is behavioral-by-inspection + integration: `PAGER=/nonexistent zig build run-demo -- help` style manual check if a demo target exists (`zig build --help` lists steps; check for a demo/example run step).

- [ ] **Step 2: Implement:**

```zig
fn writeDirect(stdout: std.Io.File, io: std.Io, content: []const u8) PageError!void {
    var wbuf: [4096]u8 = undefined;
    var fw = stdout.writer(io, &wbuf);
    fw.interface.writeAll(content) catch return error.WriteFailed;
    fw.interface.flush() catch return error.WriteFailed;
}
```

(match the function's existing error set name — read the top of pager.zig for `PageError`/error set used; reuse it.)

Replace the three inline direct-write blocks (lines 50-56, 58-65, 84-90) with calls to `writeDirect`, and change the spawn/write path:

```zig
// Spawn pager process directly. On any spawn failure, fall back to
// direct output instead of losing the content (#137).
var child = std.process.Child.init(argv_buf[0..argv_len], std.heap.page_allocator);
child.stdin_behavior = .Pipe;
child.stdout_behavior = .Inherit;
child.stderr_behavior = .Inherit;

child.spawn() catch {
    return writeDirect(stdout, io, content);
};

var write_failed = false;
if (child.stdin) |stdin| {
    var wbuf: [4096]u8 = undefined;
    var fw = stdin.writer(io, &wbuf);
    fw.interface.writeAll(content) catch {
        write_failed = true;
    };
    fw.interface.flush() catch {
        write_failed = true;
    };
    stdin.close(io);
}

const term_result = child.wait() catch {
    if (write_failed) return writeDirect(stdout, io, content);
    return;
};
// If the pager could not consume our content (e.g. exec of an invalid
// PAGER failed after fork), re-emit directly. May duplicate partial
// output in rare mid-stream failures; losing content is worse.
const pager_failed = switch (term_result) {
    .Exited => |code| code != 0,
    else => true,
};
if (write_failed or pager_failed) {
    return writeDirect(stdout, io, content);
}
```

NOTE: `less` exits non-zero when the user quits with `q`? No — `less` exits 0 on normal quit. But Ctrl-C in less may exit non-zero; the duplicate-output tradeoff is documented in the comment. If existing integration tests cover pager behavior, run them.

- [ ] **Step 3: Run `zig build test --summary all` + `zig build test-integration --summary all` — PASS.**
- [ ] **Step 4: Commit:** `fix(term): pager falls back to direct output on spawn/exec/write failure` + `Refs: #137`

---

### Task 15: Version single-sourcing + CHANGELOG + getBoolOpt (#106 NQ-NEW-003, #135 NQ-NEW-006, #138 NQ-NEW-012)

**Files:**

- Modify: `build.zig` (version parsing + options wiring), `src/root.zig:66-67`, `CHANGELOG.md`, `src/cli/command.zig:226-235`

- [ ] **Step 1: build.zig — parse the manifest version** (add near the top of `build`, after the existing `build_options` block at lines 36-38):

```zig
// Single-source the library version from build.zig.zon (#106 / NQ-053).
const manifest_version = blk: {
    const src = b.build_root.handle.readFileAlloc(b.allocator, "build.zig.zon", 64 * 1024) catch
        @panic("cannot read build.zig.zon");
    const key = ".version = \"";
    const start = (std.mem.indexOf(u8, src, key) orelse @panic("no .version in build.zig.zon")) + key.len;
    const end = std.mem.indexOfScalarPos(u8, src, start, '"') orelse @panic("unterminated .version");
    break :blk src[start..end];
};
build_options.addOption([]const u8, "version", manifest_version);
```

(Verify `readFileAlloc` parameter order for Zig 0.16's `std.fs.Dir` — if it is `readFileAlloc(sub_path, allocator, ...)` or returns differently, adapt; the goal is "read build.zig.zon into a string".)

Wire `build_options_mod` into every module that compiles `src/root.zig` as root source: `zig_cli_mod` (line 92-98: add `zig_cli_mod.addImport("build_options", build_options_mod);`) and the root tests module (lines 161-169: same addImport). Grep build.zig for other `root.zig` usages (docs step, examples) and wire those too.

- [ ] **Step 2: src/root.zig:**

```zig
/// Library version (single-sourced from build.zig.zon via build options)
pub const version = @import("build_options").version;
```

Add test in root.zig:

```zig
test "version is a semantic version" {
    _ = try std.SemanticVersion.parse(version);
}
```

- [ ] **Step 3: Run `zig build test --summary all` — PASS; confirm `version` resolves to "0.1.4" (e.g. temporary `std.debug.print` in the test or assert equality with the zon — assert: `try std.testing.expect(std.mem.eql(u8, version, "0.1.4"));` is WRONG long-term (re-introduces drift); keep only the semver-parse assertion).**
- [ ] **Step 4: CHANGELOG.md — add entries for v0.1.2, v0.1.3, v0.1.4.** Generate content from git history: `git log --oneline v0.1.1..v0.1.2`, `v0.1.2..v0.1.3`, `v0.1.3..v0.1.4` (check `git tag -l` for exact tag names). Follow the existing CHANGELOG format. Also add an Unreleased section noting this audit-fix batch including the behavioral change from Task 12 ("invalid flag default_str now returns ParseError.InvalidValue instead of being silently skipped") and Task 13 ("Windows password() now returns NotInteractive when echo suppression is unavailable").
- [ ] **Step 5: getBoolOpt in command.zig (after getBool at :227-235):**

```zig
/// Get a boolean flag value, or null when the flag was not provided.
/// `getBool` collapses "absent" to `false` for ergonomic everyday use;
/// use this variant when you must distinguish absent from false.
pub fn getBoolOpt(self: *const Context, name: []const u8) ?bool {
    if (self.getFlag(name)) |v| {
        return switch (v) {
            .bool => |b| b,
            else => null,
        };
    }
    return null;
}
```

With test (copy the Context-construction idiom from the `getFloat` tests at command.zig:666-682):

```zig
test "Context getBoolOpt distinguishes absent from false" {
    // construct ctx with one bool flag set to false, mirror getFloat tests
    // assert: getBoolOpt("set-flag") == false (not null)
    // assert: getBoolOpt("missing") == null
}
```

(Write the real construction by copying the neighboring test bodies.)

- [ ] **Step 6: Run `zig build test --summary all` — PASS. Commit:** `fix(build): single-source version from build.zig.zon; document missing releases; add Context.getBoolOpt` + `Refs: #106 #135 #138`

---

### Task 16: Documentation truth-fixes + wordWrap nit (F-02, F-07, F-08, NQ-NEW-018, #141, NP-033)

**Files:**

- Modify: `src/cli/command.zig:33-51, 187-204`, `src/util/fs.zig` (isSafePath + writeFileAtomic doc comments), `src/signal.zig` (onCleanup doc), `src/term/tty.zig` (pub API doc comments), `src/root.zig:73+` (alias docs), `src/util/text.zig:36-39`, `SECURITY.md`

- [ ] **Step 1: command.zig — correct the secret-zeroing claims (F-02/NS-016).** Replace doc list item at line 44-45:

```zig
/// 4. On `Context.deinit()`, string flag value *references* are cleared
///    from the flag map. The referenced bytes live in OS-owned argv/environ
///    memory and CANNOT be scrubbed by this library; OS-level exposure of
///    argv (e.g. /proc/<pid>/cmdline) is inherent. This is why secret
///    values must never be passed via flags or env in the first place.
```

And the `deinit` doc + inline comment (187-199):

```zig
/// Deinitialize the context.
/// String flag value references are dropped from the map. NOTE: the
/// underlying bytes are argv/environ-backed and are NOT zeroed — they
/// cannot be scrubbed from library code. See SecretPolicy docs.
```

(keep the `val.* = FlagValue{ .string = "" };` code — it is harmless reference-dropping; only the claims change).

- [ ] **Step 2: fs.zig — re-scope isSafePath + writeFileAtomic docs (F-07/F-08).** Read the current doc comments at `fs.zig:155` and `:83` first. Prepend to `isSafePath` docs:

```zig
/// SECURITY NOTE: This is a best-effort DENYLIST of obviously sensitive
/// paths, NOT a security boundary. It performs no canonicalization and
/// does not resolve symlinks: `/etc//shadow`, `./../etc/shadow` via cwd,
/// or a symlink to a sensitive file all PASS this check. Callers needing
/// a real guarantee must canonicalize (`realpathAlloc`) and validate
/// against an allowlisted root directory.
```

Append to `writeFileAtomic` docs:

```zig
/// SECURITY NOTE: The temp file and rename are resolved via cwd-relative
/// paths on each call. Callers should only target directories they
/// control; a hostile writable parent directory permits classic
/// parent-dir TOCTOU swaps between create and rename.
```

- [ ] **Step 3: signal.zig — onCleanup doc (NQ-NEW-018).** Find the `onCleanup` doc comment; ensure it states callbacks run in *normal* context from `pollSignals()` (flag-and-poll), and remove/correct any claim that callbacks run "on signal delivery" or imply async-signal-safety requirements. State: "Callbacks are invoked from `pollSignals()` in normal execution context — they may allocate, lock, and print. They do NOT run inside a signal handler."
- [ ] **Step 4: tty.zig + root.zig doc comments (#141).** Add `///` doc comments to every `pub` fn/type in `src/term/tty.zig` lacking one (describe return semantics incl. the `null` non-TTY cases). In `src/root.zig`, add one-line doc comments to the convenience re-export groups (a `///` on each alias or a section comment is fine — follow existing style at lines 73-79).
- [ ] **Step 5: SECURITY.md — trust-model statement (F-01 contract).** Add a short section:

```markdown
## Command metadata trust model

Command/flag metadata (`name`, `summary`, `help`, `examples`, ...) is
normally authored by the application developer at compile time and is
treated as trusted for layout purposes. As defense-in-depth, all help,
table, progress, and error output strips terminal control bytes
(C0 controls except `\n`/`\t`, and DEL), so escape-sequence injection
(CWE-150) is neutralized even when metadata originates from untrusted
sources (plugin manifests, registries). Markdown/roff/JSON/completion
generators apply context-specific escaping. If you render untrusted
strings through other paths, sanitize them with
`util.text.stripControlChars`.
```

- [ ] **Step 6: text.zig wordWrap nit (NP-033)** — at line 38 (no-space break path), add `last_space = null;` after `line_start = i;` for clarity/correctness symmetry.
- [ ] **Step 7: Run `zig build test --summary all` (docs compile via `zig build check` too) — PASS. Commit:** `docs: correct secret-zeroing claims, scope isSafePath/writeFileAtomic guarantees, fix onCleanup contract, document trust model` + `Refs: #141`

---

### Task 17: Markdown/pre-commit hygiene (#134 NQ-NEW-001/002/005)

**Files:**

- Modify: `docs/API.md`, `docs/guides/TABLE_FORMATTING.md`, `docs/guides/FLAG_VALIDATION.md`, `docs/guides/ACTIVE_HELP.md`, `docs/guides/CONFIG_PRECEDENCE.md`, `README.md`, `.gitlab/issue_templates/*.md`, `docs/GAP_CLOSURE_ROUND2_REPORT.md:25`, `SECURITY.md`, `scripts/detect_diamond_deps.py`

- [ ] **Step 1: Run `pre-commit run --all-files` — capture the failures (expected: markdownlint MD040/MD056, trailing-whitespace, end-of-file-fixer, ruff-format).** Let the auto-fixers fix whitespace/EOF/ruff.
- [ ] **Step 2: Fix MD040 manually:** every fenced code block flagged needs a language tag — use `zig` for Zig code, `bash`/`sh` for shell, `text` for output/plain. 16 violations across the files listed above (re-run markdownlint to enumerate exactly).
- [ ] **Step 3: Fix MD056 at `docs/GAP_CLOSURE_ROUND2_REPORT.md:25`** — make the table row's column count match its header.
- [ ] **Step 4: Re-run `pre-commit run --all-files` until fully green.** Note: hooks like gitleaks must also pass.
- [ ] **Step 5: Commit:** `chore(docs): fix markdownlint violations, whitespace, EOF, and python formatting` + `Refs: #134`

---

### Task 18: Full verification gate

- [ ] Run ALL of (each must pass):

```bash
zig fmt --check src/ tests/ build.zig
zig build check
zig build test --summary all
zig build test-integration --summary all
zig build bench   # sanity only; record numbers
pre-commit run --all-files
```

- [ ] Run `zig build scale-bench` and compare bash-completion numbers against `benchmarks/results/baseline.json` expectations (NP-029 should improve; nothing should regress >10%).
- [ ] Fix anything that fails (small fixups amend into the responsible commit or a final `fix:` commit).
- [ ] Do NOT merge/push in this task — the orchestrator handles branch integration after review.

---

## Explicitly Deferred (tracked, not in this plan)

- **GAP-0096 (#34):** splitting `help.zig`/`parser.zig`/`command.zig` (>800-line guidance) and **NQ-NEW-014** generator-duplication refactor — separate refactor plan after this batch lands.
- **NQ-NEW-021 (#142):** broader adversarial test suite — partially covered by the regression tests above; remainder rides with the refactor plan.
- **GAP-0083 (#12):** package-registry publication — v0.2.0 roadmap feature, not an audit defect.
- **F-10:** appsec review of the external `config` dependency — separate repo.
