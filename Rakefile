# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "standard/rake"

namespace :registry do
  desc "Validate the curated registry data and fail on any error"
  task :validate do
    require_relative "lib/ruby-lsp-dragonruby"

    logger = RubyLsp::Dragonruby::Logger.new(nil)
    issues = begin
      RubyLsp::Dragonruby::Registry.validate!(logger: logger)
    rescue RubyLsp::Dragonruby::Registry::InvalidDataError => error
      abort error.message
    end

    issues.each { |issue| warn issue }
    puts "Registry data valid (#{issues.count(&:warning?)} warnings)"
  end

  desc "Print the registry coverage report and fail when an M1 area is missing"
  task :coverage do
    require_relative "lib/ruby-lsp-dragonruby"

    logger = RubyLsp::Dragonruby::Logger.new(nil)
    registry = RubyLsp::Dragonruby::Registry.load(logger: logger)
    coverage = RubyLsp::Dragonruby::Registry::Coverage.call(registry)
    puts coverage
    abort "Registry coverage is incomplete" unless coverage.covered?
  end
end

desc "Run the performance benchmarks and fail when a budget is exceeded"
task :benchmark do
  ruby "benchmark/run.rb"
end

task default: %i[test standard registry:validate registry:coverage benchmark]
