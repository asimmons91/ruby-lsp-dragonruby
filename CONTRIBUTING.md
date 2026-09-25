# Contributing to ruby-lsp-dragonruby

Thanks for helping improve Ruby LSP support for DragonRuby. This document covers the
development workflow, the registry data format, and the release process.

## Getting started

```bash
bin/setup
bundle exec rake
```

`bundle exec rake` is the same gate CI runs: tests (including the fuzz sweep),
`standard` linting, registry validation, coverage, and the performance benchmarks.

Useful commands:

```bash
bundle exec rake test                                   # full test suite
bundle exec ruby -Itest test/ruby_lsp/ruby_lsp_dragonruby/test_dragonruby.rb
bundle exec standardrb --fix                            # lint and autocorrect
bundle exec rake registry:validate                      # fail on invalid data
bundle exec rake registry:coverage                      # coverage report
bundle exec rake benchmark                              # performance budgets
```

Lint is **standardrb**, not RuboCop. The requirements document mentions RuboCop in a
few places; the executable configuration is `standard`.

### Tests

Integration tests use Ruby LSP's `with_server` helper and send real completion,
hover, definition, and diagnostic requests. New features need tests for incomplete
code (trailing `.`, unclosed hash, missing values, half-typed identifiers).

Two hardening suites exercise the whole add-on:

- `test/ruby_lsp/ruby_lsp_dragonruby/test_fuzz.rb` drives every add-on feature at
  every cursor position in the sample game under `benchmark/sample_game/` and fails
  if any add-on entry point logs an error.
- `benchmark/run.rb` (via `bundle exec rake benchmark`) enforces the performance
  budgets: under 10 ms p95 for the add-on's share of a completion or hover request,
  and under one second to build the state index for a 50-file, ~10k-line workspace.

When adding to the sample game, keep the files small and run the fuzz test: it sweeps
every character position of every file.

## Registry data

All curated API data is YAML under `data/`, loaded once at activation. The format is
documented in detail in:

- [`docs/decisions/m1-registry-format.md`](docs/decisions/m1-registry-format.md) — files,
  types, members, generated families, load/validation semantics
- [`docs/decisions/m3-macros-and-primitives.md`](docs/decisions/m3-macros-and-primitives.md) —
  class macros (`attr_gtk`, `attr_sprite`) and primitive schemas
- [`docs/decisions/m6-core-extensions.md`](docs/decisions/m6-core-extensions.md) —
  core-class extensions and the `DragonRuby` label

A quick summary:

```yaml
# data/some_area.yml
types:
  - name: GTK::SomeType        # required, unique
    doc: "..."                 # optional Markdown
    parent: GTK::Base          # optional registry type
    open: true                 # optional, accepts arbitrary members
    incomplete: true           # optional, suppress warnings for now
    accepts_primitive: sprite  # optional primitive schema name (or list)
    core_backing: Array        # optional core class whose stock methods apply
    members:
      - name: do_thing
        kind: method           # method | attribute
        returns: Boolean       # type name, list for a union, or Unknown
        doc: "One to three sentences."
        docs_url: "https://..."
        params:
          - {name: value, kind: required, type: Numeric}
    generates:
      - names: some_name_list
        members:
          - name: "{{name}}"
            kind: attribute
            returns: Boolean
            doc: "The {{name}} thing."

schemas:
  - name: sprite
    primitive_marker: sprite
    keys:
      - {name: w, type: Numeric, doc: "...", default: 0, allowed_values: [0, 1]}
```

### Adding or updating an entry

1. Edit the relevant `data/*.yml` file. Keep docs to one to three sentences and use
   `docs_url` when a documentation anchor exists.
2. Add or update tests that prove the behavior (completion label, hover text, warning).
3. Run `bundle exec rake registry:validate`. Any error is fatal in CI; the load path
   logs and skips invalid data instead, so validation must pass.
4. Run `bundle exec rake registry:coverage` and make sure the report still passes. If
   an area is explicitly out of scope, add it with a `deferred: <reason>` entry rather
   than leaving it out.
5. Run `bundle exec rake` before opening a pull request.

Aliases are declared on members (`aliases: [other_name]`). Generated families keep one
identifier list in `data/names.yml` and one or more member templates so keys are never
written out by hand.

## New DragonRuby release procedure

The registry targets one DragonRuby version, recorded in `data/metadata.yml`.

1. Read the DragonRuby release notes and diff the API docs. The documentation sources
   live in the
   [dragonruby-game-toolkit-contrib](https://github.com/DragonRuby/dragonruby-game-toolkit-contrib)
   `docs/api` directory; the sidebar lists the documented areas.
2. Update the data:
   - add, remove, or rename members in the affected `data/*.yml` files
   - update primitive schemas in `data/primitives.yml` when keys or allowed values change
   - update `data/macros.yml` when class DSLs change
   - refresh `data/names.yml` when generated families gain or lose identifiers
3. Bump `dragonruby_version` (and `curated_at`) in `data/metadata.yml`.
4. Run the validator, coverage report, tests, and benchmarks:

   ```bash
   bundle exec rake
   ```

5. Update `CHANGELOG.md` under a new version heading and add the
   `Targets DragonRuby <version>` line.
6. Bump `lib/ruby_lsp_dragonruby/version.rb` following semver (the gem version is
   independent of the DragonRuby version) and release.

## Release checklist

1. Make sure the full gate passes: `bundle exec rake`.
2. Bump the version in `lib/ruby_lsp_dragonruby/version.rb`.
3. Update `CHANGELOG.md` with the release date and the targeted DragonRuby version.
4. Verify the package builds: `bundle exec rake build`.
5. Publish (requires your RubyGems credentials and MFA): `bundle exec rake release`.

`rake release` tags the version, pushes the commits and tag, and pushes the `.gem` to
RubyGems. The gemspec has `rubygems_mfa_required` enabled.
