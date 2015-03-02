angular = require 'angular'
random = require 'random-ext'
rltiles = require '../static/rltiles/rltiles-2d.json'

require 'mousetrap' # Sets window.Mousetrap

{DenseMap} = require './map.coffee'
{TILES} = require './terrain.coffee'

document.body.style.cssText = '''
  background: black;
  color: white;
  font-family: sans-serif;
'''

document.body.innerHTML += '''
<div style="color: grey">
  <strong>Keys:</strong>
  HJKL / YUBN / arrows to move-attack,
  comma to pickup items,
  &lt; and &gt; to go up and down stairs.
  Click an inventory item to wield it.
</div>
'''

canvas = document.createElement 'canvas'
canvas.height = 0
document.body.appendChild canvas
ctx = canvas.getContext '2d'
ctx.imageSmoothingEnabled = false
ctx.webkitImageSmoothingEnabled = false

drawTile = do ->
  namesToIndex = {}
  namesToIndex[key] = i for key, i in rltiles.tiles
  s = rltiles.tileSize
  w = rltiles.width
  tileset = new Image()
  tileset.src = '/rltiles/rltiles-2d.png'
  return (x, y, key) ->
    return unless key of namesToIndex
    i = namesToIndex[key]
    ty = Math.floor(i / w)
    tx = i - ty * w
    ctx.drawImage tileset, tx * s, ty * s, s, s, x * s, y * s, s, s
    return

angular.module('kragnoth', [])
  .service('UIService', ($rootScope) ->
    return new class UIService
      constructor: ->
        @socket = null
        @messages = []
        @tick = -1
        @player = null
        @levelName = null
        @status = 'Initializing...'
      addMessages: (messages) ->
        @messages.unshift messages
        @messages.splice 5
        $rootScope.$broadcast 'update'
      setTick: (@tick) ->
        $rootScope.$broadcast 'update'
      setPlayer: (@player) ->
        $rootScope.$broadcast 'update'
      setLevelName: (@levelName) ->
        $rootScope.$broadcast 'update'
      setStatus: (@status) ->
        $rootScope.$broadcast 'update'
      chooseItem: (item) ->
        @socket.send JSON.stringify type: 'input', command: 'choose-item', id: item?.id
  )
  .controller('UIController', ($rootScope, $scope, UIService) ->
    $rootScope.$on 'update', ->
      $scope.connected = UIService.socket?
      $scope.messages = UIService.messages
      $scope.tick = UIService.tick
      $scope.player = UIService.player
      $scope.levelName = UIService.levelName
      $scope.status = UIService.status
      $scope.choose = (item) -> UIService.chooseItem(item)
      $scope.$apply()
  )

el = document.createElement 'div'
el.innerHTML = '''
<div ng-controller='UIController' style="display: flex">
  <div style="flex:1; color: yellow">
    <h1 ng-show="status">{{ status }}</h1>
    <div ng-repeat="set in messages" ng-style="{'opacity': $first && 1.0 || 0.5 }">
      <div ng-repeat="m in set">{{ m }}</div>
    </div>
  </div>
  <div style="flex:1" ng-show="connected">
    <strong>{{ player.name }} - {{ levelName }}</strong><br/>
    Gold: {{ player.gold }}<br/>
    HP: {{ player.hp }}<br/>
    Weapon: {{ player.weapon.name || 'empty-handed' }}<br/>
    <hr/>
    {{ player.items.length }} items
    <div ng-repeat="item in player.items" ng-mousedown="choose(item)">
      · {{ item.name }}
    </div>
  </div>
  <div style="flex:1" ng-show="connected">Tick: {{ tick }}</div>
</div>
'''
document.body.appendChild el
angular.bootstrap el, ['kragnoth']
uiService = angular.element(el).injector().get 'UIService'

view = null
views = {}

resize = ->
  console.log 'XXX', canvas.width, document.body.clientWidth
  if document.body.clientWidth > canvas.width + 30
    delete canvas.style.width
    delete canvas.style.height
  else
    canvas.style.width = canvas.width / 2 + 'px'
    canvas.style.height = canvas.height / 2 + 'px'
