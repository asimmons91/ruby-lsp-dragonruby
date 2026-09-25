# M0-S4 — Stub-file indexing for core extensions

Status: accepted (2026-09-25)

This decision answers whether the add-on can expose curated API members
through Ruby LSP's index by installing generated stub entries, and records the
exposure approach M6 uses. Findings were produced against `ruby-lsp` 0.26.11
(the pinned range is `~> 0.26.0`) with Prism 1.9.0.

## Question

Can the add-on ship generated Ruby stub files (or synthetic entries) and have
them added to Ruby LSP's index, given that development-only gems may be
excluded from indexing by default? The outcome decides how M6 exposes
core-class extensions (REQ-M6-02) and whether curated types get
go-to-definition as a side effect.

## Candidate approaches

### 1. Explicit indexing at activation

`RubyIndexer::Index#index_single(uri, source)` is public in 0.26 and accepts
any source and URI. A prototype indexed a generated stub on a synthetic URI:

```ruby
idx.index_single(URI("file:///dragonruby_core_extensions.rb"), <<~RUBY)
  class Numeric
    def frame_index(count, hold_for, repeat = false); end
  end
RUBY
```

Findings:

- Entries are added under the `Numeric` owner and are visible through
  `method_completion_candidates(nil, "Integer")` because Integer's ancestors
  include Numeric.
- `Index#delete(uri)` removes exactly the stub entries and leaves core entries
  alone, so invalidation is clean.
- Activation runs before initial indexing; `index_all` appends and does not
  raise, so entries survive the initial pass.
- Ruby LSP labels completion items with `Entry::Member#file_name`, which is
  `File.basename(uri)` (`dragonruby_core_extensions.rb`). It cannot be set to
  a display name.

### 2. Synthetic `Index#add(Entry::Method)` entries

Constructing `RubyIndexer::Entry::Method` values directly is possible, but it
depends on entry internals, configuration, and a fabricated `Location`, and it
has the same labeling limitation as approach 1.

### 3. Enhancement-driven indexing of reopened core classes

`RubyIndexer::Enhancement` in 0.26 only receives `on_call_node_enter` and
`on_call_node_leave`. Class declarations never reach add-ons, so the
enhancement cannot see `class Numeric` in the workspace. Registering accessors
through the existing `attr_gtk`-style path is not possible for core classes.
This confirms the API limitation already recorded in
`m3-macros-and-primitives.md`.

## Decision

M6 uses the **resolver fallback** from REQ-M6-02. No stub source is indexed and
no synthetic entries are created.

Reasons:

1. **Labeling.** REQ-M6-05 and the M6 acceptance criteria require core
   extension items to carry the "DragonRuby" label. Index-derived completion
   items show the stub file's basename instead, and because Ruby LSP's built-in
   completion runs before add-on listeners, the M0-S2 de-duplication rule means
   those items would shadow the add-on's items. Nothing would read "DragonRuby"
   in the item detail.
2. **The resolver path is required regardless.** REQ-M6-03 and REQ-M6-04 apply
   extensions to receivers that index-based inference cannot type: registry
   chains (`args.inputs.keyboard.active.`), state values with inferred core
   types (`args.state.player` as `Hash`), and literals in a workspace with no
   matching index entries. Index exposure would therefore be an additional,
   redundant mechanism.
3. **Index hygiene.** Core-extension entries would appear as workspace
   definitions for every project, and go-to-definition would jump to a
   synthetic URI that does not exist on disk.
4. **Pinning.** Both approaches rely on indexer internals that are already
   documented as 0.26-specific in `m3-macros-and-primitives.md`.

Consequences:

- Curated core extensions do not appear in Ruby LSP's own completion when its
  `TypeInferrer` recognizes a literal receiver. The add-on listener fills that
  gap for the positions M6 covers.
- Curated members get no go-to-definition, matching the v1 non-goal.
- Revisit if Ruby LSP exposes add-on index contributions with display names,
  custom label details, or a supported stub-indexing API.
