# Browser-side web client.

{ClientSession} = require './client.coffee'

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
      else
        console.error "Unknown admin command: #{ command }"
    return

class RealmClientSession extends ClientSession

  protocol: 'realm-protocol'

  onCommand: (command, obj) ->
    console.log 'XXX', 'Got state'

$ ->
  new AdminClientSession('ws://localhost:8100').connect()
