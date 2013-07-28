{Map} = require './map.coffee'
{ClientWorld} = require './game.coffee'

class CanvasView

  TILESET_URL = '/data/kins32.png'
  TILESIZE = 32

  constructor: ->
    @world = new ClientWorld()

    @canvas = document.createElement 'canvas'
    @canvas.id = 'gameview'
    @ctx = @canvas.getContext '2d'

    @tileImage = document.createElement 'image'
    @tileImage.src = TILESET_URL

  _drawTile: (tx, ty, cx, cy) ->
    TS = TILESIZE
    @ctx.drawImage(
      @tileImage,
      tx * TS, ty * TS,
      TS, TS,
      cx * TS, cy * TS,
      TS, TS
    )

  draw: ->
    return if not @tileImage.width # Not yet loaded.

    # Clear.
    @ctx.fillColor = 'black'
    @ctx.fillRect 0, 0, @canvas.width, @canvas.height

    # Draw a character for each map tile.
    @world.map.foreach (p) =>
      switch @world.map.get(p)
        when Map.Cells.WALL
          switch @world.map.wallType p
            when 'h' then @_drawTile 31, 20, p.x, p.y
            when 'v' then @_drawTile 30, 20, p.x, p.y
            else @_drawTile 34, 20, p.x, p.y
        when Map.Cells.ROOM
          @_drawTile 8, 21, p.x, p.y
        when Map.Cells.DOOR
          @_drawTile 2, 21, p.x, p.y
        when Map.Cells.HALLWAY
          @_drawTile 9, 21, p.x, p.y
        else
          # Do nothing.
      return

    # Always draw alive agents on top of dead ones.
    @world.agents.sort (a, b) -> if a.isAlive() then 1 else -1

    # Draw a character for each agent.
    for agent in @world.agents
      p = agent.location

      # All dead agents are a corpse.
      if not agent.isAlive()
        continue

      switch agent.type
        when 'drone' then @_drawTile 10, 8, p.x, p.y
        when 'mosquito' then @_drawTile 5, 12, p.x, p.y
        else @_drawTile 11, 25, p.x, p.y

    return

exports.CanvasView = CanvasView
