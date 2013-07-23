{Vec2} = require 'justmath'

class ServerAgent

  constructor: ->
    @location = new Vec2()

  simulate: (world) ->

  getState: ->
    return {
      location: @location.getXY()
    }

class Dummy extends ServerAgent

  simulate: (world) ->
    @location.x = Math.floor(Math.random() * world.size.x)
    @location.y = Math.floor(Math.random() * world.size.y)

class ClientAgent

  constructor: ->
    @location = new Vec2()

exports.Dummy = Dummy
exports.ClientAgent = ClientAgent

