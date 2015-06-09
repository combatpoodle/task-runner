format = require 'string-format'
_ = require 'underscore'
q = require 'q'

class Task
    # See task-runner.spec.coffee for examples of the function arguments
    constructor: (clientSet, parent, taskParams) ->
        if taskParams.only
            @_clientSet = taskParams.only
        else
            @_clientSet = taskParams.clientSet

        @_completedClients = []
        @_parent = parent
        @_params = taskParams
        @_nonce = Math.random().toString(36).replace(/[^0-9a-z]+/g, '').substr(0, 10)
        @_failed = false

        if taskParams.timeout
            @timeout = taskParams.timeout
        else
            @timeout = 20 * 60 * 1000

        @_clientSet.sort()

    name: () ->
        return @_params.name

    run: ->
        @_defer = q.defer()

        @_parent.registerCallbacks(this, @_nonce)

        @_runTask()

        result = @_defer.promise
            .timeout(@timeout, "Task timed out")
            .then (@_done).bind(@), (@_doneWithFailure).bind(@)

        return result

    _done: (thing) ->
        @_parent.unRegisterCallbacks(@_nonce)
        return thing

    _doneWithFailure: (thing) ->
        @_parent.unRegisterCallbacks(@_nonce)
        throw thing

    _runTask: ->
        @_params.nonce = @_nonce

        @_parent.send @_params

    messageCallback: (message) ->
        if (!message.identity) or (!message.status) or (!message.response) or (!message.nonce)
            @_parent.notify format("Got a malformed response: {}", JSON.stringify(message))

        if (message.nonce != @_nonce)
            @_parent.notify "Task got a mismatched nonce"
            console.error "Task got a mismatched nonce"
            return

        if ["processing", "working", "incomplete"].indexOf(message.status) >= 0
            @_parent.notify format("Client {identity} {status}: {response}", message)

        else if message.status == "n/a"

        else if message.status == "failed"
            @_parent.notify format("Client {identity} {status}: {response}", message)
            @_completedClients.push(message.identity)
            @_failed = true

        else if message.status == "completed"
            @_parent.notify format("Client {identity} {status}: {response}", message)
            @_completedClients.push(message.identity)

        else
            @_parent.notify format("I doesn't know what to do with this status message from {identity}: {status}", message)
            console.error "I don't know what to do with status", message.status

        @_completedClients.sort()

        if _.isEqual(@_completedClients, @_clientSet)
            if @_failed
                @_defer.reject(new Error("Failed"))
            else
                @_defer.resolve("Completed")

    errorCallback: (message) ->
        console.error(message)
        @_parent.notify "Message queue connection dropped; automatic reconnect should kick in momentarily..."

module.exports = Task