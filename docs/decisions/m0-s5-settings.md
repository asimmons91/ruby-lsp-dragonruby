# M0-S5 — Settings

Status: accepted (2026-09-25)

This decision confirms how per-add-on settings reach the add-on (REQ-CFG-01)
and whether changes arrive without a restart. Findings were produced against
`ruby-lsp` 0.26.11 (the pinned range is `~> 0.26.0`) and the Ruby LSP VS Code
extension 0.5.x.

## Findings

- `GlobalState#apply_options` reads `initializationOptions.addonSettings`,
  converts the top-level keys to strings, and merges them into
  `@addon_settings` (`global_state.rb:204-208`). Values are not normalized, so
  nested keys keep whatever JSON/editor form they were sent in.
- `GlobalState#settings_for_addon(addon_name)` returns the hash stored under
  the add-on's `name`. The add-on name is stable API (`Ruby LSP DragonRuby` for
  this gem), and every editor passes initialization options through the same
  channel.
- `apply_options` runs during `initialize`, before `run_initialized` calls
  `load_addons`, so `activate` can read settings immediately.
- The server has no `workspace/didChangeConfiguration` handler. Settings
  changed in the editor after boot are not re-applied to a running server; a
  restart is required. The VS Code extension 0.5.x does not populate
  `addonSettings` at all, so users of that editor get the defaults until the
  extension exposes an add-on settings UI. Other editors can send the options
  directly.

## Decision

- Settings are read with `global_state.settings_for_addon(name)` through a
  small `Settings` value object (`lib/ruby_lsp_dragonruby/settings.rb`).
- `Settings` normalizes string/symbol keys at the top level and under
  `warnings`, tolerates missing or malformed values, and falls back to the
  REQ-CFG-03 defaults: `warnings.enabled: true`,
  `warnings.primitiveKeys: false`, `warnings.unassignedStateReads: false`,
  `warnings.allowlist: []`.
- The object is built per request (listener creation / `run_diagnostic`) rather
  than memoized at activation. This keeps zero configuration working by
  default, lets tests apply options after boot, and means a future
  `didChangeConfiguration` bridge would take effect without further changes.
- No settings UI is added by this gem; the keys and the linter identifier are
  documented in the README.

## Update (2026-09-25)

The settings key is now `rubyLspDragonruby`, matching editor configuration
conventions and decoupled from the add-on's display name. `Settings.from` looks
up `settings_for_addon(Settings::SETTINGS_KEY)`; `Addon#name` and the name
shown in Ruby LSP's add-on list remain `Ruby LSP DragonRuby`.
