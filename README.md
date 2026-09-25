# ruby-lsp-dragonruby

Ruby LSP add-on for [DragonRuby Game Toolkit](https://dragonruby.org/) projects. It
teaches Ruby LSP about DragonRuby's `args` API so editors get completion, hover,
go-to-definition, and warnings inside game code.

The add-on runs on CRuby inside Ruby LSP; it never runs inside DragonRuby itself.

## Features

- **`args` tree completion and hover** — every curated member of `args`, `args.inputs`,
  `args.outputs`, `args.grid`, `args.geometry`, `args.easing`, `args.audio`, `args.gtk`,
  `args.layout`, `args.events`, and `args.state`, including half-typed chains.
- **`args.state` tracking** — completion, hover, and go-to-definition for state paths
  written anywhere in the workspace, with inferred value types.
- **Local aliases** — types flow through locals such as `kb = args.inputs.keyboard`.
- **Primitive hash keys** — key completion, allowed-value completion, and hover inside
  sprite, label, solid, border, line, and screenshot hashes, driven by curated schemas.
- **Class macros** — `attr_gtk` accessors and `attr_sprite` sprite keys are registered
  for any class that calls them.
- **Core-class extensions** — DragonRuby's additions to `Numeric`, `Integer`, `Float`,
  `Array`, `Hash`, and `Kernel` are offered on literal and inferred receivers.
- **Undefined-API warnings** — hovering an unknown member of a confidently resolved
  type shows a warning with a "Did you mean ...?" suggestion when a close match exists.

## Requirements

| Component | Supported |
|---|---|
| Ruby | 3.2+ (CI runs 3.4 and 4.0) |
| Ruby LSP | `~> 0.26.0` (CI runs the lowest and newest 0.26.x) |
| DragonRuby | the curated registry targets **DragonRuby 7.18** |

The targeted DragonRuby version is recorded in `data/metadata.yml` and printed by
`bundle exec rake registry:coverage`.

## Installation

Add the add-on to your game's `Gemfile`, in the development group:

```ruby
group :development do
  gem "ruby-lsp-dragonruby", require: false
end
```

Then install it:

```bash
bundle install
```

Restart Ruby LSP (or your editor) and the add-on activates automatically. No
configuration is required for completion, hover, and go-to-definition.

The add-on works when the gem is only in the `:development` group, so it is never
loaded by DragonRuby at runtime.

## Warnings and diagnostics

Undefined DragonRuby members are always reported in hover (for example,
`args.inputs.keybaord` shows a warning with a `keyboard` suggestion). To also
receive them as editor diagnostics, list the add-on's linter identifier in your
editor's Ruby LSP configuration:

```jsonc
// initializationOptions
{
  "linters": ["dragonruby"]
}
```

Diagnostics are delivered through the pull model and use the `dragonruby` source.
The VS Code extension currently does not expose `linters`, so VS Code users get
the hover warning only.

### Settings

Settings live under the add-on name `Ruby LSP DragonRuby`:

| Setting | Default | Description |
|---|---|---|
| `warnings.enabled` | `true` | Turns every warning (hover and diagnostics) on or off. |
| `warnings.primitiveKeys` | `false` | Hint on hash keys in a primitive context that no schema defines. |
| `warnings.unassignedStateReads` | `false` | Hint on state paths that are read but never written in the workspace. |
| `warnings.allowlist` | `[]` | Member names and primitive keys that never warn. |

Settings are read when the Ruby LSP server starts. In the pinned `ruby-lsp` range
there is no configuration-change handler, so changing them requires a server
restart.

## Known limitations

- Hovering a bare local variable (`args` itself, or an alias like `kb` on its own) is
  not reachable through Ruby LSP's hover target selection in the pinned range. Hover
  on members reached through an alias works.
- Completion inside a primitive hash needs at least one key character typed; Ruby LSP
  discards completion targets that sit in trailing whitespace (the common `{ x: 0, |`).
- Settings need a server restart (see above), and the VS Code extension does not send
  `linters` or add-on settings.
- Go-to-definition is provided for `args.state` paths only.
- The registry targets the latest DragonRuby release only. Where the documentation does
  not name the underlying class, provisional names such as `GTK::Outputs::Sprites` are
  used.
- `args.cvars`, `args.pixel_array`, and `Zlib` are documented DragonRuby APIs that are
  intentionally deferred; `rake registry:coverage` lists them with reasons.

## Development

After checking out the repo, run `bin/setup` to install dependencies. The full gate is:

```bash
bundle exec rake
```

which runs the tests (including the fuzz sweep), `standard` linting, registry
validation and coverage, and the performance benchmarks. Individual commands:

```bash
bundle exec rake test          # test suite
bundle exec rake standard      # lint / format check
bundle exec rake registry:validate
bundle exec rake registry:coverage
bundle exec rake benchmark     # enforces REQ-PERF-02 and REQ-PERF-03
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the registry data format, how to add or
update entries, and the procedure for a new DragonRuby release.

To experiment in an IRB session, run `bin/console`. To build and install the gem
locally, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/asimmons91/ruby-lsp-dragonruby. This project is intended to be a
safe, welcoming space for collaboration, and contributors are expected to adhere to
the [code of conduct](https://github.com/asimmons91/ruby-lsp-dragonruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Ruby LSP DragonRuby project's codebases, issue trackers,
chat rooms and mailing lists is expected to follow the
[code of conduct](https://github.com/asimmons91/ruby-lsp-dragonruby/blob/main/CODE_OF_CONDUCT.md).
