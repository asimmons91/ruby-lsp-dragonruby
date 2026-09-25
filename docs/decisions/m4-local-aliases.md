# M4 — Local alias tracking

Status: accepted (2026-09-25)

This decision records how M4 implements REQ-M4-01 through REQ-M4-08: types
flow through local variables within a method. Findings were produced against
`ruby-lsp` 0.26.11 (the pinned range is `~> 0.26.0`) and Prism 1.9.0.

## Scope discovery

Add-on completion and hover listeners receive only the located target node and
a `RubyLsp::NodeContext`, and `dispatch_once` visits that node alone (M0-S1).
Resolving an alias needs the statements that precede its use, so the add-on
needs the enclosing scope AST.

`NodeContext` does not expose its nesting nodes publicly, but in 0.26.11 its
`@nesting_nodes` array holds the full `ProgramNode` / `DefNode` / `BlockNode` /
`LambdaNode` / `ClassNode` chain, each with a complete body. `LocalAliases`
reads that ivar defensively:

- if the ivar is missing, not an array, or contains unexpected nodes, alias
  resolution returns nothing and every other feature keeps working;
- nodes are filtered to those whose location covers the read offset, so a
  stale nesting entry cannot mis-scope a lookup.

Re-parsing the file from the URI was rejected: it would be stale for unsaved
buffers and adds per-request I/O and parsing (REQ-PERF-02). Waiting for a
public API was rejected because the requirement is implementable now. The
dependency on a private ivar is the same kind of pinned-version tradeoff as
the indexing enhancement API documented in `m3-macros-and-primitives.md`, and
the fallback keeps the add-on robust if it changes.

## Lookup algorithm

`LocalAliases#assignment_for(read, context)` returns the nearest visible
assignment for a local variable read:

1. Build the lexical scope chain: the nodes covering the read, trimmed at the
   innermost hard scope (`def`, `class`, `module`, `singleton class`,
   program). Blocks and lambdas are soft scopes that inherit enclosing
   locals; locals do not cross a hard boundary.
2. For each scope, collect write events from its own statements, recursing
   through non-scope nodes (conditionals, `begin`, loops) but not into nested
   scopes that are not on the chain. Block parameters (including destructured
   ones), block-locals, and numbered parameters (`_1`) become shadow events at
   the block's start offset. An implicit `it` parses as an
   `ItLocalVariableReadNode` rather than a local read; the resolver treats it
   as unknown, which is correct because the block argument's type is not
   known.
3. The event with the greatest offset before the read wins. A shadow event
   yields no alias; a write yields the assignment node.

This gives the required semantics without flow analysis:

- assignments inside conditionals count (REQ-M4-02);
- a later reassignment replaces the earlier type, including a reassignment to
  an expression that does not resolve (REQ-M4-03);
- blocks see enclosing locals, block-only locals do not leak out, and block
  parameters shadow (REQ-M4-04);
- aliases chain because the resolver resolves the assignment's value
  recursively (REQ-M4-05);
- writes inside a block conservatively do not propagate to uses after the
  block, even when the name already existed outside: textually nearest wins
  within the block, and outside uses see only the outer writes;
- top-level assignments resolve, while class-body locals do not carry into
  methods.

## Resolver integration

`Resolver#resolve` handles `LocalVariableReadNode` before the root
strategies. No visible assignment falls through to the roots, so `args`
parameters still resolve (REQ-M2-01). A write whose value cannot be an alias
(`LocalVariableOperatorWriteNode`, multiple-assignment targets) resolves to
`unknown`, which stops resolution from that point (REQ-M4-03). A per-resolver
set of in-flight assignment nodes breaks cycles such as `kb = kb`.

Because every consumer resolves receivers through `Resolver`, alias support
applies to chain completion, member and root hover, primitive contexts
(REQ-M3-06), and `attr_gtk`/`attr_sprite` accessors without further changes.

For M5, `LocalAliases#assignment_for` exposes the initializer node, so state
aliases (`s = args.state`) can be unwrapped to a path root (REQ-M4-06). No M5
code is added here.

## Hover (REQ-M4-08)

Hovering a member through an alias (`kb.key_down`) shows the member's docs
through the normal receiver path. Hovering a bare alias (`kb`) cannot be
reached in the pinned range: `Listeners::Hover::ALLOWED_TARGETS` does not
include `LocalVariableReadNode`, and the enclosing `CallNode` is discarded
when the cursor is outside its message location (M0-S1). The hover listener
already handles `on_local_variable_read_node_enter` and resolves aliases, so
the handler works on Ruby LSP versions that select locals as hover targets; it
is unit-tested here by dispatching the node directly. REQ-M4-08 was scoped
accordingly, mirroring REQ-M2-12.

## Known limitations

- A write inside a block never affects uses after the block, and an alias
  assigned only in one conditional branch is still used in later branches
  (no flow analysis, per REQ-M4-02).
- `LocalVariableOperatorWriteNode` (`kb += ...`) and multiple assignment are
  treated as reassignments to an unknown value, per REQ-M4-07.
- `||=` and `&&=` are treated as unconditional assignments to their
  right-hand side: after `kb = args.inputs.keyboard; kb ||= args.outputs.sprites`,
  completion uses the sprite collection even though the runtime value keeps the
  earlier keyboard type. Failing safe to `unknown` after a prior assignment is
  possible if this proves noisy in practice.
- Method parameters are not shadow events; a block parameter named `args`
  still resolves through the `args` parameter strategy, matching pre-M4
  behavior.
- Scope discovery depends on `NodeContext#@nesting_nodes`; a future
  `ruby-lsp` change silently disables alias resolution until the pin moves.
