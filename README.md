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

* `krag-client` - A console client which connects to a realm server.
* `krag-dev` - Just some temporary stuff.
* `krag-realm` - Listens for game channel connections and simulates a single realm (level).
* `krag-web` - Web client which connects to the admin.
* `krag-admin` - Listens for admin channel connections and handles auth, etc.
