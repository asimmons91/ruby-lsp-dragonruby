# AGENTS.md

## Project

`ruby-lsp-dragonruby` is a Ruby LSP add-on gem (runs on CRuby inside the LSP server, never inside DragonRuby) for hover/completion/go-to-definition on DragonRuby's `args` API, plus undefined-API warnings.

`docs/requirements_v1.md` is the authoritative spec — read it before implementing. It defines milestones M0–M8, per-requirement IDs (`REQ-*`), and explicit non-goals. M1 (the curated API registry under `data/`, plus loader/validator/coverage tooling), M2 (receiver resolution, args-tree completion and hover), M3 (primitive hash keys, `attr_sprite`/`attr_gtk` indexing enhancements), and M4 (local alias tracking) are implemented. M0-S1 and M0-S2 are decided in `docs/decisions/`; M0-S3–S6 remain open. Prefer milestone order for new work.

## Commands

- Setup: `bin/setup` (no committed `Gemfile.lock`)
- Full gate (same as CI): `bundle exec rake` = `rake test` + `rake standard` + `registry:validate` + `registry:coverage`
- Tests: `bundle exec rake test`
- Single test file: `bundle exec ruby -Itest test/ruby_lsp/ruby_lsp_dragonruby/test_dragonruby.rb`
- Single test: append `-n test_name` to the single-file command
- Lint/format: `bundle exec rake standard`, autocorrect with `bundle exec standardrb --fix`

Lint is **standardrb, not RuboCop**. The requirements text mentions RuboCop in a few places, but the Gemfile/Rakefile only wire up `standard`; trust the executable config.

## Gotchas

- The add-on entry point must be `lib/ruby_lsp/ruby_lsp_dragonruby/addon.rb` (REQ-PKG-01). The gem's own module is `RubyLsp::Dragonruby`, with files under `lib/ruby_lsp_dragonruby/` and the gem entry file at `lib/ruby-lsp-dragonruby.rb`, mirroring ruby-lsp-rails and ruby-lsp-yard.
- Runtime dependencies are limited to `ruby-lsp` pinned to a minor range; no other runtime deps (REQ-PKG-02/03). Dev deps: rake, minitest, standard, irb.
- Every add-on entry point must rescue exceptions, log, and contribute nothing rather than break Ruby LSP (REQ-ROB-01).
- Integration tests must use Ruby LSP's `with_server` helper and cover incomplete code: trailing `.`, unclosed hash, half-typed identifier (REQ-TEST-01/02).
- CI runs Ruby 4.0 and 3.4, while the gemspec allows `>= 3.2` and `.standard.yml` targets 3.2. The low/high `ruby-lsp` version matrix (REQ-TEST-03) is not wired up yet.
- Registry data is YAML under `data/` and is loaded once at activation (REQ-M1-01, REQ-PERF-01). The format, family expansion, and load-time skip semantics are documented in `docs/decisions/m1-registry-format.md`; curate with `rake registry:coverage` in view.
- M3 added `data/macros.yml` and list-valued `accepts_primitive`; the format and the `ruby-lsp` 0.26-specific `RubyIndexer::Enhancement` approach are documented in `docs/decisions/m3-macros-and-primitives.md`.
- M4 resolves local aliases by walking the enclosing scopes from `NodeContext`'s private `@nesting_nodes`; the algorithm, block semantics, and graceful-degradation fallback are documented in `docs/decisions/m4-local-aliases.md`. A bare alias (`kb` on its own) is still not a hover target in the pinned `ruby-lsp` range.
- Add-on completion and hover listeners do not receive the cursor position in the pinned `ruby-lsp` range. Primitive key vs. value positions are inferred from AST shape (`lib/ruby_lsp_dragonruby/primitive_context.rb`); trailing whitespace never reaches add-on listeners.
