{Vec2} = require 'justmath'
{Map} = require './map'

ASSERT = (cond) -> throw new Error('Assertion failed') if not cond

shuffle = (arr) ->
  i = arr.length
  while --i
    j = Math.floor(Math.random() * (i + 1))
    temp = arr[i]
    arr[i] = arr[j]
    arr[j] = temp
  return

# ---------------------------------------------------------------------------
# GAMEMASTER
# ---------------------------------------------------------------------------

class Command

  @Types:
    MOVE: 0

  constructor: (@agent, @type, @options) ->

class GameMaster

  constructor: ->
    @world = new ServerWorld(new Vec2(20, 10))
    for i in [0..10]
      @world.addNonPlayerAgent new DummyAgent()

  doRound: ->
    @_doBeforeRound()

    for agent in @world.getPlayerAgents()
      agent.doTurn this, this.world

    for agent in @world.getNonPlayerAgents()
      agent.doTurn this, this.world

    @_doAfterRound()

  _doBeforeRound: ->
    # agent ID -> number
    @_turnsTaken = {}

  _doAfterRound: ->

  attempt: (command) ->
    map = @world.map
    {agent, type, options} = command

    @_turnsTaken[agent.id] ?= 0
    if ++@_turnsTaken[agent.id] > 1
      console.warn "#{ agent.toString() } tried performing more than one turn"
      return

    switch type
      when Command.Types.MOVE
        {newLocation} = options
        oldLocation = agent.location

        # Check input.
        ASSERT oldLocation instanceof Vec2
        ASSERT newLocation instanceof Vec2

        # Check distance.
        distance = map.pathDistance(oldLocation, newLocation)
        if distance > 1
          console.warn "#{ agent.toString() } tried moving too far (distance = #{ distance })"
          return

        # Check other agents.
        for other in @world.getAgents()
          if agent != other and newLocation.equals(other.location)
            #console.warn "#{ agent.toString() } tried to move on top of #{ other.toString() }"
            return

        # Check that area is walkable.
        if not map.isWalkable newLocation
          #console.warn "#{ agent.toString() } tried to move to unwalkable position"
          return

        # OK to move!
        agent.location = newLocation.copy()

      else
        console.warn "#{ agent.toString() } tried invalid command: #{ type }"
        return

    return
    
  getFullState: ->
    return {
      agents: (agent.getState() for agent in @world.getAgents())
      map: @world.map.toArray()
    }

# ---------------------------------------------------------------------------
# WORLD
# ---------------------------------------------------------------------------

class ServerWorld

  constructor: (@size) ->
    @map = new Map(@size)
    @map.populateWithOneBigRoom()

    @_nextAgentId = 1

    @_playerAgents = {}
    @_nonPlayerAgents = {}

  addNonPlayerAgent: (agent) ->
    @_addAgent @_nonPlayerAgents, (agent)

  addPlayerAgent: (agent) ->
    @_addAgent @_playerAgents, (agent)

  _addAgent: (obj, agent) ->
    agent.id = @_nextAgentId++

    others = @getAgents()
    doesntOverlapOthers = (p) ->
      for other in others
        if p.equals other.location
          return false
      return true

    while agent.location == null
      p = @map.getRandomWalkableLocation()
      if doesntOverlapOthers(p)
        agent.location = p

    obj[agent.id] = agent
    return agent

  getAgents: ->
    return @getPlayerAgents().concat @getNonPlayerAgents()

  getPlayerAgents: ->
    return (agent for id, agent of @_playerAgents)

  getNonPlayerAgents: ->
    return (agent for id, agent of @_nonPlayerAgents)


class ClientWorld

  constructor: ->
    @agents = null
    @map = null

  loadFromState: (data) ->
    @agents = []
    for agent in data.agents
      @agents.push agent
    @map = Map.fromArray data.map

# ---------------------------------------------------------------------------
# AGENTS
# ---------------------------------------------------------------------------

class ServerAgent

  constructor: ->
    @id = null
    @location = null

  doTurn: (gm, world) ->

  getState: ->
    return {
      id: @id
      location: @location.getXY()
    }

  toString: ->
    return "[ServerAgent #{ @id }]"

class DummyAgent extends ServerAgent

  doTurn: (gm, world) ->
    neighbors = world.map.diagonalNeighbors @location
    shuffle neighbors
    for n in neighbors
      gm.attempt new Command(this, Command.Types.MOVE, newLocation: n)
      break
    return

class ClientAgent

  constructor: ->
    @location = new Vec2()

# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

exports.GameMaster = GameMaster
exports.ClientWorld = ClientWorld
