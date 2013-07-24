PriorityQueue = require 'priorityqueuejs'
aStar = require 'a-star'
{Vec2} = require 'justmath'

# I'm too lazy to write tests, so I'll use runtime assertions for now.
ASSERT = (cond) -> throw new Error('Assertion failed') if not cond

class Map

  # ---------------------------------------------------------------------------
  # Constants
  # ---------------------------------------------------------------------------

  @Cells:
    EMPTY: 'EMPTY'
    WALL: 'WALL'
    ROOM: 'ROOM'
    DOOR: 'DOOR'
    HALLWAY: 'HALLWAY'

  # ---------------------------------------------------------------------------
  # Constructor
  # ---------------------------------------------------------------------------

  constructor: (size) ->
    ASSERT size instanceof Vec2
    @size = new Vec2(size)
    @_map = new Array(@size.y)
    for i in [0...@size.y]
      @_map[i] = new Array(@size.x)

  # ---------------------------------------------------------------------------
  # Mutation
  # ---------------------------------------------------------------------------

  get: (p) ->
    ASSERT p instanceof Vec2
    row = @_map[p.y]
    return null if not row?
    return row[p.x]

  set: (p, value) ->
    ASSERT p instanceof Vec2
    ASSERT value of Map.Cells
    row = @_map[p.y]
    return null if not row?
    row[p.x] = value
    return value

  foreach: (cb) ->
    ASSERT typeof cb == 'function'
    for y in [0...@size.y]
      for x in [0...@size.x]
        cb new Vec2(x, y)
    return

  foreachRow: (y, cb) ->
    ASSERT 0 <= y < @size.y
    ASSERT typeof cb == 'function'
    for x in [0...@size.x]
      cb new Vec2(x, y)
    return

  # ---------------------------------------------------------------------------
  # Traversal
  # ---------------------------------------------------------------------------

  cardinalNeighbors: (p) ->
    ASSERT p instanceof Vec2
    ret = []
    if p.x > 0 then ret.push new Vec2(p.x-1, p.y)
    if p.y > 0 then ret.push new Vec2(p.x, p.y-1)
    if p.x < @size.x-1 then ret.push new Vec2(p.x+1, p.y)
    if p.y < @size.y-1 then ret.push new Vec2(p.x, p.y+1)
    return ret

  diagonalNeighbors: (p) ->
    ASSERT p instanceof Vec2
    ret = @cardinalNeighbors p
    if p.x > 0 and p.y > 0 then ret.push new Vec2(p.x-1, p.y-1)
    if p.x > 0 and p.y < @size.y-1 then ret.push new Vec2(p.x-1, p.y+1)
    if p.x < @size.x-1 and p.y >= 0 then ret.push new Vec2(p.x+1, p.y-1)
    if p.x < @size.x-1 and p.y < @size.y-1 then ret.push new Vec2(p.x+1, p.y+1)
    return ret

  euclideanDistance: (a, b) ->
    ASSERT a instanceof Vec2
    ASSERT b instanceof Vec2
    return a.dist(b)

  rectilinearDistance: (a, b) ->
    ASSERT a instanceof Vec2
    ASSERT b instanceof Vec2
    dx = b.x - a.x
    dy = b.y - a.y
    return Math.abs(dx) + Math.abs(dy)

  findPath: (start, end) ->
    results = aStar
      start: start
      isEnd: (p) -> p.equals(end)
      neighbor: (p) =>
        neighbors = @diagonalNeighbors p
        return (n for n in neighbors when @isWalkable(n))
      distance: (p1, p2) => @euclideanDistance p1, p2
      heuristic: (p) => @rectilinearDistance p, end
      hash: (p) -> p.toString()
    return results.path

  pathDistance: (start, end) ->
    path = @findPath(start, end)
    if path
      return path.length - 1
    else
      return -1

  getRandomWalkableLocation: ->
    while true
      p = new Vec2(
        Math.floor(Math.random() * @size.x),
        Math.floor(Math.random() * @size.y)
      )
      return p if @isWalkable(p)

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  isWalkable: (p) ->
    return @get(p) in [Map.Cells.EMPTY, Map.Cells.ROOM, Map.Cells.DOOR, Map.Cells.HALLWAY]

  # ---------------------------------------------------------------------------
  # Procedural Generation
  # ---------------------------------------------------------------------------
  
  populateWithOneBigRoom: ->
    @foreach (p) =>
      if p.x in [0, @size.x - 1] or p.y in [0, @size.y - 1]
        @set p, Map.Cells.WALL
      else
        @set p, Map.Cells.ROOM


exports.Map = Map
