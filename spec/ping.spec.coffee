_ = require 'underscore'

describe 'ping', ->
  parent = undefined
  ping = undefined

  args = {
    environment: "test-env"
  }

  clientSet = [
    'web',
    'master-broker',
    'slave-broker',
    'worker'
  ]

  beforeEach ->
    class parentClass
      registerCallback: (child, nonce) ->
        # console.log("registercallbacks with", child, nonce)
      unRegisterCallback: (nonce) ->
        # console.log("unRegisterCallback with", nonce)
      send: (payload) ->
        # console.log("sendpayload with", payload)
      notify: (message) ->
        # console.log("parent.notify with", message)

    parent = new parentClass()

    spyOn(parent, "send").and.callThrough()
    spyOn(parent, "registerCallback").and.callThrough()
    spyOn(parent, "unRegisterCallback").and.callThrough()
    spyOn(parent, "notify").and.callThrough()

    pingClass = require('../src/ping')
    ping = new pingClass clientSet, parent, args

  beforeEach ->
    timerCallback = jasmine.createSpy "timerCallback"
    jasmine.clock().install()

  afterEach ->
    jasmine.clock().uninstall()

  sendPingResponses = (clientSet, pingPayload) ->
    _.each clientSet, (clientName) ->
      response = {
        response: "pong",
        identity: clientName,
        nonce: pingPayload.nonce
      }

      ping.messageCallback response

  it 'works in happy state', (done) ->
    pingPayload = undefined
    pingCompleted = false

    pingCompletedCB = ->
      pingCompleted = true
      finalChecks()

    pingFailedCB = (thing) ->
      # console.error("Failed!", thing)
      fail()

    parent.send = (payload) ->
      pingPayload = payload

    spyOn(parent, "send").and.callThrough()

    ping.run().then pingCompletedCB, pingFailedCB

    sendPingResponses clientSet, pingPayload

    finalChecks = ->
      expect(pingCompleted).toEqual(true)
      expect(pingCompleted).not.toBeUndefined()
      expect(parent.registerCallback).toHaveBeenCalledWith(ping, pingPayload.nonce)
      expect(parent.unRegisterCallback).toHaveBeenCalledWith(pingPayload.nonce)

      _.each clientSet, (client) ->
        expect(parent.notify).toHaveBeenCalledWith("Received ping from " + client)

      done()

  it 'handles timeouts right', (done) ->
    pingPayload = undefined
    failedResponse = false

    pingCompletedCB = ->
      fail("Hit completed callback in failure scenario")

    pingFailedCB = (thing) ->
      failedResponse = thing
      finalChecks()

    parent.send = (payload) ->
      pingPayload = payload

    spyOn(parent, "send").and.callThrough()

    ping.run().then pingCompletedCB, pingFailedCB

    sendPingResponses clientSet.splice(0,2), pingPayload

    jasmine.clock().tick(10000)

    finalChecks = ->
      expect(parent.registerCallback).toHaveBeenCalledWith(ping, pingPayload.nonce)
      expect(parent.unRegisterCallback).toHaveBeenCalledWith(pingPayload.nonce)
      expect(failedResponse.message).toEqual("Ping timed out")

      done()
