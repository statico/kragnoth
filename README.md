# The Dungeons of Krag'noth

## Getting Started

1. Install Node.js
2. `$ npm install`
3. `$ npm install -g bower coffee-script nodemon`
4. `$ bower install`

## Terms

* _world_ - Everything in the simulation -- all levels and all players.
* _realm_ - A single level of the Kragnoth world.
* _client_ - A user connected to the world playing or observing the game.
* _agent_ - An actor in the game, either an NPC (non-player character) or human player
* _admin_ - Entity that handles user authentication and permissions for the entire world. Also directs clients to disconnect and connect to realms.
* _game master_ - Entity that handles user actions and turns in a realm.
* _admin channel_ - Socket channel between client and admin. 
* _game channel_ - Socket channel between client and realm. Transmits state of the realm.

## Description of tools

* `krag-admin` - Listens for admin channel connections and handles auth, etc.
* `krag-client` - A console client which connects to a realm server.
* `krag-dev` - Just some temporary stuff.
* `krag-realm` - Listens for game channel connections and simulates a single realm (level).
* `krag-web` - Web client which connects to the admin.

# Design Notes

The goal of the game would be to get to the bottom of the dungeon, get
something (say, some sort of amulet, if you will), and bring it back up
for gold and riches.

Most levels would be procedurally generated, like nethack, but not all:
Some can be designed, some can be special.  And the dungeon doesn't have
to be linear, it should have branches.

And it should change when people aren't on a certain level.

Relevant:

http://nethackwiki.com/wiki/Mazes_of_Menace

http://www.mapeditor.org/

Also, I want a crafting element, where things can be smelted down into
metal and combined to form random new things.

And a trading element:

http://tf2wiki.net/wiki/Crafting

There's going to be one dungeon per game world.

There's going to be a bigger "town" on the top level, like the open-air
level where everyone starts; no monsters there.

Also relevant:

http://lpc.opengameart.org/

And use the tiles in:

http://imgur.com/cHaIMjK


# Todos

* don't put a Todo section in the README, that's what github's
  issue-tracking is for!
* a new name for the dungeon game
* (more) lore
