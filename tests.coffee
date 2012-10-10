@include = ->
  @client '/tests.js': ->

    $("#tests").append(
      $testApplication = $("<div>", class: "test tr-application"),
      $testReintegration = $("<div>", class: "test tr-reintegration")
    )

    TestSuiteItem = Backbone.Model

    EqualityTest = TestSuiteItem.extend
      initialize: (options) ->
        @on 'change:actual change:expect', @updateStatus, @

      updateStatus: ->
        @set 'status', _.isEqual @get('expect'), @get('actual')

      getExpect: ->
        JSON.stringify @get 'expect'

      getActual: ->
        JSON.stringify @get 'actual'

    TestSuite = Backbone.Model.extend
      initialize: (options) ->
        @tests = new Backbone.Collection
        @tests.on "change", @updateSuiteStatus, @

      updateSuiteStatus: ->
        @set 'status', @tests.reduce(
          (memo, item) -> (
            switch item.get('status')
              when true then memo
              when false then false
              when undefined then undefined
          ),
          true
        )

    renderStatus = ($row, $cell, status) ->
      $row.toggleClass 'pass', status is true
      $row.toggleClass 'fail', status is false
      $cell.text(
        if status is true
          "pass"
        else if status is false
          "fail"
        else
          "running.."
      )

    TestItemView = Backbone.View.extend
      tagName: "tr"

      initialize: ->
        @model.on 'change', @renderStatus, @

      renderStatus: ->
        @$expected.text @model.getExpect()
        @$actual.text @model.getActual()
        renderStatus @$el, @$status, @model.get 'status'

      render: ->
        @$el.append(
          $("<td>", class: 'message').text(@model.get 'message'),
          @$expected = $("<td>", class: 'expect'),
          @$actual = $("<td>", class: 'actual'),
          @$status = $("<td>", class: 'status')
        )

        @renderStatus()

        @

    TestSuiteView = Backbone.View.extend
      className: "test-suite"

      initialize: ->
        @model.tests.on "add", @addTestItem, @
        @model.on "change:status", @renderStatus, @

      addTestItem: (testItem) ->
        @$items.append new TestItemView(model: testItem).render().$el

      getSummary: ->
        @$summaryRow = $("<tr>").append(
          $("<td>", {class: 'message', colspan: 3}).text("Summary"),
          @$summaryStatus = $("<td>", class: 'status')
        )

      getHeader: ->
        @$headerRow = $("<tr>").append(
          $("<th>").text("Test Name")
          $("<th>").text("Expected Value")
          $("<th>").text("Actual Value")
          $("<th>").text("Status")
        )

      renderStatus: ->
        if @$summaryRow and @$summaryStatus
          renderStatus @$summaryRow, @$summaryStatus, @model.get 'status'

      render: ->
        @$el.append $("<table>", class: 'suite').append(
          $("<tbody>", class: 'header').append(@getHeader()),
          @$items = $("<tbody>", class: 'items'),
          $("<tbody>", class: 'summary').append(@getSummary())
        )

        @renderStatus()

        @



    transactionApplicationTest =
      transactionSequence: [
        {
          startTn: 0, reads: ['a'], writes: {b: 1, c: 2},
          expectTn: 1, expectData: {b: 1, c: 2}
        }, {
          startTn: 0, reads: [], writes: {b: 2},
          expectTn: 2, expectData: {b: 2, c: 2}
        }, {
          startTn: 0, reads: ['a', 'b'], writes: {b: 3},
          expectTn: 2, expectData: {b: 2, c: 2}, expectFailure: true
        }, {
          startTn: 2, reads: ['a', 'b'], writes: {b: 3, a: 1},
          expectTn: 3, expectData: {a: 1, b: 3, c: 2}
        }
      ]

    transactionReintegrationTest =
      startTn: 4

      remoteTransactions: [
        {tn: 4, writes: {a: 1, b: 1}},
        {tn: 5, writes: {a: 2}},
        {tn: 6, writes: {b: 5}}
      ]

      isolatedTransactions: [
        {reads: ['a'],      writes: {b: 1}, expectFailure: true},
        {reads: [],         writes: {c: 2}},
        {reads: ['a', 'b'], writes: {b: 3}, expectFailure: true},
        {reads: ['c'],      writes: {b: 4}}
      ]

      expectData: {a: 2, b: 4, c: 2}


    getDatabaseConnection = ->
      _database: database = new Database

      reintegrateTransactions: (startTn, transactions) ->
        database.reintegrateTransactions(
          startTn, transactions
        )

      applyTransaction: (transaction, callback) ->
        database.applyTransaction transaction
        callback valid: transaction.valid, tn: database.tn

      readAll: (callback) ->
        callback database.data

    runApplicationTest = ->
      connection = getDatabaseConnection()

      testSuiteView = new TestSuiteView
        el: '#application-suite'
        model: testSuite = new TestSuite

      testSuiteView.render()

      _.each transactionApplicationTest.transactionSequence, (tr, i) ->
        testSuite.tests.add(validityStatus = new EqualityTest
          message: "Transaction #{i} - transaction validity match"
          expect: not tr.expectFailure
        )

        testSuite.tests.add(dataEqualityStatus = new EqualityTest
          message: "Transaction #{i} - data equality"
          expect: tr.expectData
        )

        connection.applyTransaction tr, ({valid, tn}) ->
          connection.readAll (data) ->
            validityStatus.set actual: valid
            dataEqualityStatus.set actual: data



    runReintegrationTest = ->
      connection = getDatabaseConnection()

      testSuiteView = new TestSuiteView
        el: '#reintegration-suite'
        model: testSuite = new TestSuite

      testSuiteView.render()

      _.each transactionReintegrationTest.remoteTransactions, (tr) ->
        connection._database.transactions[tr.tn] = tr
        _.extend connection._database.data, tr.writes

      testSuite.tests.add(dataEquality = new EqualityTest
        message: "Data equality after reintegration"
        expect: transactionReintegrationTest.expectData
      )

      connection.reintegrateTransactions(
        transactionReintegrationTest.startTn
        transactionReintegrationTest.isolatedTransactions
      )

      connection.readAll (data) ->
        dataEquality.set 'actual', data

    runApplicationTest()

    runReintegrationTest()

  renderContext = @renderContext

  @get '/tests': ->
    @render tests: renderContext

  @view tests: ->
    doctype 5
    html ->
      head ->
        title "Kung Library » Tests"
        script src: '/js/libs/jquery.js'
        script src: '/js/libs/underscore.js'
        script src: '/js/libs/backbone.js'
        script src: '/zappa/zappa.js'
        text @js 'Database.js'
        link rel: 'stylesheet', href: '/css/style.css'
      body ->

        form style: "display: none", ->
          p ->
            input type: "radio", id: "rb-local"
            label for: 'rb-local', 'Local'
          p ->
            input type: "radio", id: "rb-remote"
            label for: 'rb-remote', 'Remote'

        div id: "tests", ->
          h2 "Test Suite"
          div id: "application-suite", ->
            h3 "Sequential transaction application test"
          div id: "reintegration-suite", ->
            h3 "Transaction reintegration test"

        script src: '/tests.js'
