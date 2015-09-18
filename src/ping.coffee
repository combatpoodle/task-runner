format = require 'string-format'
_ = require 'underscore'
q = require 'q'

class Ping
    # See task-runner.spec.coffee for examples of the function arguments
    constructor: (clientSet, parent, pingParams) ->
        @_clientSet = clientSet
        @_aliveClients = []
        @_parent = parent
        @_params = pingParams
        @_nonce = Math.random().toString(36).replace(/[^0-9a-z]+/g, '').substr(0, 10)

        @_clientSet.sort()

    timeout: 2000

    run: ->
        @_defer = q.defer()

        @_parent.registerCallback(this, @_nonce)

        @_sendPing()

        return @_defer.promise.timeout(@timeout, "Ping timed out").then (@_done).bind(@), (@_doneWithFailure).bind(@)

    _done: (thing) ->
        @_parent.unRegisterCallback(@_nonce)
        return q.resolve(thing)

    _doneWithFailure: (thing) ->
        @_parent.unRegisterCallback(@_nonce)
        throw thing

    _sendPing: ->
        payload =
            command: "ping"
            params: @_params
            nonce: @_nonce

        @_parent.send payload

    messageCallback: (message) ->
        if message.response != "pong" or not message.identity
            @_parent.notify "Received unexpected response"
            return

        if message.nonce != @_nonce
            @_parent.notify "Ping got a mismatched nonce"
            return

        if @_clientSet.indexOf(message['identity']) < 0
            @_defer.reject "Unexpected client responding with identity " + message['identity']
            return

        @_aliveClients.push message['identity']
        @_aliveClients.sort()

        @_parent.notify("Received ping from " + message['identity'])

        if _.isEqual @_clientSet, @_aliveClients
            @_defer.resolve "All clients responded"

    errorCallback: ->
        # nothing to do here

module.exports = Ping
