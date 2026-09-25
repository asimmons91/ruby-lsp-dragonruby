# M3 — Primitive schemas and class macro indexing

Status: accepted (2026-09-25)

This decision records how M3 implements REQ-M3-01 through REQ-M3-18: curated
primitive hash keys, primitive-context completion and hover, and the
`attr_sprite` / `attr_gtk` class macros. Findings were produced against
`ruby-lsp` 0.26.11 (the pinned range is `~> 0.26.0`) and Prism 1.9.0.

## Registry data

`accepts_primitive` now accepts a schema name or a **list** of schema names.
Concrete collections link one schema (`sprites -> sprite`); generic
collections (`primitives`, `static_primitives`, `debug`, render targets) list
every primitive schema. When a hash in a generic context contains a
`primitive_marker: :solid` value, only that schema's keys are offered;
otherwise the union of schemas is offered, with each item's label details
naming its schema(s).

A new top-level `macros` document maps a macro name to its accessors:

```yaml
macros:
  - name: attr_gtk
    aliases: [attr_dr]
    accessors:
      - {name: inputs, returns: GTK::Inputs, doc: "..."}
  - name: attr_sprite
    primitive: sprite
```

A macro is either declared with an explicit `accessors` list or backed by a
schema via `primitive`. The loader expands primitive-backed macros from the
schema keys, so a future DragonRuby class DSL needs data only (REQ-M3-18).
`data/macros.yml` curates `attr_gtk` (alias `attr_dr`, the name the current
docs use) with the full accessor list, and `attr_sprite` backed by the sprite
schema.

`data/primitives.yml` curates every documented key for `sprite`, `label`,
`solid`, `border`, `line`, and `screenshot`, including defaults and allowed
values for enumerable keys (alignment, blend modes). `data/coverage.yml`
gains `primitives` and `macros` areas, so `rake registry:coverage` gates them.

## Indexing enhancement

`RubyLsp::Dragonruby::IndexingEnhancement` subclasses
`RubyIndexer::Enhancement`. In 0.26 the `inherited` hook registers the class
globally, and every `DeclarationListener` instantiates it. `Addon#activate`
sets the class-level `registry` and `deactivate` clears it, so the
enhancement is inert outside an active add-on.

When a workspace file calls a macro with no receiver, the enhancement adds one
method per accessor through the listener's public `add_method`, with the
curated doc as the comment. There is no marker method: a marker would show up
in `self.` completion inside the class. Instead every generated accessor's
comment starts with an invisible HTML-comment sentinel
(`<!-- dragonruby:attr_gtk -->`), and `MacroLookup.applied?` checks the
sentinel on any accessor found for the enclosing class or one of its indexed
ancestors (`Index#method_completion_candidates` linearizes ancestors).

The enhancement runs for the initial workspace index and for re-indexed files.
`RubyLsp::TestHelper#with_server` indexes the document before loading add-ons,
so tests that depend on the enhancement re-index the document inside the
`with_server` block.

## Roots and resolution

`Roots::MacroAccessor` resolves receiverless macro accessor calls (`outputs`,
`state`, ...) to the accessor's registry type when the enclosing class calls
the macro. `Resolver#resolve_call` also asks the root strategies for calls
whose receiver is `self`, which covers `self.outputs`. Chain resolution then
continues exactly as it does from `args`, so primitive contexts through
`attr_gtk` accessors work without extra code.

## Primitive context detection

Ruby LSP does not pass the cursor position to add-on completion or hover
listeners, and `dispatch_once` visits only the located target. Detection
therefore infers the position from the AST:

- A hash is a primitive context when it is an argument of `<<`, `push`, or
  `concat` on a confidently resolved collection with `accepts_primitive`, or
  an element of an array literal passed to one of those calls.
- An unclosed hash whose last element is an association is a value position
  when the association's key is non-empty and there is no trailing comma.
  Otherwise it is a key position.
- A bare call inside an append call's hash is a half-typed key; Prism wraps a
  half-typed value (`x:`) in an implicit node, which is detected through the
  enclosing association.

Completion items insert `key: ` (excluding keys already present), and
allowed values are offered for keys that declare them. Hover targets a key's
symbol or string node and uses `node_context.call_node` to find the append
call.

### Known limitations

- A cursor in trailing whitespace (`{ x: 0, |`) does not reach add-on
  listeners: `Requests::Completion` discards targets whose parent is nil, and
  whitespace locates only the program node. A ProgramNode fallback was
  prototyped and removed as unreachable. Completion appears once a key
  character is typed.
- A value position is inferred structurally, so a completed value followed by
  a comma (`blendmode: :add,`) is treated as a key position and vice versa.
- Macro recognition covers direct calls in a class or module body. Calls
  through metaprogramming remain out of scope per REQ-M3-17.
- The enhancement API used here is `ruby-lsp` 0.26-specific; the pinned range
  must be revisited before the REQ-TEST-03 version matrix moves past 0.26.
