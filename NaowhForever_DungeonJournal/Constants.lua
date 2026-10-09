-- Constants.lua: the numbers several Dungeon Journal files share (J.C).
local ns = _G.NaowhForever

local C = {}
ns.Journal.C = C

C.QUEST = { ID = 1, NAME = 2, LEVEL = 3, SIDE = 4, SHAREABLE = 5, WHERE = 6, MAP = 7, X = 8, Y = 9 }
C.PERCENT = 100
C.ROUND_HALF = 0.5
C.BYTE, C.HEX_BASE = 255, 16
C.SECONDS_PER_MINUTE = 60
C.ITEM_ARMOR, C.ITEM_RECIPE = 4, 9
C.STRIPE_EVERY = 2
C.MAP_W, C.MAP_H = 1002, 668
C.MAP_ART = "Interface\\WorldMap\\%s\\%s%d_%d"
