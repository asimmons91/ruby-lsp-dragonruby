# ruby-lsp-dragonruby — Requirements

A Ruby LSP add-on, distributed as a gem, that provides hover and completion for DragonRuby's built-in APIs. It also provides go-to-definition for `args.state` keys and warnings for references to undefined DragonRuby APIs.

---

## 1. Overview

### 1.1 Problem

DragonRuby's API is reached mainly through a dynamic object graph passed into `tick(args)`: `args.inputs.keyboard.key_down.space`, `args.outputs.sprites << { ... }`, `args.state.player.x`. Ruby LSP's built-in inference cannot tell that `args` is a `GTK::Args`. It knows nothing about primitive hash schemas, and it cannot see keys that are created dynamically on `args.state`. Editors therefore offer little or no help when writing DragonRuby code.

### 1.2 Goals

- Completion and hover for the whole `args` tree and related globals.
- Completion and hover for primitive hash keys (sprites, labels, solids, borders, lines, etc.).
- Workspace-wide tracking of `args.state` keys, with completion, hover, and go-to-definition.
- Completion and hover for DragonRuby's extensions to core Ruby classes.
- Completion and hover through local variable aliases (`kb = args.inputs.keyboard`).
- Warnings when code references a DragonRuby API member that does not exist.
- Work in any editor with a Ruby LSP integration. No editor-specific code.

### 1.3 Non-goals

- Type checking beyond the undefined-API warnings, including argument type validation.
- Signature help (may be revisited after 1.0).
- Supporting more than one DragonRuby version at a time.
- Hiding or filtering CRuby core and stdlib methods that don't exist in DragonRuby's mRuby runtime.
- Legacy array-style primitives (`[x, y, w, h, path]`).
- Inferring the schema of hashes that are built elsewhere and pushed into an output collection later.
- Go-to-definition for curated API members. This may happen incidentally; see M0-S4.

### 1.4 Assumptions

- The API data is hand-curated and targets the **latest** DragonRuby release only.
- The end user has a CRuby environment and a `Gemfile` for local dev tools (rake, rubocop, etc.), and adds this gem to it.
- The add-on runs inside Ruby LSP on CRuby, never inside DragonRuby itself.

### 1.5 Glossary

| Term | Meaning |
|---|---|
| **Registry** | The in-memory model of curated API types, members, and primitive schemas |
| **Root** | An expression whose DragonRuby type is known without further inference (e.g. an `args` parameter) |
| **Chain** | A sequence of method calls hanging off a root (`args.inputs.keyboard`) |
| **Primitive schema** | The set of valid keys, with types and defaults, for one kind of render primitive |
| **State path** | A dotted path under `args.state` (e.g. `player.x`) |
| **Confident resolution** | A receiver type that was resolved from a root through registry types only, with no `Unknown` hops |

---

## 2. Cross-cutting requirements

These apply to every milestone.

### 2.1 Packaging and compatibility

- **REQ-PKG-01** Ship as the gem `ruby-lsp-dragonruby`, with the add-on entry point at `lib/ruby_lsp/ruby_lsp_dragonruby/addon.rb`.
- **REQ-PKG-02** Declare a runtime dependency on `ruby-lsp`, pinned to a minor-version range (e.g. `~> 0.x.0`). The add-on API is experimental and has had breaking changes.
- **REQ-PKG-03** Add no runtime dependencies beyond `ruby-lsp` and what it already brings in (e.g. Prism).
- **REQ-PKG-04** Support the Ruby versions that the pinned Ruby LSP range supports.
- **REQ-PKG-05** Work when the gem is only in the `:development` group of the user's Gemfile.
- **REQ-PKG-06** The add-on reports a `name` and a `version`. The version follows semver independently of the DragonRuby version.

### 2.2 Robustness

