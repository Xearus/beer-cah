#
# Description:
#   Cards Against Humanity game managed by Hubot
#   https://github.com/coryallegory/hubot-cah
#
# Dependencies:
#   None
#
# Commands:
#   hubot cah help - List cah commands
#   hubot cah black - Display a random black card
#   hubot cah white - Display a random white card
#   hubot cah play - Add yourself to the game
#   hubot cah retire - Remove yourself as an active player
#   hubot cah czar - Display name of the current Card Czar
#   hubot cah players - List active players
#   hubot cah leaders - Top five score leaders
#   hubot cah score - Display your score
#   hubot cah hand - List cards in your hand
#   hubot cah submit <#> <#> ... - Indicate white cards to be submitted as an answer, where # indicates card index in hand and amount of white cards submitted corresponds to the amount required by the current black card
#   hubot cah answers - List the current white card submissions for the current black card (Card Czar only)
#   hubot cah choose <#> - Choose a winning answer (Card Czar only)
#   hubot cah status - Display summary of current game
#   hubot cah skip - Discard current black card and assign a new Card Czar
#
# Author:
#   Cory Metcalfe (corymetcalfe@gmail.com)
#

helpSummary = "_hubot-cah commands:_"
helpSummary += "\ncah help - List cah commands"
helpSummary += "\ncah black - Display a random black card"
helpSummary += "\ncah white - Display a random white card"
helpSummary += "\ncah play - Add yourself to the game"
helpSummary += "\ncah retire - Remove yourself as an active player"
helpSummary += "\ncah czar - Display name of the current Card Czar"
helpSummary += "\ncah players - List active players"
helpSummary += "\ncah leaders - Top five score leaders"
helpSummary += "\ncah score - Display your score"
helpSummary += "\ncah hand - List cards in your hand"
helpSummary += "\ncah submit <#> <#> ... - Indicate white cards to be submitted as an answer, where # indicates card index in hand and amount of white cards submitted corresponds to the amount required by the current black card"
helpSummary += "\ncah answers - List the current white card submissions for the current black card (Card Czar only)"
helpSummary += "\ncah choose <#> - Choose a winning answer (Card Czar only)"
helpSummary += "\ncah status - Display summary of current game"
helpSummary += "\ncah skip - Discard current black card and assign a new Card Czar"


blackBlank = "_____"

blackCards = require('./blackcards.coffee')

whiteCards = require('./whitecards.coffee')

# @return black card text string
random_black_card = () ->
  cardIndex = Math.floor(Math.random()*blackCards.length)
  return blackCards[cardIndex]

# @return white card text string
random_white_card = () ->
  cardIndex = Math.floor(Math.random()*whiteCards.length)
  return whiteCards[cardIndex]

db = {
  scores:         {},                   # {<name>: <score>, ...}
  activePlayers:  [],                   # [<player name>, ...]
  blackCard:      random_black_card(),  # <card text>
  czar:           null,                 # <player name>
  hands:          {},                   # { <name>: [<card text>, <card text>, ...], ...}
  answers:        [],                   # [ {id: id, player: <player name>, cards: [<card text>, ...]}, ... ]
}

# prune inactive player hands, ensure everyone has five cards
fix_hands = () ->
  newHands = {}
  for own name, cardArray of db.hands
    if name in db.activePlayers
      while cardArray.length < 5
        cardArray.push random_white_card()
      newHands[name] = cardArray
  db["hands"] = newHands

# add player to active list
# fix their hand so it contains five cards
# if only player, make them czar
# @param playerName: name of player coming into game
add_player = (playerName) ->
  if playerName not in db.activePlayers
    db.activePlayers.push playerName
  if !db.scores[playerName]?
    db.scores[playerName] = 0
  cards = []
  while cards.length < 5
    cards.push random_white_card()
  db.hands[playerName] = cards
  if db.activePlayers.length == 1
    db.czar = playerName
    db.blackCard = random_black_card()

# remove player from active list
# remove any associated hands
# if they were czar, assign a new one
# @param playerName: name of player leaving the game
remove_player = (playerName) ->
  i = db.activePlayers.indexOf(playerName)
  if i >= 0
    db.activePlayers.splice(i,1)
  if db.hands[playerName]?
    delete db.hands[playerName]
  if db.czar == playerName
    if db.activePlayers.length == 0
      db.czar = null
    else if i >= db.activePlayers.length
      db.czar = db.activePlayers[0]
    else
      db.czar = db.activePlayers[i]

