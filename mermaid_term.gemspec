# frozen_string_literal: true

require_relative "lib/mermaid_term/version"

Gem::Specification.new do |spec|
  spec.name = "mermaid_term"
  spec.version = MermaidTerm::VERSION
  spec.authors = ["Yudai Takada"]
  spec.email = ["t.yudai92@gmail.com"]
  spec.summary = "Render Mermaid diagrams as terminal text"
  spec.description = "A pure Ruby Mermaid diagram renderer for Unicode and ASCII terminals."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir.glob("{lib,exe,docs,sig}/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) } + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.bindir = "exe"
  spec.executables = %w[mmterm]
  spec.require_paths = %w[lib]
end
