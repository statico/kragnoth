#!./node_modules/.bin/coffee

require 'coffee-script/register' # for node-inspector

ROT = require 'rot.js'
browserify = require 'browserify-middleware'
commander = require 'commander'
express = require 'express'
http = require 'http'
random = require 'random-ext'
stylus = require 'stylus'
websocket = require 'websocket'
{vec2} = require 'gl-matrix'

{SparseMap, SparseMapList, DenseMap} = require './lib/map.coffee'
{TILES, WALKABLE_TILES, DIR_TO_VEC, ZERO} = require './lib/terrain.coffee'

# TODO: Inject
argv = commander
  .option('-n, --numPlayers <n>', "Number of players per party", parseInt, 2)
  .option('-h, --host <host>', "Bind port to this", String, '127.0.0.1')
  .option('--webPort <port>', "Main web UI port", parseInt, 9000)
  .option('--cncPort <port>', "Command and control port", parseInt, 9001)
  .option('--gamePort <port>', "Game port", parseInt, 9002)
  .parse(process.argv)

app = express()
app.use stylus.middleware src: __dirname + '/static/style'
app.use express.static __dirname + '/static'
app.set 'view engine', 'jade'
app.get '/main.js', browserify('./lib/main.coffee', transform: ['coffeeify'])
app.get '/', (req, res) -> res.render 'index', argv: argv

app.listen argv.webPort, argv.host, ->
  console.log "Web server listening on http://#{ argv.host }:#{ argv.webPort }/"

cncServer = http.createServer()
cncServer.listen argv.cncPort, argv.host, -> console.log "CNC server on #{ argv.cncPort }"

cncLobby = {}
cncWSServer = new websocket.server(httpServer: cncServer)
cncWSServer.on 'request', (req) ->
  conn = req.accept 'cnc', req.origin
  send = (obj) -> conn.sendUTF JSON.stringify obj
  console.log 'Accepted CNC connection'
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    console.log 'CNC message', msg
    if msg.type is 'hello'
      {playerId} = msg
      if playerId of cncLobby
        console.error "Error: #{ playerId } already in lobby"
        return
      cncLobby[playerId] = conn
      if Object.keys(cncLobby).length >= argv.numPlayers
        gameId = "game-#{ random.restrictedString [random.CHAR_TYPE.LOWERCASE], 4, 4 }"
        for playerId, playerConn of cncLobby
          console.log "Telling player #{ playerId } to start game #{ gameId }"
          playerConn.sendUTF JSON.stringify
            type: 'connect', url: "ws://#{ argv.host }:#{ argv.gamePort }/", gameId: gameId
          delete cncLobby[playerId]
      else
        cncLobby[playerId] = conn
        console.log "Player #{ playerId } is waiting for a game"

  conn.on 'close', ->
    console.log 'CNC closed'
  conn.on 'error', (err) ->
    console.log 'CNC error', err
  send type: 'hello'

gameServer = http.createServer()
gameServer.listen argv.gamePort, argv.host, -> console.log "Game server on #{ argv.gamePort }"

gameSchedulers = {}
gameWSServer = new websocket.server(httpServer: gameServer)
gameWSServer.on 'request', (req) ->
  conn = req.accept 'game', req.origin
  console.log 'Accepted Game connection'
  conn.on 'error', (err) ->
    console.log 'Game error', err
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    if msg.type is 'hello'
      {playerId, gameId} = msg
      scheduler = gameSchedulers[gameId]
      if not scheduler
        scheduler = new Scheduler(new World())
        gameSchedulers[gameId] = scheduler
      scheduler.addPlayer playerId, conn
      if Object.keys(scheduler.players).length >= argv.numPlayers
        scheduler.start()
        conn.on 'close', ->
          scheduler.world.gameOver = true

