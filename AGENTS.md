# AGENTS.md

## Project

`ruby-lsp-dragonruby` is a Ruby LSP add-on gem (runs on CRuby inside the LSP server, never inside DragonRuby) for hover/completion/go-to-definition on DragonRuby's `args` API, plus undefined-API warnings.

`docs/requirements_v1.md` is the authoritative spec — read it before implementing. It defines milestones M0–M8, per-requirement IDs (`REQ-*`), and explicit non-goals. M1 (the curated API registry under `data/`, plus loader/validator/coverage tooling) is implemented. The M0 technical spikes (`M0-S1`–`M0-S6`) are still open: they were deliberately deferred when M1 landed, and `docs/decisions/` records the decisions that do exist. Prefer milestone order for new work.

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
