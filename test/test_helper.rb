# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ruby-lsp-dragonruby"

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
      "schemas.yml" => SCHEMAS
    }
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
