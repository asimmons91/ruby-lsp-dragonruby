# M0-S3 — Warning delivery

Status: accepted (2026-09-25)

This decision answers how undefined-API warnings reach the user (REQ-M7-07).
Findings were produced against `ruby-lsp` 0.26.11 (the pinned range is
`~> 0.26.0`) and the Ruby LSP VS Code extension 0.5.x.

## Findings

### Add-ons have no diagnostics hook

`RubyLsp::Addon` (0.26.11) exposes completion, hover, definition, code lens,
document symbol, semantic highlighting, and discover-tests listener factories,
plus `workspace_did_change_watched_files`. There is no diagnostics listener,
and the request does not dispatch add-on listeners: `Requests::Diagnostics`
builds its result from `global_state.active_linters` only. The same is true on
`main` (checked while writing this document), so no immediate upgrade path
exists.

### Option 1 — formatter/linter registration (chosen)

`GlobalState#register_formatter` is public. A registered formatter whose
identifier appears in `initializationOptions.linters` is included in
`active_linters` and its `run_diagnostic(uri, document)` result is concatenated
into the pull response (`Requests::Diagnostics#perform`). A probe through
`RubyLsp::TestHelper#with_server` confirmed that the add-on's items appear in
`textDocument/diagnostic` once its identifier is configured, alongside Prism
syntax diagnostics.

Consequences:

- Diagnostics use the pull model: they update when the editor pulls (change or
  save, per `rubyLsp.pullDiagnosticsOn`), so REQ-M7-08's "update as the document
  is edited" holds, and Ruby LSP's document cache handles invalidation.
- Multiple linters compose: Ruby LSP concatenates every active linter's
  diagnostics, so RuboCop's and the add-on's items coexist (acceptance
  criterion). An add-on can never erase another linter's diagnostics.
- The user must opt in by adding the identifier to `linters` in editors that
  expose the option. The VS Code extension (0.5.x) passes neither `linters`
  nor `addonSettings`, so stock VS Code sees only the hover fallback until the
  extension exposes them. This is recorded as a known limitation instead of
  routed around.
- `textDocument/diagnostic` returns nothing for URIs outside
  `global_state.workspace_path` (`server.rb:889-896`). Diagnostics tests must
  use an in-workspace URI.

The identifier is `dragonruby`; the diagnostic source is `dragonruby`.

### Option 2 — publish through the outgoing queue (rejected)

The add-on could hold the `outgoing_queue` from `activate` and push
`Notification.publish_diagnostics`. The VS Code language client keeps push and
pull diagnostics in separate collections, so the items would display. It is
still rejected:

- Add-ons receive no `didOpen`/`didChange` notification. The only edit hook is
  `workspace_did_change_watched_files`, which fires on save (or external
  changes), so diagnostics go stale between saves — REQ-M7-08 fails.
- A publish replaces the full set of push diagnostics for that URI. Even if
  Ruby LSP 0.26 does not push diagnostics today, the M0-S3 risk is real and the
  Ruby LSP maintainers' guidance is that diagnostics must go through pull so
  one add-on cannot erase another's (Shopify/ruby-lsp#3736).

### Option 3 — hover warning (guaranteed baseline)

Hover always works with zero configuration and needs no settings. It is kept as
the fallback and is shown whenever warnings are enabled, regardless of whether
the linter is active (REQ-M7-07).

## Decision

- **Primary:** pull diagnostics through `global_state.register_formatter` with
  identifier `dragonruby`; users enable them by listing that identifier in the
  editor's `linters` setting/initialization option. Diagnostics have severity
  Warning or Hint and source `dragonruby` (REQ-M7-04).
- **Fallback:** the hover warning, always available and always shown when
  warnings are enabled.
- Push publishing through the message queue is not implemented.
- The VS Code limitation (no `linters`/`addonSettings` plumbing) is documented
  in the README and M0-S5; when Ruby LSP adds a first-class add-on diagnostics
  API, the formatter can delegate to it without changing the analyzer.
