# Refactor, I know...  :D

module.exports = (MessageHelper, Ping, Task) ->
    # Mock injection
    if !MessageHelper
        MessageHelper = require('message-helper')()

    format = require 'string-format'
    _ = require 'underscore'
    q = require 'q'

    if not Ping
        Ping = require('./ping')
    if not Task
        Task = require('./task')

    class TaskRunner
        # See task-runner.spec.coffee for examples of the function taskParams
        constructor: (commandSet, clientSet, taskParams, communicator) ->
            @_tasks = commandSet
            @_taskParams = taskParams
            @_communicator = communicator
            @_clients = clientSet

            @_clients.sort()

            @_aliveClients = []
            @_startOnReady = false
            @_running = false

            @_callbacks = {}

            @_messenger = new MessageHelper (@_messengerReady).bind(@), (@_messengerCallback).bind(@), (@_messengerConnectionError).bind(@)

        _sendError: (message) ->
            @_communicator.send "Error: #{message}"

        _sendMessage: (message) ->
            if message == undefined
                throw new Error "message is undefined"

            @_communicator.send message

        _messengerCallback: (message) ->
            @_messageCallback message

        _messengerReady: () ->
            @_sendMessage "Ready to start"

            if @_startOnReady
                @run()

        _messengerConnectionError: () ->
            @_errorCallback()

        registerCallback: (subscriber, nonce) ->
            @_callbacks[nonce] = subscriber

        unRegisterCallback: (nonce) ->
            @_callbacks[nonce] = false

        _messageCallback: (message) ->
            if not message.nonce
                @_sendError("Got broken message (missing nonce)")
                return

            if typeof @_callbacks[message.nonce] == "undefined"
                @_sendError("Got delayed or broken message")

            if @_callbacks[message.nonce] == false
                return

            @_callbacks[message.nonce].messageCallback(message)

        _errorCallback: (message) ->
            @_sendError "Message queue connection dropped; automatic reconnect should kick in momentarily..."

            if not message or not message.nonce
                return

            if not @_callbacks[message.nonce]
                return

            @_callbacks[message.nonce].errorCallback(message)

        run: ->
            return @_messenger.readyPromise()
                .then @_ping.bind(@), @_failed.bind(@)
                .then @_runTasks.bind(@), @_failed.bind(@)
                .then @_completed.bind(@), @_failed.bind(@)
                .catch @_failed.bind(@)

        send: (payload) ->
            @_messenger.send(payload)

        notify: (message) ->
            @_sendMessage message

        _ping: ->
            ping = new Ping @_clients, @, @_taskParams

            return ping.run()

        _completed: (message) ->
            @_sendMessage("All done")
            @_shutDown()
            return "Completed"

        _failed: (message) ->
            if not @_hasFailed
                @notify "Failed: " + message.toString()
                @_shutDown()
                @_hasFailed = true

            return q.reject(message)

        _runTasks: ->
            taskDefer = q.defer()
            taskPromise = taskDefer.promise

            createAndAttachTask = (taskDefinition) ->
                taskParams = _.extend(taskDefinition, @_taskParams)
                task = new Task @_clients, @, taskParams

                taskRun = (thing) ->
                    @notify "Initiating " + task.name()
                    task.run()

                taskFailure = (thing) ->
                    throw thing

                taskPromise = taskPromise.then taskRun.bind(@), taskFailure.bind(@)

            _.each @_tasks, createAndAttachTask, @

            taskDefer.resolve("Go")

            return taskPromise

        _shutDown: ->
            @_messenger.shutDown()

    TaskRunner