class Scheduler
  constructor: (@world) ->
    @tickSpeed = 100
    @tick = 0
    @players = {}
  addPlayer: (playerId, conn) ->
    @players[playerId] = conn
    @world.addPlayer playerId, conn
    conn.on 'message', (event) =>
      msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
      if msg.type is 'input'
        @world.handlePlayerInput playerId, msg
  send: (obj) ->
    for playerId, conn of @players
      conn.sendUTF JSON.stringify obj
  start: ->
    oldLevelIndex = null
    doTick = =>
      start = Date.now()
      @tick++
      if oldLevelIndex != @world.levelIndex
        @send
          type: 'level-init'
          index: @world.levelIndex
          name: @world.level.name
          width: @world.level.width
          height: @world.level.height
        oldLevelIndex = @world.levelIndex
      diff = @world.simulate(@tickSpeed, @tick)
      if @world.gameOver
        console.log "Game over"
        @send type: 'gameover', reason: "Your party has exited the dungeon. Goodbye!"
        return
      monsters = []
      items = []
      if @world.level?
        for _, monster of @world.level.monsters
          monsters.push monster.toViewJSON() if diff.get monster.pos
        for _, item of @world.level.items
          if diff.get item.pos
            items.push item.toViewJSON()
      players = {}
      for playerId, actor of @world.playerActors
        players[playerId] = actor.toViewJSON()
      @send
        type: 'tick'
        tick: @tick
        players: players
        monsters: monsters
        items: items
        diff: diff.toJSON()
        messages: @world.messages
      next = (start + @tickSpeed) - Date.now()
      @timer = setTimeout doTick, if next < 0 then 0 else next
    doTick()
  end: ->
    clearTimeout @timer

