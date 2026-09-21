# frozen_string_literal: true

module MermaidTerm
  module Shareable
    def self.make(value)
      defined?(Ractor) ? Ractor.make_shareable(value) : value.freeze
    end
  end
end
