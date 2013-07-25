PriorityQueue = require 'priorityqueuejs'
aStar = require 'a-star'
{Vec2} = require 'justmath'
perlin = require './perlin'

# I'm too lazy to write tests, so I'll use runtime assertions for now.
ASSERT = (cond) -> throw new Error('Assertion failed') if not cond

# ---------------------------------------------------------------------------
# UTILS
# ---------------------------------------------------------------------------

randInt = (x) -> Math.floor(Math.random() * x)

# ---------------------------------------------------------------------------
# MAP
# ---------------------------------------------------------------------------

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

  toArray: ->
    result = []
    @foreach (p) =>
      result[p.y] ?= []
      result[p.y][p.x] = @get(p)
    return result

  @fromArray: (arr) ->
    result = new Map(new Vec2(arr[0].length, arr.length))
    for y in [0...arr.length]
      row = arr[y]
      for x in [0...row.length]
        result.set new Vec2(x, y), row[x]
    return result

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

  findPath: (start, end, filter = (-> true)) ->
    ASSERT start instanceof Vec2
    ASSERT end instanceof Vec2

    results = aStar
      start: start
      isEnd: (p) -> p.equals(end)
      neighbor: (p) =>
        neighbors = @diagonalNeighbors p
        return (n for n in neighbors when @isPassable(n) and filter(n))
      distance: (p1, p2) => @euclideanDistance p1, p2
      heuristic: (p) => @rectilinearDistance p, end
      hash: (p) -> p.toString()

    # Remove start.
    path = results.path
    path?.splice 0, 1
    return path

  pathDistance: (start, end) ->
    return @findPath(start, end)?.length

  getRandomWalkableLocation: ->
    while true
      p = new Vec2(
        Math.floor(Math.random() * @size.x),
        Math.floor(Math.random() * @size.y)
      )
      return p if @isPassable(p)

  # ---------------------------------------------------------------------------
  # Properties
  # ---------------------------------------------------------------------------

  isPassable: (p) ->
    return @get(p) in [Map.Cells.ROOM, Map.Cells.DOOR, Map.Cells.HALLWAY]

  isDiggable: (p) ->
    return @get(p) == Map.Cells.EMPTY

  # ---------------------------------------------------------------------------
  # Procedural Generation
  # ---------------------------------------------------------------------------
  
  fillWithOneBigRoom: ->
    @foreach (p) =>
      if p.x in [0, @size.x - 1] or p.y in [0, @size.y - 1]
        @set p, Map.Cells.WALL
      else
        @set p, Map.Cells.ROOM

  fillWithLotsOfRooms: ->
    @foreach (p) => @set p, Map.Cells.EMPTY
    rooms = @_makeRooms 300
    @_makeHallways rooms, 1000

  _makeRooms: (density = 300) ->
    L = 0
    R = @size.x - 1
    T = 0
    B = @size.y - 1

    rooms = []

    roomCollision = (tuple1, tuple2, pad = 1) ->
      [t1, r1, b1, l1] = tuple1
      [t2, r2, b2, l2] = tuple2
      return false if b1 < t2 - pad
      return false if t1 > b2 + pad
      return false if r1 < l2 - pad
      return false if l1 > r2 + pad
      return true

    # Pick a reasonable number of rooms for the tile.
    for i in [1..Math.floor(@size.magSq() / density)]

      tries = 1000
      while tries > 0
        tries--

        l = L + randInt (R - L)
        t = T + randInt (B - T)
        r = l + 6 + randInt 12
        b = t + 3 + randInt 10
        continue if l <= L or t <= T # XXX ?
        continue if r >= R - 1
        continue if b >= B - 1

        current = [t, r, b, l]
        ok = true
        for other in rooms
          if roomCollision current, other
            ok = false
            break
        if ok
          rooms.push current
          break

    if not rooms.length
      throw new Error("Couldn't create any satisfactory rooms")

    for i in [0...rooms.length]
      room = rooms[i]
      [t, r, b, l] = room

      # Draw the room.
      for y in [t..b]
        for x in [l..r]
          @set new Vec2(x, y), Map.Cells.ROOM

      # Draw the perimeter.
      for x in [l..r]
        @set new Vec2(x, t), Map.Cells.WALL
        @set new Vec2(x, b), Map.Cells.WALL
      for y in [t+1..b-1]
        @set new Vec2(l, y), Map.Cells.WALL
        @set new Vec2(r, y), Map.Cells.WALL

      # Add at least one door.
      count = 1 + randInt (r-l) * 2 / 10
      for [1..count]
        rx = l + 1 + randInt(r - l - 1)
        ry = t + 1 + randInt(b - t - 1)
        switch randInt 4
          when 0 # top
            x = rx
            y = t
          when 1 # right
            x = r
            y = ry
          when 2 # bottom
            x = rx
            y = b
          when 3 # left
            x = l
            y = ry
        @set new Vec2(x, y), Map.Cells.DOOR

    return rooms

  _makeHallways: (rooms, density = 600) ->
    L = 0
    R = @size.x - 1
    T = 0
    B = @size.y - 1

    # Adding a little Perlin Simplex noise makes the hallways a little more
    # natural and windy.
    noise = new perlin.SimplexNoise random: -> 0.123 # Seed the noise.

    filter = (node) =>
      #@set new Vec2(node.x, node.y), 5 if !node.value
      x = node.value
      return (!x or x in [Map.Cells.EMPTY, Map.Cells.DOOR, Map.Cells.HALLWAY])

    findDoors = (room) =>
      [t, r, b, l] = room
      doors = []
      for x in [l..r]
        xt = new Vec2(x, t)
        if @get(xt) == Map.Cells.DOOR # top wall
          doors.push xt
        xb = new Vec2(x, b)
        if @get(xb) == Map.Cells.DOOR # bottom wall
          doors.push xb
      for y in [t..b]
        ly = new Vec2(l, y)
        if @get(ly) == Map.Cells.DOOR # left wall
          doors.push ly
        ry = new Vec2(r, y)
        if @get(ry) == Map.Cells.DOOR # right wall
          doors.push ry
      return doors

    # Connect each room with one other.
    hallwayPoints = []
    for i in [0..rooms.length - 1]

      # Pick another room at random.
      j = i
      while j == i
        j = randInt rooms.length
      room = rooms[i]
      other = rooms[j]

      a = findDoors(room)
      b = findDoors(other)
      continue if not a.length or not b.length
      door1 = a[0]
      door2 = b[0]

      results = aStar
        start: door1
        isEnd: (p) -> p.equals(door2)
        neighbor: (p) =>
          neighbors = @diagonalNeighbors p
          return (n for n in neighbors when @isDiggable(n))
        distance: (p1, p2) => @euclideanDistance p1, p2
        heuristic: (p) =>
          if @get(door2) == Map.Cells.HALLWAY
            return 0
          else
            return @rectilinearDistance(p, door2) + Math.floor(noise.noise(door1.x/15, door1.y/15) * 20)
        hash: (p) -> p.toString()

      #path = @map.astar x1, y1, x2, y2, filter, heuristic
      for p in results.path
        @set p, Map.Cells.HALLWAY
        hallwayPoints.push p

    if not hallwayPoints
      throw new Error("Could not create any hallwayPoints")

    # Pick some random parts of a hallway and make branches to nowhere.
    for i in [1..Math.floor(@size.magSq() / density)]
      door1 = hallwayPoints[randInt hallwayPoints.length]
      door2 = null
      r = Math.floor(Math.sqrt(@size.magSq()) * .2)
      tries = 1000
      while not door2 and tries > 0
        tries--
        x = door1.x - r + randInt(r * 2)
        y = door1.y - r + randInt(r * 2)
        possible = new Vec2(x, y)
        if not @get(possible)
          door2 = possible
      if not possible
        throw new Error("Could not create hallway #{ i } from #{ door1 }")

      results = aStar
        start: door1
        isEnd: (p) -> p.equals(door2)
        neighbor: (p) =>
          neighbors = @diagonalNeighbors p
          return (n for n in neighbors when @isDiggable(n))
        distance: (p1, p2) => @euclideanDistance p1, p2
        heuristic: (p) =>
          if @get(door2) == Map.Cells.HALLWAY
            return 0
          else
            return @rectilinearDistance(p, door2) + Math.floor(noise.noise(door1.x/15, door1.y/15) * 20)
        hash: (p) -> p.toString()

      #path = @map.astar x1, y1, x2, y2, filter, heuristic
      for p in results.path
        console.log 'XXX', p
        @set p, Map.Cells.HALLWAY

exports.Map = Map
