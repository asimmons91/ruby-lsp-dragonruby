# M0-S2 — Interaction with built-in completion

Status: accepted (2026-09-25)

This decision records what Ruby LSP 0.26.11 already offers at the positions the
add-on completes, and fixes the de-duplication rule from REQ-UX-03.

## Baseline behavior

Probes through `RubyLsp::TestHelper#with_server` with no workspace index
entries relevant to DragonRuby produce an empty completion list for:

- `args.`
- `args.inputs.keyboard.`
- `args.inputs.ke`
- `5.`
- a key position inside a primitive hash literal

`Listeners::Completion#complete_methods` only emits items when
`TypeInferrer#infer_receiver_type` returns a type. That inference is name-based:
it guesses a constant from the receiver's raw text (`args.inputs` becomes a
guess for `Inputs`) and looks it up in Ruby LSP's index. The curated registry is
YAML data, not index entries, so `args`, `inputs`, `outputs`, and friends have
no inferred type and Ruby LSP contributes nothing. Sorbet does not contribute
either in an untyped project.

A collision is possible when a workspace defines a constant that matches a
receiver name (for example `class Inputs`), or once M6 exposes curated types to
the index. In that case Ruby LSP may offer methods from its index at the same
position the add-on offers curated members.

## Listener ordering

`Requests::Completion` constructs the built-in `Listeners::Completion` first and
then calls `Addon#create_completion_listener` for each add-on, all registering
`on_call_node_enter` on the same dispatcher. `dispatch_once` invokes listeners
in registration order, so by the time the add-on handler runs, built-in items
are already in the shared `ResponseBuilders::CollectionResponseBuilder`.

## Decision

The add-on applies this rule before pushing each completion item:

1. Read the labels already in the response builder and skip any candidate whose
   label is present.
2. De-duplicate its own candidates by label so canonical names and aliases do
   not produce two items.

Because the add-on only ever offers curated registry members (never core Ruby
methods), it cannot duplicate standard method completion in the common case;
the label check covers the inferred-type collision case. Hover is unaffected:
the add-on only pushes content when it has a confident DragonRuby resolution,
and the hover response builder joins contributions from all listeners.
