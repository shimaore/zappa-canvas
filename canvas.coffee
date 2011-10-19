#!/usr/bin/env coffee

require('zappa') ->
  @enable 'default layout', 'serve jquery',
    'serve sammy' # , 'minify'
  @use 'static'

  @get '/': ->
    @render 'index'

  # TODO Load from storage at startup
  history = [{do:'wipe'}]
  redo = []

  # Canvas server
  @on connection: ->
    # Update the newly-connected client with history
    console.log "Client #{@id} connected"
    if not @client.nickname?
      @emit 'request nickname': {}
    @emit 'run commands': {commands:history}

  @on disconnect: ->
    console.log "Client #{@id} disconnected"
    @broadcast log: {text:"#{@client.nickname} disconnected."}
    delete @client.nickname

  @on 'canvas clear': ->
    history = [{do:'wipe'}]
    @broadcast 'run commands': {commands:history}
    @emit      'run commands': {commands:history}
    @broadcast log: {text:"Cleared by #{@client.nickname}!"}
    @emit      log: {text:"Cleared by #{@client.nickname}!"}

  @on 'canvas line': ->
    command =
      do:'line'
      from:@data.from
      to:@data.to
      color:@data.color
      author:@client.nickname
    history.push command
    @broadcast 'run commands': {commands:[command]}

  @on 'canvas undo': ->
    if history.length <= 1
      @emit log: {text: "Nothing to undo"}
      return
    redo.push history.pop()
    @broadcast 'run commands': {commands:history}
    @emit      'run commands': {commands:history}

  @on 'canvas redo': ->
    if redo.length < 1
      @emit log: {text: "Nothing to redo"}
      return
    command = redo.pop()
    history.push command
    @broadcast 'run commands': {commands:[command]}
    @emit      'run commands': {commands:[command]}

  # Chat Server (based on zappa's chat example)
  @on 'set nickname': ->
    @client.nickname = @data.nickname
    console.log "#{@client.nickname} connected"
    @broadcast log: {text: "#{@client.nickname} connected"}
    @emit      log: {text: "#{@client.nickname} connected"}

  @on said: ->
    @broadcast said: {nickname: @client.nickname, text: @data.text}
    @emit      said: {nickname: @client.nickname, text: @data.text}

  @shared '/shared.js': ->

  @client '/index.js': ->

    # See http://www.williammalone.com/articles/create-html5-canvas-javascript-drawing-app/
    $.fn.draw = (cb) ->
      precision = 2
      paint = false
      last_point = null
      @mousedown (e) ->
        point =
          x: e.pageX - @offsetLeft
          y: e.pageY - @offsetTop

        paint = true
        cb point, point
        last_point = point

      @mousemove (e) ->
        if paint
          point =
            x: e.pageX - @offsetLeft
            y: e.pageY - @offsetTop
          dx = point.x - last_point.x
          dy = point.y - last_point.y
          if -precision <= dx <= precision or -precision <= dy <= precision
            return
          cb last_point, point
          last_point = point

      @mouseup (e) ->
        paint = false

      @mouseleave (e) ->
        paint = false

    canvas_ctx = null
    canvas_width = null
    canvas_height = null

    render_command = (command) ->

      if not canvas_ctx
        log "Canvas not ready yet"
        return

      switch command.do
        when 'wipe'
          # Remove any text div
          # Wipe canvas
          canvas_ctx.clearRect(0,0,canvas_width,canvas_height)

        when 'line'
          canvas_ctx.strokeStyle = '#' + command.color
          canvas_ctx.lineJoin = 'round'
          canvas_ctx.lineWidth = 5

          canvas_ctx.beginPath()
          canvas_ctx.moveTo command.from.x, command.from.y
          canvas_ctx.lineTo command.to.x,   command.to.y
          canvas_ctx.stroke()
          
    log = (text) ->
      console.log text
      $('#log').prepend "<p>#{text}</p>"

    @on connection: ->
      log "Connected as #{@id}"

    @on disconnect: ->
      log "Disconnected"

    @on log: ->
      log @data.text

    @on said: ->
      log """
        <span class="author">#{@data.nickname}</span>
        said:
        <span class="message">#{@data.text}</span>
      """

    @on 'request nickname': ->
      @emit 'set nickname': {nickname: prompt 'Pick a nickname!'}

    @get '#/': =>

      # Whiteboard
      $('#canvas').each ->
        if @getContext
          canvas_ctx = @getContext '2d'
          if canvas_ctx
            log 'Canvas is ready'
          canvas_width = @width
          canvas_height = @height
        else
          log 'Canvas is not supported'

      $('#canvas').draw (from,to) =>
        color = $('#swatch').data 'value'
        @emit 'canvas line': {from:from,to:to,color:color}
        render_command do:'line',from:from,to:to,color:color

      $('#undo').click =>
        @emit 'canvas undo': {}
        return false

      $('#redo').click =>
        @emit 'canvas redo': {}
        return false

      # Chat
      $('#box').focus()

      $('button').click (e) =>
        @emit said: {text: $('#box').val()}
        $('#box').val('').focus()
        e.preventDefault()

    @get '#/clear': =>
      @emit 'canvas clear': {}

    @get '#/draw': ->
      # Select drawing tool

    @get '#/text': ->
      # Create new text box


    @on 'run commands': ->
      render_command command for command in @data.commands

    # Connect to socket.io 
    @connect()

  @css '/index.css': '''
    canvas { border: 1px solid black; }
    a, span#undo, span#redo { margin: 2px; }
    .author { font-style: italic; }
    .message { font-weight: bold; }

    /* colorpicker */
    #colorpicker {
      float: right;
    }
    #red, #green, #blue {
      float: left;
      clear: left;
      width: 300px;
      margin: 15px;
    }
    #swatch {
      width: 120px;
      height: 100px;
      margin-top: 18px;
      margin-left: 350px;
      background-image: none;
    }
    #red .ui-slider-range { background: #ef2929; }
    #red .ui-slider-handle { border-color: #ef2929; }
    #green .ui-slider-range { background: #8ae234; }
    #green .ui-slider-handle { border-color: #8ae234; }
    #blue .ui-slider-range { background: #729fcf; }
    #blue .ui-slider-handle { border-color: #729fcf; }
  '''

  @view index: ->
    @title = 'Whiteboard!'
    @scripts = ['/socket.io/socket.io', '/zappa/jquery',
      '/zappa/sammy', '/zappa/zappa', '/shared', '/index']
    @stylesheets = ['/index']

    # Jquery UI (colorpicker)
    @scripts.push 'js/jquery-ui-1.8.16.custom.min'
    @stylesheets.push 'css/smoothness/jquery-ui-1.8.16.custom'

    h1 @title
    div class:'board', ->
      canvas width:1000, height:300, id:'canvas'

    a href:'#/clear', 'Clear'
    span id:'undo', 'Undo'
    span id:'redo', 'Redo'
    a href:'#/draw', 'Draw'
    a href:'#/text', 'Text'

    # colorpicker
    div id:'colorpicker', ->
      div id:'red'
      div id:'green'
      div id:'blue'

      div id:'swatch', class:'ui-widget-content ui-corner-all'

      coffeescript ->
        hexFromRGB = (r, g, b) ->
          hex = [
            r.toString( 16 )
            g.toString( 16 )
            b.toString( 16 )
          ]
          $.each hex, ( nr, val ) ->
            if val.length is 1
              hex[ nr ] = "0" + val
          return hex.join( "" ).toUpperCase()
        refreshSwatch = ->
          red   = $( "#red"   ).slider( "value" )
          green = $( "#green" ).slider( "value" )
          blue  = $( "#blue"  ).slider( "value" )
          hex = hexFromRGB( red, green, blue )
          $( "#swatch" ).css( "background-color", "#" + hex )
          $( "#swatch" ).data 'value', hex
        $ ->
          $( "#red, #green, #blue" ).slider
            orientation: "horizontal"
            range: "min"
            max: 255
            value: 127
            slide: refreshSwatch,
            change: refreshSwatch
          $( "#red" ).slider( "value", 255 )
          $( "#green" ).slider( "value", 140 )
          $( "#blue" ).slider( "value", 60 )


    div id:'chat', ->
      form ->
        input id: 'box'
        button 'Send'
      div id:'log'
