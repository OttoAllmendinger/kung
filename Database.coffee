_ = require?('underscore') or window._

class Database
  constructor: (@data = {}) ->
    @tn = 0
    @transactions = {}

  read: (key) ->
    @data[key] if _.has(@data, key)

  write: (key, value) ->
    @data[key] = value

  getTransaction: (tn) ->
    @transactions[tn]

  # write transaction data and add transaction to transaction table
  addTransaction: (transaction) ->
    _.each(transaction.writes, (value, key) => @write key, value)
    @transactions[transaction.tn = @tn += 1] = transaction

  getTransactionRange: (startTn, endTn) ->
    if startTn <= endTn
      _.map _.range(startTn, endTn + 1), (tn) => @getTransaction tn
    else
      []

  validate: (transaction, base) ->
    transaction.valid = _.all base, (t) ->
      _.isEmpty _.intersection _.keys(t.writes), transaction.reads

  applyTransaction: (transaction) ->
    baseTransactions = @getTransactionRange transaction.startTn + 1, @tn

    if @validate transaction, baseTransactions
      @addTransaction transaction

    transaction

  reintegrateTransactions: (startTn, transactions) ->
    base = @getTransactionRange startTn + 1, @tn

    _.each transactions, (t) =>
      if @validate(t, base) then @addTransaction t

    transactions


exports?.Database = Database
window?.Database = Database