- **REQ-ROB-01** An exception inside any listener or indexing hook must never break Ruby LSP's own response. Every add-on entry point rescues errors, logs them, and contributes nothing.
- **REQ-ROB-02** Every feature degrades gracefully on incomplete or syntactically invalid code, returning nothing rather than raising.
- **REQ-ROB-03** The add-on never mutates Ruby LSP documents or global state except through documented APIs.

### 2.3 Performance

- **REQ-PERF-01** Load and validate the registry once, at activation.
- **REQ-PERF-02** The add-on's share of a completion or hover request should be negligible next to Ruby LSP's own work (target: under 10 ms p95 on a typical game file). Per-request work is limited to local AST walking and hash lookups.
- **REQ-PERF-03** Build the initial `args.state` index for a typical game (≈ 50 files, ≈ 10k lines) in under 1 s.
- **REQ-PERF-04** When a file changes, re-index only that file's contributions.

### 2.4 Configuration

- **REQ-CFG-01** Settings are read through Ruby LSP's per-add-on settings mechanism (confirm in M0), so they work in any editor.
- **REQ-CFG-02** Every feature works with zero configuration.
- **REQ-CFG-03** Configurable settings (full list in M7):
  - `warnings.enabled`: default `true`
  - `warnings.primitiveKeys`: default `false`
  - `warnings.unassignedStateReads`: default `false`
  - `warnings.allowlist`: default `[]`

### 2.5 Presentation

- **REQ-UX-01** Hover content is Markdown. It shows a signature or type line first, then a short description, then a "DragonRuby docs" link when a URL is curated.
- **REQ-UX-02** Completion items carry the correct LSP kind (method, property, field, etc.). Their detail shows the return or value type, and their documentation shows the curated description.
- **REQ-UX-03** The add-on never produces completion items that duplicate what Ruby LSP already offers at the same position.

### 2.6 Testing

- **REQ-TEST-01** Integration tests use Ruby LSP's `with_server` test helper and send real `textDocument/completion`, `textDocument/hover`, and `textDocument/definition` requests.
- **REQ-TEST-02** Every feature has tests for incomplete code: trailing `.`, unclosed hash, missing values, a half-typed identifier.
- **REQ-TEST-03** CI runs against the lowest and highest `ruby-lsp` versions in the pinned range.

---

## 3. Milestones

Each milestone ends with a usable, releasable increment. Milestones are ordered by dependency:

- The registry comes before everything else.
- The resolver comes before primitives, aliases, and state.
- Warnings come last because they depend on the registry being complete.

---

### M0 — Foundations and technical spikes

**Goal:** a gem skeleton that activates inside Ruby LSP, plus answers to the open technical questions that later milestones depend on.

#### Deliverables

- **REQ-M0-01** A gem skeleton with the gemspec, the add-on entry point, and a no-op `activate`/`deactivate`.
- **REQ-M0-02** CI running the test suite, RuboCop, and the version matrix from REQ-TEST-03.
- **REQ-M0-03** A test harness with helpers that build a document with a cursor marker and assert on completion labels and hover content.
- **REQ-M0-04** Error isolation around every entry point (REQ-ROB-01), including a logger for rescued errors.

#### Spikes

Each spike produces a short written decision in `docs/decisions/`.

- **M0-S1 — Node context sufficiency.** For a cursor in a half-typed chain (`args.inputs.`), determine what the node context passed to listeners provides: the call node, the enclosing method, its parameters, and locals. Decide whether the add-on must walk the enclosing method's AST itself.
- **M0-S2 — Interaction with built-in completion.** Record what Ruby LSP already offers after `args.`, `state.`, `5.`, and inside a hash literal. This covers its name-based type guessing for variables and core-method completion. Define the de-duplication rule (REQ-UX-03).
- **M0-S3 — Warning delivery.** Ruby LSP's add-on API has no diagnostics listener. Evaluate these options:
  1. Register a diagnostics provider through the linter/formatter mechanism, and check whether it requires user configuration.
  2. Publish diagnostics directly through the outgoing message queue. The risk is overwriting Ruby LSP's own diagnostics, because a publish for a document replaces the full set of diagnostics for that document.
  3. Show a warning inside hover only.

  Choose a primary mechanism and a fallback. Option 3 is the guaranteed baseline.
