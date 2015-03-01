# immediate TODO
1. dungeon generation
1. endgame
1. multiplayer
1. room-based FOV
1. renderer
1. content
  - full armor
  - food
  - wands
  - boulders
  - potions

# architecture
- server
  - all server-side objects have all state -- no data hiding, sanitizing user input is up to the game master
  - World - holds levels, players, all state
    - builds Levels with a LevelBuilder
  - Level - one active per world at one time
    - layers
      - terrain
      - items
      - actors (players & AI)
  - GameMaster - sees everything!
    - handles each turn in order: acts on players, AI, items, terrain
    - calculates what's visible to the players and sends those layers
  - Scheduler
    - waits for input, sends ticks to gamemaster
  - ServerPeer
    - for now, just sends entire world every tick
    - later on, calculates diffs
  - Player
    - for now, just a username
  - Party
    - keeps track of who's in the party
- client
  - ClientWorld - incomplete World state
  - ClientLevel - incomplete state that the party has seen
  - ClientPeer - handles input commands and sends them to the server
- AI
  - speed should be specified in "number of ticks per second" -- use tickPeriod

# server-side
- authentication
- websocket origin auth
- split game server?
- hand off main connection

# client-side
- reconnecting websockets

# ideas
- use Int8Array for DenseMap in places
- optimize diffing
- optimize vector garbage
