{Vec2} = require 'justmath'
{Map} = require './map'

ASSERT = (cond) -> throw new Error('Assertion failed') if not cond

# ---------------------------------------------------------------------------
# UTILS
# ---------------------------------------------------------------------------

shuffle = (arr) ->
  return if not arr?.length
  i = arr.length
  while --i
    j = Math.floor(Math.random() * (i + 1))
    temp = arr[i]
    arr[i] = arr[j]
    arr[j] = temp
  return

roll = (numDice, numFaces) ->
  sum = 0
  for [1..numDice]
    sum = Math.floor(Math.random() * numFaces) + 1
  return sum

# ---------------------------------------------------------------------------
# GAMEMASTER
# ---------------------------------------------------------------------------

class Command

  @Types:
    MOVE: 'MOVE'
    MELEE: 'MELEE'

  constructor: (@agent, @type, @options) ->

class GameMaster

  constructor: ->
    @world = new ServerWorld(new Vec2(20, 10))
    @world.addNonPlayerAgent new Mosquito()
    for i in [0..10]
      @world.addNonPlayerAgent new Drone()

  doRound: ->
    @_doBeforeRound()

    for agent in @world.getPlayerAgents()
      if agent.isAlive()
        agent.doTurn this, this.world

    for agent in @world.getNonPlayerAgents()
      if agent.isAlive()
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
      agent.log "You tried performing more than one turn"
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
          agent.log "You tried moving too far (distance = #{ distance })"
          return

        # Check other agents.
        for other in @world.getAgents()
          if agent != other and newLocation.equals(other.location)
            agent.log "You can't move there, #{ other.toString() } is in the way"
            return

        # Check that area is walkable.
        if not map.isWalkable newLocation
          agent.log "You can't move there"
          return

        # OK to move!
        agent.location = newLocation.copy()

      when Command.Types.MELEE
        {targetLocation} = options

        # Check input
        ASSERT targetLocation instanceof Vec2

        # Check distance.
        distance = map.pathDistance(agent.location, targetLocation)
        if distance > 1
          agent.log "You can't attack that far away"
          return

        # Check who's there.
        for other in @world.getAgents()
          if other.location.equals targetLocation
            target = other
            break
        if not target
          agent.log "You attack thin air"
          return

        # Check if the target is alive.
        if not target.isAlive()
          agent.log "Beating up corpses gets you nowhere"
          return

        # Check whether the target defends.
        if target.calculatePhysicalDodge(agent)
          agent.log "You miss the #{ target.type }"
          target.log "The #{ target.type } misses"
          return

        # Do the damage.
        agent.log "You hit the #{ target.type }!"
        target.log "The #{ target.type } hits!"
        damage = agent.calculatePhysicalAttack()
        target.hp -= damage
        if target.hp <= 0
          target.hp = 0
          target.log "You die!"
          agent.log "You kill the #{ target.type }!"
        return

      else
        agent.log "You attempted an invalid command: #{ type }"
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

    @_allAgents = {}
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

    while not agent.location
      p = @map.getRandomWalkableLocation()
      if doesntOverlapOthers(p)
        agent.location = p

    @_allAgents[agent.id] = agent
    obj[agent.id] = agent
    return agent

  getAgent: (id) ->
    return @_allAgents[id]

  getAgents: ->
    return (agent for id, agent of @_allAgents)

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
    for state in data.agents
      @agents.push ClientAgent.fromState state
    @map = Map.fromArray data.map

# ---------------------------------------------------------------------------
# AGENTS
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Base
# ---------------------------------------------------------------------------

class Agent

  type: null

  constructor: ->
    @id = null
    @location = null

    @level = 1
    @hp = 1
    @ac = 10
    @melee = 2

  isAlive: ->
    return @hp > 0

  calculatePhysicalAttack: ->
    return roll(1, @melee)

  calculatePhysicalDodge: (attacker) ->
    if @ac < 0
      randomAC = Math.floor(Math.random() * (Math.abs(@ac))) * -1 - 1
      target = 10 + randomAC + attacker.level
    else
      target = 10 + @ac + attacker.level
    target = 1 if target < 0
    return roll(1, 20) > target

  doTurn: (gm, world) ->

  getState: ->
    return {
      type: @type
      id: @id
      location: @location.getXY()
      level: @level
      hp: @hp
      ac: @ac
      melee: @melee
    }

  log: (text) ->
    console.log "#{ @toString() } #{ text }"

  toString: ->
    return "[#{ @constructor.name } ##{ @id }]"

class ClientAgent extends Agent

  @fromState: (obj) ->
    agent = new ClientAgent()
    for key, value of obj
      agent[key] = value
    return agent

# ---------------------------------------------------------------------------
# Drone
# ---------------------------------------------------------------------------

class Drone extends Agent

  type: 'drone'

  doTurn: (gm, world) ->
    neighbors = world.map.diagonalNeighbors @location
    shuffle neighbors
    for n in neighbors
      gm.attempt new Command(this, Command.Types.MOVE, newLocation: n)
      break
    return

# ---------------------------------------------------------------------------
# Mosquito
# ---------------------------------------------------------------------------

class Mosquito extends Agent

  type: 'mosquito'

  constructor: ->
    @targetId = null
    super()

  doTurn: (gm, world) ->
    if @targetId
      target = world.getAgent @targetId
      @targetId = null if not target.isAlive()

    if not @targetId
      possibles = (agent for agent in world.getAgents() when agent.type == 'drone')
      return if not possibles.length
      shuffle possibles
      @targetId = possibles[0].id

    target = world.getAgent @targetId
    path = world.map.findPath @location, target.location
    if path.length > 1
      gm.attempt new Command(this, Command.Types.MOVE, newLocation: path[0])
    else
      gm.attempt new Command(this, Command.Types.MELEE, targetLocation: target.location)
    return

# ---------------------------------------------------------------------------
# EXPORTS
# ---------------------------------------------------------------------------

exports.GameMaster = GameMaster
exports.ClientWorld = ClientWorld
