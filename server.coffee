#!/usr/bin/env coffee

browserify = require 'browserify-middleware'
bundleUp = require 'bundle-up'
express = require 'express'
http = require 'http'
humanize = require 'humanize-plus'
loremIpsum = require 'lorem-ipsum'
moment = require 'moment'
path = require 'path'
stylus = require 'stylus'

util = require './lib/util'

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

app.use '/lib', browserify('./lib')

app.configure ->
  app.use express.static path.join "#{ __dirname }/public"

app.locals
  moment: moment
  humanize: humanize
  loremIpsum: loremIpsum

# -------------------------------------------------------------------------
# HANDLERS
# -------------------------------------------------------------------------

app.get '/', (req, res) ->
  res.render 'index'

# -------------------------------------------------------------------------
# SERVER
# -------------------------------------------------------------------------

http.createServer(app).listen PORT, ->
  console.log "Server listening on http://localhost:#{ PORT }"
