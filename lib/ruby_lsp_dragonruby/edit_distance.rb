# frozen_string_literal: true

module RubyLsp
  module Dragonruby
    # Bounded edit distance used to suggest the closest registry member, key,
    # or name. The metric is the restricted Damerau-Levenshtein (optimal string
    # alignment) distance, so a single transposition such as `keybaord` →
    # `keyboard` counts as one edit.
    module EditDistance
      module_function

      # The closest candidate within the distance budget, or nil. Short names
      # only match candidates starting with the same character, so a stray `x`
      # does not suggest `y`.
      def suggestion(name, candidates)
        return nil if name.nil? || name.empty?

        name = name.to_s
        max = (name.length >= 5) ? 2 : 1
        best = nil
        best_distance = nil

        candidates.each do |candidate|
          candidate = candidate.to_s
          next if candidate.empty? || candidate == name
          next if (candidate.length - name.length).abs > max
          next if name.length < 5 && candidate[0] != name[0]

          distance = between(name, candidate)
          next if distance > max
          next if best_distance && distance >= best_distance

          best = candidate
          best_distance = distance
        end

        best
      end

      def between(left, right)
        left = left.to_s
        right = right.to_s
        return right.length if left.empty?
        return left.length if right.empty?

        rows = Array.new(left.length + 1) { Array.new(right.length + 1, 0) }
        (0..left.length).each { |i| rows[i][0] = i }
        (0..right.length).each { |j| rows[0][j] = j }

        (1..left.length).each do |i|
          (1..right.length).each do |j|
            cost = (left[i - 1] == right[j - 1]) ? 0 : 1
            rows[i][j] = [
              rows[i - 1][j] + 1,
              rows[i][j - 1] + 1,
              rows[i - 1][j - 1] + cost
            ].min

            if i > 1 && j > 1 && left[i - 1] == right[j - 2] && left[i - 2] == right[j - 1]
              rows[i][j] = [rows[i][j], rows[i - 2][j - 2] + 1].min
            end
          end
        end

        rows[left.length][right.length]
      end
    end
  end
end
