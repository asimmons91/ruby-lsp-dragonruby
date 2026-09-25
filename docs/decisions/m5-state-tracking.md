# M5 — `args.state` tracking, hover, and go-to-definition

Status: accepted (2026-09-25)

This decision records how M5 implements REQ-M5-01 through REQ-M5-11: a
workspace-wide store of `args.state` paths with completion, hover, and
go-to-definition. Findings were produced against `ruby-lsp` 0.26.11 (the pinned
range is `~> 0.26.0`) and Prism 1.9.0. The storage choice and its M0-S6 basis
are recorded in `m0-s6-workspace-changes.md`.

## Collection

`RubyLsp::Dragonruby::StateCollector` walks a parsed document and recognizes:

- `args.state.<path> ||= <expr>`, parsed as `Prism::CallOrWriteNode`
  (initialization),
- `args.state.<path> = <expr>`, parsed as a `Prism::CallNode` with
  `attribute_write?` and a `name` ending in `=` (assignment).

Reads are never recorded (REQ-M5-06). The same forms work through `attr_gtk`
`state.` accessors and `self.state.` because the collector resolves the write's
receiver with the existing `Resolver` inside a `NodeContext` it builds from the
scope chain, so `Roots::MacroAccessor` and `LocalAliases` apply unchanged.
Aliases of `args.state` and of state sub-paths participate through the same
`Resolver` (REQ-M4-06).

Path extraction is structural: the collector walks the receiver chain inward
until a node resolves to the state root or to a state path, then appends the
outer segments. This matters because curated `GTK::Entity` members such as `x`
and `y` would otherwise stop a nested write like `args.state.player.x ||= 0`
when the store has not seen the path yet.

Nested paths create intermediate nodes (`player` for `player.x`) carrying the
nested write's site and the `GTK::Entity` type (REQ-M5-02). Hash literal
right-hand sides record their symbol and string keys as child paths,
recursively (REQ-M5-05). DragonRuby's curated `GTK::Entity` documentation
states that properties "can be read and written with method syntax, including
nested values", which is what makes these children offerable; the idiomatic
`args.state.player ||= { x: 0 }; args.state.player.x += 1` game code depends on
it.

Types are inferred from the right-hand side (REQ-M5-04): literal node classes
map directly (`Integer`, `Float`, `String`, `Symbol`, `Boolean`, `Array`,
`Hash`), and everything else is resolved through the registry, so
`args.state.new_entity(...)` becomes `GTK::Entity` and
`args.state.kb = args.inputs.keyboard` becomes `GTK::Keyboard`. Unresolvable
values store `Unknown`.

## Storage

`StateStore` keeps, per path: its parent, direct children, and the list of
write sites with URI, range, kind, and inferred type. Contributions are
indexed by URI, so `replace` drops a file's previous paths before inserting the
new ones and `remove` drops them outright (REQ-PERF-04). `StateTracker` owns
the store and drives it:

- `ensure_workspace_scanned` globs `**/*.rb` under the workspace (skipping
  `vendor`, `node_modules`, `tmp`, and hidden directories, which Ruby's glob
  already excludes) and runs once, lazily on the first add-on entry point. It
  waits until `index.initial_indexing_completed`, because `activate` runs
  before initial indexing, which itself runs on a background thread; a first
  request can otherwise scan with an empty index and miss `attr_gtk` roots.
  Requests in that window still get same-file completion from the AST refresh.
- `workspace_did_change_watched_files` replaces changed files from disk and
  removes deleted ones.
- `refresh` re-collects the current document from its parsed AST on completion
  and definition requests, so unsaved edits are visible.
- `entry_with_context` answers hover: it prefers the store, and falls back to a
  URI-less collection of the current AST when the path is unknown. Hover cannot
  refresh the store itself because `create_hover_listener` receives no URI in
  the pinned range; write sites collected this way display as `line N`.

Bulk collection resets `LocalAliases`' memoized scope walks before each
document, and those walks are indexed by variable name so a read scans only its
own candidates. Without both, resolving every `args` read in a file re-walked
the whole program, and the 50-file/10k-line scan took over 8 seconds. With
them, the generated sample scans in well under the REQ-PERF-03 one-second
budget.

The per-request re-collection of the current file is linear in its state
writes (measured at roughly 6 microseconds per write plus the AST walk in
Ruby 4.0). Typical game files stay within the REQ-PERF-02 guidance; a
multi-thousand-write file can exceed it on each keystroke, which is accepted
because such files are not the target workload.

## Resolution

`Resolution` gains `of_state(path)` alongside registry and core types. A
`state_path?` resolution is confident but not `resolved_type?`, so every
existing consumer (primitive contexts, member hover, chain completion) keeps
its current behavior unless it opts in.

`Resolver#resolve_call` extends chains when:

- the receiver is the `GTK::State` type (`Registry#state_type`), the member is
  missing, and the call is plain (no arguments, parentheses, or block): the
  call becomes `of_state(name)`;
- the receiver is a state path: a store-known child path wins, then a curated
  `GTK::Entity` member, then an argument-free extension.

The store check is what makes `args.state.player.x` a state path even though
`GTK::Entity` curates `x` for event positions.

## Features

- **Completion (REQ-M5-08).** After `args.state.`, the curated `GTK::State`
  members and the root's known children are offered. After a sub-path, the
  curated `GTK::Entity` members and that path's children are offered. Dynamic
  items are `FIELD` kind, show the union of inferred types in their detail,
  and carry the write count and first initialization in their documentation.
  Existing labels win, preserving the M0-S2 de-duplication rule. Cross-file
  keys work because the store is workspace-wide (REQ-M5-11).
- **Hover (REQ-M5-09).** Shows `path → T1 | T2`, the number of write sites,
  and the first initialization site, initializations first in file order.
- **Definition (REQ-M5-10).** Every write site of the path, `||=` sites first,
  then by URI and position, returned as `Interface::Location`s so editors with
  multiple-definition support get the full list.

## Known limitations

- No flow analysis: any write of a path counts regardless of the condition it
  sits under, matching M4's alias semantics.
- Method chains on state values (`args.state.player.as_hash.foo = 1`) can
  collect a path that the runtime would not treat as state; such chains are
  not idiomatic.
- Hover data can be stale until the next completion or definition request in
  the same file, a watcher notification, or the initial scan.
- `||=` is the only or-write form tracked; `&&=` and operator writes (`+=`)
  are reads plus a write and are not collected.
- The initial scan reads files from disk, so unsaved buffers are only current
  for the document the request targets.
