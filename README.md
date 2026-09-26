# ruby-lsp-dragonruby

Editor intelligence for [DragonRuby Game Toolkit](https://dragonruby.org/) projects.

This is a [Ruby LSP](https://github.com/Shopify/ruby-lsp) add-on that teaches Ruby LSP
about DragonRuby's `args` API, so your editor gets completion, hover,
go-to-definition, and warnings inside your game code.

The add-on runs on CRuby inside Ruby LSP. It is never loaded by DragonRuby itself, so
it has no effect on your game at runtime.

## Requirements

| Component | Supported |
|---|---|
| Ruby (editor process) | 3.2+ (CI runs 3.4 and 4.0) |
| Ruby LSP | `~> 0.26.0` (CI runs the lowest and newest 0.26.x) |
| DragonRuby | the curated registry targets **DragonRuby 7.18** |

The registry tracks the latest DragonRuby release. A new DragonRuby version is
supported once this gem ships a release that targets it.

## Installation

`ruby-lsp-dragonruby` is not on RubyGems yet. Add it to your game's `Gemfile` from
GitHub, in the development group:

```ruby
group :development do
  gem "ruby-lsp-dragonruby",
    github: "asimmons91/ruby-lsp-dragonruby",
    require: false
end
```

Install it and restart Ruby LSP (or your editor):

```bash
bundle install
```

Once the gem is published, the dependency becomes:

```ruby
gem "ruby-lsp-dragonruby", require: false
```

No further configuration is required for completion, hover, and go-to-definition.
Open a game file and type `args.` to confirm the add-on is active. Because the gem is
in the `:development` group and required with `require: false`, DragonRuby never loads
it at runtime.

## Features

- **`args` tree completion and hover** — every curated member of `args`, `args.inputs`,
  `args.outputs`, `args.grid`, `args.geometry`, `args.easing`, `args.audio`, `args.gtk`,
  `args.layout`, `args.events`, and `args.state`, including half-typed chains.
- **`args.state` tracking** — completion, hover, and go-to-definition for state paths
  written anywhere in the workspace, with inferred value types. A key written in
  `app/player.rb` is offered in `app/main.rb`.
- **Local aliases** — types flow through locals such as `kb = args.inputs.keyboard`.
- **Primitive hashes** — key completion, allowed-value completion, and hover inside
  sprite, label, solid, border, line, and screenshot hashes, driven by curated schemas.
- **Class macros** — `attr_gtk` accessors and `attr_sprite` sprite keys are registered
  for any class that calls them.
- **Core-class extensions** — DragonRuby's additions to `Numeric`, `Integer`, `Float`,
  `Array`, `Hash`, and `Kernel` are offered on literal and inferred receivers, labeled
  as DragonRuby additions.
- **Undefined-API warnings** — hovering an unknown member of a confidently resolved
  type shows a warning with a "Did you mean ...?" suggestion when a close match exists.
  Warnings can also be delivered as editor diagnostics (see below).

```ruby
def tick(args)
  kb = args.inputs.keyboard
  kb.key_down?(:space) # aliases keep their DragonRuby type

  args.outputs.sprites << { x: 0, y: 0, w: 32, h: 32, path: "player.png" }
  #                         ^ completes sprite keys and validates allowed values

  args.state.player.x ||= 0 # tracked across the whole workspace
end
```

## Configuration

Hovering an unknown member always shows a warning. To also receive warnings as editor
diagnostics, list the add-on's linter identifier in Ruby LSP's initialization options:

```jsonc
{
  "initializationOptions": {
    "linters": ["dragonruby"]
  }
}
```

Diagnostics use the pull model, the `dragonruby` source, and update as you edit. They
compose with other linters, such as RuboCop. The VS Code extension (0.5.x) does not
expose `linters`, so VS Code users get the hover warning only.

### Settings

Add-on settings live under the `rubyLspDragonruby` key:

```jsonc
{
  "initializationOptions": {
    "addonSettings": {
      "rubyLspDragonruby": {
        "warnings": {
          "enabled": true,
          "primitiveKeys": false,
          "unassignedStateReads": false,
          "allowlist": []
        }
      }
    }
  }
}
```

| Setting | Default | Description |
|---|---|---|
| `warnings.enabled` | `true` | Turns every warning (hover and diagnostics) on or off. |
| `warnings.primitiveKeys` | `false` | Hint on hash keys in a primitive context that no schema defines. |
| `warnings.unassignedStateReads` | `false` | Hint on state paths that are read but never written in the workspace. |
| `warnings.allowlist` | `[]` | Member names and primitive keys that never warn. |

Settings are read when the Ruby LSP server starts. In the pinned `ruby-lsp` range there
is no configuration-change handler, so changing them requires a server restart. The
VS Code extension (0.5.x) does not currently send add-on settings either.

## Known limitations

- Hovering a bare local variable (`args` itself, or an alias like `kb` on its own) is
  not reachable through Ruby LSP's hover target selection in the pinned range. Hover
  on members reached through an alias works.
- Completion inside a primitive hash needs at least one key character typed; Ruby LSP
  discards completion targets that sit in trailing whitespace (the common `{ x: 0, |`).
- Go-to-definition is provided for `args.state` paths only.
- The registry targets the latest DragonRuby release only. Where the documentation
  does not name the underlying class, provisional names such as `GTK::Outputs::Sprites`
  are used.
- `args.cvars`, `args.pixel_array`, and `Zlib` are documented DragonRuby APIs that are
  intentionally deferred; `bundle exec rake registry:coverage` lists them with reasons.
- Settings require a server restart, and VS Code does not send `linters` or add-on
  settings (see [Configuration](#configuration)).

## Development

After checking out the repo, run `bin/setup` to install dependencies. The full gate,
which runs the tests, linting, registry validation and coverage, and the performance
benchmarks, is:

```bash
bundle exec rake
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the registry data format, how to add or
update entries, and the release process. To experiment in an IRB session, run
`bin/console`.

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
