# Uses the attr_sprite macro so sprite hash keys become accessors.
class Player
  attr_sprite

  def initialize(x, y)
    @x = x
    @y = y
    @w = 32
    @h = 32
    @path = "sprites/player.png"
  end

  def move(dx, dy)
    @x += dx
    @y += dy
  end

  def rect
    {x: @x, y: @y, w: @w, h: @h}
  end
end
