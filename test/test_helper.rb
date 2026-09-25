# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby-lsp-dragonruby"
require "ruby_lsp/internal"
require "ruby_lsp/test_helper"
require "ruby_lsp_dragonruby/indexing_enhancement"
require "ruby_lsp_dragonruby/listeners/completion"
require "ruby_lsp_dragonruby/listeners/definition"
require "ruby_lsp_dragonruby/listeners/hover"
require "ruby_lsp_dragonruby/state_collector"
require "ruby_lsp_dragonruby/state_store"
require "ruby_lsp_dragonruby/state_tracker"

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "stringio"

module RegistryTestHelper
  METADATA = <<~YAML
    dragonruby_version: "5.0"
    curated_at: 2026-09-25
    schema_version: 1
  YAML

  NAMES = <<~YAML
    names:
      keys:
        - a
        - {name: b, aliases: [bee]}
  YAML

  TYPES = <<~YAML
    types:
      - name: GTK::Args
        doc: Root object
        members:
          - {name: inputs, kind: attribute, returns: GTK::Inputs, doc: Inputs}
          - {name: state, kind: attribute, returns: GTK::State, doc: State}
          - {name: score, kind: method, returns: [Integer, Float], doc: Score}
          - {name: mystery, kind: method, returns: Unknown, doc: Mystery}
      - name: GTK::Inputs
        parent: GTK::Base
        members:
          - {name: keyboard, kind: attribute, returns: GTK::Keyboard, doc: Keyboard}
      - name: GTK::Base
        members:
          - {name: base, kind: attribute, returns: Boolean, doc: Base}
      - name: GTK::Keyboard
        members:
          - {name: key_down, kind: attribute, returns: GTK::Keys, doc: Key down}
        generates:
          - names: keys
            members:
              - {name: "{{name}}", kind: attribute, returns: Boolean, doc: "The {{name}} key"}
      - name: GTK::Keys
        members:
          - name: key_down?
            kind: method
            returns: Boolean
            doc: Checks a key
            params:
              - {name: key, kind: required, type: Symbol}
              - {name: repeat, kind: keyword, type: Boolean}
              - {kind: block, type: Unknown}
      - name: GTK::State
        open: true
        members:
          - {name: new_entity, kind: method, returns: GTK::Entity, doc: Builds an entity}
      - name: GTK::Entity
        open: true
        members: []
  YAML

  SCHEMAS = <<~YAML
    schemas:
      - name: sprite
        primitive_marker: sprite
        keys:
          - {name: w, type: Numeric, doc: Width, default: 0, allowed_values: [0, 1]}
          - {name: blend_mode_enum, type: Integer, doc: Blend mode, default: 0, allowed_values: [0, 1]}
      - name: solid
        primitive_marker: solid
        keys:
          - {name: w, type: Numeric, doc: Width}
  YAML

  MACROS = <<~YAML
    macros:
      - name: attr_gtk
        aliases: [attr_dr]
        doc: DragonRuby environment accessors
        accessors:
          - {name: args, returns: GTK::Args, doc: The args}
          - {name: inputs, returns: GTK::Inputs, doc: The inputs}
          - {name: state, returns: GTK::State, doc: The state}
      - name: attr_sprite
        doc: Sprite accessors
        primitive: sprite
  YAML

  SHARED_MACROS = <<~YAML
    macros:
      - name: attr_gtk
        accessors:
          - {name: args, returns: GTK::Args, doc: The args}
      - name: attr_other
        accessors:
          - {name: args, returns: GTK::Inputs, doc: The inputs}
  YAML

  PRIMITIVE_TYPES = <<~YAML
    types:
      - name: GTK::Args
        members:
          - {name: outputs, kind: attribute, returns: GTK::Outputs, doc: Outputs}
      - name: GTK::Outputs
        members:
          - {name: sprites, kind: attribute, returns: GTK::Outputs::Sprites, doc: Sprites}
          - {name: labels, kind: attribute, returns: GTK::Outputs::Labels, doc: Labels}
          - {name: primitives, kind: attribute, returns: GTK::Outputs::Primitives, doc: Primitives}
      - name: GTK::Outputs::Collection
        members:
          - {name: "<<", kind: method, returns: GTK::Outputs::Collection, doc: Push}
          - {name: push, kind: method, returns: GTK::Outputs::Collection, doc: Push}
          - {name: concat, kind: method, returns: GTK::Outputs::Collection, doc: Push}
      - name: GTK::Outputs::Sprites
        parent: GTK::Outputs::Collection
        accepts_primitive: sprite
        members: []
      - name: GTK::Outputs::Labels
        parent: GTK::Outputs::Collection
        accepts_primitive: label
        members: []
      - name: GTK::Outputs::Primitives
        parent: GTK::Outputs::Collection
        accepts_primitive: [sprite, label]
        members: []
  YAML

  PRIMITIVE_SCHEMAS = <<~YAML
    schemas:
      - name: sprite
        primitive_marker: sprite
        keys:
          - {name: x, type: Numeric, doc: X}
          - {name: y, type: Numeric, doc: Y}
          - {name: path, type: [String, Symbol], doc: Path}
          - {name: blend_mode_enum, type: Integer, doc: Blend, default: 0, allowed_values: [0, 1]}
      - name: label
        primitive_marker: label
        keys:
          - {name: x, type: Numeric, doc: X}
          - {name: text, type: String, doc: Text}
          - {name: alignment_enum, type: Integer, doc: Align, default: 0, allowed_values: [0, 1, 2]}
  YAML

  RUNTIME = <<~YAML
    types:
      - name: GTK::Runtime
        doc: The runtime
        members:
          - {name: args, kind: attribute, returns: GTK::Args, doc: The args, docs_url: "https://docs.dragonruby.org/#/api/runtime"}
  YAML

  def quiet_logger
    RubyLsp::Dragonruby::Logger.new(StringIO.new)
  end

  def with_data(files)
    Dir.mktmpdir do |dir|
      files.each do |name, contents|
        path = File.join(dir, name)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, contents)
      end
      yield dir
    end
  end

  def with_registry(files, logger: quiet_logger)
    with_data(files) do |dir|
      registry = RubyLsp::Dragonruby::Registry::Loader.new(data_dir: dir, logger: logger).load
      yield registry, dir
    end
  end

  def load_registry(files, logger: quiet_logger)
    with_registry(files, logger: logger) { |registry, _dir| registry }
  end

  def valid_files
    {
      "metadata.yml" => METADATA,
      "names.yml" => NAMES,
      "types.yml" => TYPES,
      "schemas.yml" => SCHEMAS,
      "macros.yml" => MACROS
    }
  end

  def files_with_runtime
    valid_files.merge("runtime.yml" => RUNTIME)
  end

  def primitive_files
    {
      "metadata.yml" => METADATA,
      "types.yml" => PRIMITIVE_TYPES,
      "schemas.yml" => PRIMITIVE_SCHEMAS
    }
  end

  def load_primitive_registry
    load_registry(primitive_files)
  end

  def validation_issues(files)
    with_data(files) do |dir|
      RubyLsp::Dragonruby::Registry::Loader.new(data_dir: dir).validation_issues
    end
  end

  def issues_for(type_yaml, schemas: nil, names: nil, metadata: METADATA)
    files = {"types.yml" => type_yaml}
    files["metadata.yml"] = metadata if metadata
    files["names.yml"] = names if names
    files["schemas.yml"] = schemas if schemas
    validation_issues(files)
  end

  def error_messages(issues)
    issues.select(&:error?).map(&:message)
  end
