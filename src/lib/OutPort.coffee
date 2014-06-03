#     NoFlo - Flow-Based Programming for JavaScript
#     (c) 2014 TheGrid (Rituwall Inc.)
#     NoFlo may be freely distributed under the MIT license
#
# Output Port (outport) implementation for NoFlo components
BasePort = require './BasePort'

class OutPort extends BasePort
  connect: (socketId = null) ->
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in sockets
      continue unless socket
      socket.connect()

  beginGroup: (group, socketId = null) ->
    sockets = @getSockets socketId
    @checkRequired sockets
    sockets.forEach (socket) ->
      return unless socket
      return socket.beginGroup group if socket.isConnected()
      socket.once 'connect', ->
        socket.beginGroup group
      socket.connect()

  send: (data, socketId = null) ->
    sockets = @getSockets socketId
    @checkRequired sockets
    sockets.forEach (socket) ->
      return unless socket
      return socket.send data if socket.isConnected()
      socket.once 'connect', ->
        socket.send data
      socket.connect()

  endGroup: (socketId = null) ->
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in sockets
      continue unless socket
      socket.endGroup()

  disconnect: (socketId = null) ->
    sockets = @getSockets socketId
    @checkRequired sockets
    for socket in sockets
      continue unless socket
      socket.disconnect()

  checkRequired: (sockets) ->
    if sockets.length is 0 and @isRequired()
      throw new Error "#{@getId()}: No connections available"

  getSockets: (socketId) ->
    # Addressable sockets affect only one connection at time
    if @isAddressable()
      throw new Error "#{@getId()} Socket ID required" if socketId is null
      return [] unless @sockets[socketId]
      return [@sockets[socketId]]
    # Regular sockets affect all outbound connections
    @sockets

module.exports = OutPort