# combine black and white cards into complete phrase
# @param blackCard: black card text string
# @param whiteCards: array of white card text strings
# @return completed string
generate_phrase = (blackCard, whiteCards) ->
  phrase = ""
  blackBits = blackCard.split blackBlank
  if blackBits.length == 1
    phrase += "#{blackCard} *#{whiteCards[0]}*"
  else
    wi = 0
    bi = 0
    if blackCard.substring(0, blackBlank.length) == blackBlank
      phrase += "*#{whiteCards[0].match(/(.*[a-zA-Z0-9])[^a-zA-Z0-9]*$/i)[0]}*"
      wi = 1
    while wi < whiteCards.length or bi < blackBits.length
      if bi < blackBits.length
        phrase += blackBits[bi]
        bi++
      if wi < whiteCards.length
        phrase += "*#{whiteCards[wi].match(/(.*[a-zA-Z0-9])[^a-zA-Z0-9]*$/i)[0]}*"
        wi++
  return phrase

shuffle = (a) ->
  i = a.length
  while --i > 0
    j = ~~(Math.random() * (i + 1))
    t = a[j]
    a[j] = a[i]
    a[i] = t
  return a

shuffle_answers = () ->
  db.answers = shuffle(db.answers)
  i = 0
  for answer in db.answers
    answer.id = i
    i += 1

# remove cards from player hand and add to answers
# @param playerName: player submitting answer
# @param handIndices: indices of cards in player hand
submit_answer = (playerName, handIndices) ->
  playerHand = db.hands[playerName]
  cards = []
  for i in handIndices
    cards.push playerHand[i]
  for card in cards
    i = playerHand.indexOf(card)
    playerHand.splice(i,1)
  db.answers.push {id: db.answers.length, player: playerName, cards: cards}

  if db.answers.length == activePlayers.length
    shuffle_answers()

# specify winning card and reset game for next round
# @param answerIndex: if value outside db.answers array range, no winner this round
# @return string for public display
czar_choose_winner = (answerIndex) ->
  responseString = "Next round:"
  if 0 <= answerIndex and answerIndex < db.answers.length
    responseString = "*#{db.blackCard}*"
    for answer in db.answers
      responseString += "\n"
      for s in answer.cards
        responseString += ", #{s}"

    winner = db.answers[answerIndex].player
    cards = db.answers[answerIndex].cards
    winningPhrase = generate_phrase(db.blackCard, cards)

    responseString += "\n\n#{winner} earns a point for\n*#{winningPhrase}*"

    db.scores[winner] = (db.scores[winner] ? db.scores[winner] : 0) + 1

  db.answers = []
  fix_hands()
  db.blackCard = random_black_card()
  if db.activePlayers.length == 0
    db.czar = null
  else if !db.czar?
    db.czar = db.activePlayers[0]
  else
    czarIndex = db.activePlayers.indexOf db.czar
    if czarIndex < 0 or czarIndex == db.activePlayers.length-1
      db.czar = db.activePlayers[0]
    else
      db.czar = db.activePlayers[czarIndex+1]
  return responseString + "\n\nNext round:\n" + game_state_string()

# generate string describing game state
# czar, black card, number of submissions
game_state_string = () ->
  if !db.czar?
    return "Waiting for players."
  else
    return "*#{db.blackCard}* [#{db.czar}, #{db.answers.length}/#{db.activePlayers.length-1}]"

# @param msg: message object
# @return name of message sender
sender = (msg) ->
  return msg.message.user.name.toLowerCase()

# Usage: zip(arr1, arr2, arr3, ...)
zip = () ->
  lengthArray = (arr.length for arr in arguments)
  length = Math.min(lengthArray...)
  for i in [0...length]
    arr[i] for arr in arguments

objectify = (ks vs) ->
  o = { }
  for k, v in zip ks vs
    o[k] = v
  return o

