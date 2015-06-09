_ = require 'underscore'
q = require 'q'

describe 'task-runner', ->
  communicator = undefined

  taskRunner = undefined
  taskRunnerClass = undefined

  messageHelper = undefined
  messageHelperDefer = undefined
  MessageHelperClass = undefined

  ping = undefined
  pingDefer = undefined
  PingClass = undefined

  task = undefined
  taskDefers = undefined
  tasks = undefined
  TaskClass = undefined

  taskCallback = undefined
  taskMessageCallback = undefined
  taskErrorCallback = undefined

  isReady = false

  pingCommand =
    command: "ping"

  taskParams =
    environment: "acdev"

  clientSet = [
    'web',
    'master-broker',
    'slave-broker',
    'worker'
  ]

  runStages = []

  applyCommandSet = []

  # You're pretty much guaranteed to not see this elsewhere in your code...
  # Used for worst-case error handler on promises
  funkyChickenError = (thing) ->
    console.error "funkyChickenError", thing

  beforeEach ->
    applyCommandSet = [
      { name: "stop web UI", command: "stop-web-ui", only: ["web"], environment: "should_be_overridden" },
      { name: "stop messaging services", command: "stop-messaging", only: ["worker"] },
      { name: "stop slave broker", command: "stop-slave-broker", only: ["slave-broker"] },
      { name: "stop master broker", command: "stop-master-broker", only: ["master-broker"] },
      { name: "run puppet-apply", command: "puppet-apply", only: ["all"] },
      { name: "start master message broker", command: "start-master-broker", only: ["master-broker"] },
      { name: "start slave message broker", command: "start-slave-broker", only: ["slave-broker"] },
      { name: "start messaging services", command: "start-messaging", only: ["worker"] },
      { name: "start web UI", command: "start-web-ui", only: ["web"] },
    ]

    communicator =
      send: (message)->
        # console.log "comm.send", message

    communicator.send = spyOn(communicator, "send").and.callThrough()

    messageHelper = undefined
    messageHelperDefer = q.defer()

    class MessageHelperClass
      constructor: (readyFn, callbackFn, errbackFn) ->
        @ready = false

        @readyFn = readyFn
        @callbackFn = callbackFn
        @errbackFn = errbackFn

        messageHelper = this

        spyOn(messageHelper, "send").and.callThrough()
        spyOn(messageHelper, "isReady").and.callThrough()
        spyOn(messageHelper, "shutDown").and.callThrough()

      isReady: ->
        return @ready

      send: (message) ->
        try
          commandId = messageHelper.send.calls.all()[0].args[0].commandId
        catch e
          console.log "caught error in catcher", e

      readyPromise: () ->
        return messageHelperDefer.promise

      shutDown: ->

    ping = undefined
    pingDefer = q.defer()

    class PingClass
      constructor: (clientSet, parent, pingParams) ->
        spyOn(this, "run").and.callThrough()
        spyOn(this, "messageCallback").and.callThrough()
        spyOn(this, "errorCallback").and.callThrough()

        ping = @

      run: ->
        return pingDefer.promise

      messageCallback: (message) ->
      errorCallback: ->

    tasks = []
    taskDefers = []

    class TaskClass
      constructor: (@clientSet, @parent, @params) ->
      run: ->
        if taskCallback
          return taskCallback @
      messageCallback: (message) ->
        if messageCallback
          taskMessageCallback @, message
      errorCallback: (message) ->
        if errorCallback
          taskErrorCallback @, message
      name: ->
        return @params.name

  beforeEach ->
    timerCallback = jasmine.createSpy "timerCallback"
    jasmine.clock().install()

  afterEach ->
    jasmine.clock().uninstall()

  afterEach ->
    # No process should be able to preclude the shutdown process
    expect(messageHelper.shutDown.calls.count()).toEqual 1

  it 'works in warm sunny weather', (done) ->
    d = q.defer()

    startMessageHelper = ->
      messageHelperDefer.resolve("Default -> Completed")

    resolvePing = ->
      pingDefer.resolve("Default -> Completed")

    runSucceeded = (message) ->
      finalChecks()

    runFailed = (message) ->
      expect("succeeded").toEqual("failed")
      done()

    taskMessageCallback = undefined
    taskErrorCallback = undefined

    taskCallback = (task) ->
      taskResult = q.defer()
      task.parent.notify "Completed " + task.name()
      taskResult.resolve("Completed " + task.name())
      return taskResult.promise

    d.promise
      .then(startMessageHelper)
      .then(resolvePing)
      .catch(funkyChickenError)

    taskRunnerClass = require('../src/task-runner')(MessageHelperClass, PingClass, TaskClass)
    taskRunner = new taskRunnerClass applyCommandSet, clientSet, taskParams, communicator
    taskRunner.run().then runSucceeded, runFailed
      .catch funkyChickenError

    d.resolve()

    finalChecks = ->
      expect(ping.run).toHaveBeenCalled()

      _.each applyCommandSet, (command) ->
        expect(communicator.send).toHaveBeenCalledWith "Initiating " + command.name
        expect(communicator.send).toHaveBeenCalledWith "Completed " + command.name

      expect(communicator.send).toHaveBeenCalledWith "All done"

      done()

  it 'handles ping failure correctly', (done) ->
    d = q.defer()

    startMessageHelper = ->
      messageHelperDefer.resolve("Default -> Completed")

    resolvePing = ->
      pingDefer.reject(new Error("Ping rejected"))

    runSucceeded = (message) ->
      expect("succeeded").toEqual("failed")
      done()

    runFailed = (message) ->
      finalChecks()

    d.promise
      .then startMessageHelper
      .then resolvePing
      .catch funkyChickenError

    taskRunnerClass = require('../src/task-runner')(MessageHelperClass, PingClass, TaskClass)
    taskRunner = new taskRunnerClass applyCommandSet, clientSet, taskParams, communicator
    taskRunner.run().then runSucceeded, runFailed
      .catch funkyChickenError

    d.resolve()

    finalChecks = ->
      expect(communicator.send).toHaveBeenCalledWith "Failed: " + (new Error("Ping rejected").toString())

      done()

  it 'handles task failure correctly', (done) ->
    d = q.defer()

    startMessageHelper = ->
      messageHelperDefer.resolve("Default -> Completed")

    resolvePing = ->
      pingDefer.resolve("Default -> Completed")

    runSucceeded = (message) ->
      expect("succeeded").toEqual("failed")
      done()

    runFailed = (message) ->
      finalChecks()

    taskMessageCallback = undefined
    taskErrorCallback = undefined

    taskCount = 0

    taskCallback = (task) ->
      taskCount += 1

      if taskCount < 4
        task.parent.notify "Completed " + task.name()

        return "Completed " + task.name()
      else
        throw new Error("Forced failure in " + task.name())

    d.promise
      .then startMessageHelper
      .then resolvePing
      .catch funkyChickenError

    taskRunnerClass = require('../src/task-runner')(MessageHelperClass, PingClass, TaskClass)
    taskRunner = new taskRunnerClass applyCommandSet, clientSet, taskParams, communicator
    taskRunner.run().then runSucceeded, runFailed
      .catch funkyChickenError

    d.resolve()

    finalChecks = ->
      expect(ping.run).toHaveBeenCalled()

      _.each _.clone(applyCommandSet).splice(0,3), (command) ->
        expect(communicator.send).toHaveBeenCalledWith "Initiating " + command.name
        expect(communicator.send).toHaveBeenCalledWith "Completed " + command.name

      _.each _.clone(applyCommandSet).splice(4), (command) ->
        expect(communicator.send).not.toHaveBeenCalledWith "Initiating " + command.name
        expect(communicator.send).not.toHaveBeenCalledWith "Completed " + command.name

      expect(communicator.send).toHaveBeenCalledWith "Failed: Error: Forced failure in stop master broker"

      done()
