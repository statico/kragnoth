ngular = require 'angular'
keymaster = require 'keymaster'

{DenseMap} = require './map.coffee'

SIZE = 20
canvas = document.createElement 'canvas'
document.body.appendChild canvas
ctx = canvas.getContext '2d'
ctx.imageSmoothingEnabled = false
ctx.webkitImageSmoothingEnabled = false

angular.module('kragnoth', [])
  .service('UIService', ($rootScope) ->
    return new class UIService
      constructor: ->
        @socket = null
        @messages = []
        @tick = -1
        @player = null
      addMessages: (messages) ->
        @messages.unshift messages
        @messages.splice 5
        $rootScope.$broadcast 'update'
      updateTick: (@tick) ->
        $rootScope.$broadcast 'update'
      updatePlayer: (@player) ->
        $rootScope.$broadcast 'update'
      chooseItem: (item) ->
        @socket.send JSON.stringify type: 'input', command: 'choose-item', id: item?.id
  )
  .controller('UIController', ($rootScope, $scope, UIService) ->
    $rootScope.$on 'update', ->
      $scope.messages = UIService.messages
      $scope.tick = UIService.tick
      $scope.player = UIService.player
      $scope.choose = (item) -> UIService.chooseItem(item)
      $scope.$apply()
  )

el = document.createElement 'div'
el.innerHTML = '''
<div ng-controller='UIController' style="display: flex">
  <div style="flex:1">
    <div ng-repeat="set in messages"
        ng-style="{'color': 'yellow', 'opacity': $first && 1.0 || 0.5 }">
      <div ng-repeat="m in set">{{ m }}</div>
    </div>
  </div>
  <div style="flex:1">
    <strong>{{ player.name }}</strong><br/>
    Gold: {{ player.gold }}<br/>
    HP: {{ player.hp }}<br/>
    Weapon: {{ player.weapon.name || 'empty-handed' }}<br/>
    <hr/>
    {{ player.items.length }} items
    <div ng-repeat="item in player.items" ng-mousedown="choose(item)">
      · {{ item.name }}
    </div>
  </div>
  <div style="flex:1">Tick: {{ tick }}</div>
</div>
'''
document.body.appendChild el
angular.bootstrap el, ['kragnoth']
uiService = angular.element(el).injector().get 'UIService'

gameSocket = view = null

cncSocket = new WebSocket('ws://127.0.0.1:8081', ['cnc'])
cncSocket.onopen = ->
  cncSocket.send JSON.stringify type: 'hello'
cncSocket.onmessage = (event) ->
  msg = JSON.parse event.data
  if msg.type is 'connect'
    gameSocket = new WebSocket(msg.url, ['game'])
    uiService.socket = gameSocket
    gameSocket.onmessage = (event) ->
      msg = JSON.parse event.data

      if msg.type is 'init'
        {width, height} = msg
        view = new DenseMap(width, height)
        view.fill -> {}
        canvas.width = width * SIZE
        canvas.height = height * SIZE

      if msg.type is 'tick'
        {tick, diff, player, messages} = msg
        uiService.updateTick tick
        uiService.updatePlayer player
        uiService.addMessages(messages) if messages.length

        for y, row of diff.map
          for x, obj of row
            state = view.get [x, y]
            state.tick = tick
            state.terrain = obj.terrain

        ctx.clearRect 0, 0, canvas.width, canvas.height
        for y, row of view.map
          for x, obj of row
            ctx.globalAlpha = if obj.tick is tick then 1.0 else 0.4
            style = switch obj.terrain
              when 0 then '#333'
              when 1 then '#999'
              when 2 then '#ccc'
              when 3 then '#806424'
            if style
              ctx.fillStyle = style
              ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

        ctx.globalAlpha = 1.0

        for item in msg.items
          [x, y] = item.pos
          style = switch item.class
            when 'gold' then 'gold'
            when 'weapon' then 'orange'
          ctx.fillStyle = style
          ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

        [x, y] = msg.player.pos
        ctx.fillStyle = 'pink'
        ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

        for monster in msg.monsters
          [x, y] = monster.pos
          style = switch monster.name
            when 'mosquito' then '#45A9C4'
            when 'slug' then '#00c'
          ctx.fillStyle = style
          ctx.fillRect x * SIZE, y * SIZE, SIZE, SIZE

  return

sendInput = (dir) ->
  gameSocket?.send JSON.stringify type: 'input', command: 'attack-move', direction: dir
keys = {
  h: 'w', j: 's', k: 'n', l: 'e',
  y: 'nw', u: 'ne', b: 'sw', n: 'se',
  left: 'w', down: 's', up: 'n', right: 'e',
}
for key, dir of keys
  do (key, dir) ->
    keymaster key, -> sendInput dir
keymaster '.', -> gameSocket?.send JSON.stringify type: 'input', command: 'pickup'
