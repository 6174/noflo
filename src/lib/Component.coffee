#     NoFlo - Flow-Based Programming for JavaScript
#     (c) 2013-2014 TheGrid (Rituwall Inc.)
#     (c) 2011-2012 Henri Bergius, Nemein
#     NoFlo may be freely distributed under the MIT license
#
# Baseclass for regular NoFlo components.
{EventEmitter} = require 'events'

ports = require './Ports'
IP = require './IP'

class Component extends EventEmitter
  description: ''
  icon: null
  started: false
  load: 0

  constructor: (options) ->
    options = {} unless options
    options.inPorts = {} unless options.inPorts
    if options.inPorts instanceof ports.InPorts
      @inPorts = options.inPorts
    else
      @inPorts = new ports.InPorts options.inPorts

    options.outPorts = {} unless options.outPorts
    if options.outPorts instanceof ports.OutPorts
      @outPorts = options.outPorts
    else
      @outPorts = new ports.OutPorts options.outPorts

  getDescription: -> @description

  isReady: -> true

  isSubgraph: -> false

  setIcon: (@icon) ->
    @emit 'icon', @icon
  getIcon: -> @icon

  error: (e, groups = [], errorPort = 'error') =>
    if @outPorts[errorPort] and (@outPorts[errorPort].isAttached() or not @outPorts[errorPort].isRequired())
      @outPorts[errorPort].beginGroup group for group in groups
      @outPorts[errorPort].send e
      @outPorts[errorPort].endGroup() for group in groups
      @outPorts[errorPort].disconnect()
      return
    throw e

  shutdown: ->
    @started = false

  # The startup function performs initialization for the component.
  start: ->
    @started = true
    @started

  isStarted: -> @started

  # Sets process handler function
  process: (handle) ->
    unless typeof handle is 'function'
      throw new Error "Process handler must be a function"
    unless @inPorts
      throw new Error "Component ports must be defined before process function"
    @handle = handle
    for name, port of @inPorts.ports
      port.on 'ip', (ip) =>
        @handleIP ip
    @

  handleIP: (ip) ->
    input = new ProcessInput @inPorts, ip.scope
    output = new ProcessOutput @outPorts, ip.scope, @,
      ordered: @ordered
    @load++
    @handle input, output, output.done

exports.Component = Component

class ProcessInput
  constructor: (@ports, @scope) ->

  has: ->
    res = true
    res and= @ports[port].ready @scope for port in arguments
    res

  get: ->
    res = (@ports[port].get @scope for port in arguments)
    if arguments.length is 1 then res[0] else res

  getData: ->
    ips = @get.apply this, arguments
    res = (ip.data for ip in ips)
    if arguments.length is 1 then res[0] else res

class ProcessOutput
  constructor: (@ports, @scope, @nodeInstance, @options) ->
    @options ?= {}
    @options.ordered ?= true
    @queue = []

  sendIP: (port, packet) ->
    if typeof packet isnt 'object' or
    IP.types.indexOf(packet.type) is -1
      ip = new IP 'data', packet
    else
      ip = packet
    # TODO output buffering
    @nodeInstance.outPorts[port].sendIP ip

  send: (outputMap) ->
    for port, packet of outputMap
      @sendIP port, packet

  sendDone: (outputMap) ->
    @send outputMap
    @done()

  done: ->
    # TODO Flush queue
    @nodeInstance.load--