- **M0-S4 — Stub-file indexing.** Determine whether the add-on can ship generated Ruby stub files and have them added to Ruby LSP's index, given that development-only gems may be excluded from indexing by default. Candidate approaches are explicit indexing at activation or synthetic index entries. The outcome decides how M6 exposes core-class extensions, and whether curated types get go-to-definition as a side effect.
- **M0-S5 — Settings.** Confirm how per-add-on settings reach the add-on, and whether changes arrive without a server restart.
- **M0-S6 — Workspace change events.** Confirm which file-change notifications reach the add-on, and whether indexing enhancements re-run per file on change. This informs the storage choice in M5.

#### Acceptance criteria

- With the gem in a sample project's Gemfile, Ruby LSP lists the add-on as active.
- All six spike decisions are written down, and any requirement they invalidate is updated.

---

### M1 — API data model and core curation

**Goal:** a validated, curated registry covering the `args` tree.

#### Data model

- **REQ-M1-01** Store registry data as YAML files under `data/`, one file per type or logical area.
- **REQ-M1-02** A **type** has:
  - a fully qualified name, using DragonRuby's actual class names where known (confirm during curation)
  - an optional parent type
  - a list of members
  - an optional `accepts_primitive` schema reference, for collection types
  - an optional `open: true` flag, for types that accept arbitrary members, such as state entities
- **REQ-M1-03** A **member** has:
  - `name`
  - `kind`: `method` or `attribute`
  - `params`: name, kind (required, optional, keyword, rest, block), and type
  - `returns`: a registry type, a core type (`Integer`, `Boolean`, …), a union, or `Unknown`
  - `doc`: Markdown, one to three sentences
  - `docs_url`: optional
  - `aliases`: optional
- **REQ-M1-04** A **primitive schema** has a name, an optional `primitive_marker` value, and keys. Each key has a name, type, default, doc, and optional allowed values. The schema data is defined here and curated in M3.
- **REQ-M1-05** Registry metadata records the targeted DragonRuby version and the curation date.
- **REQ-M1-06** Families of generated members, such as individual keyboard keys, are expressed as one list plus a template for the doc. Each member is not written out by hand.

#### Loader and validation

- **REQ-M1-07** A loader builds the immutable in-memory registry at activation.
- **REQ-M1-08** A schema validator runs in CI and at load time. At load time, invalid data is logged and skipped, never fatal. It checks:
  - required fields are present
  - every `returns` and param type resolves
  - there are no duplicate members
  - there are no dangling schema references
- **REQ-M1-09** A coverage report lists curated types and member counts next to a checklist mapped to DragonRuby documentation sections.

#### Curation scope for M1

- **REQ-M1-10** Curate at least:
  - `args`
  - `args.inputs`: keyboard, mouse, controllers, touch, and the combined directional helpers
  - `args.outputs`: all collections, including `static_*`, `debug`, `background_color`, and render targets
  - `args.grid`
  - `args.geometry`
  - `args.easing`
  - `args.audio`
  - `args.gtk` / `$gtk`: commonly used members
  - `args.layout`
  - `args.events`
  - `args.state`: its non-dynamic members only

#### Acceptance criteria

- The validator passes in CI.
- The coverage report shows every M1 area curated.
- The registry loads in under 100 ms.

---

### M2 — Receiver resolution, args-tree completion and hover

**Goal:** completion and hover work anywhere in the `args` tree, starting from any recognized root. `attr_gtk` roots are added in M3.

#### Roots