class World
  constructor: ->
    @_nextGUID = 1

    @levels = [new Level(this, 1, 'level-1')]
    @levelIndex = 0
    @level = @levels[@levelIndex]
    @gameOver = false
    @messages = null

    @playerConns = {}
    @playerActors = {}

  addPlayer: (id, conn) ->
    actor = new Player(id)
    @playerConns[id] = conn
    @playerActors[id] = actor
    actor.pos = @level.pickPositionOfType TILES.STAIRCASE_UP
    throw new Error("Couldn't find staircase up") unless actor.pos
    @level.actors.add actor.pos, actor

  handlePlayerInput: (id, msg) ->
    @playerActors[id].lastInput = msg

  getGUID: ->
    return @_nextGUID++

  kill: (actor) ->
    @level.actors.remove actor.pos, actor
    delete @level.monsters[actor.id]

  simulate: (tickSpeed, tick) ->
    @messages = if tick is 1 then ['Welcome to Kragnoth'] else []

    max = [@level.width - 1, @level.height - 1]

    updatePos = (actor, command, dir) =>
      delta = DIR_TO_VEC[dir] or ZERO
      next = [0, 0]
      vec2.add next, actor.pos, delta
      vec2.min next, next, max
      vec2.max next, next, ZERO

      tile = @level.terrain.get next
      pile = @level.piles.get next
      occupants = @level.actors.get next
      isMove = command in ['move', 'attack-move']
      isAttack = command in ['attack-move', 'attack']

      # 1. Players cannot attack themselves or other players.
      # 2. Players can overlap players.
      # 3. Monsters cannot overlap players.

      if isAttack
        candidates = (o for o in occupants when o.isPlayer != actor.isPlayer) if occupants
        defender = candidates?[0]
        solveAttack actor, defender if defender?

      if isMove
        if tile of WALKABLE_TILES
          if actor.isPlayer
            blockers = (o for o in occupants when not o.isPlayer) if occupants
          else
            blockers = occupants
          if not blockers?.length
            vec2.copy actor.pos, next
            vec2.copy item.pos, next for item in actor.items

      return

    solveAttack = (attacker, defender) =>
      ap = attacker.ap
      ap += attacker.weapon.ap if attacker.weapon?
      defender.hp -= ap
      if attacker.isPlayer
        @messages.push "Player #{ attacker.name } hit the #{ defender.name }"
        if attacker.ap is 0
          msg += " It seems unaffected."
        @messages.push msg
      if defender.isPlayer
        msg = "The #{ attacker.name } hits #{ defender.name }!"
        if attacker.ap is 0
          msg += " They seem unaffected."
        @messages.push msg
      if defender.hp <= 0
        @kill defender
        if attacker.isPlayer
          @messages.push "#{ attacker.name } kills the #{ defender.name }!"

    handlePickup = (actor) =>
      pile = @level.piles.get actor.pos
      if pile
        @level.piles.delete actor.pos
        loop
          item = pile.shift()
          delete @level.items[item.id]
          switch item.class
            when 'gold'
              actor.gold += item.value
              msg = "#{ item.value } gold"
            when 'weapon'
              actor.items.push item
              article = if (/^[aeiouy]/i).test(item.name) then 'an' else 'a'
              msg = "#{ article } #{ item.name }"
            when 'potion'
              actor.items.push item
              msg = 'a potion!'
          if actor.isPlayer
            @messages.push "#{ actor.name } picks up #{ msg }"
          else
            @messages.push "The #{ actor.name } picks up #{ msg }"
          break unless pile.length
      else
        if actor.isPlayer
          @messages.push "There nothing for #{ actor.name } to pickup"

    goLevelUp = =>
      if @level.depth is 1
        @gameOver = true
        @levelIndex = -1
        @level = null
      else
        @levelIndex--
        @level = @levels[@levelIndex]
        pos = @level.pickPositionOfType TILES.STAIRCASE_DOWN
        for _, player of @playerActors
          vec2.copy player.pos, pos

    goLevelDown = =>
      @levelIndex++
      @level = @levels[@levelIndex]
      if not @level?
        depth = @levelIndex + 1
        @level = new Level(this, depth, "level-#{ depth }")
        if depth > 2
          pos = @level.pickPositionOfType TILES.STAIRCASE_DOWN
          @level.terrain.set pos, TILES.FLOOR
        @levels[@levelIndex] = @level
      pos = @level.pickPositionOfType TILES.STAIRCASE_UP
      for _, player of @playerActors
        vec2.copy player.pos, pos

    for _, player of @playerActors
      command = player.simulate()
      switch command?.command
        when 'move', 'attack-move', 'attack'
          dir = command.direction
          if dir in ['up', 'down']
            tile = @level.terrain.get player.pos
            actors = @level.actors.get player.pos
            if actors
              actors = (a for a in actors when a.isPlayer)
            if actors?.length is argv.numPlayers
              if dir is 'up' and tile is TILES.STAIRCASE_UP
                goLevelUp()
              else if dir is 'down' and tile is TILES.STAIRCASE_DOWN
                goLevelDown()
              else
                @messages.push "There is no #{ dir } staircase here."
            else
              @messages.push "All #{ argv.numPlayers } players must be on the staircase."
          else
            oldPos = vec2.copy [0,0], player.pos
            updatePos player, command.command, command.direction
            @level.actors.remove oldPos, player
            @level.actors.add player.pos, player
        when 'pickup'
          handlePickup player
        when 'choose-item'
          for i in player.items
            item = i if i.id is command.id
          if item?
            if item.class is 'weapon'
              player.weapon = item
            else if item.class is 'potion'
              player.hp = Math.min (player.hp + item.hp), player.maxHp
              player.items = (i for i in player.items when i.id != item.id)
              delete @level.items[item.id]
            else
              @messages.push "Can't use #{ item.name } as a weapon"

    return if @gameOver

    for _, monster of @level.monsters
      delta = (tick - monster.lastTick) * tickSpeed
      continue unless delta >= 1000 / monster.speed
      command = monster.simulate(this)
      switch command?.command
        when 'move', 'attack-move', 'attack'
          oldPos = vec2.copy [0,0], monster.pos
          updatePos monster, command.command, command.direction
          @level.actors.remove oldPos, monster
          @level.actors.add monster.pos, monster
        when 'pickup'
          handlePickup monster
      monster.lastTick = tick

    # computer what areas the player can see
    pos = [0, 0]
    diff = new SparseMap(@level.width, @level.height)
    isWalkable = (x, y) =>
      vec2.set pos, x, y
      @level.terrain.get(pos) of WALKABLE_TILES
    fov = new ROT.FOV.PreciseShadowcasting(isWalkable)
    for _, player of @playerActors
      [x, y] = player.pos
      fov.compute x, y, 10, (x, y, _, visible) =>
        # for now, just send terrain data
        vec2.set pos, x, y
        diff.set pos, terrain: @level.terrain.get pos

    return diff

  toJSON: ->
    return {
      players: (p.toJSON() for _, p of @playerActors)
      level: @level.toJSON()
    }

