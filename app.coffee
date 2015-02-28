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
        monsters.push monster.toViewJSON() if diff.get monster.pos
      items = []
      for _, item of @world.items
        if diff.get item.pos
          items.push item.toViewJSON()
      @send
        type: 'tick'
        tick: @tick
        levelName: @world.level.name
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

    @level = new Level('level-1')

    @player = new Player(playerName)
    @player.pos = @level.pickPositionOfType 8
    @level.actors.set @player.pos, @player

    @monsters = [new Mosquito(), new Slug(), new Slug(), new Slug(), new Slug()]
    for monster in @monsters
      monster.id = @getGUID()
      monster.lastTick = random.integer 10
      monster.pos = @level.pickRandomSpawnablePosition()
      @level.actors.set monster.pos, monster

    @items = {}
    for cls in ['gold', 'weapon']
      for i in [0..3]
        item = Item.createFromClass cls
        item.id = @getGUID()
        vec2.copy item.pos, @level.pickRandomSpawnablePosition()
        pile = @level.items.get(item.pos) ? []
        pile.push item
        @level.items.set item.pos, pile
        @items[item.id] = item

    @messages = null

  getGUID: ->
    return @_nextGUID++

  kill: (actor) ->
    @level.actors.delete actor.pos
    index = @monsters.indexOf actor
    @monsters.splice index, 1 if index != -1

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
      items = @level.items.get next

      moved = false
      if actor != neighbor
        if command in ['move', 'attack-move']
          if tile in [2, 3, 8, 9] and not neighbor
            moved = true
            vec2.copy actor.pos, next
          if actor.isPlayer and items?.length
            @messages.push "There are items here: #{ (i.name for i in items).join ', ' }"
          if actor.isPlayer and neighbor and command != 'attack-move'
            @messages.push "#{ neighbor.name } is in the way"
        if command in ['attack-move', 'attack']
          if neighbor
            solveAttack actor, neighbor
      if moved
        for item in actor.items
          vec2.copy item.pos, actor.pos
        if tile is 8
          @messages.push "There is a staircase up here."
        if tile is 9
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
      pile = @level.items.get actor.pos
      if pile?.length
        @level.items.delete actor.pos
        loop
          item = pile.shift()
          switch item.class
            when 'gold'
              actor.gold += item.value
              delete @items[item.id]
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

    command = @player.simulate()
    switch command?.command
      when 'move', 'attack-move', 'attack'
        oldPos = vec2.copy [0,0], @player.pos
        updatePos @player, command.command, command.direction
        @level.actors.delete oldPos
        @level.actors.set @player.pos, @player
      when 'pickup'
        handlePickup @player
      when 'choose-item'
        item = @items[command.id]
        if item?
          if item.class = 'weapon'
            @player.weapon = item
          else
            @messages.push "Can't use #{ item.name } as a weapon"

    for monster in @monsters
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
    test = (x, y) => @level.terrain.get([x, y]) in [2, 3, 8, 9]
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
  constructor: (@name) ->
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
        [0,1,2,2,8,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,0,0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,1,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,3,0,0,0,0,0,0,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,1,1,2,2,2,2,2,1,0,0,0,0,0,1,1,1,1,1,1,1,3,1,1,1,1,1,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,3,3,3,3,3,3,3,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,9,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,1,2,2,2,2,2,2,2,2,2,2,2,2,1,0,0,0]
        [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0]
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]
      ]

  pickPositionOfType: (type) ->
    pos = [0, 0]
    for x in [0...@width]
      for y in [0...@height]
        vec2.set pos, x, y
        return pos if @terrain.get(pos) is type
    return null

  pickRandomSpawnablePosition: ->
    pos = [0, 0]
    loop
      vec2.set pos, random.integer(@width), random.integer(@height)
      return pos if @terrain.get(pos) is 2 and not @actors.get(pos)

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
