# Shell Completions Guide

This guide explains how to generate and install shell completion scripts.

## Generating Completions

```zig
const cli = @import("cli");

const root_cmd = cli.Command{
    .name = "myapp",
    .summary = "My application",
    // ...
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // Generate for different shells
    const bash = try cli.generateCompletions(.bash, &root_cmd, gpa.allocator());
    defer gpa.allocator().free(bash);

    const zsh = try cli.generateCompletions(.zsh, &root_cmd, gpa.allocator());
    defer gpa.allocator().free(zsh);

    const fish = try cli.generateCompletions(.fish, &root_cmd, gpa.allocator());
    defer gpa.allocator().free(fish);
}
```

## Adding a Completion Subcommand

```zig
const completion_cmd = cli.Command{
    .name = "completion",
    .summary = "Generate shell completion script",
    .flags = &.{
        cli.FlagSpec{
            .name = "shell",
            .short = 's',
            .help = "Shell type (bash, zsh, fish)",
            .ftype = .string,
            .required = true,
        },
    },
    .run = runCompletion,
};

fn runCompletion(ctx: *cli.Context) !void {
    const shell_str = ctx.getString("shell").?;

    const shell: enum { bash, zsh, fish } = blk: {
        if (std.mem.eql(u8, shell_str, "bash")) break :blk .bash;
        if (std.mem.eql(u8, shell_str, "zsh")) break :blk .zsh;
        if (std.mem.eql(u8, shell_str, "fish")) break :blk .fish;
        try ctx.err("Unknown shell: {s}\n", .{shell_str});
        return;
    };

    const script = try cli.generateCompletions(shell, &root_cmd, ctx.allocator);
    defer ctx.allocator.free(script);

    try ctx.stdout.writeAll(script);
}
```

## Installation Instructions

### Bash

```bash
# System-wide
myapp completion --shell bash | sudo tee /etc/bash_completion.d/myapp

# User only
myapp completion --shell bash > ~/.local/share/bash-completion/completions/myapp
```

### Zsh

```bash
# Oh My Zsh
myapp completion --shell zsh > ~/.oh-my-zsh/completions/_myapp

# Without Oh My Zsh
mkdir -p ~/.zsh/completions
myapp completion --shell zsh > ~/.zsh/completions/_myapp
echo 'fpath=(~/.zsh/completions $fpath)' >> ~/.zshrc
echo 'autoload -U compinit && compinit' >> ~/.zshrc
```

### Fish

```bash
myapp completion --shell fish > ~/.config/fish/completions/myapp.fish
```

## What Gets Completed

The generated scripts provide completion for:

1. **Subcommands** at each level
2. **Long flags** (`--verbose`, `--config`)
3. **Short flags** (`-v`, `-c`)
4. **Flag values** (file paths for `.path` type flags)

## Customizing Completions

The completion generators use command metadata:

```zig
const cmd = cli.Command{
    .name = "serve",
    .summary = "Start the server",  // Used in completion descriptions
    .hidden = false,                 // Hidden commands excluded
    .flags = &.{
        cli.FlagSpec{
            .name = "config",
            .ftype = .path,  // Triggers file completion
        },
    },
};
```

## Testing Completions

### Bash

```bash
source <(myapp completion --shell bash)
myapp <TAB><TAB>  # Shows subcommands
myapp --<TAB>     # Shows flags
```

### Zsh

```zsh
source <(myapp completion --shell zsh)
myapp <TAB>       # Shows subcommands with descriptions
myapp --<TAB>     # Shows flags with descriptions
```

### Fish

```fish
myapp completion --shell fish | source
myapp <TAB>       # Shows subcommands
complete -c myapp # Shows all completions
```

## Best Practices

1. **Always include a completion subcommand** in your CLI
2. **Document installation** in your README
3. **Test completions** on each target shell
4. **Keep flag names consistent** for predictable completion
5. **Use descriptive summaries** - they appear in zsh/fish completions