class Level
  constructor: (@world, @depth, @name) ->
    @width = 60
    @height = 24
    @actors = new SparseMapList(@width, @height)
    @piles = new SparseMapList(@width, @height)

    @terrain = new DenseMap(@width, @height)
    pos = [0, 0]
    map = new ROT.Map.Digger(@width, @height)
    map.create (x, y, v) =>
      vec2.set pos, x, y
      @terrain.set pos, switch v
        when 0 then TILES.FLOOR
        when 1 then TILES.VOID

    for corridor in map.getCorridors()
      for x in [corridor._startX..corridor._endX]
        for y in [corridor._startY..corridor._endY]
          vec2.set pos, x, y
          @terrain.set pos, TILES.CORRIDOR if @terrain.get(pos) is TILES.FLOOR

    maybeDoor = (x, y) =>
      vec2.set pos, x, y
      tile = @terrain.get pos
      if tile is TILES.FLOOR then @terrain.set pos, TILES.DOOR
      if tile is TILES.VOID then @terrain.set pos, TILES.WALL
    for room in map.getRooms()
      x1 = room._x1 - 1
      x2 = room._x2 + 1
      y1 = room._y1 - 1
      y2 = room._y2 + 1
      for x in [x1..x2]
        maybeDoor x, y1
        maybeDoor x, y2
      for y in [y1+1..y2-1]
        maybeDoor x1, y
        maybeDoor x2, y

    pos = @pickPositionOfType(TILES.FLOOR)
    @terrain.set pos, TILES.STAIRCASE_UP
    pos = @pickPositionOfType(TILES.FLOOR)
    @terrain.set pos, TILES.STAIRCASE_DOWN

    @monsters = {}
    monsterSpec = [
      { cls: Mosquito, min: 1, max: 3 }
      { cls: Slug, min: 3, max: 6 }
      { cls: Seeker, min: 5, max: 8 }
    ]
    for {cls, min, max} in monsterSpec
      for i in [0..random.integer(max, min)]
        monster = new cls()
        monster.id = @world.getGUID()
        monster.lastTick = random.integer 10
        monster.pos = @pickRandomSpawnablePosition()
        @actors.add monster.pos, monster
        @monsters[monster.id] = monster

    @items = {}
    itemSpec = [
      { cls: 'gold', min: 0, max: 3 },
      { cls: 'weapon', min: 0, max: 3},
      { cls: 'potion', min: 0, max: 1},
    ]
    for {cls, min, max} in itemSpec
      for i in [0..random.integer(max, min)]
        item = Item.createFromClass cls
        item.id = @world.getGUID()
        vec2.copy item.pos, @pickRandomSpawnablePosition()
        @piles.add item.pos, item
        @items[item.id] = item

  pickPositionOfType: (type) ->
    tries = 0
    pos = [0, 0]
    loop
      vec2.set pos, random.integer(@width-1), random.integer(@height-1)
      return pos if @terrain.get(pos) is type
      break if tries++ > 1000
    for x in [0...@width]
      for y in [0...@height]
        vec2.set pos, x, y
        return pos if @terrain.get(pos) is type
    return null

  pickRandomSpawnablePosition: ->
    pos = [0, 0]
    loop
      vec2.set pos, random.integer(@width-1), random.integer(@height-1)
      return pos if @terrain.get(pos) is TILES.FLOOR and @actors.isEmpty(pos)

  toJSON: ->
    return {
      name: @name
      width: @width
      height: @height
      terrain: @terrain.toJSON()
    }

class Actor
  constructor: ->
    @id = -1
    @pos = [0, 0]
    @items = []
    @weapon = null
    @gold = 0

class Player extends Actor
  constructor: (@name) ->
    super()
    @lastInput = null
    @isPlayer = true
    @ap = 5
    @hp = 50
    @maxHp = 50
  simulate: ->
    obj = @lastInput
    @lastInput = null
    return obj
  toViewJSON: ->
    return {
      id: @id
      name: @name
      pos: @pos
      items: (i.toViewJSON() for i in @items)
      gold: @gold
      ap: @ap
      hp: @hp
      maxHp: @maxHp
      weapon: @weapon?.toViewJSON()
    }

