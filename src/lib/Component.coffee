#     NoFlo - Flow-Based Programming for JavaScript
#     (c) 2013-2016 TheGrid (Rituwall Inc.)
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
  ordered: false
  outputQ: []
  activateOnInput: true
  forwardBrackets:
    in: ['out', 'error']
  bracketBuffer: {}

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

    @icon = options.icon if options.icon
    @description = options.description if options.description
    @ordered = options.ordered if 'ordered' of options
    @activateOnInput = options.activateOnInput if 'activateOnInput' of options

    if typeof options.process is 'function'
      @process options.process

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

  # Ensures braket forwarding map is correct for the existing ports
  prepareForwarding: ->
    for inPort, outPorts of @forwardBrackets
      unless inPort of @inPorts.ports
        delete @forwardBrackets[inPort]
        continue
      tmp = []
      for outPort in outPorts
        tmp.push outPort if outPort of @outPorts.ports
      if tmp.length is 0
        delete @forwardBrackets[inPort]
      else
        @forwardBrackets[inPort] = tmp
        @bracketBuffer[inPort] = []

  # Sets process handler function
  process: (handle) ->
    unless typeof handle is 'function'
      throw new Error "Process handler must be a function"
    unless @inPorts
      throw new Error "Component ports must be defined before process function"
    @prepareForwarding()
    @handle = handle
    for name, port of @inPorts.ports
      do (name, port) =>
        port.name = name unless port.name
        port.on 'ip', (ip) =>
          @handleIP ip, port
    @

  # Handles an incoming IP object
  handleIP: (ip, port) ->
    if port.name of @forwardBrackets and
    (ip.type is 'openBracket' or ip.type is 'closeBracket')
      @bracketBuffer[port.name].push port.buffer.pop()
      return
    return unless port.options.triggering
    result = {}
    input = new ProcessInput @inPorts, ip, @, port, result
    output = new ProcessOutput @outPorts, ip, @, result
    @load++
    @handle input, output, -> output.done()

exports.Component = Component

class ProcessInput
  constructor: (@ports, @ip, @nodeInstance, @port, @result) ->
    @scope = @ip.scope

  # Sets component state to `activated`
  activate: ->
    @result.__resolved = false
    if @nodeInstance.ordered
      @nodeInstance.outputQ.push @result

  # Returns true if a port (or ports joined by logical AND) has a new IP
  has: (port = 'in') ->
    res = true
    res and= @ports[port].ready @scope for port in arguments
    res

  # Fetches IP object(s) for port(s)
  get: (port = 'in') ->
    if @nodeInstance.ordered and
    @nodeInstance.activateOnInput and
    not ('__resolved' of @result)
      @activate()
    res = (@ports[port].get @scope for port in arguments)
    if arguments.length is 1 then res[0] else res

  # Fetches `data` property of IP object(s) for given port(s)
  getData: (port = 'in') ->
    ips = @get.apply this, arguments
    if arguments.length is 1
      return ips?.data ? undefined
    (ip?.data ? undefined for ip in ips)

class ProcessOutput
  constructor: (@ports, @ip, @nodeInstance, @result) ->
    @scope = @ip.scope

  # Sets component state to `activated`
  activate: ->
    @result.__resolved = false
    if @nodeInstance.ordered
      @nodeInstance.outputQ.push @result

  # Checks if a value is an Error
  isError: (err) ->
    err instanceof Error or
    Array.isArray(err) and err.length > 0 and err[0] instanceof Error

  # Sends an error object
  error: (err) ->
    multiple = Array.isArray err
    err = [err] unless multiple
    if 'error' of @ports and
    (@ports.error.isAttached() or not @ports.error.isRequired())
      @sendIP 'error', new IP 'openBracket' if multiple
      @sendIP 'error', e for e in err
      @sendIP 'error', new IP 'closeBracket' if multiple
    else
      throw e for e in err

  # Sends a single IP object to a port
  sendIP: (port, packet) ->
    if typeof packet isnt 'object' or
    IP.types.indexOf(packet.type) is -1
      ip = new IP 'data', packet
    else
      ip = packet
    ip.scope = @scope if @scope isnt null and ip.scope is null
    if @nodeInstance.ordered
      @result[port] = [] unless port of @result
      @result[port].push ip
    else
      @nodeInstance.outPorts[port].sendIP ip

  # Sends packets for each port as a key in the map
  # or sends Error or a list of Errors if passed such
  send: (outputMap) ->
    if @nodeInstance.ordered and
    not ('__resolved' of @result)
      @activate()
    return @error outputMap if @isError outputMap
    for port, packet of outputMap
      @sendIP port, packet

  # Alias for `complete()`
  sendDone: (outputMap) ->
    @complete outputMap

  # Sends the argument via `send()` and marks activation as `done()`
  complete: (outputMap) ->
    @send outputMap
    @done()

  # Makes a map-style component pass a result value to `out`
  # keeping all IP metadata received from `in`,
  # or modifying it if `options` is provided
  pass: (data, options = {}) ->
    unless 'out' of @ports
      throw new Error 'output.pass() requires port "out" to be present'
    for key, val of options
      @ip[key] = val
    @ip.data = data
    @sendIP 'out', @ip
    @done()

  # Finishes process activation gracefully
  done: (error) ->
    @error error if error
    if @nodeInstance.ordered
      @result.__resolved = true
      while @nodeInstance.outputQ.length > 0
        result = @nodeInstance.outputQ[0]
        break unless result.__resolved
        for port, ips of result
          continue if port is '__resolved'
          for ip in ips
            @nodeInstance.outPorts[port].sendIP ip
        @nodeInstance.outputQ.shift()
    @nodeInstance.load--
