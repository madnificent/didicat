`import startApp from 'didicat/tests/helpers/start-app'`

App = null
server = null

friends = [ {
  id: 'http://127.0.0.1:3001/'
  url: 'http://127.0.0.1:3001/'
}, {
  id: 'http://127.0.0.1:3002/'
  url: 'http://127.0.0.1:3002/'
}, {
  id: 'http://127.0.0.1:3003/'
  url: 'http://127.0.0.1:3003/'
} ]

module 'Integration - Friends page',
  setup: ->
    App = startApp()

    server = new Pretender ->
      @get '/api/friends', (request) ->
        [200, {'Content-Type': 'application/json'}, JSON.stringify(friends: friends)]
      @get '/api/friends/:id', (request) ->
        friend = friends.findBy 'id', +request.params.id
        [200, {'Content-Type': 'application/json'}, JSON.stringify(friends: friend)]

  teardown: ->
    Ember.run(App, 'destroy')
    server.shutdown()
    
test 'Should navigate to the friends page', ->
  visit('/').then ->
    click("a:contains('Friends')").then ->
      equal find('h3').text(), 'These are my friends'

test 'Should display a link to each friend', ->
  visit('/friends').then ->
    for friend in friends
      equal find("a:contains('#{friend.url}')").length, 1
  
test 'Should display the url', ->
  friend = friends.get('firstObject')
  visit("/friends/#{encodeURIComponent friend.url}").then ->
    equal find('.friend h4').text(), friend.url
