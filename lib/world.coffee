{Vec2} = require 'justmath'
{Map} = require './map'

class ServerWorld

  constructor: (@size) ->
    @_tick = 0

    @_ground = new Map(@size)
    @_ground.foreach (p) =>
      {x, y} = p
      if x == 0 or x == @size.x - 1 or y == 0 or y == @size.y - 1
        value = 1
      else
        value = 0
      @_ground.set new Vec2(x, 0), value

    @_agents = []

  getTick: ->
    return @_tick

  simulate: ->
    @tick++

    agents = []
    for agent in @_agents
      agent.simulate(this)
      agents.push agent.getState()

    return {
      tick: @_tick
      agents: agents
    }

  addAgent: (agent) ->
    @_agents.push agent

class ClientWorld

  constructor: ->
    @_tick = null
    @_agents = null

  loadFromState: (data) ->
    @_tick = data.tick
    @_agents = []
    for agent in data.agents
      @_agents.push agent

  getAgents: ->
    return @_agents

exports.ServerWorld = ServerWorld
exports.ClientWorld = ClientWorld
