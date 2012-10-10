@include = ->
  @client '/client.js': ->

    @connect()

    socket_emit = @emit
    socket_on = @on



    localData = new Backbone.Model

    isolatedTransactions = new Backbone.Collection


    class RemoteDatabase
      constructor: (@model, @isolatedTransactions) ->
        @online = true

      disconnect: ->
        @online = false
        @isolatedTransactions.reset()

      reconnect: (callback) ->
        @online = true

        socket_emit(
          'reintegrateTransactions',
          startTn: @lastValidTn
          transactions: @isolatedTransactions.map((t) => t.toJSON()),
          -> callback @data
        )

      read: (keys, callback) ->
        socket_emit 'read', keys, (response) =>
          @model.set response.values
          callback response

      applyTransaction: (transaction, callback) ->
        if @online
          socket_emit 'applyTransaction', transaction.toJSON(), callback
        else
          @isolatedTransactions.add transaction
          callback()

    remoteDatabase = new RemoteDatabase localData, isolatedTransactions


    Column = Backbone.Model

    TableRow = Backbone.Model.extend
      initialize: (options) ->
        @set('columns',
          new Backbone.Collection(
            _.map _.range(0, options.columns), => new Column()
          )
        )

      isEmpty: ->
        @get('columns').all (c) -> _.isEmpty c.get 'value'

    Table = Backbone.Collection.extend
      model: TableRow

    ColumnView = Backbone.View.extend
      tagName: 'td'

      events:
        'input input': 'updateColumn'

      updateColumn: ->
        @model.set 'value', @input.val()

      render: ->
        @$el.append @input = $('<input>')
        @input.focus => @trigger 'focus'
        @input.blur => @trigger 'blur'
        return @

    TableRowView = Backbone.View.extend
      tagName: 'tr'

      getColumnView: (model, i) ->
        new ColumnView model: model

      render: ->
        @model.get('columns').each (column, i) =>
          view = @getColumnView column, i
          view.on 'focus', => @trigger 'focus'
          view.on 'blur', => @trigger 'blur'
          @$el.append view.render().$el
        return @

    TableView = Backbone.View.extend
      getTableRowView: (model) ->
        new TableRowView model: model

      createNewRow: ->
        @collection.add model = new TableRow columns: @options.columns
        @rowViews.push @lastRow = view = @getTableRowView model
        @$el.append view.render().$el

        view.on 'focus', =>
          view.off 'focus'
          @createNewRow()

        view.on 'blur', =>
          if view.model.isEmpty() and (view isnt @lastRow)
            @collection.remove view.model
            view.remove()

      render: ->
        @$el.empty()
        @rowViews = []
        @createNewRow()
        return @

    Reads = Backbone.Collection.extend
      toJSON: ->
        _.compact @map (row) -> row.get('columns').first().get 'value'

    Writes = Backbone.Collection.extend
      toJSON: ->
        @reduce (
          (obj, row) ->
            key = row.get('columns').at(0).get 'value'
            value = row.get('columns').at(1).get 'value'
            if key and value then obj[key] = value
            obj
          ), {}

    Transaction = Backbone.Model.extend
      initialize: (options) ->
        @reads = options?.reads or new Reads
        @writes = options?.writes or new Writes

      isEmpty: ->
        (@reads.all (r) => r.isEmpty()) and (@writes.all (r) => r.isEmpty())

      toJSON: ->
        _.extend(
          Backbone.Model.prototype.toJSON.apply(@),
          reads: @reads.toJSON()
          writes: @writes.toJSON(),
        )

    ReadTableView = TableView.extend
      refresh: ->
        _.each @rowViews, (rv) -> rv.readValueView.render()

      getTableRowView: (model) ->
        dataCell = model.get('columns').first()

        LocalTableRowView = TableRowView.extend
          getReadValueView: ->
            ReadValueView = Backbone.View.extend
              tagName: "td"

              className: 'value'

              render: ->
                key = dataCell.get 'value'
                data = localData.get key
                @$el.text if key? then (data or 'undefined') else ''
                @$el.toggleClass 'no-data', key? and (not data)
                @

            new ReadValueView

          render: ->
            TableRowView.prototype.render.apply @
            @$el.append (@readValueView = @getReadValueView()).render().$el
            @

        new LocalTableRowView model: model

    TransactionCreateView = Backbone.View.extend
      CREATE: "create"
      REFRESH: "refresh"

      initialize: ->
        @createRefreshButton = @$("#create-refresh")
        @buttonState = @CREATE

        (@editorPanel = @$(".editor")).hide()

        localData.on 'change', => @readTable.refresh()

      updateSubmitButton: ->
        @$('#submit').prop 'disabled', @model.isEmpty()

      events:
        'input *':                      'updateSubmitButton'
        'click button#create-refresh':  'createOrRefresh'
        'click button#submit':          'submitTransaction'

      createOrRefresh: ->
        if @buttonState is @CREATE
          @createRefreshButton.text @buttonState = @REFRESH
          @create()
        else if @buttonState is @REFRESH
          @refreshReads()
        else
          throw "invalid button state"

      create: ->
        window.transaction = @model = new Transaction
        @model.reads.on 'all', => @updateSubmitButton()
        @model.writes.on 'all', => @updateSubmitButton()
        @model.on 'change:startTn', => @renderStartTn()
        @editorPanel.slideDown()
        @render()
        @refreshReads()

      refreshReads: ->
        remoteDatabase.read @model.reads.toJSON(), (response) =>
          @model.set 'startTn', response.tn

      submitTransaction: ->
        remoteDatabase.applyTransaction @model, (response) =>
          @createRefreshButton.text @buttonState = @CREATE
          @editorPanel.slideUp()

      renderStartTn: ->
        @$(".start-tn").text @model.get 'startTn'

      render: ->
        @updateSubmitButton()

        @readTable = new ReadTableView
          columns: 1
          el: @$ '.transaction.reads'
          collection: @model.reads

        @readTable.render()

        @writeTable = new TableView
          el: @$ '.transaction.writes'
          collection: @model.writes
          columns: 2

        @writeTable.render()

        return @

    TransactionLogView = Backbone.View.extend
      initialize: ->
        @collection.on 'add', @addLogEntry, @
        @collection.on 'reset', @resetTable, @

      resetTable: ->
        @$entries.empty()

      addLogEntry: (entry) ->
        prettyString = (data) ->
          if _.isEmpty(data) then 'none' else JSON.stringify(data)

        row = [
          entry.get('startTn'),
          entry.get('tn'),
          prettyString(entry.reads),
          prettyString(entry.writes),
          valid = entry.get('valid')
        ]

        @$entries.append(
          $("<tr>").append(
            (_.map row, (text) => $("<td>").text text)...
          ).addClass(if valid then "valid" else "invalid")
        )

      render: ->
        th = (text) -> $("<th>").text text

        @$el.append(
          $("<tr>").append(
            th('StartTn'), th('Tn'), th('Reads'), th('Writes'), th('Valid')
          )
        )

        @$el.append(@$entries = $("<tbody>", class: 'entries'))

        @


    SettingsView = Backbone.View.extend
      events:
        'click #online': 'toggleOnline'

      initialize: ->

      toggleOnline: (event) ->
        @model.set 'online', @$('input#online').attr('checked')?



    window.settingsView = new SettingsView(
      el: '#settings'
      model: window.settings = new Backbone.Model
    )

    settings.on 'change:online', =>
      if (settings.get 'online') and (not remoteDatabase.online)
        remoteDatabase.reconnect (log) -> console.log log

      if (not settings.get 'online') and remoteDatabase.online
        remoteDatabase.disconnect()



    window.completedLogView = new TransactionLogView(
      el: '#completed-transactions table'
      collection: completedLog = new Backbone.Collection
    )

    socket_on logCompleted: -> completedLog.add new Transaction @data

    window.completedLogView.render()



    window.isolatedLogView = new TransactionLogView(
      el: '#isolated-transactions table'
      collection: isolatedTransactions
    )

    window.isolatedLogView.render()



    window.transactionCreateView = new TransactionCreateView
      model: window.transaction = new Transaction
      el: '#create-transaction'

    transactionCreateView.render()


  @get '/': ->
    @render index: {layout: no}

  @view index: ->
    doctype 5
    html ->
      head ->
        title "Kung Library » Transaction Console"
        script src: '/socket.io/socket.io.js'
        script src: '/js/libs/jquery.js'
        script src: '/js/libs/underscore.js'
        script src: '/js/libs/backbone.js'
        script src: '/zappa/zappa.js'
        link rel: 'stylesheet', href: '/css/style.css'

      body ->
        div id: 'left', ->
          div id: 'settings', ->
            h2 'Settings'
            input type: 'checkbox', id: 'online', checked: 'checked'
            label for: 'online', 'online'

          div id: 'create-transaction', ->
            h2 'Create Transaction'

            button id: 'create-refresh', 'create'

            div class: 'editor', ->
              p ->
                span 'Transaction startTn: '
                span class: 'start-tn'

              h3 'Reads'
              table class: 'transaction reads'

              h3 'Writes'
              table class: 'transaction writes'

              button id: 'submit', 'submit'

        div id: 'right', ->
          h2 "Transaction Monitor"

          div id: 'isolated-transactions', ->
            h3 "Isolated Transactions"
            table class: 'transaction-log'


          div id: 'completed-transactions', ->
            h3 "Completed Transactions"
            table class: 'transaction-log'

        script src: '/client.js'

