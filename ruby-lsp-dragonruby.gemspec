# frozen_string_literal: true

require_relative "lib/ruby_lsp_dragonruby/version"

Gem::Specification.new do |spec|
  spec.name = "ruby-lsp-dragonruby"
  spec.version = RubyLsp::Dragonruby::VERSION
  spec.authors = ["Austin Simmons"]
  spec.email = ["austin_simmons@fastmail.com"]

  spec.summary = "Ruby LSP add-on for DragonRuby Game Toolkit projects."
  spec.description = "Completion, hover, go-to-definition, and undefined-API warnings " \
    "for DragonRuby's args API, driven by a curated registry of the latest release."
  spec.homepage = "https://github.com/asimmons91/ruby-lsp-dragonruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ benchmark/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby-lsp", "~> 0.26.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://guides.rubygems.org/make-your-own-gem/
end