- **REQ-M2-01** A method parameter named `args` resolves to the Args type, in any method, not only `tick`.
- **REQ-M2-02** The globals `$gtk` and `$args` resolve to their registry types.
- **REQ-M2-03** Curated top-level constants (e.g. `GTK`, `Geometry`, if curated as modules) resolve to their registry types.
- **REQ-M2-04** The resolver's set of roots is extensible, so M3 (`attr_gtk`) and M4 (local aliases) can add roots without changing the chain logic.

#### Chain resolution

- **REQ-M2-05** Resolve chains left to right through member `returns` types.
- **REQ-M2-06** An `Unknown` hop, a member missing from the registry, or an unrecognized root ends resolution. A non-confident resolution never produces add-on completions or hovers.
- **REQ-M2-07** Handle safe navigation (`&.`) and parenthesized calls.
- **REQ-M2-08** `args.outputs[:name]` (index call with any argument) resolves to the render-target type.
- **REQ-M2-09** Resolution works on half-typed chains: a trailing `.`, or a partial member name after the `.`.

#### Completion and hover

- **REQ-M2-10** After a confidently resolved receiver followed by `.`, offer every member of that type (and its parents), filtered by any partial name typed.
- **REQ-M2-11** Hovering a member name in a confidently resolved chain shows that member's signature, return type, and doc (REQ-UX-01).
- **REQ-M2-12** Hovering a root (`args` or `$gtk`) shows the root's type and doc.
- **REQ-M2-13** Apply the de-duplication rule from M0-S2.

#### Acceptance criteria

- `def tick(args); args.inputs.keyboard.|` offers the curated keyboard members.
- `args.outputs[:rt].|` offers the outputs collection members.
- `foo.bar.|` with an unknown root produces no add-on items.
- Every M2 behavior has a test for incomplete code.

---

### M3 — Primitive hash keys and class DSLs (`attr_sprite`, `attr_gtk`)

**Goal:** completion and hover for keys inside primitive hash literals, and support for DragonRuby's two class-level DSLs: `attr_sprite` and `attr_gtk`. Both DSLs are handled as indexing enhancements that share one implementation.

#### Curation

- **REQ-M3-01** Curate schemas for sprite, label, solid, border, and line, plus any other current primitive kinds, with every documented key.
- **REQ-M3-02** Link each output collection type to its schema through `accepts_primitive`.
- **REQ-M3-03** Record allowed values where they are enumerable, such as alignment and blend mode values.

#### Detection

- **REQ-M3-04** A hash literal is a **primitive context** when it is:
  - an argument to `<<`, `push`, or `concat` on a confidently resolved collection with an `accepts_primitive` schema
  - an element of an array literal passed to one of those calls
- **REQ-M3-05** For a generic `primitives` collection, choose the schema from the hash's `primitive_marker` value when present. Otherwise offer the union of all schemas, marking each key's schema(s) in the item detail.
- **REQ-M3-06** Primitive contexts are recognized through local aliases once M4 lands (e.g. `sprites = args.outputs.sprites; sprites << { … }`).

#### Completion and hover

- **REQ-M3-07** Inside a primitive context, at a key position, offer schema keys not already present in the hash. Each item's detail shows the type and default, and its insert text is `key: `.
- **REQ-M3-08** Once a key with enumerable allowed values has been typed, offer those values at the value position.
- **REQ-M3-09** Hovering a key inside a primitive context shows its type, default, allowed values, and doc.

#### `attr_sprite`

- **REQ-M3-10** An indexing enhancement registers sprite-schema accessors on any class that calls `attr_sprite`.
- **REQ-M3-11** Hover on those accessors shows the sprite key doc.

#### `attr_gtk`