class Monster extends Actor
  constructor: ->
    super()
    @pos = [0, 0]
    @isPlayer = false
  simulate: (world) ->
    dir = random.pick 'n w s e nw sw se ne'.split ' '
    return { command: 'attack-move', direction: dir }
  toJSON: ->
    return {
      id: @id
      name: @name
      pos: @pos
      speed: @speed
    }
  toViewJSON: ->
    return {
      id: @id
      name: @name
      pos: @pos
    }

class Mosquito extends Monster
  constructor: ->
    super()
    @name = 'mosquito'
    @speed = 10
    @hp = 1
    @ap = 1

class Slug extends Monster
  constructor: ->
    super()
    @name = 'slug'
    @speed = 1
    @hp = 10
    @ap = 0

class Seeker extends Monster
  constructor: ->
    super()
    @name = 'seeker'
    @speed = 3
    @sightRadius = 5
    @hp = 10
    @ap = 2
  simulate: (world) ->
    {level, actors} = world

    vision = new SparseMap(level.width, level.height)
    pos = [0, 0]
    isWalkable = (x, y) ->
      vec2.set pos, x, y
      return level.terrain.get(pos) of WALKABLE_TILES
    fov = new ROT.FOV.PreciseShadowcasting(isWalkable)
    fov.compute @pos[0], @pos[1], 4, (x, y, _, visible) ->
      vec2.set pos, x, y
      vision.set pos, true
    for y of vision.map
      for x of vision.map[y]
        vec2.set pos, x, y
        actors = level.actors.get pos
        if actors?
          for actor in actors
            if actor.isPlayer
              target = actor.pos
              break

    if not target
      return super(world)

    steps = []
    path = new ROT.Path.AStar(target[0], target[1], isWalkable)
    path.compute @pos[0], @pos[1], (x, y) ->
      steps.push [x, y]

    if steps.length is 0
      return super(world)
    if steps.length is 1
      throw new Error("Weird single step from #{ @pos } to #{ target }")
    if steps.length > 1
      vec2.sub pos, steps[1], steps[0]
      for dir, offset of DIR_TO_VEC
        if pos[0] is offset[0] and pos[1] is offset[1]
          return { command: 'attack-move', direction: dir }

class Item
  constructor: ->
    @id = -1
    @pos = [0, 0]
  @createFromKey: (key) ->
    return @createFromSpec ITEMS[key]
  @createFromClass: (cls) ->
    spec = random.pick(v for k, v of ITEMS when v.class is cls)
    throw new Error("Unknown item class: #{ cls }") unless spec?
    return @createFromSpec spec
  @createFromSpec: (spec) ->
    item = new this()
    item.name = spec.name
    item.class = spec.class
    switch spec.class
      when 'weapon'
        item.ap = random.integer spec.apMax, spec.apMin
      when 'gold'
        item.value = random.integer 15, 1
      when 'potion'
        item.hp = random.integer spec.hpMax, spec.hpMin
    return item
  toViewJSON: ->
    return {
      id: @id
      name: @name
      class: @class
      pos: @pos
    }

ITEMS =
  gold:
    name: 'pieces of gold'
    class: 'gold'
  majorHealthPotion:
    name: 'major health potion'
    class: 'potion'
    hpMin: 10
    hpMax: 20
  minorHealthPotion:
    name: 'minor health potion'
    class: 'potion'
    hpMin: 4
    hpMax: 8
  shortSword:
    name: 'short sword'
    class: 'weapon'
    apMin: 3
    apMax: 6
  longSword:
    name: 'long sword'
    class: 'weapon'
    apMin: 4
    apMax: 8
  dagger:
    name: 'dagger'
    class: 'weapon'
    apMin: 2
    apMax: 4
  sabre:
    name: 'sabre'
    class: 'weapon'
    apMin: 6
    apMax: 8
  knife:
    name: 'knife'
    class: 'weapon'
    apMin: 1
    apMax: 3
  screwdriver:
    name: 'screwdriver'
    class: 'weapon'
    apMin: 1
    apMax: 2
