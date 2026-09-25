# Pushes primitive hashes and uses core-class extensions.
module UI
  def self.draw_bar(args, x, y, width, ratio)
    args.outputs.solids << {x: x, y: y, w: width, h: 8, r: 40, g: 40, b: 40}
    args.outputs.solids << {x: x, y: y, w: width * ratio, h: 8, r: 90, g: 220, b: 120}

    args.outputs.labels << {
      x: x,
      y: y + 12,
      text: "#{(ratio * 100).to_i}%",
      size_enum: 0,
      alignment_enum: 1
    }

    args.outputs.primitives << {primitive_marker: :border, x: x, y: y, w: width, h: 8}
    args.outputs.sprites << {x: 8, y: 8, w: 16, h: 16, path: :solid}
  end

  def self.overlap?(a, b)
    a.intersect_rect?(b)
  end
end