- **REQ-M3-12** Curate the full set of accessors that `attr_gtk` defines in the latest DragonRuby release. Store them in the registry as a single list, with each accessor mapped to its registry type. The list includes at least `args`, `state`, `inputs`, `outputs`, `grid`, `geometry`, `gtk`, `layout`, `audio`, `easing`, and `events`.
- **REQ-M3-13** An indexing enhancement registers those accessors on any class or module that calls `attr_gtk`, so Ruby LSP's built-in features know those methods exist.
- **REQ-M3-14** Inside such a class or module, bare calls and `self.` calls to those accessors become resolver roots, using the extension point from REQ-M2-04. Resolution then continues through the chain exactly as it does from `args`.
- **REQ-M3-15** Primitive contexts are recognized through `attr_gtk` accessors (e.g. `outputs.sprites << { … }` inside an `attr_gtk` class).
- **REQ-M3-16** Hovering an `attr_gtk` accessor shows its type and doc, and notes that it comes from `attr_gtk`.
- **REQ-M3-17** Recognize `attr_gtk` when it is called directly in the class or module body. Calls made through metaprogramming, and inheritance from a superclass defined outside the workspace, are out of scope. Inheritance from a workspace class that calls `attr_gtk` is in scope when Ruby LSP's index already resolves that ancestry.
- **REQ-M3-18** `attr_sprite` and `attr_gtk` share one enhancement implementation, driven by registry data: macro name → accessor list. Supporting a future DragonRuby class DSL should then require only a data change.

#### Acceptance criteria

- `args.outputs.sprites << { x: 0, |` offers the sprite keys minus `x`.
- `args.outputs.labels << [{ |` offers the label keys.
- `args.outputs.primitives << { primitive_marker: :solid, |` offers only the solid keys.
- In a class that calls `attr_sprite`, `self.|` includes the sprite accessors.
- A hash not in a primitive context gets no key completions.
- In a class that calls `attr_gtk`, `outputs.|` offers the same members as `args.outputs.|`, and `inputs.keyboard.|` offers the keyboard members.
- In an `attr_gtk` class, `outputs.sprites << { |` offers the sprite keys.
- In a subclass of a workspace class that calls `attr_gtk`, `state.|` resolves.
- In a class that does not call `attr_gtk`, bare `outputs.|` produces no add-on items.

---

### M4 — Local alias tracking

**Goal:** types flow through local variables within a method.

- **REQ-M4-01** When a local variable is assigned an expression that resolves confidently (`kb = args.inputs.keyboard`), later uses of that variable in the same scope resolve to that type.
- **REQ-M4-02** Resolution uses the **nearest preceding assignment** in source order within the scope. Assignments inside conditionals count; the add-on does no flow analysis.
- **REQ-M4-03** A later reassignment to an expression that does not resolve (or resolves to a different type) replaces the earlier type from that point on.
- **REQ-M4-04** Block scoping follows Ruby semantics:
  - blocks see enclosing locals
  - locals first assigned in a block are not visible after it
  - block parameters shadow outer locals
- **REQ-M4-05** Aliases may chain (`i = args.inputs; kb = i.keyboard`).
- **REQ-M4-06** Aliases of `args.state` or of state sub-paths participate in M5 tracking.
- **REQ-M4-07** Instance variables, multiple assignment, and aliases across methods are out of scope.
- **REQ-M4-08** Hovering an alias variable shows its resolved type.

#### Acceptance criteria

- `kb = args.inputs.keyboard; kb.|` offers the keyboard members.
- `s = args.outputs.sprites; s << { |` offers the sprite keys.
- After `kb = nil`, `kb.|` produces no add-on items.
- A block-local alias does not leak out of its block.

---

### M5 — `args.state` tracking and go-to-definition

**Goal:** workspace-wide knowledge of state paths, with completion, hover, and definition.

#### Collection

- **REQ-M5-01** Record writes to state paths from these patterns:
  - `args.state.<path> ||= <expr>`
  - `args.state.<path> = <expr>`
  - the same forms through `attr_gtk` `state`
  - the same forms through M4 aliases of state or state sub-paths
