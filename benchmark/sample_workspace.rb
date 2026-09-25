# frozen_string_literal: true

require "fileutils"
require "tmpdir"

module RubyLsp
  module Dragonruby
    module Benchmarks
      # Provides the committed sample game and expands it into the 50-file,
      # ~10k-line workspace that REQ-PERF-03 is measured against.
      module SampleWorkspace
        GAME_DIR = File.expand_path("sample_game", __dir__)
        FILE_COUNT = 50
        LINES_PER_FILE = 200
        # Syntactically valid files used to generate the benchmark workspace.
        # `wip.rb` is intentionally incomplete and is only part of the fuzz sweep.
        WORKSPACE_FILES = %w[main.rb scene.rb ui.rb player.rb].freeze

        module_function

        def game_dir
          GAME_DIR
        end

        def game_paths
          Dir.glob(File.join(GAME_DIR, "*.rb")).sort
        end

        def game_sources
          game_paths.to_h { |path| [File.basename(path), File.read(path)] }
        end

        def workspace_paths
          WORKSPACE_FILES.map { |name| File.join(GAME_DIR, name) }
        end

        # Yields a temporary directory containing the generated workspace and
        # removes it afterwards.
        def with_workspace(file_count: FILE_COUNT)
          Dir.mktmpdir("dragonruby-workspace") do |dir|
            file_count.times do |index|
              path = File.join(dir, "app", "file_#{index}.rb")
              FileUtils.mkdir_p(File.dirname(path))
              File.write(path, source_for(index))
            end

            yield dir
          end
        end

        # One representative game file, padded with unique state writes so the
        # workspace has enough lines to exercise the scan at scale.
        def source_for(index)
          source = +File.read(workspace_paths[index % workspace_paths.size])
          source << "\n"
          padding = LINES_PER_FILE - source.lines.size - 2
          padding = 0 if padding.negative?

          source << "def tick_#{index}(args)\n"
          padding.times do |line|
            source << "  args.state.file_#{index}_key_#{line} ||= #{line}\n"
          end
          source << "end\n"
          source
        end
      end
    end
  end
end
