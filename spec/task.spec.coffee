_ = require 'underscore'

describe 'task', ->
  parent = undefined
  task = undefined
  defaultParams = undefined
  defaultTaskDefinition = undefined
  clientSet = undefined

  beforeEach ->
    defaultParams = {
      environment: "test-env"
    }

    defaultTaskDefinition = { name: "Stop web UI", command: "stop-web-ui", only: ["web", "worker"], environment: "should_be_overridden" }

    clientSet = [
      'web',
      'master-broker',
      'slave-broker',
      'worker'
    ]

  # You're pretty much guaranteed to not see this elsewhere in your code...
  # Used for worst-case error handler on promises
  funkyChickenError = (thing) ->
    console.error "funkyChickenError", thing

  beforeEach ->
    class parentClass
      registerCallbacks: (child, nonce) ->
        # console.log("registercallbacks with", child, nonce)
      unRegisterCallbacks: (nonce) ->
        # console.log("unRegisterCallbacks with", nonce)
      send: (payload) ->
        # console.log("sendpayload with", payload)
      notify: (message) ->

    parent = new parentClass()

    spyOn(parent, "send").and.callThrough()
    spyOn(parent, "registerCallbacks").and.callThrough()
    spyOn(parent, "unRegisterCallbacks").and.callThrough()
    spyOn(parent, "notify").and.callThrough()

  beforeEach ->
    timerCallback = jasmine.createSpy "timerCallback"
    jasmine.clock().install()

  afterEach ->
    jasmine.clock().uninstall()

  setUpPlainTask = ->
    taskClass = require('../src/task')
    task = new taskClass clientSet, parent, _.extend(defaultTaskDefinition, defaultParams)

  sendTaskUpdates = (clientSet, taskPayload) ->
    _.each clientSet, (clientName) ->
      response =
        status: "working",
        response: "output"
        identity: clientName,
        nonce: taskPayload.nonce

  sendTaskResponses = (clientSet, taskPayload) ->
    _.each clientSet, (clientName) ->
      response =
        status: "completed"
        response: "output"
        identity: clientName
        nonce: taskPayload.nonce

      task.messageCallback response

  sendTaskFailedResponses = (clientSet, taskPayload) ->
    _.each clientSet, (clientName) ->
      response =
        status: "failed"
        response: "Are you feeling lucky?"
        identity: clientName
        nonce: taskPayload.nonce

      task.messageCallback response

  sendMismatchedResponse = (clientSet, taskPayload) ->
    _.each _.clone(clientSet).splice(0,1), (clientName) ->
      response =
        status: "failed"
        response: "Are you feeling lucky?"
        identity: clientName
        nonce: 12345

      task.messageCallback response      

  it 'works in happy state', (done) ->
    taskPayload = undefined

    setUpPlainTask()

    taskCompletedCB = ->
      finalChecks()

    taskFailedCB = (thing) ->
      # console.error("Failed!", thing)
      fail()

    parent.send = (payload) ->
      taskPayload = payload

    spyOn(parent, "send").and.callThrough()

    task.run().then taskCompletedCB, taskFailedCB
      .catch funkyChickenError

    sendTaskResponses ["web", "worker"], taskPayload

    finalChecks = ->
      expect(parent.registerCallbacks).toHaveBeenCalledWith(task, taskPayload.nonce)
      expect(parent.unRegisterCallbacks).toHaveBeenCalledWith(taskPayload.nonce)

      expect(parent.notify).toHaveBeenCalledWith("Client web completed: output")
      expect(parent.notify).toHaveBeenCalledWith("Client worker completed: output")

      done()

  it 'handles timeouts right', (done) ->
    taskPayload = undefined
    failedResponse = false

    setUpPlainTask()

    taskCompletedCB = ->
      fail("Hit completed callback in failure scenario")

    taskFailedCB = (thing) ->
      failedResponse = thing
      finalChecks()

    parent.send = (payload) ->
      taskPayload = payload

    spyOn(parent, "send").and.callThrough()

    task.run().then taskCompletedCB, taskFailedCB
      .catch funkyChickenError

    sendTaskResponses ["web"], taskPayload

    jasmine.clock().tick(60*60*1000)

    finalChecks = ->
      expect(parent.registerCallbacks).toHaveBeenCalledWith(task, taskPayload.nonce)
      expect(parent.unRegisterCallbacks).toHaveBeenCalledWith(taskPayload.nonce)
      expect(failedResponse.message).toEqual("Task timed out")

      done()

  it 'throws failures from the remote', (done) ->
    taskPayload = undefined

    setUpPlainTask()

    taskCompletedCB = ->
      console.error "Should not have gotten to task complete callback"
      fail()

    taskFailedCB = (thing) ->
      finalChecks()

    parent.send = (payload) ->
      taskPayload = payload

    spyOn(parent, "send").and.callThrough()

    task.run().then taskCompletedCB, taskFailedCB
      .catch funkyChickenError

    sendTaskFailedResponses ["web", "worker"], taskPayload

    finalChecks = ->
      console
      expect(parent.registerCallbacks).toHaveBeenCalledWith(task, taskPayload.nonce)
      expect(parent.unRegisterCallbacks).toHaveBeenCalledWith(taskPayload.nonce)

      expect(parent.notify).toHaveBeenCalledWith('Client web failed: Are you feeling lucky?')

      done()