- **REQ-M5-02** Nested paths create intermediate nodes (`args.state.player.x ||= 0` records `player` and `player.x`).
- **REQ-M5-03** For each path, record every write site (URI and range), and mark each as `||=` (initialization) or `=` (assignment).
- **REQ-M5-04** Infer a value type from simple right-hand sides:
  - literals
  - array literals
  - hash literals
  - `args.state.new_entity(...)` and other curated entity constructors
  - expressions that resolve confidently through the registry
  - otherwise `Unknown`
- **REQ-M5-05** When the right-hand side is a hash literal, record its symbol keys as child paths. This depends on confirming during curation that DragonRuby allows method-style access to hash keys on state values. If it doesn't, children are recorded but only offered where valid.
- **REQ-M5-06** Reads are not recorded as definitions.

#### Storage and invalidation

- **REQ-M5-07** Choose between Ruby LSP's index (via an indexing enhancement, with synthetic owners) and an add-on-owned store, based on M0-S6. Either way:
  - the initial build covers the whole workspace at activation or at initial indexing
  - a changed file's contributions are replaced; a deleted file's are removed
  - the performance targets in REQ-PERF-03 and REQ-PERF-04 are met

#### Features

- **REQ-M5-08** After a state root (`args.state.`, `state.`, or an alias) or a state sub-path, offer:
  - the known child paths
  - the curated non-dynamic members of the state type
- **REQ-M5-09** Hover on a state path shows its inferred type(s) (a union if the write sites disagree), the number of write sites, and the first initialization site.
- **REQ-M5-10** Go-to-definition on a state path returns every write site, with `||=` sites first, in file order.
- **REQ-M5-11** State completion and hover work across files: a key written in `app/player.rb` is offered in `app/main.rb`.

#### Acceptance criteria

- After editing a file to add `args.state.score ||= 0`, `args.state.|` in another file offers `score` without a restart.
- Removing the last write of a key removes it from completion.
- Definition on `args.state.player.x` jumps to its write sites.
- Index build time meets REQ-PERF-03 on the sample project.

---

### M6 — Core-class extensions

**Goal:** completion and hover for DragonRuby's additions to core Ruby classes.

- **REQ-M6-01** Curate DragonRuby's extensions to core classes, such as Numeric/Integer/Float, Hash, Array, Kernel, and any others documented, as registry entries marked `core_extension: true`. Examples include geometry helpers like `intersect_rect?` on Hash and Array, and frame and time helpers on Numeric; exact coverage comes from curation.
- **REQ-M6-02** Expose core extensions using the approach chosen in M0-S4:
  - **Preferred:** make them known to Ruby LSP's index, so its own type inference offers them wherever it already knows the receiver is a core type.
  - **Fallback:** offer them from the add-on's resolver.
- **REQ-M6-03** The resolver also applies core extensions when a chain resolves to a core type through the registry, e.g. a member returning `Integer`, or a state path inferred as `Hash`.
- **REQ-M6-04** The resolver types literal receivers: `5.`, `1.5.`, `{}.`, `[].`, `"".`, `:sym.`.
- **REQ-M6-05** Core-extension completion items and hovers are labeled as DragonRuby additions, so users can tell them apart from standard Ruby methods.
- **REQ-M6-06** Follow the de-duplication rule; never re-offer standard Ruby core methods.

#### Acceptance criteria

- `5.|` includes the curated Numeric extensions.
- `args.state.player ||= { … }` followed by `args.state.player.|` includes the Hash extensions.
- The extensions show the "DragonRuby" label in their item detail.

---

### M7 — Undefined-API warnings

**Goal:** warn when code calls a DragonRuby API member that doesn't exist, without noisy false positives.

#### Rules

- **REQ-M7-01** Warn when a call's receiver resolves **confidently** to a registry type and:
  - the called member is not in that type or its parents, **and**
  - the member is not defined for that type anywhere in Ruby LSP's index (covers users reopening DragonRuby classes), **and**
  - the member is not a standard Ruby method on that type (e.g. `inspect`, `class`, `send`), **and**
  - the type is not marked `open`.
