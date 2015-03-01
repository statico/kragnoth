#!./node_modules/.bin/coffee

require 'coffee-script/register' # for node-inspector

ROT = require 'rot.js'
browserify = require 'browserify-middleware'
express = require 'express'
http = require 'http'
random = require 'random-ext'
websocket = require 'websocket'
{vec2} = require 'gl-matrix'

{SparseMap, DenseMap} = require './lib/map.coffee'
{TILES} = require './lib/terrain.coffee'

# TODO: Inject
WEB_PORT = 9000
CNC_PORT = 9001
GAME_PORT = 9002

app = express()

app.get '/main.js', browserify('./lib/main.coffee', transform: ['coffeeify'])

app.get '/', (req, res) ->
  res.send '''
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8"/>
        <title>Kragnoth</title>
        <style>
        body {
          background: black;
          color: white;
          font-family: sans-serif;
        }
        </style>
      </head>
      <body>
        <script src="/main.js"></script>
      </body>
    </html>
    '''

app.listen WEB_PORT, '0.0.0.0', ->
  console.log "Web server listening on http://127.0.0.1:#{ WEB_PORT }/"

cncServer = http.createServer()
cncServer.listen CNC_PORT, '0.0.0.0', -> console.log "CNC server on #{ CNC_PORT }"

cncWSServer = new websocket.server(httpServer: cncServer)
cncWSServer.on 'request', (req) ->
  conn = req.accept 'cnc', req.origin
  console.log 'Accepted CNC connection'
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    console.log 'CNC message', msg
  conn.on 'close', ->
    console.log 'CNC closed'
  conn.on 'error', (err) ->
    console.log 'CNC error', err
  conn.sendUTF JSON.stringify type: 'hello'
  conn.sendUTF JSON.stringify type: 'connect', url: "ws://127.0.0.1:#{ GAME_PORT }/"

gameServer = http.createServer()
gameServer.listen GAME_PORT, '0.0.0.0', -> console.log "Game server on #{ GAME_PORT }"

gameWSServer = new websocket.server(httpServer: gameServer)
gameWSServer.on 'request', (req) ->
  conn = req.accept 'game', req.origin
  console.log 'Accepted Game connection'
  conn.on 'message', (event) ->
    msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
    console.log 'Game message', msg
  conn.on 'error', (err) ->
    console.log 'Game error', err

  world = new World('player1')
  scheduler = new Scheduler(world, conn)
  scheduler.start()
  conn.on 'close', ->
    scheduler.end()

