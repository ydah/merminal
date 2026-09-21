# frozen_string_literal: true

module Property
  def property(runs:, seed:)
    chosen_seed = Integer(ENV.fetch("SEED", seed))
    rng = Random.new(chosen_seed)
    runs.times do |index|
      input = nil
      yield rng, ->(value) { input = value }
    rescue StandardError, RSpec::Expectations::ExpectationNotMetError
      warn "property seed=#{chosen_seed} run=#{index}\n#{input}"
      raise
    end
  end
end