end

module NodeContextHelper
  CURSOR = "\u2038"

  # Locates the node context for a source with a cursor marker. Ruby LSP's
  # completion request adjusts the position back by one, hover does not.
  def locate_context(source, adjust: -1, node_types: [Prism::CallNode])
    position = source.index(CURSOR)
    raise ArgumentError, "source is missing the #{CURSOR.inspect} cursor marker" unless position

    clean = source.delete(CURSOR)
    global_state = RubyLsp::GlobalState.new
    document = RubyLsp::RubyDocument.new(
      source: clean,
      version: 1,
      uri: URI("file:///test.rb"),
      global_state: global_state
    )
    RubyLsp::RubyDocument.locate(
      document.ast,
      position + adjust,
      code_units_cache: document.code_units_cache,
      node_types: node_types
    )
  end
end

module ServerTestHelper
  include RubyLsp::TestHelper

  CURSOR = "\u2038"

  def reindex(server, uri, source)
    server.global_state.index.index_single(uri, source.delete(CURSOR))
  end

  def with_cursor(source, **options)
    clean, line, character = cursor_position(source)
    with_server(clean, **options) do |server, uri|
      yield server, uri, line, character
    end
  end

  def cursor_position(source)
    index = source.index(CURSOR)
    raise ArgumentError, "source is missing the #{CURSOR.inspect} cursor marker" unless index

    clean = source.delete(CURSOR)
    before = source[0...index]
    line = before.count("\n")
    character = before.split("\n", -1).last.length
    [clean, line, character]
  end

  def completion_items(server, uri, line, character, trigger_character: nil)
    context = trigger_character ? {triggerCharacter: trigger_character} : nil
    server.process_message(
      id: 1,
      method: "textDocument/completion",
      params: {
        textDocument: {uri: uri},
        position: {line: line, character: character},
        context: context
      }.compact
    )
    pop_result(server).response
  end

  def completion_labels(server, uri, line, character, trigger_character: nil)
    completion_items(server, uri, line, character, trigger_character: trigger_character).map(&:label)
  end

  def hover_content(server, uri, line, character)
    server.process_message(
      id: 1,
      method: "textDocument/hover",
      params: {textDocument: {uri: uri}, position: {line: line, character: character}}
    )
    pop_result(server).response&.contents&.value
  end

  def definition_locations(server, uri, line, character)
    server.process_message(
      id: 1,
      method: "textDocument/definition",
      params: {textDocument: {uri: uri}, position: {line: line, character: character}}
    )
    Array(pop_result(server).response)
  end

  def dragonruby_addon(_server = nil)
    RubyLsp::Addon.addons.find { |addon| addon.is_a?(RubyLsp::Dragonruby::Addon) }
  end

  def reindex_state(server, uri, source)
    dragonruby_addon(server).state_tracker.replace_source(uri, source)
  end

  def state_tracker(server)
    dragonruby_addon(server).state_tracker
  end

  # Test servers never run initial indexing, and watcher notifications are
  # deferred until it completes.
  def mark_indexing_complete(server)
    server.global_state.index.instance_variable_set(:@initial_indexing_completed, true)
  end
end