resize()
angular.element(window).on 'resize', resize

playerId = "player-#{ random.restrictedString [random.CHAR_TYPE.LOWERCASE], 4, 4 }"
gameId = null
gameSocket = null
gameSend = (obj) ->
  if gameSocket?.readyState is 1
    gameSocket.send JSON.stringify obj
  else
    setTimeout (-> gameSend obj), 1000

cncSocket = new WebSocket("ws://#{ argv.host }:#{ argv.cncPort }", ['cnc'])
cncSend = (obj) -> cncSocket.send JSON.stringify obj
cncSocket.onopen = ->
  cncSend type: 'hello', playerId: playerId
cncSocket.onclose = ->
  uiService.addMessages ['ERROR: Connection closed']
  uiService.setStatus 'Game Over'
cncSocket.onmessage = (event) ->
  msg = JSON.parse event.data

  if msg.type is 'hello'
    uiService.setStatus 'Waiting for game...'

  if msg.type is 'connect'
    {gameId, url} = msg
    gameSocket = new WebSocket(url, ['game'])
    gameSend type: 'hello', playerId: playerId, gameId: gameId
    uiService.socket = gameSocket
    uiService.setStatus null
    gameSocket.onmessage = (event) ->
      msg = JSON.parse event.data

      if msg.type is 'gameover'
        uiService.addMessages [msg.reason]
        uiService.setStatus 'Game Over'

      if msg.type is 'level-init'
        {width, height, name, index} = msg
        if index of views
          view = views[index]
        else
          view = new DenseMap(width, height)
          view.fill -> {}
          views[index] = view
        canvas.width = width * rltiles.tileSize
        canvas.height = height * rltiles.tileSize
        resize()
        uiService.setLevelName name

      if msg.type is 'tick'
        {tick, diff, players, messages, levelName} = msg
        uiService.setTick tick
        uiService.addMessages(messages) if messages.length
        for pid, obj of players
          uiService.setPlayer obj if pid is playerId

        for y, row of diff.map
          for x, obj of row
            state = view.get [x, y]
            state.tick = tick
            state.terrain = obj.terrain

        ctx.clearRect 0, 0, canvas.width, canvas.height
        for y, row of view.map
          for x, obj of row
            ctx.globalAlpha = if obj.tick is tick then 1.0 else 0.6
            drawTile x, y, switch obj.terrain
              when TILES.DOOR then 'corridor'
            drawTile x, y, switch obj.terrain
              when TILES.VOID then 'dark_part_of_a_room'
              when TILES.WALL then 'dngn_rock_wall_07'
              when TILES.FLOOR then 'floor_of_a_room'
              when TILES.CORRIDOR then 'corridor'
              when TILES.DOOR then 'open_door_v'
              when TILES.STAIRCASE_UP then 'staircase_up'
              when TILES.STAIRCASE_DOWN then 'staircase_down'

        ctx.globalAlpha = 1.0

        for item in msg.items
          [x, y] = item.pos
          drawTile x, y, switch item.class
            when 'gold' then 'gold_piece'
            when 'weapon' then 'short_sword2'
            when 'potion' then 'purple_red'

        for pid, obj of msg.players
          [x, y] = obj.pos
          drawTile x, y, 'duane'

        for monster in msg.monsters
          [x, y] = monster.pos
          drawTile x, y, switch monster.name
            when 'mosquito' then 'giant_mosquito'
            when 'slug' then 'blue_jelly'

  return

sendInput = (dir) -> gameSend type: 'input', command: 'attack-move', direction: dir
keys = {
  h: 'w', j: 's', k: 'n', l: 'e',
  y: 'nw', u: 'ne', b: 'sw', n: 'se',
  left: 'w', down: 's', up: 'n', right: 'e',
  '>': 'down', '<': 'up'
}
for key, dir of keys
  do (key, dir) ->
    Mousetrap.bind key, -> sendInput dir
Mousetrap.bind ',', -> gameSend type: 'input', command: 'pickup'
