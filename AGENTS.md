# AGENTS.md

## Project

`ruby-lsp-dragonruby` is a Ruby LSP add-on gem (runs on CRuby inside the LSP server, never inside DragonRuby) for hover/completion/go-to-definition on DragonRuby's `args` API, plus undefined-API warnings.

`docs/requirements_v1.md` is the authoritative spec — read it before implementing. It defines milestones M0–M8, per-requirement IDs (`REQ-*`), and explicit non-goals. M1 (the curated API registry under `data/`, plus loader/validator/coverage tooling), M2 (receiver resolution, args-tree completion and hover), M3 (primitive hash keys, `attr_sprite`/`attr_gtk` indexing enhancements), M4 (local alias tracking), M5 (`args.state` tracking with completion/hover/definition), M6 (core-class extensions), M7 (undefined-API warnings), and M8 (benchmarks, fuzz tests, coverage deferrals, docs, 1.0.0 packaging) are implemented. All M0 spikes (S1–S6) are decided in `docs/decisions/`. The 1.0.0 gem is packaged and ready; publishing to RubyGems is left to the maintainer. Prefer milestone order for new work.

## Commands

- Setup: `bin/setup` (no committed `Gemfile.lock`)
- Full gate (same as CI): `bundle exec rake` = `rake test` + `rake standard` + `registry:validate` + `registry:coverage` + `rake benchmark`
- Tests: `bundle exec rake test`
- Single test file: `bundle exec ruby -Itest test/ruby_lsp/ruby_lsp_dragonruby/test_dragonruby.rb`
- Single test: append `-n test_name` to the single-file command
- Benchmarks: `bundle exec rake benchmark` (enforces REQ-PERF-02/03 budgets; standalone via `bundle exec ruby benchmark/run.rb`)
- Lint/format: `bundle exec rake standard`, autocorrect with `bundle exec standardrb --fix`
- Version matrix check: `RUBY_LSP_VERSION=0.26.0 bundle install && bundle exec rake test`, then `bundle update ruby-lsp` to restore the default

Lint is **standardrb, not RuboCop**. The requirements text mentions RuboCop in a few places, but the Gemfile/Rakefile only wire up `standard`; trust the executable config.

## Gotchas

