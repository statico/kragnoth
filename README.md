# krag'noth

![](http://i.imgur.com/MM4y7U2.gif)

VERY WORK IN PROGRESS / PROOF OF CONCEPT

## Getting started
- `npm install`
- `npm install -g nodemon nodeunit`
- `npm test`
- `nodemon -e coffee app.coffee --numPlayers 1`
- Go to http://127.0.0.1:8080/
- Use HJKL/NBYU keys to navigate (for now)

## Running on a server
Make sure the app knows how to connect to itself:
- `./app.coffee --host myhost.example.com`
