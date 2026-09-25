# M8 — Hardening, benchmarks, and release decisions

Status: accepted (2026-09-25)

This decision records how M8 satisfies the hardening and release requirements
(REQ-M8-01 through REQ-M8-07) and the REQ-TEST-03 version matrix.

## Benchmark methodology (REQ-M8-01)

`benchmark/run.rb` runs as `bundle exec rake benchmark` and is part of the default
rake task, so CI fails when a budget is exceeded. It measures three things:

- **REQ-PERF-02 (add-on share, p95 < 10 ms).** For each sampled cursor position in
  the representative `benchmark/sample_game/main.rb`, it locates the target the way
  Ruby LSP does, creates the add-on's completion and hover listeners through the
  real `Addon` factories, and fires the single callback that Ruby LSP's
  `dispatch_once(target)` fires, with the cursor's `NodeContext`. Invoking the
  callback directly isolates the add-on's share from Prism's dispatch overhead.
  Definition timings are reported for information but are not budgeted.
- **REQ-PERF-03 (workspace scan < 1 s).** `benchmark/sample_workspace.rb` expands
  the sample game into a 50-file, ~10k-line workspace with unique state writes;
  the benchmark times `StateTracker#ensure_workspace_scanned` against it.
- **Registry load** is reported for information (M1's < 100 ms target).

Garbage collection is stopped during each timing pass (`GC.start` then
`GC.disable`/`GC.enable`) so a single global GC pause does not distort p95. GC cost
caused by the add-on is amortized across requests in a real server, so excluding
inter-iteration collections is the fair measure of per-request work.

`test_state_performance.rb` keeps the test-level REQ-PERF-03 assertion and shares
the same workspace builder, so the test suite catches regressions even when the
benchmark is not run.

## Fuzz approach (REQ-M8-02)

`test_fuzz.rb` has three parts:

1. **Add-on sweep.** For every character position in every
   `benchmark/sample_game/**/*.rb` file (including the intentionally incomplete
   `wip.rb`), it locates the `NodeContext` Ruby LSP would provide, creates all three
   listeners through the `Addon` factories, and invokes the callbacks registered for
   the located node plus any enclosing call nodes. The add-on's entry points rescue
   and log errors, so the test asserts the quiet logger stays empty; anything that
   escapes a callback fails immediately with the file and offset.
2. **Diagnostics.** `Warnings::Formatter#run_diagnostic` runs once per sample file
   with the same logger assertion. Diagnostics are whole-document, not
   cursor-position dependent.
3. **Server smoke.** A handful of real completion, hover, definition, and
   diagnostic requests run through `with_workspace_server`, asserting the add-on
   logger stays clean.

The direct-callback sweep is fast enough to keep in the default test task
(seconds), while still exercising every AST node of every handled type at a
plausible cursor context.

## Coverage deferrals (REQ-M8-03)

A coverage area may carry `deferred: <reason>` in `data/coverage.yml`. A deferred
area counts as resolved, is excluded from `incomplete`, and prints `DEFERRED` plus
the reason in the report. This is audited against the documented API areas in the
DragonRuby docs `docs/api` directory:

- Curated: `args`, `args.inputs`, `args.outputs`, `args.grid`, `args.geometry`,
  `args.easing`, `args.audio`, `args.gtk`/runtime, `args.layout`, `args.events`,
  `args.state`, primitive schemas, class macros, and the Array/Numeric core
  extensions.
- Deferred: `args.cvars` (keys come from user metadata files), `args.pixel_array`
  (dynamic symbol receiver), and `Zlib` (top-level utility outside the args tree).

## Version matrix (REQ-TEST-03)

The `Gemfile` adds `gem "ruby-lsp", ENV["RUBY_LSP_VERSION"]` when the environment
variable is set; the requirement intersects with the gemspec's `~> 0.26.0` pin.
CI runs the matrix `ruby: [4.0, 3.4] × ruby-lsp: [0.26.0, "~> 0.26.0"]` with
`fail-fast: false`. `Gemfile.lock` is not committed, so `bundler-cache` is disabled
and each job runs `bundle install`; this avoids restoring a lockfile resolved for a
different matrix entry.

## Release (REQ-M8-06, REQ-M8-07)

Version 1.0.0 ships with real gemspec metadata (summary, description, homepage,
source/changelog URIs), `rubygems_mfa_required`, and `benchmark/` excluded from the
package. `CHANGELOG.md` states the targeted DragonRuby version for every release.
The maintainer publishes with `bundle exec rake release`; the repository does not
hold RubyGems credentials.
