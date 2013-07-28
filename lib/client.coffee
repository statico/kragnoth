class ClientSession

  protocol: 'undefined-protocol'

  constructor: (@url) ->

  # Send a command to the server.
  send: (command, obj={}) ->
    @ws.send JSON.stringify [command, obj]
    return

  # Called when a command is received from the server.
  onCommand: (command, obj) ->

  # Called when the socket connects.
  onOpen: ->

  # Called when the socket disconnects.
  onClose: ->

  # Connect to the URL.
  connect: ->
    @close()

    console.log "Connecting to #{ @url }..."
    @ws = new WebSocket(@url, @protocol)

    @ws.onerror = (err) =>
      console.error "#{ @toString() } socket error"

    @ws.onopen = =>
      @onOpen()

    @ws.onclose = =>
      console.log "#{ @toString() } closed. Reconnecting..."
      clearTimeout @_retryTimer
      @_retryTimer = setTimeout (=> @connect()), 1000

    @ws.onmessage = (message) =>
      try
        tuple = JSON.parse message.data
      catch e
        console.error "#{ @toString() } couldn't parse:", message.data
        return
      [command, obj] = tuple
      @onCommand command, obj
      return

  # Close the connection.
  close: ->
    @ws?.close()
    clearTimeout @_retryTimer

  toString: ->
    return "<#{ @constructor.name }>"

exports.ClientSession = ClientSession
