#!./node_modules/.bin/coffee

ROT = require 'rot.js'
browserify = require 'browserify-middleware'
express = require 'express'
http = require 'http'
random = require 'random-ext'
websocket = require 'websocket'
{vec2} = require 'gl-matrix'

{SparseMap, DenseMap} = require './lib/map'

# TODO: Inject
WEB_PORT = 8080
CNC_PORT = 8081
GAME_PORT = 8082

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
    console.log 'XXX', 'CNC message', msg
  conn.on 'close', ->
    console.log 'XXX', 'CNC closed'
  conn.on 'error', (err) ->
    console.log 'XXX', 'CNC error', err
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
    console.log 'XXX', 'Game message', msg
  conn.on 'error', (err) ->
    console.log 'XXX', 'Game error', err

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
    @send type: 'init', width: @world.level.width, height: @world.level.height
  send: (obj) -> @playerConn.sendUTF JSON.stringify obj
  start: ->
    doTick = =>
      start = Date.now()
      @tick++
      diff = @world.simulate(@tickSpeed, @tick)
      monsters = []
      for monster in @world.monsters
        [x, y] = monster.pos
        monsters.push monster.toViewJSON() if diff.get x, y
      items = []
      for item in @world.items
        [x, y] = item.pos
        if diff.get x, y
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
    @level = new Level()

    @player = new Player(playerName)
    @player.pos = @level.pickRandomSpawnablePosition()
    @level.actors.set @player.pos[0], @player.pos[1], @player

    @monsters = [new Mosquito(), new Slug(), new Slug(), new Slug(), new Slug()]
    for monster in @monsters
      monster.lastTick = Math.floor(Math.random() * 10)
      monster.pos = @level.pickRandomSpawnablePosition()
      @level.actors.set monster.pos[0], monster.pos[1], monster

    @items = []
    for cls in ['gold', 'weapon']
      for i in [0..7]
        item = Item.createFromClass cls
        @items.push item
        [x, y] = item.pos = @level.pickRandomSpawnablePosition()
        pile = @level.items.get(x, y) ? []
        pile.push item
        @level.items.set x, y, pile

    @messages = null

  kill: (actor) ->
    [x, y] = actor.pos
    @level.actors.delete x, y
    index = @monsters.indexOf actor
    @monsters.splice index, 1 if index != -1

  simulate: (tickSpeed, tick) ->
    @messages = []

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
      tile = @level.terrain.get next[0], next[1]
      neighbor = @level.actors.get next[0], next[1]

      moved = false
      if command in ['move', 'attack-move']
        if tile in [2, 3] and not neighbor
          moved = true
          vec2.copy actor.pos, next
        if actor.isPlayer and neighbor and command != 'attack-move'
          @messages.push "#{ neighbor.name } is in the way"
      if command in ['attack-move', 'attack']
        if neighbor
          solveAttack actor, neighbor

    solveAttack = (attacker, defender) =>
      defender.hp -= attacker.ap
      if attacker.isPlayer
        @messages.push "You hit the #{ defender.name }"
      if defender.isPlayer
        @messages.push "The #{ attacker.name } hits!"
      if defender.hp <= 0
        @kill defender
        if attacker.isPlayer
          @messages.push "You kill the #{ defender.name }!"

    handlePickup = (actor) =>
      [x, y] = actor.pos
      pile = @level.items.get x, y
      if pile?.length
        @level.items.delete x, y
        loop
          item = pile.shift()
          index = @items.indexOf item
          @items.splice index, 1 if index != -1
          switch item.class
            when 'gold'
              actor.gold += item.value
              msg = "#{ item.value } gold"
            when 'weapon'
              actor.inventory.push item
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

    command = @player.simulate()
    if command?.command in ['move', 'attack-move', 'attack']
      oldPos = vec2.copy [0,0], @player.pos
      updatePos @player, command.command, command.direction
      @level.actors.delete oldPos[0], oldPos[1]
      @level.actors.set @player.pos[0], @player.pos[1], @player
    if command?.command is 'pickup'
      handlePickup @player

    for monster in @monsters
      delta = (tick - monster.lastTick) * tickSpeed
      continue unless delta >= 1000 / monster.speed
      command = monster.simulate()
      if command?.command in ['move', 'attack-move', 'attack']
        oldPos = vec2.copy [0,0], monster.pos
        updatePos monster, command.command, command.direction
        @level.actors.delete oldPos[0], oldPos[1]
        @level.actors.set monster.pos[0], monster.pos[1], monster
      if command?.command is 'pickup'
        handlePickup monster
      monster.lastTick = tick

    # computer what areas the player can see
    diff = new SparseMap(@level.width, @level.height)
    test = (x, y) => @level.terrain.get(x, y) in [2, 3]
    fov = new ROT.FOV.PreciseShadowcasting(test)
    [x, y] = @player.pos
    fov.compute x, y, 10, (x, y, _, visible) =>
      # for now, just send terrain data
      diff.set x, y, terrain: @level.terrain.get x, y

    return diff

  toJSON: ->
    return {
      player: @player.toJSON()
      level: @level.toJSON()
    }

class Level
  constructor: ->
    @name = null
    @width = 40
    @height = 14
    @actors = new SparseMap(@width, @height)
    @items = new SparseMap(@width, @height)
    @terrain = DenseMap.fromJSON
      width: @width
      height: @height
      map: [
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,3,3,3,3,3,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,3,3,0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,0,0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,1,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,1,1,1,1,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0]
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]

  pickRandomSpawnablePosition: ->
    loop
      x = Math.floor Math.random() * @width
      y = Math.floor Math.random() * @height
      return [x, y] if @terrain.get(x, y) is 2 and not @actors.get(x, y)

  toJSON: ->
    return {
      name: @name
      width: @width
      height: @height
      terrain: @terrain.toJSON()
    }

class Player
  constructor: (@name) ->
    @pos = [3, 3]
    @lastInput = null
    @isPlayer = true
    @ap = 5
    @hp = 50
    @gold = 0
    @inventory = []
  simulate: ->
    if @lastInput
      command = { command: @lastInput.command, direction: @lastInput.direction }
      @lastInput = null
    return command
  toViewJSON: ->
    return {
      name: @name
      pos: @pos
      inventory: (i.toViewJSON() for i in @inventory)
    }

class Monster
  constructor: ->
    @isPlayer = false
    @gold = 0
  simulate: ->
    directions = 'n w s e nw sw se ne'.split ' '
    dir = directions[Math.floor(Math.random() * directions.length)]
    return { command: 'move', direction: dir }
  toJSON: ->
    return {
      name: @name
      pos: @pos
      speed: @speed
    }
  toViewJSON: ->
    return {
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
    @pos = [0, 0]
  @createFromClass: (cls) ->
    spec = random.pick(v for k, v of ITEMS when v.class is cls)
    throw new Error("Unknown item class: #{ cls }") unless spec?
    item = new this()
    item.name = spec.name
    item.class = cls
    switch cls
      when 'weapon'
        item.ap = random.integer spec.apMax, spec.apMin
      when 'gold'
        item.value = random.integer 15, 1
    return item
  toViewJSON: ->
    return {
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
