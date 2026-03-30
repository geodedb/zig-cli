# Benchmark Results

Performance baseline and historical results for the CLI library.

## Files

- `baseline.json` - Current accepted performance baseline
- `{git-sha}.json` - Historical results keyed by commit hash

## Workflow

```sh
# Run benchmarks and save to baseline
make bench-baseline

# Run benchmarks and compare against baseline
make bench-compare

# Save current results with commit hash
make bench-save

# Quick benchmarks (existing tests/bench.zig)
make bench
```

## JSON Schema

```json
{
  "version": 1,
  "timestamp": "2026-03-30T12:00:00Z",
  "git_commit": "abc1234",
  "system": { "os": "linux", "arch": "x86_64" },
  "spice_enabled": true,
  "tiers": [
    {
      "name": "small",
      "subcmd_count": 8,
      "total_flags": 24,
      "parse_ns": 1234,
      "parse_ops_sec": 810372,
      "help_gen_ns": 5678,
      "bash_completion_ns": 9012,
      "zsh_completion_ns": 3456,
      "fish_completion_ns": 7890,
      "ps_completion_ns": 2345,
      "levenshtein_ns": 456,
      "parallel_foreach_ns": 789,
      "skipped": false
    }
  ]
}
```

## Regression Detection

The `compare-bench` tool checks each metric against the baseline with a
configurable threshold (default: 20%). Throughput metrics (ops/sec) fail
when the current value is more than 20% below baseline. Latency metrics
(ns) fail when more than 20% above baseline.

```sh
# Custom threshold (15%)
zig build compare-bench -- benchmarks/results/baseline.json /tmp/current.json 15
```

Exit codes: 0 = PASS, 1 = FAIL (regression), 2 = argument error.
