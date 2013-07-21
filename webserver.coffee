#!/usr/bin/env coffee

browserifyExpress = require 'browserify-express'
bundleUp = require 'bundle-up'
dnode = require 'dnode'
express = require 'express'
http = require 'http'
humanize = require 'humanize-plus'
loremIpsum = require 'lorem-ipsum'
moment = require 'moment'
path = require 'path'
shoe = require 'shoe'
stylus = require 'stylus'

util = require './lib/util'
rpc = require './lib/rpc'

PORT = parseInt(util.requireEnv('PORT', 8000), 10)

# -------------------------------------------------------------------------
# INIT
# -------------------------------------------------------------------------

app = express()

app.configure ->
  app.set 'port', PORT
  app.set 'views', "#{ __dirname }/views"
  app.set 'view engine', 'jade'
  app.use express.bodyParser()
  app.use express.methodOverride()
  app.use express.cookieParser util.requireEnv 'COOKIE_SECRET'
  app.use express.cookieSession secret: util.requireEnv 'SESSION_SECRET'
  app.use app.router
  app.use express.favicon "#{ __dirname }/public/favicon.png"
  app.use stylus.middleware(__dirname + '/public')

app.configure 'development', ->
  app.locals.pretty = true
  app.use express.logger 'dev'
  app.use express.errorHandler(dumpExceptions: true, showStack: true)

app.configure 'production', ->
  app.use express.logger 'warn'
  app.use express.errorHandler()

DEBUG = app.get('env') == 'development'

bundleUp app, "#{ __dirname }/lib/assets", {
  staticRoot: "#{ __dirname }/public"
  staticUrlRoot: '/'
  bundle: not DEBUG
  minifyCss: not DEBUG
  minifyJs: not DEBUG
}

app.use browserifyExpress
  entry: "#{ __dirname }/lib/index.coffee"
  watch: "#{ __dirname }/lib"
  mount: "/lib.js"
  verbose: DEBUG
  minify: not DEBUG
  bundle_opts: { debug: DEBUG }

app.configure ->
  app.use express.static path.join "#{ __dirname }/public"

app.locals
  moment: moment
  humanize: humanize
  loremIpsum: loremIpsum

# -------------------------------------------------------------------------
# HANDLERS
# -------------------------------------------------------------------------

app.get '/', (req, res) -> res.render 'index'

for i in require('./lib/index').APPS
  do (i) ->
    app.get "/#{ i }", (req, res) ->
      res.render 'index', entryPoint: i

# -------------------------------------------------------------------------
# SERVER
# -------------------------------------------------------------------------

rpcHandler = shoe (stream) ->
  d = dnode(rpc)
  d.pipe(stream).pipe(d)

server = http.createServer(app)
server.listen PORT, -> console.log "Server listening on http://localhost:#{ PORT }"
rpcHandler.install server, '/dnode'
