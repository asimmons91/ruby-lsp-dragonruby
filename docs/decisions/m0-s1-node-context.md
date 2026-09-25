# M0-S1 — Node context sufficiency

Status: accepted (2026-09-25)

This decision answers whether the node context passed to add-on listeners gives
enough information to resolve DragonRuby chains, or whether the add-on must walk
the AST itself. Findings were produced by probing `ruby-lsp` 0.26.11 (the pinned
range is `~> 0.26.0`) with a recording add-on and by parsing sample sources with
Prism 1.9.0.

## What the node context provides

`RubyLsp::NodeContext` (0.26.11) exposes:

- `node` and `parent` for the located target,
- `nesting` and `surrounding_method`,
- `locals_for_scope`, which includes method parameters.

It does **not** expose the nesting nodes, the AST root, or a parent chain. Once
a listener callback runs, only the target node and its own children are
reachable, because both `textDocument/completion` and `textDocument/hover`
call `dispatcher.dispatch_once(target)`, which visits that node only.

## Findings

### Completion targets

For `def tick(args); args.inputs.keyboard.|` the completion target passed to
add-ons is the call node for `keyboard`, not a call with an empty message.
Prism recovers a trailing `.` by attaching the **next** token as the message:

```
def tick(args)
  args.inputs.keyboard.
end
```

parses as `keyboard.end`, a `CallNode` whose `message_loc` is the `end` keyword
on the following line and whose `call_operator_loc` is the trailing dot. The
same recovery happens when the next line begins with any other token (`foo`).

The add-on therefore detects a half-typed chain by comparing the call operator
with the message location: if the message starts on a later line than the call
operator ends (or the message is empty), the user has typed a trailing dot and
the receiver chain is the thing to resolve. Otherwise the message text is the
partial name to filter by. This is a self-contained AST check and needs no
context information beyond the target node.

### Hover targets

`textDocument/hover` locates the target through
`Listeners::Hover::ALLOWED_TARGETS`, which does not include
`Prism::LocalVariableReadNode`. When the cursor is over a method parameter such
as `args`, the request locates the enclosing `CallNode` and then discards it
because the cursor is outside the message location, so `create_hover_listener`
is never called. `$gtk` (`GlobalVariableReadNode`) and constant roots
(`ConstantReadNode`/`ConstantPathNode`) do reach add-ons; call members reach
add-ons when the cursor is on the message.

`LocalVariableReadNode` cannot become a hover target in the pinned range. In
0.26.x `Requests::Hover` locates through `Listeners::Hover::ALLOWED_TARGETS`,
which does not include local variable reads. In 0.27.0.beta5, hover locates
without a type filter and does call add-on hover listeners with a
`LocalVariableReadNode`; the add-on registers
`on_local_variable_read_node_enter` so the parameter root works there, but that
path cannot be exercised while the gem pins `~> 0.26.0`.

### Root detection

Prism only produces `LocalVariableReadNode` for identifiers it already knows are
local variables, including method parameters. `def tick(args); args.` therefore
parses the receiver as a `LocalVariableReadNode` named `args`, while an
undefined method named `args` at the top level parses as a `CallNode` with the
`variable_call` flag. No scope walk or parameter inspection is needed to
recognize the parameter root; the node type plus the name is sufficient.

## Decision

1. The resolver walks the receiver chain itself from the target node. It does
   not rely on the node context for chain shape.
2. Roots are recognized from the target/receiver node alone: a
   `LocalVariableReadNode` named `args`, the `$gtk`/`$args` globals, and
   constants that match a registry type name. The root rule set is a list of
   strategies so later milestones can append without touching chain logic.
3. Half-typed chains are detected with the call-operator/message gap check
   described above.
4. Hovering a parameter root named `args` is out of reach for add-ons in the
   pinned Ruby LSP range. REQ-M2-12 is scoped to `$gtk`, `$args`, and curated
   constants. The hover listener still registers on
   `on_local_variable_read_node_enter`, so the parameter case works on Ruby LSP
   versions that select locals as hover targets, and the 0.26.x limitation
   disappears when the pinned range moves.
