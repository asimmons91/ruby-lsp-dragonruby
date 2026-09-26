# Changelog

All notable changes to this project are documented here. Every release states the
DragonRuby version its registry targets.

## [Unreleased]

- The settings key under `initializationOptions.addonSettings` is now
  `rubyLspDragonruby`; the add-on name reported by Ruby LSP is unchanged.

## [1.0.0] - 2026-09-25

Targets DragonRuby 7.18.

- M8: performance benchmark suite with a committed sample game that enforces the
  completion/hover and workspace-scan budgets in CI
- M8: fuzz suite that exercises every feature at every cursor position in the sample
  game, including intentionally incomplete files
- M8: registry coverage report can explicitly defer a documented API area with a
  reason; `args.cvars`, `args.pixel_array`, and `Zlib` are recorded as deferred
- M8: CI runs the lowest and highest `ruby-lsp` versions in the pinned range
- M8: README, CONTRIBUTING, and release metadata
- M7: undefined-API warnings with edit-distance suggestions. Hover always shows the
  warning; diagnostics (source `dragonruby`) are delivered through the pull model when
  the editor lists the `dragonruby` linter. Optional primitive-key and
  unassigned-state-read hints and per-add-on settings
- M6: curated core-class extensions with completion and hover, including literal
  receivers and core-typed state values
- M5: workspace-wide `args.state` path tracking with completion, hover, and
  go-to-definition
- M4: local alias tracking, including aliases of state paths
- M3: primitive hash keys, allowed values, and the `attr_gtk`/`attr_sprite` macros
- M2: `args`-tree receiver resolution with completion and hover
- M1: curated DragonRuby API registry with loader, validator, and coverage tooling

## [0.1.0] - 2026-09-25

Targets DragonRuby 7.18.

- Initial release
