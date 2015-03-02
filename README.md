# Krag'noth: Valley of the Beast
(or some equally as stupid name for an RPG)

VERY WORK IN PROGRESS / PROOF OF CONCEPT

DO NOT SHARE

## Getting started with local development
- `npm install`
- `npm install -g nodemon nodeunit`
- `npm test`
- `nodemon -e coffee app.coffee --numPlayers 1`
- Go to http://127.0.0.1:8080/
- Use HJKL/NBYU keys to navigate (for now)

## Running on a server
Make sure the app knows how to connect to itself:
- `./app.coffee --host myhost.example.com`
