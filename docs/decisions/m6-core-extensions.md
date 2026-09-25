# M6 — Core-class extensions

Status: accepted (2026-09-25)

This decision records how M6 implements REQ-M6-01 through REQ-M6-06:
completion and hover for DragonRuby's additions to core Ruby classes. Findings
were produced against `ruby-lsp` 0.26.11 (the pinned range is `~> 0.26.0`) and
Prism 1.9.0. The M0-S4 exposure choice is recorded in
`m0-s4-stub-indexing.md`.

## Data model

`data/core_extensions.yml` curates six types with a new type-level flag:

```yaml
types:
  - name: Numeric
    core_extension: true
    open: true
    members:
      - {name: seconds, kind: method, returns: Integer, doc: "..."}
```

- `core_extension: true` marks a type as curating a core Ruby class. The
  validator warns when the name is not one of the registry's core types. The
  loader builds the flag on `Type`, and `Registry#core_extension_type(name)`
  returns only flagged types.
- `Integer` and `Float` declare `parent: Numeric`, so `Integer` and `Float`
  inherit every Numeric member through the existing ancestor flattening.
- `Hash` and `Array` reuse one anchored block of Geometry mixin definitions via
  YAML anchors. Anchors are per file, so `geometry.yml` keeps its module
  variants (whose signatures take the receiver as a parameter); the mixin
  variants take only the arguments after the receiver.
- `Array` also curates its documented instance extensions and class-level
  method variants. `Kernel` curates `tick_count` and `global_tick_count`.

Members gained a `scope` field:

| scope | offered for |
|---|---|
| `instance` (default) | literal receivers, registry-resolved core returns, state values |
| `class` | constant roots (`Numeric.`, `Kernel.`, `Array.`) |
| `both` | both receiver kinds |

Curation follows the documented pages (`numeric.md`, `array.md`, and the
Geometry mixin list), with one deferral: `center_inside_rect_x` and
`center_inside_rect_y` are listed as mixins but have no documented signature,
so they are not curated until the engine source confirms their behavior.

## Resolution

`Resolution.of_core` is unchanged: `resolution_for` prefers `of_core` whenever
a return name is a core type, even though a core-extension type exists. This
keeps every pre-M6 consumer (`Resolution#core?`) behaviorally identical.

- `Resolver#resolve` types literal receivers: `Integer`, `Float`, `Hash`,
  `Array`, `String` (plain and interpolated), and `Symbol` (REQ-M6-04).
- `Resolver#resolve_call` resolves a member on a core receiver through
  `Registry#core_extension_type` and continues through the member's return
  type (REQ-M6-03). This covers literal receivers and registry returns such as
  `args.inputs.keyboard.active.seconds`.
- `Resolver#resolve_state_member` consults the state entry's inferred types
  after known child paths and curated entity members, so
  `args.state.player.intersect_rect?` resolves through the Hash extension.
- Receiverless calls matching a curated `Kernel` member (`tick_count`) resolve
  to the member's return type, so `tick_count.seconds` chains.
- Core-extension constants resolve through the existing constant root
  strategy; the `scope` filter is what keeps `Numeric.` from offering
  instance-only members.

## Presentation

- Completion adds a core branch. Literal and registry-resolved core receivers
  offer instance-scope members; core-extension constant roots offer class-scope
  members; state paths offer instance members for every inferred core type
  alongside entity members and child paths. Class scope is decided from the
  receiver node (a constant), not from the resolution kind, so a macro accessor
  that returns a core type (`attr_gtk`'s `passes` → `Hash`) is still an
  instance receiver. Bare `Kernel` calls complete the Kernel members.
- `StandardMethods` filters candidates that stock CRuby already defines.
  Instance filtering uses `instance_methods + private_instance_methods`; class
  filtering uses public `respond_to?(name)`. Private `Kernel` methods
  (`Kernel#rand`, `Kernel#select`) are not callable with an explicit class
  receiver in stock Ruby, so documented DragonRuby class-level extensions with
  those names stay offered. Lookups are memoized. This covers REQ-M6-06
  (`clamp`, `fdiv`, `between?`, `times`, `product`, ...) while a member's
  behavior can still be documented and resolve chains. The check runs only
  when offering completion items; hover still shows the curated docs for an
  explicitly written call.
- Items reuse the existing `"DragonRuby"` label detail. Hover adds
  `DragonRuby extension of \`<core type>\`.` to the docs (REQ-M6-05), for
  member calls and for bare or `self.` Kernel calls.

## Known limitations

- Core extensions are not exposed to Ruby LSP's own index (see M0-S4), so
  built-in completion does not see them and they have no go-to-definition.
- The hover note names the receiver's core type (`Integer` for `5.seconds`),
  not the ancestor that owns the member (`Numeric`).
- Class-level members are filtered by `scope`, so `Numeric.` offers only
  class/both members; `Array.` offers the documented class-level variants,
  many of which are stock instance methods promoted as extensions.
- Curated class-level signatures mirror the instance variants; documented
  class-only variants (`frame_index(start_at:, frame_count:)`,
  `Numeric.mid(l:, m:, r:)`) are not separately modeled.
- `rand` is offered at `Numeric.` (CRuby cannot call the private `Kernel#rand`
  with an explicit class receiver) but suppressed for instance receivers, where
  stock Ruby already defines it; other stock names (`clamp`, `times`, ...) are
  curated for docs and chain resolution but never offered as completion items
  (REQ-M6-06).