cah_commands = {
  help: () -> return helpSummary,
  black: () -> return random_black_card(),
  white: () -> return random_white_card(),
  play: (name) ->
    add_player(name)
    return "You are now an active CAH player.",
  remove: (name) ->
    remove_player(name)
    return "You are no longer a CAH player. Your score will be preserved should you decide to play again.",
  czar: () -> db.czar ? db.czar : "No Card Czar yet, waiting for players."
  players: () -> return db.activePlayers.length? db.activePlayers.join(",") : "Waiting for players."
  leaders: () ->
    scoreTuples = (objectify(["name", "score"], [name, score]) for name, score in db.scores)
    scoreTuples.sort (a,b) -> return b.score - a.score
    return "CAH Leaders:" + [0...Math.min(5, scoreTuples.length-1)].map (i) -> "\n#{scoreTuples[i].name} #{scoreTuples[i].score}",
  score: (name) -> return db.scores[name]? db.scores[name] : "No CAH score on record.",
  hand: (name) ->
    cards = db.hands[name]
    responseString = "Your white CAH cards:"
    if cards?
      for i in [0...cards.length] by 1
        responseString += "\n#{i}: #{cards[i]}"
    return responseString,
  submit: (name, nums) ->
    if name == db.czar
      return "You are currently the Card Czar!"
    if db.hands[sender(msg)].length < 5
      return "You have already submitted cards for this round."
    expectedCount = (db.blackCard.match(blackBlank) || []).length
    if expectedCount == 0
      expectedCount = 1
    if nums.length != expectedCount
      return "You submitted #{nums.length} cards, #{expectedCount} expected."
    for i in [0...nums.length] by 1
      if nums[i] >= db.hands[sender(msg)].length
        return "#{nums[i]} is not a valid card number."
    for i in [0...nums.length] by 1
      for j in [i+1...nums.length] by 1
        if nums[i] == nums[j]
          return "You cannot submit a single card more than once."
    submit_answer(name, nums)
    return "Submission accepted.",
  answers: (name) ->
    if name != db.czar
      return "Only the Card Czar may see the white card submissions."
    if db.answers.length < db.activePlayers
      return "Some players haven't yet submitted their choice."

    responseString = "White card submissions thus far:"
    for answer in db.answers
      cards = answer.cards
      id = answer.id
      responseString += "\n#{id}: #{generate_phrase(db.blackCard, cards)}"
    return responseString,
  choose: (name, num) ->
    if sender(msg) != db.czar
      return "Only the Card Czar may choose a winner."
    if db.answers.length < db.activePlayers.length
      return "Some players have not submitted their answer yet."

    i = 0
    for answer in answers
      if answer.id == num
        return czar_choose_winner(num)
      else
        i += 1
    return "That is not an valid choice, try again.",
  status: () -> return game_state_string(),
  skip: () -> return czar_choose_winner -1,
}

# web application
var express = require('express');
var app = express();
app.get('/cah', function (req, res) {
  res.send('Hello World!');
});

var server = app.listen(80, function () {
  var host = server.address().address;
  var port = server.address().port;
});

# hubot application
module.exports = (robot) ->

  robot.respond /cah help$/i, (msg) ->
    msg.send cah_commands.help()

  robot.respond /cah black$/i, (msg) ->
    msg.send cah_commands.black()

  robot.respond /cah white$/i, (msg) ->
    msg.send cah_commands.white()

  robot.respond /cah play$/i, (msg) ->
    name = sender(msg)
    robot.messageRoom name, cah_commands.play(name)

  robot.respond /cah retire$/i, (msg) ->
    name = sender(msg)
    robot.messageRoom name, cah_commands.remove(name)

  robot.respond /cah czar$/i, (msg) ->
    msg.send cah_commands.czar()

  robot.respond /cah players$/i, (msg) ->
    msg.send cah_commands.players()

  robot.respond /cah leaders$/i, (msg) ->
    msg.send cah_commands.leaders()

  robot.respond /cah score$/i, (msg) ->
    msg.reply cah_commands.score(sender(msg))

  robot.respond /cah hand$/i, (msg) ->
    name = sender(msg)
    robot.messageRoom name, cah_commands.hand(name)

  robot.respond /cah submit(?: ([0-4]+))+$/i, (msg) ->
    name = sender(msg)
    numString = msg.match[0].split("submit ")[1]
    nums = numString.split(" ")
    for i in [0...nums.length] by 1
      nums[i] = parseInt(nums[i])
    msg.reply cah_commands.submit(name, nums)

  robot.respond /cah answers$/i, (msg) ->
    name = sender(msg)
    robot.messageRoom name, cah_commands.answers(name)

  robot.respond /cah choose ([0-9]+)$/i, (msg) ->
    name = sender(msg)
    num = parseInt(msg.match[1])
    robot.reply cah_commands.choose(name, num)

  robot.respond /cah status$/i, (msg) ->
    msg.send cah_commands.status

  robot.respond /cah skip$/i, (msg) ->
    msg.send cah_commands.skip
