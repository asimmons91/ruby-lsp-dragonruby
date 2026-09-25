# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Workspace-wide index of `args.state` paths collected from writes.
    #
    # Contributions are tracked per source URI so a changed file replaces its
    # own paths and a deleted file's paths disappear, without touching the
    # rest of the workspace. Paths are stored as dotted strings (`player.x`);
    # the root's children use `""` as their parent.
    class StateStore
      Record = Struct.new(:path, :parent, :site)

      # One write site: where the path was written and whether the write was an
      # initialization (`||=`) or an assignment (`=`). Lines and characters are
      # zero-based, matching LSP positions.
      WriteSite = Struct.new(:uri, :line, :character, :end_line, :end_character, :kind, :type_name) do
        def initialization?
          kind == :initialization
        end

        def same_site?(other)
          uri == other.uri && line == other.line && character == other.character && kind == other.kind
        end

        # `||=` sites first, then file order (REQ-M5-10).
        def sort_key
          [initialization? ? 0 : 1, uri.to_s, line, character]
        end
      end

      class Entry
        attr_reader :path, :parent, :writes

        def initialize(path:, parent:)
          @path = path
          @parent = parent
          @writes = []
        end

        def add_write(site)
          @writes << site unless @writes.any? { |existing| existing.same_site?(site) }
        end

        def remove_writes_from(uri)
          @writes.reject! { |site| site.uri == uri }
        end

        # The union of the write sites' inferred types (REQ-M5-09).
        def types
          names = @writes.map(&:type_name).compact.reject { |name| name == Registry::UNKNOWN }.uniq
          names.empty? ? [Registry::UNKNOWN] : names.sort
        end

        def write_count
          @writes.size
        end

        # The first initialization site in file order (REQ-M5-09).
        def first_initialization
          @writes.select(&:initialization?).min_by(&:sort_key)
        end
      end

      def initialize
        @entries = {}
        @children = {}
        @uris = {}
      end

      def replace(uri, records)
        key = uri.to_s
        remove(key)

        records.each do |record|
          entry = ensure_entry(record.path, record.parent)
          entry.add_write(record.site)
          link(record.parent, record.path)
          ((@uris[key] ||= []) << record.path)
        end
      end

      def remove(uri)
        key = uri.to_s
        paths = @uris.delete(key)
        return unless paths

        paths.uniq.each do |path|
          @entries[path]&.remove_writes_from(key)
        end

        # Deepest paths first, so a pruned child leaves its parent childless.
        paths.uniq.sort_by { |path| -path.count(".") }.each do |path|
          entry = @entries[path]
          prune(path) if entry && entry.writes.empty? && children_for(path).empty?
        end
      end

      def entry(path)
        @entries[path]
      end

      def path?(path)
        @entries.key?(path)
      end

      # The known direct child names of a path; `args.state`'s children use the
      # empty string as the parent.
      def child_names(path = "")
        (@children[path] || []).sort
      end

      def empty?
        @entries.empty?
      end

      private

      def ensure_entry(path, parent)
        @entries[path] ||= Entry.new(path: path, parent: parent)
      end

      def link(parent, path)
        return if parent.nil?

        segment = path.split(".").last
        children = (@children[parent] ||= [])
        children << segment unless children.include?(segment)
      end

      def children_for(path)
        @children[path] || []
      end

      def prune(path)
        @entries.delete(path)
        parent = path.include?(".") ? path.rpartition(".").first : ""
        children = @children[parent]
        return unless children

        children.delete(path.split(".").last)
        @children.delete(parent) if children.empty?
      end
    end
  end
end
