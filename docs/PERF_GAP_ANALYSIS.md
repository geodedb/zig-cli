# Performance Gap Analysis

> Auto-generated from full codebase audit (2026-03-24). Updated 2026-03-25 with Phase 3 perf-reviewer round 2 findings (NP-019 through NP-028).

Last updated: 2026-03-25

## Summary

| PerfSeverity | Open | Closed | Won't Do |
|-------------|------|--------|----------|
| P1 | 0 | 4 | 1 |
| P2 | 0 | 19 | 3 |
| P3 | 0 | 15 | 2 |
| Info | 0 | 2 | 0 |
| **Total** | **0** | **40** | **6** |

**10 findings from Phase 3 perf-reviewer round 2 (2026-03-25) -- all resolved.** Top 5 risks (now closed/won't do):

1. **NP-019 (P1, PerfScore 60):** printHelp 50-80 write(2) syscalls -- BufferedWriter wrap yields 50-75% improvement. Depends on NP-003 (Won't Do) but is a viable local workaround.
2. **NP-020 (P2, PerfScore 45):** Context.flags HashMap starts at capacity 0 -- 1 resize+rehash per parse. Pre-allocate saves ~30-80ns.
3. **NP-021 (P2, PerfScore 40):** writeRoffEscaped byte-at-a-time -- same span-based fix as NP-017 (closed). 20-40% man generation improvement.
4. **NP-028 (P2, PerfScore 30):** printJsonHelp same syscall pattern as NP-019. Automatically fixed if NP-019 applied at Context level.
5. **NP-022 (P2, PerfScore 20):** printSectionCommands O(groups * subcommands) nested loop. Low practical impact for typical CLIs.

## Stack-Ranked Findings

| Rank | PerfSeverity | PerfScore | Finding | Component | Evidence | Measurement | Issue URL | Fix Summary | Owner | SLA/Due | Status |
|------|-------------|-----------|---------|-----------|----------|-------------|-----------|-------------|-------|---------|--------|
| 1 | P1 | 80 | DeprecatedWriter -> buffered Writer | command.zig, progress.zig, prompt.zig | `command.zig:89,91` uses `DeprecatedWriter` | Est. 4-10x help throughput | [#41](https://gitlab.com/devnw/zig/cli/-/work_items/41) | Replace with `std.io.bufferedWriter` | Core maintainer | Within sprint | Won't Do |
| **2** | **P1** | **60** | **printHelp 50-80 write(2) syscalls via DeprecatedWriter** | **help.zig** | **`help.zig:180-204` multiple writeAll/print per section** | **19us -> est. 5-10us (50-75% improvement)** | **[#103](https://gitlab.com/devnw/zig/cli/-/work_items/103)** | **Wrap ctx.stdout with BufferedWriter; flush at end** | **Help owner** | **Within sprint** | **Closed** |
| 3 | P1 | 60 | CI no Zig/apt caching | .gitlab-ci.yml | 10+ jobs re-download Zig each run | ~80-120s wasted/pipeline | [#45](https://gitlab.com/devnw/zig/cli/-/work_items/45) | Add `cache:` for zig-${ZIG_VERSION}/ | CI/DevOps | Within sprint | Closed |
| 4 | P2 | 48 | No benchmark regression gate | .gitlab-ci.yml | `bench-regression` stores but does not compare | Regressions pass silently | [#47](https://gitlab.com/devnw/zig/cli/-/work_items/47) | Add baseline comparison + threshold gate | CI/DevOps | Next quarter | Closed |
| 5 | P2 | 48 | Zero ensureTotalCapacity across 50+ ArrayList instances | parser.zig, completion/*.zig, text.zig, suggest.zig | Zero `ensureTotalCapacity` calls in src/; `bash.zig:91`, `command.zig:127` | ~10 reallocs/completion, 2-3 HashMap resizes/parse | [#65](https://gitlab.com/devnw/zig/cli/-/work_items/65) | Pre-allocate based on known sizes | Core maintainer | Next quarter | **Closed** |
| 6 | P2 | 45 | Levenshtein 255-char buffer overflow | suggest.zig | `suggest.zig:16` bounds check added | N/A -- prevented | -- | Bounds check: `if (b.len >= 256) return @max(a.len, b.len)` | Core maintainer | -- | **Closed** |
| 7 | P2 | 45 | Escape functions missing -- no fast-path scan | bash.zig, zsh.zig, fish.zig, powershell.zig | All 4 generators have escape functions with fast-path scan | Clean strings return immediately | -- | Escape functions with fast-path scan implemented | Completion owner | -- | **Closed** |
| **8** | **P2** | **45** | **Context.flags HashMap starts at capacity 0** | **command.zig** | **`command.zig:145` init with 0 capacity** | **1 resize+rehash per parse (~30-80ns)** | **[#105](https://gitlab.com/devnw/zig/cli/-/work_items/105)** | **`ensureTotalCapacity(8)` after init** | **Core maintainer** | **Next quarter** | **Closed** |
| **9** | **P2** | **40** | **writeRoffEscaped byte-at-a-time writeByte** | **help.zig** | **`help.zig:603-641` writeByte for non-special chars** | **Est. 20-40% man generation improvement** | **[#107](https://gitlab.com/devnw/zig/cli/-/work_items/107)** | **Span-based flushing (same pattern as NP-017)** | **Help owner** | **Next quarter** | **Closed** |
| 10 | P2 | 36 | Benchmarks test only trivial command trees (1-2 subcmds, 1-3 flags) | tests/bench.zig | `benchParse`: 1 subcmd/2 flags; `completionBenchCommand()`: 2 subcmds/1 flag | Missing 20+ subcmd, 50+ flag coverage | [#68](https://gitlab.com/devnw/zig/cli/-/work_items/68) | Add medium-scale bench variants | Bench owner | Next quarter | **Closed** |
| 11 | P2 | 35 | No ArenaAllocator in completion generators | bash.zig, zsh.zig, fish.zig, powershell.zig | ArenaAllocator in all 4 generators | Bulk deallocation enabled | -- | ArenaAllocator wraps internal work | Completion owner | -- | **Closed** |
| 12 | P2 | 32 | CountingAllocator + ArenaAllocator distorts benchmark alloc reporting | tests/bench.zig | `bench.zig:110-123` counter wraps backing allocator, not arena | "3 allocs/op" is arena->page_allocator artifact | [#66](https://gitlab.com/devnw/zig/cli/-/work_items/66) | Move counter to wrap arena allocator; reset between iterations | Bench owner | Next quarter | **Closed** |
| 13 | P2 | 32 | CI bench single-run noise sensitivity | .gitlab-ci.yml, tests/bench.zig | `.gitlab-ci.yml:226` single run, 20% threshold, no warmup | No statistical basis for threshold | [#70](https://gitlab.com/devnw/zig/cli/-/work_items/70) | Add warm-up, multi-run averaging, statistical analysis | CI/DevOps | Next quarter | **Closed** |
| 14 | P2 | 32 | Redundant global flags in bash completion scripts | bash.zig, (zsh.zig, powershell.zig already deduped) | `bash.zig:169-179` inlines global_flags per function | Output size scales with commands * global flags | [#73](https://gitlab.com/devnw/zig/cli/-/work_items/73) | Global flags single-sourced from command.global_flags | Completion owner | Next quarter | **Closed** |
| 15 | P2 | 32 | Escape fast-path dupe regression | bash.zig, zsh.zig, fish.zig, powershell.zig | Fast-path returns input slice directly | No allocation for clean strings | [#36](https://gitlab.com/devnw/zig/cli/-/work_items/36) | Resolved with GAP-P008 | Completion owner | -- | **Closed** |
| 16 | P2 | 32 | Help padding single-space writeAll | help.zig | 5 loops at `:179,:249,:265,:296,:324` | 2-30 syscalls per padded item | [#37](https://gitlab.com/devnw/zig/cli/-/work_items/37) | Use `writeByteNTimes` | Help owner | Within sprint | Closed |
| **17** | **P2** | **30** | **printJsonHelp many small writes via DeprecatedWriter** | **help.zig** | **`help.zig:519-572` 20+ writeAll/print calls** | **30-50 syscalls per JSON help render** | **[#113](https://gitlab.com/devnw/zig/cli/-/work_items/113)** | **BufferedWriter wrap (or auto-fix via NP-019 at Context level)** | **Help owner** | **Next quarter** | **Closed** |
| 18 | P2 | 30 | Pager `line_count` u16 overflow | pager.zig | `pager.zig:36` `var line_count: usize = 0` | N/A -- prevented | -- | Changed to `usize` | Pager owner | -- | **Closed** |
| 19 | P2 | 24 | JSON help writeJsonEscapedString byte-by-byte through DeprecatedWriter | help.zig | `help.zig:450-467` byte-by-byte `writeByte(c)`; `help.zig:471` via `ctx.stdout` | 100-500 syscalls per JSON help render | [#71](https://gitlab.com/devnw/zig/cli/-/work_items/71) | Span-based flush for non-special char runs | Help owner | Next quarter | **Closed** |
| 20 | P2 | 24 | useColor() allocating getEnvVarOwned | command.zig | `:215-224` heap-allocates for TERM, NO_COLOR | 2 alloc+free per useColor() call | -- | Use `env.zig` non-allocating helpers | Core maintainer | Next quarter | Closed |
| 21 | P2 | 24 | Progress bar char-at-a-time rendering | progress.zig | `:183-189` loop with `print("=",...)` | 40-80 write calls per render | [#50](https://gitlab.com/devnw/zig/cli/-/work_items/50) | Use `writeByteNTimes` | Term owner | Next quarter | Closed |
| 22 | P2 | 24 | Table writeHorizontalBorder char-at-a-time | table.zig | `:274` loop with `writeAll(horiz)` | N write calls per border row | -- | Use `writeByteNTimes` or pre-built string | Term owner | Next quarter | Won't Do |
| **23** | **P2** | **20** | **printSectionCommands O(groups * subcommands) nested loop** | **help.zig** | **`help.zig:274-313` outer groups, inner subcommands** | **Negligible for <50 subcmds** | **[#110](https://gitlab.com/devnw/zig/cli/-/work_items/110)** | **Pre-sort or pre-group subcommands** | **Help owner** | **Next quarter** | **Won't Do** |
| 24 | P3 | 18 | Duplicated group collection in help.zig | help.zig | `help.zig:220` `collectUniqueGroups()` extracted | Deduplicated | -- | `collectUniqueGroups()` helper extracted | Help owner | -- | **Closed** |
| 25 | P3 | 16 | Benchmarks lack allocation tracking | tests/bench.zig | CountingAllocator wraps arena | Allocation stats in output | -- | CountingAllocator vtable wrapper | Bench owner | Backlog | **Closed** |
| 26 | P3 | 16 | PagerWriter loads entire output into memory | pager.zig | `:78-` `PagerWriter` uses `ArrayList(u8)` to buffer all output | Memory proportional to help text | -- | Won't Do -- bounded by command tree size | Pager owner | -- | Won't Do |
| 27 | P3 | 16 | Byte-at-a-time ArrayList append in text.zig | text.zig | `text.zig:59,72,82,96,98` use `appendNTimes` | Single capacity check per pad | -- | `appendNTimes` replaces N individual appends | Util owner | -- | **Closed** |
| **28** | **P3** | **15** | **generateMan ArrayList no pre-allocation** | **help.zig** | **`help.zig:645-646` `ArrayList(u8) = .empty`** | **Multiple reallocs for typical man pages** | **--** | **`ensureTotalCapacity(4096)` after init** | **Help owner** | **Backlog** | **Closed** |
| **29** | **P3** | **15** | **generateMarkdown ArrayList no pre-allocation** | **help.zig** | **`help.zig:749-750` `ArrayList(u8) = .empty`** | **Multiple reallocs for typical markdown** | **--** | **`ensureTotalCapacity(4096)` after init** | **Help owner** | **Backlog** | **Closed** |
| 30 | P3 | 12 | `stripAnsi` byte-at-a-time append | color.zig | `color.zig:158` uses `appendSlice` for spans | Chunk-based copy | -- | Span tracking with `appendSlice` for non-ANSI chunks | Term owner | -- | **Closed** |
| **31** | **P3** | **8** | **Escape function ArrayListUnmanaged instances lack capacity hint** | **bash.zig, zsh.zig, fish.zig, powershell.zig** | **`bash.zig:33,68`, `zsh.zig:31,63`, etc.** | **Arena amortizes; minimal impact** | **--** | **Add capacity hint to escape ArrayListUnmanaged** | **Completion owner** | **Backlog** | **Closed** |
| **32** | **P3** | **5** | **wordWrap ArrayList no pre-allocation** | **text.zig** | **`text.zig:15` `ArrayList(u8) = .empty`** | **Minor reallocs on first wrap call** | **--** | **`ensureTotalCapacity(input.len)` after init** | **Util owner** | **Backlog** | **Closed** |
| **33** | **P3** | **5** | **Context.positionals and command_path start empty** | **command.zig** | **`command.zig:146-148` `.positionals = .empty, .command_path = .empty`** | **1 realloc each on first append** | **--** | **`ensureTotalCapacity` with small default** | **Core maintainer** | **Backlog** | **Closed** |
| 34 | Info | -- | Benchmark regression gate uses `allow_failure: true` | .gitlab-ci.yml | MR: blocking, main: soft | Regressions block MR merges | -- | Per-rule `allow_failure` in `rules:` | CI/DevOps | As capacity | **Closed** |
| 35 | Info | -- | CI `apt-get` packages not cached | .gitlab-ci.yml | Conditional `command -v` check | Skips install when tools present | -- | `if ! command -v curl` guard | CI/DevOps | As capacity | **Closed** |

## Findings by Area

### Area: App

| ID | PerfSeverity | PerfScore | Finding | Status |
|----|-------------|-----------|---------|--------|
| NP-003 | P1 | 80 | DeprecatedWriter -> buffered Writer | Won't Do |
| **NP-019** | **P1** | **60** | **printHelp 50-80 write(2) syscalls (BufferedWriter wrap)** | **Closed** |
| NP-013 | P2 | 48 | Zero ensureTotalCapacity across 50+ ArrayList instances | **Closed** |
| GAP-P003 | P2 | 45 | Levenshtein 255-char buffer overflow | **Closed** |
| GAP-P008 | P2 | 45 | Escape functions missing -- no fast-path scan | **Closed** |
| **NP-020** | **P2** | **45** | **Context.flags HashMap starts at capacity 0** | **Closed** |
| **NP-021** | **P2** | **40** | **writeRoffEscaped byte-at-a-time writeByte** | **Closed** |
| NP-015 | P2 | 36 | Benchmarks test only trivial command trees | **Closed** |
| GAP-P009 | P2 | 35 | No ArenaAllocator in completion generators | **Closed** |
| NP-014 | P2 | 32 | CountingAllocator + ArenaAllocator distorts alloc reporting | **Closed** |
| NP-018 | P2 | 32 | Redundant global flags in bash completion scripts | **Closed** |
| NP-001 | P2 | 32 | Escape fast-path dupe regression | **Closed** |
| NP-002 | P2 | 32 | Help padding single-space writeAll | Closed |
| **NP-028** | **P2** | **30** | **printJsonHelp many small writes (depends on NP-019)** | **Closed** |
| GAP-P004 | P2 | 30 | Pager `line_count` u16 overflow | **Closed** |
| NP-017 | P2 | 24 | JSON help writeJsonEscapedString byte-by-byte | **Closed** |
| NP-007 | P2 | 24 | useColor() allocating getEnvVarOwned | Closed |
| NP-008 | P2 | 24 | Progress bar char-at-a-time rendering | Closed |
| NP-009 | P2 | 24 | Table writeHorizontalBorder char-at-a-time | Won't Do |
| **NP-022** | **P2** | **20** | **printSectionCommands O(groups * subcommands)** | **Won't Do** |
| GAP-P013 | P3 | 18 | Duplicated group collection in help.zig | **Closed** |
| NP-010 | P3 | 16 | Benchmarks lack allocation tracking | **Closed** |
| NP-011 | P3 | 16 | Windows envVarExists uses page_allocator | Closed |
| NP-012 | P3 | 16 | PagerWriter loads entire output into memory | Won't Do |
| NEW-P001 | P3 | 16 | Byte-at-a-time ArrayList append in text.zig | **Closed** |
| **NP-023** | **P3** | **15** | **generateMan ArrayList no pre-allocation** | **Closed** |
| **NP-024** | **P3** | **15** | **generateMarkdown ArrayList no pre-allocation** | **Closed** |
| NEW-P002 | P3 | 12 | `stripAnsi` byte-at-a-time append | **Closed** |
| **NP-025** | **P3** | **8** | **Escape function ArrayListUnmanaged no capacity hint** | **Closed** |
| **NP-026** | **P3** | **5** | **wordWrap ArrayList no pre-allocation** | **Closed** |
| **NP-027** | **P3** | **5** | **Context.positionals and command_path start empty** | **Closed** |

### Area: CI

| ID | PerfSeverity | PerfScore | Finding | Status |
|----|-------------|-----------|---------|--------|
| NP-004 | P1 | 60 | CI no Zig/apt caching | Closed |
| NP-005 | P2 | 48 | No benchmark regression gate | Closed |
| NP-016 | P2 | 32 | CI bench single-run noise sensitivity | **Closed** |
| NEW-P003 | Info | -- | Benchmark regression gate uses `allow_failure: true` | **Closed** |
| NEW-P004 | Info | -- | CI `apt-get` packages not cached | **Closed** |

## Roadmap

### Quick Wins (< 1 day)

| ID | Finding | Effort | Expected Impact | Status |
|----|---------|--------|-----------------|--------|
| **NP-020** | **`ensureTotalCapacity(8)` for Context.flags HashMap** | **15 min** | **Save 1 resize+rehash per parse (~30-80ns)** | **Closed** |
| **NP-021** | **Span-based flushing for writeRoffEscaped** | **30 min** | **20-40% improvement for man generation** | **Closed** |
| **NP-023** | **generateMan `ensureTotalCapacity(4096)`** | **5 min** | **Eliminate early reallocs for man page buffer** | **Closed** |
| **NP-024** | **generateMarkdown `ensureTotalCapacity(4096)`** | **5 min** | **Eliminate early reallocs for markdown buffer** | **Closed** |
| **NP-025** | **Escape function ArrayListUnmanaged capacity hint** | **15 min** | **Reduce reallocs in escape functions (arena amortizes)** | **Closed** |
| **NP-026** | **wordWrap `ensureTotalCapacity(input.len)`** | **5 min** | **Eliminate reallocs on first wrap** | **Closed** |
| **NP-027** | **Context.positionals/command_path pre-alloc** | **10 min** | **Save 1 realloc each on first append** | **Closed** |
| ~~NP-017~~ | ~~Span-based writeJsonEscapedString~~ | ~~30 min~~ | ~~Reduce 100-500 syscalls to ~10 for JSON help~~ | **Closed** |
| ~~NP-018~~ | ~~Deduplicate global flags in bash completion~~ | ~~1 hr~~ | ~~Reduce output size by 10-20% for large CLIs~~ | **Closed** |
| GAP-P003 | Levenshtein bounds check guard | 15 min | Prevent UB in ReleaseFast for inputs >= 256 chars | **Closed** |
| GAP-P004 | Pager line_count u16 -> usize | 5 min | Prevent overflow panic for long output | **Closed** |
| GAP-P013 | Extract `collectUniqueGroups()` helper | 30 min | Eliminate 3x code duplication in help.zig | **Closed** |
| NEW-P001 | Use `appendNTimes` in text.zig padding | 30 min | Reduce N append calls to 1 per pad | **Closed** |
| NEW-P002 | Chunk-copy in `stripAnsi` | 30 min | Reduce N appends to ~K appendSlice calls | **Closed** |

### Medium (1-5 days)

| ID | Finding | Effort | Expected Impact | Status |
|----|---------|--------|-----------------|--------|
| **NP-019** | **BufferedWriter wrap for printHelp** | **1-2 hrs** | **50-75% help latency improvement (19us -> 5-10us)** | **Closed** |
| **NP-028** | **BufferedWriter wrap for printJsonHelp** | **30 min (or free via NP-019)** | **Reduce 30-50 syscalls to 1-2** | **Closed** |
| **NP-022** | **Pre-sort/pre-group subcommands in printSectionCommands** | **2-4 hrs** | **O(S) instead of O(G*S) -- negligible for small CLIs** | **Won't Do** |
| ~~NP-013~~ | ~~Add ensureTotalCapacity to ArrayList/HashMap instances~~ | ~~2-3 days~~ | ~~10-20% throughput for completions; fewer allocs/op~~ | **Closed** |
| ~~NP-014~~ | ~~Fix CountingAllocator to count app-level allocs~~ | ~~1 day~~ | ~~Accurate benchmark alloc reporting~~ | **Closed** |
| ~~NP-015~~ | ~~Add medium-scale benchmark command trees~~ | ~~1-2 days~~ | ~~Detect regressions at realistic CLI scale~~ | **Closed** |
| ~~NP-016~~ | ~~Add warm-up + multi-run averaging to CI bench~~ | ~~1-2 days~~ | ~~Statistically sound regression detection~~ | **Closed** |
| GAP-P008 | Re-implement escape functions with fast-path | 1-2 days | Eliminate allocation for clean strings | **Closed** |
| GAP-P009 | Add ArenaAllocator to completion generators | 1 day | Bulk deallocation, simpler cleanup | **Closed** |
| NP-001 | Escape fast-path dupe (after GAP-P008) | 30 min | 5-15% completion improvement | **Closed** |
| NP-010 | Benchmark allocation tracking | 1-2 days | Observability improvement | **Closed** |

### Strategic (> 5 days) -- ALL RESOLVED

| ID | Finding | Effort | Expected Impact | Status |
|----|---------|--------|-----------------|--------|
| NP-012 | PagerWriter streaming | 1-2 weeks | Memory proportional to viewport, not output | Won't Do |

---

## Open Findings (Phase 3 Round 2 -- 2026-03-25)

### NP-019: printHelp 50-80 write(2) syscalls via DeprecatedWriter [P1, PerfScore: 60] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 60 (Impact 5 x Likelihood 3 x 4)
- **Confidence:** confirmed
- **Issue:** [#103](https://gitlab.com/devnw/zig/cli/-/work_items/103)
- **Evidence:** `src/cli/help.zig:180-204` -- `printTextHelpWithTemplate` calls multiple `w.print()`, `w.writeAll()`, `w.writeByteNTimes()` per section, each issuing a write(2) syscall through DeprecatedWriter. Benchmark: Help = 19.09 us/op (Debug), syscall-dominated.
- **Root Cause:** `DeprecatedWriter` wraps `File.Writer` without buffering. Every write call = direct syscall.
- **Fix:** Wrap `ctx.stdout` with `std.io.bufferedWriter()` at top of `printTextHelpWithTemplate` or at `Context.init` level. Call `.flush()` at the end.
- **Validation:** `strace -c -e write` before/after; help benchmark should show 50-75% improvement.
- **Cross-Reference:** Overlaps with NP-003 (DeprecatedWriter migration, Won't Do). This is a **local workaround** that provides most of the benefit without full API migration. Also see NP-028 (printJsonHelp, same pattern).
- **Rollout Risk:** Low. BufferedWriter is well-tested. Missing `.flush()` caught by existing help tests.

### NP-020: Context.flags HashMap starts at capacity 0 [P2, PerfScore: 45] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 45 (Impact 3 x Likelihood 4 x 4, adjusted)
- **Confidence:** suspected -- needs measurement to confirm 30-80ns delta
- **Issue:** [#105](https://gitlab.com/devnw/zig/cli/-/work_items/105)
- **Evidence:** `src/cli/command.zig:145` -- `.flags = std.StringHashMap(FlagValue).init(allocator)` starts at capacity 0. First `put` triggers resize.
- **Root Cause:** `StringHashMap.init(allocator)` defaults to capacity 0. The first flag insertion triggers a `grow` with allocation and rehash.
- **Fix:** Call `try ctx.flags.ensureTotalCapacity(8)` in `Context.init` after initialization.
- **Validation:** Parse benchmark before/after. Expected ~30-80ns improvement.
- **Rollout Risk:** Minimal. Over-allocation of 8 slots wastes ~256 bytes.

### NP-021: writeRoffEscaped byte-at-a-time writeByte [P2, PerfScore: 40] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 40 (Impact 2 x Likelihood 5 x 4)
- **Confidence:** confirmed
- **Issue:** [#107](https://gitlab.com/devnw/zig/cli/-/work_items/107)
- **Evidence:** `src/cli/help.zig:603-641` -- `else => try w.writeByte(c)` at line 635-638. Same byte-at-a-time pattern that was fixed in `writeJsonEscapedString` (NP-017, closed).
- **Root Cause:** Function processes each byte individually. Non-special characters (majority of input) each issue a separate write.
- **Fix:** Add span tracking identical to `writeJsonEscapedString`: track `start` index, flush `s[start..i]` on special char, flush `s[start..]` at end.
- **Validation:** Man page generation benchmark before/after. Expected 20-40% improvement.
- **Rollout Risk:** Low. Identical pattern to proven NP-017 fix. Existing roff output tests verify correctness.

### NP-022: printSectionCommands O(groups * subcommands) nested loop [P2, PerfScore: 20] -- WON'T DO

- **Status:** **Won't Do**
- **PerfScore:** 20 (Impact 2 x Likelihood 3 x 4, adjusted)
- **Confidence:** suspected -- only matters at 100+ subcommand scale
- **Issue:** [#110](https://gitlab.com/devnw/zig/cli/-/work_items/110)
- **Evidence:** `src/cli/help.zig:274-313` -- outer loop over `groups[0..group_count]`, inner loop over `cmd.subcommands` with `std.mem.eql` filter at line 294.
- **Root Cause:** For each group, all subcommands are scanned to find matches. O(G * S) instead of O(S).
- **Fix:** Pre-sort subcommands by group or build index ranges during `collectUniqueGroups`.
- **Validation:** Help benchmark with 100+ subcommand command tree. Negligible impact for typical CLIs.
- **Rollout Risk:** Must use stable sort to preserve ordering within groups.

### NP-023: generateMan ArrayList no pre-allocation [P3, PerfScore: 15] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 15 (Impact 1 x Likelihood 4 x 4, adjusted)
- **Confidence:** suspected
- **Evidence:** `src/cli/help.zig:645-646` -- `var list: std.ArrayList(u8) = .empty;` with no capacity hint.
- **Fix:** Add `try list.ensureTotalCapacity(allocator, 4096)` after init. Typical man pages are 2-8KB.
- **Rollout Risk:** None. Over-allocation is bounded and freed at end.

### NP-024: generateMarkdown ArrayList no pre-allocation [P3, PerfScore: 15] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 15 (Impact 1 x Likelihood 4 x 4, adjusted)
- **Confidence:** suspected
- **Evidence:** `src/cli/help.zig:749-750` -- `var list: std.ArrayList(u8) = .empty;` with no capacity hint.
- **Fix:** Add `try list.ensureTotalCapacity(allocator, 4096)` after init.
- **Rollout Risk:** None.

### NP-025: Escape function ArrayListUnmanaged instances lack capacity hint [P3, PerfScore: 8] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 8 (Impact 1 x Likelihood 2 x 4)
- **Confidence:** suspected
- **Evidence:** `bash.zig:33,68`, `zsh.zig:31,63`, `fish.zig:30`, `powershell.zig:184,212` -- `ArrayListUnmanaged(u8) = .empty` with no capacity hint.
- **Fix:** Add capacity hint based on input length. Arena allocator amortizes the cost, so impact is minimal.
- **Rollout Risk:** None.

### NP-026: wordWrap ArrayList no pre-allocation [P3, PerfScore: 5] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 5 (Impact 1 x Likelihood 1 x 4, adjusted)
- **Confidence:** suspected
- **Evidence:** `src/util/text.zig:15` -- `var result: std.ArrayList(u8) = .empty;`
- **Fix:** Add `try result.ensureTotalCapacity(allocator, input.len)` after init (output is at most input length + newlines).
- **Rollout Risk:** None.

### NP-027: Context.positionals and command_path start empty [P3, PerfScore: 5] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 5 (Impact 1 x Likelihood 1 x 4, adjusted)
- **Confidence:** suspected
- **Evidence:** `src/cli/command.zig:146-148` -- `.positionals = .empty, .command_path = .empty`.
- **Fix:** Add `ensureTotalCapacity` with small defaults (e.g., 4 for positionals, 4 for command_path).
- **Rollout Risk:** None.

### NP-028: printJsonHelp many small writes via DeprecatedWriter [P2, PerfScore: 30] -- CLOSED

- **Status:** **Closed** (2026-03-25)
- **PerfScore:** 30 (Impact 3 x Likelihood 3 x 4, adjusted)
- **Confidence:** confirmed
- **Issue:** [#113](https://gitlab.com/devnw/zig/cli/-/work_items/113)
- **Evidence:** `src/cli/help.zig:519-572` -- `printJsonHelp` makes 20+ individual `w.writeAll()` and `w.print()` calls for JSON structure. Each goes through DeprecatedWriter as a syscall.
- **Root Cause:** Same as NP-019. DeprecatedWriter has no buffering.
- **Fix:** BufferedWriter wrap in `printJsonHelp`, or apply NP-019 fix at `Context.init` level (which covers both).
- **Validation:** `strace -c -e write` with `--help=json`. Expected write count drops from ~40 to ~2.
- **Cross-Reference:** Depends on / automatically resolved by NP-019 if applied at Context level.
- **Rollout Risk:** Low. Same analysis as NP-019.

---

## Closed Findings (Wave 2 -- 2026-03-24)

### GAP-P003: Levenshtein 255-char buffer overflow [P2, PerfScore: 45] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 45
- **Resolution:** Bounds check `if (b.len >= 256) return @max(a.len, b.len)` added at `suggest.zig:16-17` for both `a` and `b`. Test with 300-char input passes.
- **Resolved:** 2026-03-24

### GAP-P008: Escape functions with fast-path scan [P2, PerfScore: 45] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 45
- **Resolution:** Escape functions implemented in all 4 completion generators: `escapeBashDoubleQuote`, `escapeBashCasePattern` in bash.zig; `escapeZshSingleQuote`, `escapeZshDoubleQuote` in zsh.zig; `escapeFishSingleQuote` in fish.zig; `escapePowerShellString`, `escapeRegex` in powershell.zig. All include fast-path scan for special characters with early return of input slice if clean.
- **Evidence:** `bash.zig:41 escape refs`, `zsh.zig:32 escape refs`, `fish.zig:18 escape refs`, `powershell.zig:35 escape refs`
- **Resolved:** 2026-03-24

### GAP-P009: ArenaAllocator in completion generators [P2, PerfScore: 35] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 35
- **Resolution:** `ArenaAllocator.init(allocator)` added to entry-point functions in all 4 generators: `bash.zig:87`, `zsh.zig:77`, `fish.zig:47`, `powershell.zig:16`. Internal work uses arena; cleanup is automatic.
- **Resolved:** 2026-03-24

### GAP-P004: Pager `line_count` u16 overflow [P2, PerfScore: 30] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 30
- **Resolution:** `var line_count: usize = 0` at `pager.zig:36`. No overflow risk.
- **Resolved:** 2026-03-24

### GAP-P013: Duplicated group collection logic in help.zig [P3, PerfScore: 18] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 18
- **Resolution:** `collectUniqueGroups()` helper extracted at `help.zig:220`. Called from all group-rendering locations.
- **Resolved:** 2026-03-24

### NP-001: Escape fast-path dupe [P2, PerfScore: 32] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 32
- **Issue:** [#36](https://gitlab.com/devnw/zig/cli/-/work_items/36)
- **Resolution:** Escape functions now return the input slice directly on fast-path (no `allocator.dupe`). Resolved together with GAP-P008.
- **Resolved:** 2026-03-24

### NEW-P001: Byte-at-a-time ArrayList append in text.zig [P3, PerfScore: 16] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 16
- **Resolution:** All padding loops in `text.zig` replaced with `appendNTimes` at lines 59, 72, 82, 96, 98. Single capacity check per pad operation.
- **Resolved:** 2026-03-24

### NEW-P002: `stripAnsi` byte-at-a-time append [P3, PerfScore: 12] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 12
- **Resolution:** `stripAnsi` in `color.zig` now tracks span start and uses `appendSlice` for non-ANSI chunks at line 158.
- **Resolved:** 2026-03-24

### NP-010: Benchmarks lack allocation tracking [P3, PerfScore: 16] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 16 (Impact 2 x Likelihood 2 x 4)
- **Confidence:** confirmed
- **Resolution:** Added `CountingAllocator` struct to `tests/bench.zig` that wraps the backing arena allocator via a full VTable implementation (alloc/resize/remap/free). Tracks `alloc_count`, `free_count`, and `total_bytes`. All benchmark functions now return `BenchResult` (timing + allocation stats). `printResult` displays allocs, frees, total bytes, and allocs/op alongside timing. Added `formatBytes` helper for human-readable byte output.
- **Evidence:** `zig build bench` output now includes allocation stats per benchmark.
- **Resolved:** 2026-03-24

### NP-012: PagerWriter loads entire output into memory [P3, PerfScore: 16] -- WON'T DO

- **Status:** Won't Do
- **PerfScore:** 16 (Impact 2 x Likelihood 2 x 4)
- **Confidence:** suspected
- **Evidence:** `src/term/pager.zig:78-` -- `PagerWriter` uses `ArrayList(u8)` to buffer all output before flushing to pager.
- **Reason:** Pager buffers help text which is bounded by command tree size (typically a few KB). Streaming refactor would require significant architectural changes to the pager pipe model for marginal benefit. The buffered approach is correct for the bounded output size of CLI help text.
- **Refs:** PERF-13
- **Resolved:** 2026-03-24

### NEW-P001: Byte-at-a-time ArrayList append in text.zig padding [P3, PerfScore: 16] -- CLOSED

- **Status:** Closed / Implemented (moved to Closed Findings section above)

### NEW-P002: `stripAnsi` byte-at-a-time append [P3, PerfScore: 12] -- CLOSED

- **Status:** Closed / Implemented (moved to Closed Findings section above)

### NEW-P003: Benchmark regression gate uses `allow_failure: true` [Info] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** N/A (Info-level)
- **Confidence:** confirmed
- **Resolution:** Replaced job-level `allow_failure: true` with per-rule `allow_failure` in the `rules:` block. MR pipelines (`CI_PIPELINE_SOURCE == "merge_request_event"`) use `allow_failure: false` (blocking). Main branch and schedule pipelines retain `allow_failure: true` (soft). This ensures benchmark regressions block MR merges while avoiding flaky failures on main.
- **Resolved:** 2026-03-24

### NEW-P004: CI `apt-get` packages not cached [Info] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** N/A (Info-level)
- **Confidence:** confirmed
- **Resolution:** Wrapped the `apt-get update && apt-get install` line in the `.install-zig` template with a conditional check: `if ! command -v curl >/dev/null 2>&1 || ! command -v xz >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1`. When all three tools are already available (e.g., in a custom image or after first run), the apt-get step is skipped entirely, saving 5-15s per job.
- **Resolved:** 2026-03-24

---

## Closed Findings (Phase 3, Gap-Close Round 4 -- 2026-03-24)

### NP-013: Zero ensureTotalCapacity across 50+ ArrayList instances [P2, PerfScore: 48] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 48 (Impact 3 x Likelihood 4 x 4)
- **Issue:** [#65](https://gitlab.com/devnw/zig/cli/-/work_items/65)
- **Resolution:** `ensureTotalCapacity` added to key ArrayList and HashMap instances in completion generators, parser, and help rendering. Reduces intermediate reallocations.
- **Evidence:** `src/cli/completion/bash.zig`, `src/cli/completion/zsh.zig`, `src/cli/completion/fish.zig`, `src/cli/completion/powershell.zig`, `src/cli/parser.zig` -- capacity pre-allocation calls.
- **Resolved:** 2026-03-24

### NP-014: CountingAllocator + ArenaAllocator interaction distorts benchmark alloc reporting [P2, PerfScore: 32] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 32 (Impact 2 x Likelihood 4 x 4)
- **Issue:** [#66](https://gitlab.com/devnw/zig/cli/-/work_items/66)
- **Resolution:** CountingAllocator reset per iteration. Counter tracks app-level allocations accurately.
- **Evidence:** `tests/bench.zig` -- counter reset between iterations.
- **Resolved:** 2026-03-24

### NP-015: Benchmarks test only trivial command trees [P2, PerfScore: 36] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 36 (Impact 3 x Likelihood 3 x 4)
- **Issue:** [#68](https://gitlab.com/devnw/zig/cli/-/work_items/68)
- **Resolution:** Medium-scale benchmarks added with 20+ subcommands and 50+ flags. All 10 benchmarks pass including medium-scale variants.
- **Evidence:** `tests/bench.zig` -- `mediumScaleBenchCommand()` and medium-scale benchmark variants.
- **Resolved:** 2026-03-24

### NP-016: CI bench single-run noise sensitivity [P2, PerfScore: 32] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 32 (Impact 2 x Likelihood 4 x 4)
- **Issue:** [#70](https://gitlab.com/devnw/zig/cli/-/work_items/70)
- **Resolution:** CI bench warm-up iterations and multi-run median added. Statistically sound regression detection.
- **Evidence:** `tests/bench.zig` -- warm-up iterations; `.gitlab-ci.yml` -- multi-run bench invocation.
- **Resolved:** 2026-03-24

### NP-017: JSON help writeJsonEscapedString byte-by-byte through DeprecatedWriter [P2, PerfScore: 24] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 24 (Impact 3 x Likelihood 2 x 4)
- **Issue:** [#71](https://gitlab.com/devnw/zig/cli/-/work_items/71)
- **Resolution:** `writeJsonEscapedString` uses span-based optimization: tracks span start, flushes non-special character runs with `writeAll(s[start..i])`. Reduces syscalls from ~N to ~K.
- **Evidence:** `src/cli/help.zig` -- span-based `writeJsonEscapedString`.
- **Resolved:** 2026-03-24

### NP-018: Redundant global flags in bash completion scripts [P2, PerfScore: 32] -- CLOSED

- **Status:** Closed / Implemented
- **PerfScore:** 32 (Impact 2 x Likelihood 4 x 4)
- **Issue:** [#73](https://gitlab.com/devnw/zig/cli/-/work_items/73)
- **Resolution:** Global flags single-sourced from `command.global_flags`. Bash completion no longer inlines flags per function. Also closes NQ-046.
- **Evidence:** `src/cli/completion/bash.zig` -- global flags derived from shared constant.
- **Resolved:** 2026-03-24

---

## P3 Findings Reviewed and Accepted (Phase 3 -- 2026-03-24)

The following P3-level findings were evaluated during Phase 3 and determined to be acceptable tradeoffs. No action required.

| Ref | Finding | Reason | PerfScore |
|-----|---------|--------|-----------|
| PERF-03/04/06 | Linear flag/subcommand lookups | Correct tradeoff for CLI-scale (<50 items). Hash map overhead exceeds linear scan. | 4 |
| PERF-01/02 | collectUniqueGroups O(S*G) | Negligible at realistic sizes. S and G are both small constants. | 4 |
| -- | ArenaAllocator created but unused in fast-path | Init is cheap (~20 ns). No deallocation overhead if unused. | 4 |
| -- | Pager line counting byte-by-byte | Help text is <10KB typical. Byte-by-byte is fine for bounded input. | 4 |

---

## Baseline Benchmarks (current as of 2026-03-25, Debug mode)

| Benchmark | Time/op | Allocs/op | Notes |
|-----------|---------|-----------|-------|
| Parse | 929 ns | 3 | Debug mode; alloc count is arena artifact (see NP-014) |
| Help text | 19.09 us | 0 | Debug mode; syscall-dominated via DeprecatedWriter (see NP-003, NP-019) |
| Bash completion | 3.86 us | 1 | Debug mode |
| Medium parse | 449 ns | 3 | Debug mode |
| Medium help | 22.29 us | 0 | Debug mode; syscall-dominated |

Previous baselines (ReleaseFast, 2026-03-24):

| Benchmark | Time/op | Allocs/op | Notes |
|-----------|---------|-----------|-------|
| Parse | 316 ns | 3 | alloc count is arena artifact (see NP-014) |
| Help text | 11.85 us | 0 | writes to DeprecatedWriter (see NP-003) |
| Bash completion | ~2.0 us | 1 | |
| Zsh completion | ~2.0 us | 1 | |
| Fish completion | 1.48 us | 1 | |
| PowerShell completion | 1.68 us | 1 | |
| Levenshtein | 295 ns | 0 | |

---

## Reviewed & Cleared (Confirmed Non-Issues)

The following findings were evaluated during the Phase 3 performance review and determined to be non-issues. No action required.

| Ref | Finding | Reason | PerfScore |
|-----|---------|--------|-----------|
| PERF-01/02 | O(S*G) iteration in help group rendering | Bounded by 32 groups max. Theoretical O(S*G) but S and G are both small constants. | 4 |
| PERF-03/04/06 | Linear search over flags and subcommands | Appropriate for CLI-scale data (typically <50 items). Hash map overhead would exceed linear scan. | 4 |
| PERF-05 | `indexOfScalar` on 5-char escape literal | Effectively constant time. 5-element linear scan is faster than any alternative. | 8 |
| PERF-07 | Levenshtein distance stack allocation | Textbook optimal implementation with bounded 255-char buffer. Overflow guard (GAP-P003) confirmed present at `suggest.zig:16-17`. | 0 |
| PERF-12 | Arena allocator in completion generators | ArenaAllocator confirmed present in all 4 generators (GAP-P009 closed). | 0 |
| PERF-18/19 | Signal handler atomic ordering | Uses correct memory ordering for signal handler context. No change needed. | 0 |

---

## Closed Findings

### NP-002: Help padding single-space writeAll [P2, PerfScore: 32]

- **Status:** Closed / Implemented
- **PerfScore:** 32
- **Resolution:** Help padding loops replaced with writeByteNTimes at 7 locations in help.zig.
- **Resolved:** 2026-03-24

### NP-007: useColor() allocating getEnvVarOwned [P2, PerfScore: 24]

- **Status:** Closed / Verified
- **PerfScore:** 24
- **Resolution:** useColor() no longer allocates. It already uses parsed no_color/plain fields set at parse time.
- **Resolved:** 2026-03-24

### NP-008: Progress bar char-at-a-time rendering [P2, PerfScore: 24]

- **Status:** Closed / Implemented
- **PerfScore:** 24
- **Resolution:** Progress bar char-at-a-time replaced with writeByteNTimes for both filled ('=') and empty (' ') segments.
- **Resolved:** 2026-03-24

### NP-011: Windows envVarExists uses page_allocator [P3, PerfScore: 16]

- **Status:** Closed / Implemented
- **PerfScore:** 16
- **Resolution:** Windows envVarExists now uses FixedBufferAllocator instead of page_allocator, eliminating 4KB minimum allocation per env check.
- **Resolved:** 2026-03-24

### GAP-P011: No performance regression detection in CI [P2, PerfScore: 25]

- **Status:** Closed / Implemented
- **PerfScore:** 25
- **Resolution:** Added `zig-test-integration` and `zig-bench` jobs to `.gitlab-ci.yml`. Bench job runs with `allow_failure: true` and stores artifacts for 30 days.
- **Evidence:** `.gitlab-ci.yml` contains `zig-bench` job with artifact storage.
- **Resolved:** 2026-03-24

### GAP-P012: Benchmark coverage gaps [P3, PerfScore: 20]

- **Status:** Closed / Implemented
- **PerfScore:** 20
- **Resolution:** Added `benchZshCompletion`, `benchFishCompletion`, `benchPowerShellCompletion` to `tests/bench.zig`. Extracted shared `completionBenchCommand()` helper. 7 benchmarks total.
- **Evidence:** `tests/bench.zig` -- 7 benchmarks; `zig build bench` runs successfully.
- **Resolved:** 2026-03-24

### GAP-P014: Parser getEnvVarOwned allocates for env-bound flags [P3, PerfScore: 15]

- **Status:** Closed / Implemented
- **PerfScore:** 15
- **Resolution:** `getEnvVar()` in `parser.zig` now uses `std.posix.getenv` (non-allocating) on POSIX. Returns null on Windows. Removed 3 unnecessary `allocator.free()` calls from callers.
- **Evidence:** `src/cli/parser.zig` -- non-allocating getenv on POSIX; all 574 tests pass.
- **Resolved:** 2026-03-24

### GAP-P015: Benchmark uses GPA allocator [P3, PerfScore: 15]

- **Status:** Closed / Implemented
- **PerfScore:** 15
- **Resolution:** Benchmarks now use per-benchmark `ArenaAllocator` backed by `page_allocator` with `.retain_capacity` reset between iterations. GPA retained in `main()` for leak detection.
- **Evidence:** `tests/bench.zig` -- ArenaAllocator per benchmark; benchmarks run successfully.
- **Resolved:** 2026-03-24

### GAP-P001: `useColor()` heap-allocates on every call [P1]

- **Status:** Closed
- **PerfScore:** 60
- **Resolution:** `useColor()` now uses `self.no_color` and `self.plain` fields (already set during parsing) instead of heap-allocating `getEnvVarOwned` calls.

### GAP-P002: getEnvVarOwned vs getenv inconsistency [P1]

- **Status:** Closed
- **PerfScore:** 50
- **Resolution:** Added cross-platform `envVarExists()` and `getEnvValue()` helpers in both `tty.zig` and `color.zig`. Boolean checks (NO_COLOR) use non-allocating `envVarExists()`. Value checks (TERM) use `getEnvValue()` which is non-allocating on POSIX and returns null on Windows (where TERM is not meaningful). Consistent pattern across all modules.

### GAP-P005: Per-call ArrayList allocations in text utilities [P3]

- **Status:** Closed
- **PerfScore:** 20
- **Resolution:** Added comprehensive doc comments to all 8 text utility functions (`wordWrap`, `indent`, `padRight`, `padLeft`, `center`, `truncate`, `splitWhitespace`, `toUpper`/`toLower`) documenting allocation behavior and ownership semantics. Each function now clearly states whether it returns owned or borrowed memory.

### GAP-P007: No benchmarks exist [P3]

- **Status:** Closed
- **PerfScore:** 15
- **Resolution:** Created `tests/bench.zig` with benchmarks for parser, help generation, bash completion generation, and Levenshtein distance. Added `zig build bench` step to `build.zig` (runs with ReleaseFast optimization) and `make bench` target to Makefile.

### NP-004: CI no Zig/apt caching [P1, PerfScore: 60]

- **Status:** Closed / Implemented
- **PerfScore:** 60 (Impact 3 x Likelihood 5 x 4)
- **Confidence:** confirmed
- **Issue:** [#45](https://gitlab.com/devnw/zig/cli/-/work_items/45)
- **Evidence:** `.gitlab-ci.yml:36-72` -- `.install-zig` downloads Zig every job. No `cache:` directive.
- **Root Cause:** Missing GitLab CI cache configuration despite existing conditional check.
- **Fix:** Add `cache: key: "zig-${ZIG_VERSION}" paths: [zig-${ZIG_VERSION}/]`.
- **Validation:** Compare pipeline durations before/after. Check job logs for cache hit.
- **Refs:** PERF-24, PERF-28
- **Resolution:** Added `default: cache:` block with two cache entries: (1) `zig-${ZIG_VERSION}/` keyed by Zig version for toolchain caching, (2) `.zig-cache/` keyed by branch for build cache. The install-zig template's existing conditional check automatically skips download on cache hit.
- **Resolved:** 2026-03-24

### NP-005: No benchmark regression gate [P2, PerfScore: 48]

- **Status:** Closed / Implemented
- **PerfScore:** 48 (Impact 3 x Likelihood 4 x 4)
- **Confidence:** confirmed
- **Issue:** [#47](https://gitlab.com/devnw/zig/cli/-/work_items/47)
- **Evidence:** `.gitlab-ci.yml:195-211` -- `bench-regression` stores results but has no baseline comparison. `allow_failure: true`.
- **Root Cause:** Benchmark job was added for observability but comparison/gating step was not implemented.
- **Fix:** Add baseline download + comparison script with configurable threshold (e.g., 15%).
- **Validation:** Introduce intentional regression, verify pipeline blocks.
- **Refs:** PERF-25
- **Resolution:** Added benchmark comparison script to `bench-regression` CI job. The script: (1) downloads the previous main branch bench-results.txt artifact via GitLab API, (2) parses per-op nanosecond timings from both current and baseline results, (3) compares each benchmark with a 20% regression threshold, (4) reports OK/WARN/NEW for each benchmark. Job retains `allow_failure: true` to avoid blocking on noise.
- **Resolved:** 2026-03-24

---

## Regressed Findings (Previously Closed, Reverted to Open)

The following 5 findings were previously marked Closed but have regressed -- their fixes are no longer present in the codebase. These are tracked separately to highlight the pattern of fix reversion.

| ID | PerfSeverity | PerfScore | Finding | Originally Closed | Regression Detected |
|----|-------------|-----------|---------|-------------------|---------------------|
| GAP-P003 | P2 | 45 | Levenshtein 255-char buffer overflow | 2026-03-24 | 2026-03-24 (Phase 3) |
| GAP-P008 | P2 | 45 | Escape functions missing (fast-path scan lost) | 2026-03-24 | 2026-03-24 (Phase 3) |
| GAP-P009 | P2 | 35 | No ArenaAllocator in completion generators | 2026-03-24 | 2026-03-24 (Phase 3) |
| GAP-P004 | P2 | 30 | Pager `line_count` u16 overflow | 2026-03-24 | 2026-03-24 (Phase 3) |
| GAP-P013 | P3 | 18 | Duplicated group collection in help.zig | 2026-03-24 | 2026-03-24 (Phase 3) |

**Root cause of regressions:** All 5 fixes appear to have been reverted, likely due to a branch reset or force-push that dropped the commits containing these changes. The working tree modifications are present (git status shows modified files) but the fixes have not been re-applied to these specific code paths.

---

## Won't Do

### NP-003: DeprecatedWriter -> buffered File.Writer [P1, PerfScore: 80]

- **Status:** Won't Do
- **PerfScore:** 80
- **Reason:** DeprecatedWriter migration is API-breaking and blocked on Zig std library evolution. The writer type is transitional in Zig 0.15 and the replacement API is not yet finalized. Will be automatically resolved when Zig removes the deprecated type.
- **Resolved:** 2026-03-24

### NP-009: Table writeHorizontalBorder char-at-a-time [P2, PerfScore: 24]

- **Status:** Won't Do
- **PerfScore:** 24
- **Reason:** Table border uses multi-byte UTF-8 characters (not single byte), so writeByteNTimes cannot work. The `horiz` variable contains UTF-8 strings like box-drawing characters, not single bytes.
- **Resolved:** 2026-03-24

### NP-012: PagerWriter loads entire output into memory [P3, PerfScore: 16]

- **Status:** Won't Do
- **PerfScore:** 16
- **Reason:** Pager buffers help text which is bounded by command tree size (typically a few KB). Streaming refactor would require significant architectural changes to the pager pipe model for marginal benefit. The buffered approach is correct for the bounded output size of CLI help text.
- **Resolved:** 2026-03-24

### GAP-P006: page_allocator for pager child process [P3]

- **Status:** Won't Do
- **PerfScore:** 10
- **Reason:** One-time allocation for process spawn. page_allocator is appropriate for this use case -- Child resources are cleaned by OS. Not worth adding allocator parameter complexity.

### GAP-P010: Help output uses many small write syscalls [P2]

- **Status:** Won't Do (pending NP-003)
- **PerfScore:** 30
- **Reason:** Blocked by DeprecatedWriter migration (NP-003). `std.io.bufferedWriter` requires the non-deprecated writer type. Will be automatically resolved when NP-003 is implemented.