- The add-on entry point must be `lib/ruby_lsp/ruby_lsp_dragonruby/addon.rb` (REQ-PKG-01). The gem's own module is `RubyLsp::Dragonruby`, with files under `lib/ruby_lsp_dragonruby/` and the gem entry file at `lib/ruby-lsp-dragonruby.rb`, mirroring ruby-lsp-rails and ruby-lsp-yard.
- Runtime dependencies are limited to `ruby-lsp` pinned to a minor range; no other runtime deps (REQ-PKG-02/03). Dev deps: rake, minitest, standard, irb.
- Every add-on entry point must rescue exceptions, log, and contribute nothing rather than break Ruby LSP (REQ-ROB-01).
- Integration tests must use Ruby LSP's `with_server` helper and cover incomplete code: trailing `.`, unclosed hash, half-typed identifier (REQ-TEST-01/02).
- CI runs the `ruby: [4.0, 3.4] × ruby-lsp: [0.26.0, "~> 0.26.0"]` matrix (REQ-TEST-03). The Gemfile adds `gem "ruby-lsp", ENV["RUBY_LSP_VERSION"]` when set; the requirement intersects with the gemspec pin. `bundler-cache` is disabled because `Gemfile.lock` is not committed and a cache resolved for one matrix entry would conflict with another.
- Registry data is YAML under `data/` and is loaded once at activation (REQ-M1-01, REQ-PERF-01). The format, family expansion, and load-time skip semantics are documented in `docs/decisions/m1-registry-format.md`; curate with `rake registry:coverage` in view.
- M3 added `data/macros.yml` and list-valued `accepts_primitive`; the format and the `ruby-lsp` 0.26-specific `RubyIndexer::Enhancement` approach are documented in `docs/decisions/m3-macros-and-primitives.md`.
- M4 resolves local aliases by walking the enclosing scopes from `NodeContext`'s private `@nesting_nodes`; the algorithm, block semantics, and graceful-degradation fallback are documented in `docs/decisions/m4-local-aliases.md`. A bare alias (`kb` on its own) is still not a hover target in the pinned `ruby-lsp` range.
- M5 owns its state index instead of using `RubyIndexer` synthetic owners, because indexing enhancements only receive call nodes (no `CallOrWriteNode` for `||=`) and no nesting context. `StateStore`/`StateTracker` are populated by a lazy workspace scan (which waits for `index.initial_indexing_completed`), `workspace_did_change_watched_files`, and a per-request refresh from the current document AST; hover has no URI in the pinned range and falls back to a URI-less collection. See `docs/decisions/m0-s6-workspace-changes.md` and `docs/decisions/m5-state-tracking.md`.
- M6 curates core-class additions in `data/core_extensions.yml` with `core_extension: true` types and member `scope` (`instance`/`class`/`both`), and exposes them only through the resolver (M0-S4 rejected stub indexing because index-derived completion items cannot carry the `"DragonRuby"` label). `StandardMethods` filters stock CRuby methods from completion (REQ-M6-06). See `docs/decisions/m0-s4-stub-indexing.md` and `docs/decisions/m6-core-extensions.md`.
- Bulk state collection must call `Resolver#reset_aliases!` per parsed document: `LocalAliases` memoizes scope walks and indexes events by variable name, and without the reset a 10k-line workspace scan takes seconds instead of well under the REQ-PERF-03 budget.
- Add-on completion and hover listeners do not receive the cursor position in the pinned `ruby-lsp` range. Primitive key vs. value positions are inferred from AST shape (`lib/ruby_lsp_dragonruby/primitive_context.rb`); trailing whitespace never reaches add-on listeners.
- M7 delivers diagnostics through the pull model only (M0-S3): `Warnings::Formatter` is registered via `global_state.register_formatter` under `Settings::LINTER_ID` (`"dragonruby"`) and runs only when the editor lists that identifier in `linters`. The hover warning (`Warnings::UndefinedMember`) always works and is the zero-config fallback. VS Code's extension sends neither `linters` nor `addonSettings`, so it gets hover warnings only. See `docs/decisions/m0-s3-warning-delivery.md` and `docs/decisions/m0-s5-settings.md`.
- `textDocument/diagnostic` returns nothing for URIs outside `global_state.workspace_path`, so diagnostics integration tests must use `with_workspace_server`/`with_workspace_cursor` instead of the default `file:///fake.rb`. Document diagnostics are also cached per request: configure `linters`/`addonSettings` before the first pull in a test.
- Warnings share one Prism walk (`Warnings::Analyzer`) that tracks scope nodes like `StateCollector`, so `attr_gtk` and local aliases resolve. Undefined-member suppression order is open/incomplete types, allowlist, registry members, `core_backing` standard methods (`data/*.yml` `core_backing: Array|Hash|...`), Ruby LSP's index (reopened classes), then stock `Object` methods (`StandardMethods.standard_object_method?`). Unassigned-state-read hints are gated on `StateTracker#scanned?`, so nothing warns before the workspace scan has run.
- M8 benchmark methodology: `benchmark/run.rb` measures the add-on share by creating listeners through the real `Addon` factories and firing the one callback Ruby LSP's `dispatch_once(target)` fires for the located node (callbacks directly, not `Prism::Dispatcher`), with GC disabled during each timing pass for stable p95. `benchmark/sample_workspace.rb` expands the committed sample game into the 50-file/~10k-line workspace and is shared with `test_state_performance.rb`. See `docs/decisions/m8-hardening.md`.
- The sample game lives at `benchmark/sample_game/`; `wip.rb` is intentionally syntactically invalid and the whole fixture directory is ignored by standardrb (`.standard.yml`). `test_fuzz.rb` sweeps every character position of every sample file, invoking listener callbacks directly with the located `NodeContext` and asserting the add-on's quiet logger stays empty; incomplete `wip.rb` is part of the sweep.
- `Registry::Coverage` areas accept `deferred: <reason>` in `data/coverage.yml`: a deferred area counts as covered, is excluded from `incomplete`, and prints `DEFERRED` plus the reason. `args.cvars`, `args.pixel_array`, and `Zlib` are deferred in the shipped data.
- Release data: 1.0.0, targeted DragonRuby version in `data/metadata.yml` (7.18), every CHANGELOG release states its target version, gemspec has real metadata plus `rubygems_mfa_required`, and `benchmark/` is excluded from the packaged files. The maintainer runs `bundle exec rake release`; no credentials live in the repo.
