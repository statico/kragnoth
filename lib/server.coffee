WebSocketServer = require('websocket').server

# A base class used to handle commands from the client. We send commands
# a JSON-ified object of the form ['command', {foo: bar, ...}].
class ServerSession

  constructor: (@id, @conn) ->

  # Send a command back to the client.
  send: (command, obj={}) ->
    @conn.send JSON.stringify [command, obj]
    return

  # Called when a command is received from the client.
  onCommand: (command, obj) ->

  # Called when the client disconnects.
  onRemoved: ->

  toString: ->
    return "<#{ @constructor.name } #{ @id }>"

# Class which handles the bookkeeping of connected clients and handling
# messages they send.
class ServerSessionManager

  @_NextClientID: 1

  # @param klass A class which extends ServerSession
  # @param protocol Name of the websocket protocol
  constructor: (@klass, @protocol) ->
    @clients = {}

  # Perform an action for each connected client.
  # @param cb A callback which takes on parameter, a client.
  everyone: (cb) ->
    for _, client of @clients
      cb client
    return

  # Attach to a Node HttpServer.
  attachTo: (httpServer) ->
    @ws = new WebSocketServer(
      httpServer: httpServer
      autoAcceptConnections: false
    )

    @ws.on 'request', (req) =>
      try
        conn = req.accept @protocol, req.origin
      catch e
        console.error "Couldn't accept protocol #{ @protocol }:", e
        conn.close()
        return

      client = @_addClient conn
      console.log "#{ client.toString() } connected."

      conn.on 'error', (err) =>
        console.error "#{ client.toString() } error: ", err
        return

      conn.on 'message', (message) =>
        try
          tuple = JSON.parse message.utf8Data
        catch e
          console.error "Client #{ client.id } sent invalid message: #{ message.utf8Data }"
          return
        [command, obj] = tuple
        client.onCommand command, obj
        return

      conn.on 'close', =>
        @_removeClient client.id
        console.log "#{ client.toString() } disconnected."
        return

    return

  _addClient: (conn) ->
    id = ServerSessionManager._NextClientID++
    client = new @klass(id, conn)
    @clients[id] = client
    return client

  _removeClient: (id) ->
    delete @clients[id]
    return

exports.ServerSessionManager = ServerSessionManager
exports.ServerSession = ServerSession
