# run with
#
#  node-dev server.coffee
#

sys = require 'sys'


_ = require 'underscore'
$ = require 'jquery'


{Database} = require('./Database')






require('zappajs') ->

  assets = require 'connect-assets'

  database = new Database foo: 'bar'

  @use 'static'

  @renderContext = layout: no

  @use assets
    src: './public'
    build: true
    buildDir: 'public/bin'
    minifyBuilds: false
    helperContext: @renderContext

  @on
    read: ->
      @ack
        tn: database.tn
        values: _.reduce(
          @data,
          ((o, key) -> o[key] = database.read(key) or null; o),
          {}
        )

    reintegrateTransactions: ->
      {startTn, transactions} = @data

      transactions = database.reintegrateTransactions(
        startTn, transactions
      )

      @ack _.reduce transactions, ((obj, t) -> obj[t.tn] = t.valid; obj), {}

      _.each transactions, (t) =>
        @emit logCompleted: t
        @broadcast logCompleted: t

    applyTransaction: ->
      transaction = @data

      database.applyTransaction transaction

      @ack {valid: transaction.valid, tn: database.tn}
      data = logCompleted: transaction
      @emit data
      @broadcast data

  @include './client'

  @include './tests'

