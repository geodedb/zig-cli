# Gap Analysis: zig-cli vs Cobra

This document provides a detailed analysis of feature gaps between zig-cli and [Cobra](https://github.com/spf13/cobra), the industry-standard Go CLI framework. Each gap is tracked as a GitLab issue for implementation.

## Executive Summary

zig-cli implements most of Cobra's core functionality:
- Command/subcommand structure with aliases
- Comprehensive flag parsing
- Help and completion generation
- Configuration file support (via zig-config, equivalent to Viper)

**11 gaps** have been identified and tracked:

| Priority | Count | Examples |
|----------|-------|----------|
| High | 6 | Persistent hooks, flag groups, positional validators |
| Medium | 5 | Command groups, Markdown docs, version command |

## Gap Details

### High Priority Gaps

#### 1. PowerShell Completion ([#13](https://gitlab.com/devnw/zig/cli/-/issues/13))

**What Cobra Has:**
PowerShell completion scripts for Windows users, supporting command, flag, and value completion.

**Current State:**
zig-cli supports bash, zsh, and fish completions. PowerShell is missing.

**Impact:**
Windows users without WSL cannot use shell completion.

**Implementation Notes:**
- Add `src/cli/completion/powershell.zig`
- Use PowerShell's `Register-ArgumentCompleter` API
- Reference: [Cobra PowerShell implementation](https://github.com/spf13/cobra/blob/main/powershell_completions.go)

---

#### 2. Persistent Hooks ([#14](https://gitlab.com/devnw/zig/cli/-/issues/14))

**What Cobra Has:**
```go
rootCmd.PersistentPreRun = func(cmd *cobra.Command, args []string) {
    // Runs before ANY command in the tree
    initLogging()
}
```

**Current State:**
zig-cli has `pre_run` and `post_run` hooks, but they only run for the specific command that defines them. Hooks do not cascade to child commands.

**Impact:**
Common patterns like database connection setup at root level require manual propagation.

**Implementation Notes:**
- Add `persistent_pre_run` and `persistent_post_run` to Command struct
- Collect hooks from parent chain during execution
- Execute in order: parent persistent hooks -> child hooks -> run -> reverse order for post

---

#### 3. Flag Groups ([#16](https://gitlab.com/devnw/zig/cli/-/issues/16))

**What Cobra Has:**
```go
cmd.MarkFlagsMutuallyExclusive("json", "yaml", "table")
cmd.MarkFlagsRequiredTogether("username", "password")
cmd.MarkFlagsOneRequired("config", "inline")
```

**Current State:**
No flag group validation. Users can pass conflicting flags without error.

**Impact:**
Applications must manually validate flag combinations in run functions.

**Implementation Notes:**
- Add `flag_groups` field to Command struct
- Support types: mutually_exclusive, required_together, one_required
- Validate during parsing, before command execution

---

#### 4. Positional Argument Validators ([#17](https://gitlab.com/devnw/zig/cli/-/issues/17))

**What Cobra Has:**
```go
cmd.Args = cobra.ExactArgs(1)           // Exactly 1 arg
cmd.Args = cobra.MinimumNArgs(2)        // At least 2 args
cmd.Args = cobra.RangeArgs(1, 3)        // Between 1 and 3 args
cmd.Args = cobra.NoArgs                 // No args allowed
cmd.Args = cobra.OnlyValidArgs          // Only from ValidArgs list
```

**Current State:**
No built-in argument count validation. Commands must check manually.

**Impact:**
Commands accept arbitrary positional arguments even when they shouldn't.

**Implementation Notes:**
- Add `args` field to Command struct with union type
- Implement validators: none, exact, minimum, maximum, range, only_valid
- Validate after parsing, before hooks

---

#### 5. Flag Value Completion ([#22](https://gitlab.com/devnw/zig/cli/-/issues/22))

**What Cobra Has:**
```go
cmd.RegisterFlagCompletionFunc("format", func(cmd *cobra.Command, args []string, toComplete string) ([]string, cobra.ShellCompDirective) {
    return []string{"json", "yaml", "table"}, cobra.ShellCompDirectiveNoFileComp
})
```

**Current State:**
Completions only suggest flag names, not their possible values.

**Impact:**
Users must remember valid values for flags like `--format`, `--log-level`.

**Implementation Notes:**
- Add `completions` field to FlagSpec for static values
- Add `complete_fn` for dynamic value completion
- Path-type flags should auto-complete filesystem paths

---

#### 6. Package Registry Publishing ([#12](https://gitlab.com/devnw/zig/cli/-/issues/12))

**What Cobra Has:**
Available via `go get github.com/spf13/cobra`.

**Current State:**
Manual installation via git URL required.

**Impact:**
Friction for new users; not discoverable in package searches.

**Implementation Notes:**
- Register with Zig package registry
- Ensure build.zig.zon follows conventions
- Add package metadata

---

### Medium Priority Gaps

#### 7. Command Groups ([#15](https://gitlab.com/devnw/zig/cli/-/issues/15))

**What Cobra Has:**
```go
rootCmd.AddGroup(&cobra.Group{ID: "core", Title: "Core Commands:"})
serveCmd.GroupID = "core"
```

Help output:
```
Available Commands:

Core Commands:
  serve       Start the server
  build       Build the project

Utility Commands:
  completion  Generate shell completions
  version     Print version information
```

**Current State:**
All subcommands listed in a flat list.

**Impact:**
CLIs with many commands become hard to navigate.

---

#### 8. Markdown Documentation Generation ([#18](https://gitlab.com/devnw/zig/cli/-/issues/18))

**What Cobra Has:**
```go
doc.GenMarkdownTree(rootCmd, "./docs")
```

**Current State:**
Man page generation only.

**Impact:**
Cannot auto-generate documentation for GitHub/GitLab wikis or static sites.

---

#### 9. Custom Help Templates ([#19](https://gitlab.com/devnw/zig/cli/-/issues/19))

**What Cobra Has:**
```go
cmd.SetUsageTemplate(`Usage: {{.CommandPath}} [options] <args>
{{if .HasAvailableSubCommands}}
Commands:
{{range .Commands}}  {{.Name}}{{end}}
{{end}}`)
```

**Current State:**
Fixed help format, no customization.

**Impact:**
Cannot match corporate style guides or add custom sections.

---

#### 10. Active Help ([#20](https://gitlab.com/devnw/zig/cli/-/issues/20))

**What Cobra Has:**
Dynamic hints during shell completion:
```
$ myapp get user<TAB>
user/123  (recently accessed)
user/456  (frequently used)
_         Hint: Use --format=json for scripting
```

**Current State:**
Static completion only.

**Impact:**
Cannot provide context-aware suggestions or tips.

---

#### 11. Version Command with Build Metadata ([#21](https://gitlab.com/devnw/zig/cli/-/issues/21))

**What Cobra Has:**
```
$ myapp version
myapp version 1.2.3
Commit: a1b2c3d
Built: 2024-01-15T10:30:00Z
Go: 1.21.5
```

**Current State:**
`--version` flag returns version string only.

**Impact:**
Debug information not available; CI/CD tracking harder.

---

#### 12. Environment Variables in Help ([#23](https://gitlab.com/devnw/zig/cli/-/issues/23))

**What Cobra Has:**
Environment variables documented in help output.

**Current State:**
`env` field on FlagSpec exists but not displayed in help.

**Impact:**
Users must read source or documentation to discover env vars.

---

## Features Unique to zig-cli

zig-cli provides several features not found in Cobra:

| Feature | Description |
|---------|-------------|
| **Secret Handling Policy** | Flags can require values from file/stdin only, rejecting command-line input |
| **Progress Indicators** | Built-in spinners and progress bars with TTY awareness |
| **Interactive Prompts** | Input, password, confirm, select, multi-select prompts |
| **Pager Integration** | Automatic less pager for long output |
| **Path Redaction** | Sensitive paths auto-redacted in error messages |
| **Provenance Tracking** | Track exactly where each config value originated |

## Contributing

To work on a gap:

1. Comment on the issue to claim it
2. Read existing related code
3. Write tests first
4. Implement the feature
5. Update documentation
6. Submit merge request

See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed guidelines.