- **REQ-M7-02** Never warn:
  - on receivers that are not resolved confidently
  - on `args.state` or other `open` types
  - on names in `warnings.allowlist`
  - when the add-on has marked the registry for that type as incomplete (a curation flag)
- **REQ-M7-03** Warning message format: *"`<member>` is not a known member of `<Type>` in DragonRuby <version>"*. When a registry member is close by edit distance, add *"Did you mean `<suggestion>`?"*.
- **REQ-M7-04** Severity is Warning. The diagnostic source is `dragonruby`.

#### Optional warnings (off by default)

- **REQ-M7-05** `warnings.primitiveKeys`: warn on hash keys in a primitive context that are not in the schema. Hint severity. Off by default because DragonRuby allows arbitrary extra keys on primitives.
- **REQ-M7-06** `warnings.unassignedStateReads`: warn when a state path is read but has no write sites anywhere in the workspace. Hint severity.

#### Delivery

- **REQ-M7-07** Deliver warnings through the primary mechanism chosen in M0-S3. The hover warning (the fallback) is always shown regardless of mechanism: hovering an undefined member displays the warning text.
- **REQ-M7-08** Warnings update as the document is edited, and never replace or hide diagnostics from Ruby LSP or other add-ons.
- **REQ-M7-09** `warnings.enabled: false` turns off all warnings.

#### Acceptance criteria

- `args.inputs.keybaord` warns with a suggestion of `keyboard`.
- `args.state.anything` never warns.
- `foo.inputs.keybaord` with an unknown root does not warn.
- Reopening `GTK::Outputs` in the workspace to add `my_helper` suppresses the warning for `args.outputs.my_helper`.
- RuboCop diagnostics still appear alongside the add-on's warnings.

---

### M8 — Hardening and 1.0 release

**Goal:** production quality, documentation, and a sustainable curation process.

- **REQ-M8-01** A performance benchmark suite with a representative sample game, which enforces REQ-PERF-02 and REQ-PERF-03 in CI.
- **REQ-M8-02** Fuzz-style tests: every feature exercised at every cursor position in the sample game files must raise nothing.
- **REQ-M8-03** The coverage report shows every documented DragonRuby API area curated, or explicitly deferred with a reason.
- **REQ-M8-04** A README covering installation (Gemfile snippet), supported Ruby LSP versions, the targeted DragonRuby version, settings, and known limitations.
- **REQ-M8-05** `CONTRIBUTING.md` documenting:
  - the data format
  - how to add or update registry entries
  - how to run the validator and coverage report
  - the procedure when a new DragonRuby release ships: diff the release notes, update the data, bump the targeted version in metadata, release
- **REQ-M8-06** A changelog. Every release states which DragonRuby version its registry targets.
- **REQ-M8-07** Publish 1.0.0 to RubyGems.

#### Acceptance criteria

- All acceptance criteria from M1–M7 pass in CI across the Ruby LSP version matrix.
- The benchmarks meet their targets.
- A fresh project following the README gets working completion within five minutes.

---

## 4. Open questions

| # | Question | Resolved by |
|---|---|---|
| 1 | Does the node context give enough scope information, or must the add-on walk the method AST? | M0-S1 |
| 2 | Which warning delivery mechanism is viable without clobbering other diagnostics? | M0-S3 |
| 3 | Can the gem's stub files or synthetic entries be indexed when the gem is development-only? | M0-S4 |
| 4 | Store state in Ruby LSP's index or an add-on-owned store? | M0-S6, M5 |
| 5 | Does DragonRuby allow method-style access to hash keys on state values (affects REQ-M5-05)? | M1 curation |
| 6 | Exact DragonRuby class names for curated types | M1 curation |
| 7 | Which core-class extensions DragonRuby currently documents | M6 curation |
