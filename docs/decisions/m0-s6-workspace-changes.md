# M0-S6 — Workspace change events and the M5 storage choice

Status: accepted (2026-09-25)

This decision answers which file-change notifications reach the add-on and
whether indexing enhancements re-run per file on change, and records the
storage choice that M5 (REQ-M5-07) makes from those findings. Findings were
produced against `ruby-lsp` 0.26.11 (the pinned range is `~> 0.26.0`) and Prism
1.9.0.

## File change events

- `RubyLsp::Addon.load_addons` classifies an add-on as a file-watcher add-on
  when it responds to `workspace_did_change_watched_files`. The server then
  calls that method on every `workspace/didChangeWatchedFiles` notification
  (`server.rb:1069-1077`), passing the raw `changes` array (`{uri:, type:}`,
  with `type` 1/2/3 for created/changed/deleted).
- Ruby LSP registers `**/*.rb` (plus the RuboCop config files) when the client
  supports file watching (`server.rb:310-326`), so workspace Ruby files arrive
  without any add-on registration.
- Events are deferred (re-queued after a 2 second sleep) until
  `global_state.index.initial_indexing_completed` is true
  (`server.rb:1028-1042`), which means the add-on sees them only after the
  initial index exists.
- Before add-ons are notified, Ruby LSP updates its own index for `.rb`
  changes: created → `index_single`, changed → `handle_change` unless the URI
  is an open document managed by the store, deleted → `index.delete`
  (`server.rb:1080-1105`).

## Enhancement re-runs

`RubyIndexer::Enhancement.all` is invoked once per `DeclarationListener`
(`declaration_listener.rb:16`), so enhancements run on:

- initial `index_all` (one listener per file),
- `index_single` / `handle_change` triggered by watcher events,
- `run_combined_requests`, which re-indexes an open document on completion,
  hover, and definition requests (`server.rb:495-507`).

However, in 0.26 the only enhancement callbacks are `on_call_node_enter` and
`on_call_node_leave` (`ruby_indexer/enhancement.rb`). A state write with `||=`
parses as `Prism::CallOrWriteNode`, which never reaches an enhancement, and an
enhancement receives no parent or nesting context, so it cannot resolve M4
aliases or `attr_gtk` roots. A synthetic-owner index entry set therefore cannot
meet REQ-M5-01 for `args.state.x ||= ...`.

## Decision

M5 uses an **add-on-owned store** (`RubyLsp::Dragonruby::StateStore`) rather
than Ruby LSP's index:

- The store is populated by a one-time workspace scan (`StateTracker`). The
  scan runs lazily on the first add-on entry point instead of in `activate`,
  because `activate` runs before initial indexing and `attr_gtk` roots need the
  index (`MacroLookup`). This is the earliest point where the scan can follow
  every REQ-M5-01 pattern, and it satisfies REQ-M5-07's whole-workspace initial
  build and the REQ-PERF-03 budget.
- Watcher events replace a changed file's contributions and remove a deleted
  file's (REQ-PERF-04); `workspace_did_change_watched_files` is implemented on
  the add-on with its own rescue/log.
- Completion and definition requests carry a URI, so they refresh the current
  document from its already parsed AST before querying the store. Hover carries
  no URI in the pinned range, so it reads the store and falls back to an
  URI-less collection of the current AST when a path is unknown. This
  limitation is recorded in `m5-state-tracking.md`.
