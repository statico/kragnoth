# Browser-side web client.

{ClientSession} = require './client.coffee'
{CanvasView} = require './viewport.coffee'

class AdminClientSession extends ClientSession

  protocol: 'admin-protocol'

  onOpen: ->
    @send 'auth'

  onCommand: (command, obj) ->
    switch command
      when 'connect-to-realm'
        @realmSession?.close()
        @realmSession = new RealmClientSession(obj.url)
        @realmSession.connect()
      when 'message'
        $('#messages').append $('<div>').text(obj.text)
      else
        console.error "Unknown admin command: #{ command }"
    return

class RealmClientSession extends ClientSession

  protocol: 'realm-protocol'

  onOpen: ->
    @view = new CanvasView()
    container = $('#gameview')
    canvas = @view.canvas
    canvas.width = container.width() * 2
    canvas.height = 800
    canvas.style.width = "#{ canvas.width / 2 }px"
    canvas.style.height = "#{ canvas.height / 2 }px"
    container.empty().append canvas

  onClose: ->
    $(@view.canvas).remove()

  onCommand: (command, obj) ->
    switch command
      when 'state'
        @view.world.loadFromState obj
        @view.draw()
      else
        console.error "Unknown realm command: #{ command }"
    return

$ ->
  new AdminClientSession('ws://localhost:8100').connect()
