-- GambleHelp.lua: in-game instructions for Gamble sessions.
local ns = _G.NaowhForever

ns.GambleHelpText = [[HOW TO PLAY

SET UP A SESSION
Enter the pool in gold-and-silver format: an integer followed by "g", then an integer followed by "s" (for example, 10g50s). One gold is 100 silver, so 10g50s is 1,050 silver. All roll limits use the pool's total silver value. Party and Raid chat are supported; choose the channel your group is using. Both pool components must be whole numbers.

Select New Game to announce the session. Players, including the host, join by saying the configured join word in the selected chat. They can leave the lobby by saying the leave word. The host can use Last Call to remind the group, then select Start Rolling once at least two players have joined.

CLASSIC
When the host selects Start Rolling, chat announces that everyone can roll and gives the roll limit. Every joined player rolls from 1 to the pool's total silver value using /roll. With a 10g50s pool, each player rolls from 1 to 1,050. Use Announce Rolls to remind players who still need to roll and show the roll range.

When everyone has rolled, the player with the lowest roll pays the player with the highest roll the difference between those original rolls. The difference is silver and is announced in gold-and-silver format (for example, 50 silver is shown as 0g50s). If the highest or lowest roll is tied, only the players tied at that extreme reroll to decide that side's winner or loser. The original high and low rolls determine the amount, even if a tie-break roll changes the order. If every player rolls the same number, nobody pays and everyone rolls again.

DEATHROLL
After the host starts the game, two joined players are selected at random. Gamble announces the selected players, then announces which one was randomly chosen to roll first.

The first player rolls from 1 to the pool's total silver value. With a 10g50s pool, the first roll is from 1 to 1,050. The two selected players then alternate: after each roll, the next player rolls from 1 to the value just rolled. Use Announce Rolls to identify whose turn it is and the current roll range. The first player to roll 1 loses; the other player wins the pool, announced in gold-and-silver format.

ENDING A SESSION
The host can select Cancel Session at any time before the session completes. The cancellation is announced in chat and the session ends for everyone. Completed sessions cannot be cancelled.

Gamble only announces results; it does not transfer gold. Players settle any announced amount themselves.]]
