# M1 — Registry format and curation decisions

Status: accepted (2026-09-25)

This decision defines the YAML data format, the in-memory model, and the
validation and loading rules for the curated DragonRuby API registry
(REQ-M1-01 through REQ-M1-09). It also records how the two M1-relevant open
questions were resolved.

## Files

Registry data lives under `data/`, one file per logical area:

| File | Contents |
|---|---|
| `metadata.yml` | `dragonruby_version`, `curated_at`, `schema_version` |
| `names.yml` | Named lists of identifiers used by generated member families |
| `args.yml` | `GTK::Args` |
| `inputs.yml` | Inputs, keyboard, mouse, controllers, shared keys |
| `outputs.yml` | Outputs collections and render targets |
| `grid.yml`, `geometry.yml`, `easing.yml`, `audio.yml`, `layout.yml`, `events.yml`, `state.yml` | One area each |
| `runtime.yml` | `GTK::Runtime` (`$gtk` / `args.gtk`) |
| `primitives.yml` | Primitive schemas (names and markers only in M1) |
| `coverage.yml` | M1 coverage checklist, not part of the registry itself |

A file has one or more top-level keys: `types`, `schemas`, `names`, or the
metadata keys. Unknown keys are ignored.

## Types

```yaml
types:
  - name: GTK::Args            # required, unique
    doc: "..."                 # optional Markdown
    parent: GTK::Base          # optional registry type
    open: true                 # optional, default false
    incomplete: true           # optional curation flag for M7
    accepts_primitive: sprite  # optional primitive schema name
    core_backing: Array        # optional core class the type behaves like
    members: [...]             # optional
    generates: [...]           # optional generated families
```

`core_backing` names a core type (`Array`, `Hash`, `String`, ...) whose
standard instance methods the type also responds to. It is inherited from
ancestors, must name a core type that has a CRuby class to reflect, and is used
by M7 to suppress undefined-member warnings for methods such as `length` on
`GTK::Audio` or `size` on the output collections.

A member:

```yaml
- name: key_down?              # required, unique after expansion
  kind: method                 # required: method | attribute
  returns: Boolean             # required: name, list (union), or Unknown
  doc: "..."                   # required, one to three sentences
  docs_url: "https://..."      # optional
  aliases: [key_pressed?]      # optional alternate names
  params:                      # methods only
    - {name: key, kind: required, type: Symbol}
```

Param kinds are `required`, `optional`, `keyword`, `rest`, and `block`.
A `block` param may omit `name` (anonymous block). Attributes must not
declare params.

`returns` and param `type` accept a single name, a list of names for a union,
or the literal `Unknown`. A name resolves to a registry type, to one of the
core types (`Array`, `Boolean`, `Float`, `Hash`, `Integer`, `Numeric`,
`Object`, `Proc`, `Range`, `String`, `Symbol`), or to `Unknown`.

## Generated families

Families keep one identifier list and one or more member templates:

```yaml
# names.yml
names:
  keyboard_keys:
    - a
    - {name: w_scancode, aliases: [up_wasd]}
```

```yaml
# a type
generates:
  - names: keyboard_keys
    members:
      - name: "{{name}}"
        kind: attribute
        returns: Boolean
        doc: "Returns true while the {{name}} key is down or held."
```

`{{name}}` is substituted in every string value of the template. Aliases
declared on a name-list entry are merged into every member generated from that
entry. One list can feed several types or templates without repeating the
identifiers.

## Primitive schemas

```yaml
schemas:
  - name: sprite
    primitive_marker: sprite
    keys:
      - {name: w, type: Numeric, doc: "...", default: 0, allowed_values: [0, 1]}
```

The model and validator support keys, defaults, and allowed values. M1 shipped
placeholder schemas with empty key lists; M3 filled them and added the
`macros` document plus list-valued `accepts_primitive`. See
`m3-macros-and-primitives.md` for the extended format.

## Load and validation semantics

- The loader parses every `data/**/*.yml` in sorted order, expands families,
  then validates.
- CI (`rake registry:validate`) treats any error as fatal. The load path logs
  every issue and continues.
- A malformed type is dropped whole; a malformed member or primitive key is
  dropped individually; an unresolvable `parent` or `accepts_primitive`
  reference is cleared. A file that cannot be parsed is skipped with an issue.
- Validation checks required fields, enum kinds, type resolution, duplicate
  type/member/schema/key names, dangling `parent`, `accepts_primitive`, and
  name-list references, and parent cycles. Alias collisions are warnings; the
  colliding alias is dropped and the member is kept.

## Provisional class names

The docs site names `GTK::Args`, `GTK::Controller::NINTENDO_SWITCH_PRO_CONTROLLER`,
and the top-level `Grid`, `Geometry`, `Easing`, and `Layout` modules. The
documentation does not name the classes behind output collections, render
targets, or per-key state objects, so the registry uses these registry-level
names and revisits them if the engine source confirms different ones:

- `GTK::Outputs::<Kind>` for each collection, `GTK::Outputs::RenderTarget`,
  `GTK::Outputs::Collection` as their shared parent
- `GTK::KeyboardKeys`, `GTK::ControllerKeys`, `GTK::MouseKeys`,
  `GTK::MouseButtons`, `GTK::MouseButton`, `GTK::SharedKeys`
- `GTK::Runtime` (the docs call the runtime `DR` and `DR::Runtime`)
- `GTK::State`, `GTK::Events`, `GTK::Audio`, `GTK::AudioSource`, `GTK::Entity`

## Open questions

- **#5 Hash-style access on state values**: resolved yes. The State and
  Geometry docs use `args.state.player.x` on hash values and state entities
  support method-style access (`as_hash`, `entity_id`, and arbitrary children).
  M5 may rely on this.
- **#6 Exact class names**: resolved as far as the docs allow. Names listed
  above are used where the docs name them; the provisional names are recorded
  so later engine-source confirmation can correct them without changing the
  format.

## Sequencing deviation

M1 and the minimal M0 prerequisites (add-on entry point, logger, `ruby-lsp`
dependency, registry load at activation) landed before the M0 spikes. This was
an explicit decision: the M1 loader, validator, coverage tooling, and curated
data do not depend on any spike outcome, so the registry work could proceed
independently. M0-S1 and M0-S2 were since decided alongside M2.

Still open from M0 and later milestones:

- M0-S3 and M0-S5 have no written decisions yet. M0-S4 is decided in
  `m0-s4-stub-indexing.md` (resolver fallback for core extensions).
- CI runs a Ruby version matrix, not the low/high `ruby-lsp` range required by
  REQ-TEST-03.