class Scheduler
  constructor: (@world, @playerConn) ->
    @tickSpeed = 100
    @tick = 0
    @playerConn.on 'message', (event) =>
      msg = JSON.parse if event.type is 'utf8' then event.utf8Data else event.binaryData
      if msg.type is 'input'
        @world.player.lastInput = msg
  send: (obj) -> @playerConn.sendUTF JSON.stringify obj
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
        @send type: 'gameover'
        return
      monsters = []
      items = []
      if @world.level?
        for _, monster of @world.level.monsters
          monsters.push monster.toViewJSON() if diff.get monster.pos
        for _, item of @world.level.items
          if diff.get item.pos
            items.push item.toViewJSON()
      @send
        type: 'tick'
        tick: @tick
        player: @world.player.toViewJSON()
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
  constructor: (playerName) ->
    @_nextGUID = 1

    @levels = [new Level(this, 1, 'level-1')]
    @levelIndex = 0
    @level = @levels[@levelIndex]
    @gameOver = false

    @player = new Player(playerName)
    @player.pos = @level.pickPositionOfType TILES.STAIRCASE_UP
    throw new Error("Couldn't find staircase") unless @player.pos
    @level.actors.set @player.pos, @player

    @messages = null

  getGUID: ->
    return @_nextGUID++

  kill: (actor) ->
    @level.actors.delete actor.pos
    delete @level.monsters[actor.id]

  simulate: (tickSpeed, tick) ->
    @messages = if tick is 1 then ['Welcome to Kragnoth'] else []

    updatePos = (actor, command, dir) =>
      delta = switch dir
        when 'n' then [0, -1]
        when 's' then [0, 1]
        when 'e' then [1, 0]
        when 'w' then [-1, 0]
        when 'nw' then [-1, -1]
        when 'sw' then [-1, 1]
        when 'ne' then [1, -1]
        when 'se' then [1, 1]
        else [0, 0]
      next = [0, 0]
      vec2.add next, actor.pos, delta
      vec2.min next, next, [@level.width - 1, @level.height - 1]
      vec2.max next, next, [0, 0]
      tile = @level.terrain.get next
      neighbor = @level.actors.get next
      pile = @level.piles.get next

      moved = false
      if actor != neighbor
        if command in ['move', 'attack-move']
          if tile in [TILES.FLOOR, TILES.CORRIDOR, TILES.STAIRCASE_UP, TILES.STAIRCASE_DOWN] and not neighbor
            moved = true
            vec2.copy actor.pos, next
          if actor.isPlayer and pile?.length
            @messages.push "There are items here: #{ (i.name for i in pile).join ', ' }"
          if actor.isPlayer and neighbor and command != 'attack-move'
            @messages.push "#{ neighbor.name } is in the way"
        if command in ['attack-move', 'attack']
          if neighbor
            solveAttack actor, neighbor
      if moved
        for item in actor.items
          vec2.copy item.pos, actor.pos
        if tile is TILES.STAIRCASE_UP
          @messages.push "There is a staircase up here."
        if tile is TILES.STAIRCASE_DOWN
          @messages.push "There is a staircase down here."
      return

    solveAttack = (attacker, defender) =>
      ap = attacker.ap
      ap += attacker.weapon.ap if attacker.weapon?
      defender.hp -= ap
      if attacker.isPlayer
        @messages.push "You hit the #{ defender.name }"
        if attacker.ap is 0
          msg += " It seems unaffected."
        @messages.push msg
      if defender.isPlayer
        msg = "The #{ attacker.name } hits!"
        if attacker.ap is 0
          msg += " You seem unaffected."
        @messages.push msg
      if defender.hp <= 0
        @kill defender
        if attacker.isPlayer
          @messages.push "You kill the #{ defender.name }!"

    handlePickup = (actor) =>
      pile = @level.piles.get actor.pos
      if pile?.length
        @level.piles.delete actor.pos
        loop
          item = pile.shift()
          switch item.class
            when 'gold'
              actor.gold += item.value
              delete @level.items[item.id]
              msg = "#{ item.value } gold"
            when 'weapon'
              actor.items.push item
              article = if /aeiouy/.test(item.name) then 'an' else 'a'
              msg = "#{ article } #{ item.name }"
          if actor.isPlayer
            @messages.push "You pick up #{ msg }"
          else
            @messages.push "The #{ actor.name } picks up #{ msg }"
          break unless pile.length
      else
        if actor.isPlayer
          @messages.push "There is nothing here to pickup"

    goLevelUp = =>
      if @level.depth is 1
        @gameOver = true
        @levelIndex = -1
        @level = null
      else
        @levelIndex--
        @level = @levels[@levelIndex]
        vec2.copy @player.pos, @level.pickPositionOfType TILES.STAIRCASE_DOWN

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
      vec2.copy @player.pos, @level.pickPositionOfType TILES.STAIRCASE_UP

    command = @player.simulate()
    switch command?.command
      when 'move', 'attack-move', 'attack'
        dir = command.direction
        if dir in ['up', 'down']
          tile = @level.terrain.get @player.pos
          if dir is 'up' and tile is TILES.STAIRCASE_UP
            goLevelUp()
          else if dir is 'down' and tile is TILES.STAIRCASE_DOWN
            goLevelDown()
          else
            @messages.push "There is no staircase here."
        else
          oldPos = vec2.copy [0,0], @player.pos
          updatePos @player, command.command, command.direction
          @level.actors.delete oldPos
          @level.actors.set @player.pos, @player
      when 'pickup'
        handlePickup @player
      when 'choose-item'
        for i in @player.items
          item = i if i.id is command.id
        if item?
          if item.class = 'weapon'
            @player.weapon = item
          else
            @messages.push "Can't use #{ item.name } as a weapon"

    return if @gameOver

    for _, monster of @level.monsters
      delta = (tick - monster.lastTick) * tickSpeed
      continue unless delta >= 1000 / monster.speed
      command = monster.simulate()
      switch command?.command
        when 'move', 'attack-move', 'attack'
          oldPos = vec2.copy [0,0], monster.pos
          updatePos monster, command.command, command.direction
          @level.actors.delete oldPos
          @level.actors.set monster.pos, monster
        when 'pickup'
          handlePickup monster
      monster.lastTick = tick

    # computer what areas the player can see
    diff = new SparseMap(@level.width, @level.height)
    test = (x, y) => @level.terrain.get([x, y]) in [TILES.FLOOR, TILES.CORRIDOR, TILES.STAIRCASE_UP, TILES.STAIRCASE_DOWN]
    fov = new ROT.FOV.PreciseShadowcasting(test)
    [x, y] = @player.pos
    temp = [0, 0]
    fov.compute x, y, 10, (x, y, _, visible) =>
      # for now, just send terrain data
      vec2.set temp, x, y
      diff.set temp, terrain: @level.terrain.get temp

    return diff

  toJSON: ->
    return {
      player: @player.toJSON()
      level: @level.toJSON()
    }

class Level
  constructor: (@world, @depth, @name) ->
    @width = 80
    @height = 24
    @actors = new SparseMap(@width, @height)
    @piles = new SparseMap(@width, @height)

    @terrain = new DenseMap(@width, @height)
    map = new ROT.Map.Digger(@width, @height)
    map.create (x, y, v) =>
      @terrain.set [x, y], switch v
        when 0 then TILES.FLOOR
        when 1 then TILES.VOID
    @terrain.set @pickPositionOfType(TILES.FLOOR), TILES.STAIRCASE_UP
    @terrain.set @pickPositionOfType(TILES.FLOOR), TILES.STAIRCASE_DOWN
    console.log 'XXX', @terrain.toString()
    console.log 'XXX', map.getRooms()

    @monsters = {}
    for monster in [new Mosquito(), new Slug(), new Slug(), new Slug(), new Slug()]
      monster.id = @world.getGUID()
      monster.lastTick = random.integer 10
      monster.pos = @pickRandomSpawnablePosition()
      @actors.set monster.pos, monster
      @monsters[monster.id] = monster

    @items = {}
    for cls in ['gold', 'weapon']
      for i in [0..3]
        item = Item.createFromClass cls
        item.id = @world.getGUID()
        vec2.copy item.pos, @pickRandomSpawnablePosition()
        pile = @piles.get(item.pos) ? []
        pile.push item
        @piles.set item.pos, pile
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
      return pos if @terrain.get(pos) is TILES.FLOOR and not @actors.get(pos)

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
      weapon: @weapon?.toViewJSON()
    }

class Monster extends Actor
  constructor: ->
    super()
    @isPlayer = false
  simulate: ->
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
    @pos = [10, 10]
    @speed = 10
    @hp = 1
    @ap = 1

class Slug extends Monster
  constructor: ->
    super()
    @name = 'slug'
    @pos = [11, 10]
    @speed = 1
    @hp = 10
    @ap = 0

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
