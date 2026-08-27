-------------------------------------------------------------------------------
--  NaowhUI_SmartReminders_Abilities.lua -- tank busters the game does not flag.
--
--  GENERATED. Regenerate rather than hand-editing.
--
--  This addon reads everything else out of the player's own client on purpose, and this
--  file is the one deliberate exception. The reason is measured, not assumed.
--
--  The engine-played callout is registered against every catalogue ability carrying
--  Blizzard's TankRole bit. Checked against a live 870-event catalogue: of the 31 boss
--  tank busters in this season's pool, 23 exist in that catalogue and only 13 carry the
--  bit. So the bit alone is correctly silent on nearly half of them, and correct silence
--  is indistinguishable from a broken feature from where the player is sitting.
--
--  So this list is ADDITIVE and never a replacement. An ability is called if Blizzard
--  says so OR this list does, which means the feature keeps working unchanged on content
--  this file has never heard of.
--
--  Keyed by SPELL ID, not by encounterEventID. Event ids are a client-side index that can
--  be reallocated between builds; a spell id is stable, and the catalogue is plain so the
--  join happens at runtime on the player's own client.
--
--  The value is the DAMAGE TYPE rather than a flag, because which defensive helps depends
--  on whether the hit is physical or magical, and a later version can use it to choose.
--
--  Ability classification is derived from Tactyks' public Season 2 dungeon spreadsheet.
--  Spell ids and names are Blizzard's own.
-------------------------------------------------------------------------------
local ns = _G.NaowhUITankReminder
if not ns then return end

ns.TANK_ABILITIES = {
    -- Every id below was audited against the installed BigWigs/LittleWigs and DBM module
    -- source on 2026-08-26. Ids NEITHER mod ever broadcasts were removed (Frigid Shard
    -- 372808, Chaos Barrage 1230298, Warden's Wrath 1239821, Forceful Slam 1297797,
    -- Heart Attack 268007, Tainted Strike 1303446 -- aura-sound only in BigWigs, a TODO
    -- in DBM -- and Searing Beak's aura twin 466091), since the engine can only fire on
    -- a broadcast key. Do not re-add them from the sheet without rechecking the modules.
    [265910] = "Physical",   -- The Golden Serpent: Tail Thrash
    [266237] = "Physical",   -- The Council of Tribes: Debilitating Backhand
    [268586] = "Physical",   -- Dazar, The First King: Blade Combo
    [372858] = "Mixed",   -- Kokia Blazehoof: Searing Blows
    [381512] = "Mixed",   -- Kyrakka and Erkhart Stormvein: Stormslam
    [473898] = "Physical",   -- Xathuux the Annihilator: Legion Strike
    [1222642] = "Magical",   -- Atroxus: Hulking Claw
    [1222795] = "Mixed",   -- Zaen Bladesorrow: Envenom
    [1234753] = "Mixed",   -- Lightblossom Trinity: Bedrock Slam
    [1247685] = "Mixed",   -- Ziekket: Thornspike
    [1311804] = "Mixed",   -- Adderis and Aspix: Overload (was 1288428; BigWigs bars 1311804)
    [1290797] = "Mixed",   -- Merektha: Lightning Bite
    [1296220] = "Magical",   -- Rav'i: Triple Shot
    [1297017] = "Magical",   -- Taz'Rah: Void Blast
    [1298949] = "Physical",   -- The Writhing Coil: Tail Scythe
    [1301350] = "Physical",   -- Zul'jan: Chop Down
    [269230] = "Physical",   -- Dazar, The First King: Hunting Leap (was aura id 1303039)
    [1303488] = "Physical",   -- Dazar, The First King: Savage Maul (was aura id 1303490)
    [1311923] = "Magical",   -- Charonus: Dark Waves

    -- Marked as tank hits in publicly available community boss research; damage
    -- type not recorded there, so it is Unknown until observed.
    [466064] = "Unknown",   -- Emberdawn: Searing Beak
    [1241692] = "Unknown",   -- Vorasius: Shadowclaw Slam
    [467620] = "Unknown",   -- Commander Kro'luk: Rampage
    [472888] = "Unknown",   -- Derelict Duo: Bone Hack
    [1247937] = "Unknown",   -- Nysarra: Void Gash
    [1251023] = "Unknown",   -- Rak'tul: Spiritbreaker
    [1251554] = "Unknown",   -- Vor'daza: Drain Soul
    [1253950] = "Unknown",   -- Emberdawn: Searing Rend
    [1268562] = "Unknown",   -- Nymrissa Wavecaller: Water Jet (Mythic only)
    [1267049] = "Unknown",   -- Midnight Falls: Heaven's Lance
    [1221781] = "Unknown",   -- Rotmire: Putrid Fist
    [1233787] = "Unknown",   -- Crown of the Cosmos: Dark Hand
    [1245645] = "Unknown",   -- Vaelgor & Ezzorak: Rakfang
    [1246461] = "Unknown",   -- Crown of the Cosmos: Rift Slash
    [1246736] = "Unknown",   -- Lightblinded Vanguard: Judgement
    [1251857] = "Unknown",   -- Lightblinded Vanguard: Judgement
    [1262623] = "Unknown",   -- Vaelgor & Ezzorak: Nullbeam
    [1265131] = "Unknown",   -- Vaelgor & Ezzorak: Vaelwing
    [1280458] = "Unknown",   -- Vaelgor & Ezzorak: Grappling Maw
    [1280935] = "Unknown",   -- Vashnik the Malignant: Dripping Fangs
    [1284458] = "Unknown",   -- Entombed Sentinels: Empowering Slam
    [1284487] = "Unknown",   -- Entombed Sentinels: Bloodvenom Injection
    [1288538] = "Unknown",   -- The Twin Fangs: Stone Breaker
    [1295854] = "Unknown",   -- The Lost Explorers: Shredding Shards
    [1250803] = "Unknown",   -- Fallen-King Salhadaar: Shattering Twilight
    [1260763] = "Unknown",   -- Belo'ren, Child of Al'ar: Guardian's Edict
    [1277025] = "Unknown",   -- Sszorak: Apex Predator
    [1286573] = "Unknown",   -- The Coiled Altar: Soul Sever
    [1299680] = "Unknown",   -- The Coiled Altar: Sever
    [1307279] = "Unknown",   -- The Coiled Altar: Blighted Sever
    -- 1284103 (the debuff aura, BigWigs' own soundOnApplied trigger) never reaches
    -- BigWigs_Message/StartBar -- confirmed against BigWigs_TheVenomousAbyss/Nekzali.lua.
    -- The bar it actually fires (self:Bar) is keyed by 1292036, so that is the id this
    -- addon has to match against.
    [1292036] = "Unknown",   -- Nek'zali the Soulcoiler: Possession Barrage
    -- Hollowing Strikes (1284110, stacking debuff) deliberately NOT here: still a real
    -- tank mechanic (its own Tank role tag in Setup comes straight off the live journal
    -- scrape, independent of this table), just default OFF rather than auto-enabled --
    -- flip it on per-boss from Setup's own checkbox if wanted.

    -- Tank hits the community modules gate on a tank role check in code rather than
    -- flagging on the ability, which is why the sheet-derived rows above never carried
    -- them. Found by auditing every Midnight party module for that gate (2026-08-20)
    -- after Den of Nalorakk called nothing at all for a whole dungeon.
    [472662] = "Unknown",   -- The Restless Heart: Tempest Slash
    [474496] = "Unknown",   -- Arcanotron Custos: Repulsing Slam
    [1243569] = "Unknown",   -- Nalorakk: Overwhelming Onslaught
    [1266480] = "Unknown",   -- Murojin and Nekraxx: Flanking Spear
    [1280113] = "Unknown",   -- Degentrius: Hulking Fragment
    -- Classified but NOT fingerprintable from the modules: Ula'tek drives this off
    -- Blizzard event ids rather than bar durations, so there is no duration to key on.
    -- Needs /nutank learn then /nutank tank on a real pull.
    [1298367] = "Unknown",   -- Ula'tek: Mother's Wrath
}

-- BigWigs broadcasts its stable option key, which is not always the id the Dungeon
-- Journal lists for the same mechanic -- and Setup's per-ability store is keyed by the
-- journal id. Broadcast key -> journal id for the confirmed mismatches, so the engine
-- can still find the player's Setup choices for them.
ns.BOSSMOD_KEY_TO_JOURNAL = {
    [1292036] = 1284103,   -- Nek'zali the Soulcoiler: Possession Barrage
}

-- DBM keys some of the same warnings by a different spell id than BigWigs, usually the
-- debuff/aura id (Possession Barrage's is deliberate on DBM's side: 1292036 has no
-- tooltip, their module says so). The engine, the curated list and Setup's rows all
-- speak BigWigs ids, so DBM timer ids are normalized through this map before
-- ns.HandleBigWigsAbility. DBM's Emberdawn module tracks no Searing Rend at all, so
-- 1253950 stays BigWigs-only.
ns.DBM_TO_BIGWIGS = {
    [1241836] = 1241692,   -- Vorasius: Shadowclaw Slam
    [1288484] = 1288538,   -- The Twin Fangs: Stone Breaker
    [1253024] = 1250803,   -- Fallen-King Salhadaar: Shattering Twilight
    [1287227] = 1307279,   -- The Coiled Altar: Blighted Sever
    [1284103] = 1292036,   -- Nek'zali the Soulcoiler: Possession Barrage
}

-- Some BigWigs bars are driven purely by the encounter timeline (a scripted countdown
-- matched by rounded duration, ENCOUNTER_TIMELINE_EVENT_ADDED) rather than any spell
-- cast -- confirmed against BigWigs_TheVenomousAbyss/TwinFangs.lua and CoiledAltar.lua,
-- both self:CDBar(barInfo.key, ...) off duration matching alone, no cast involved at
-- all. castSourceGUID (fed only by SPELL_CAST_START/SUCCESS) can never learn a caster
-- for these, so TankingCaster's "nocache" path always fell back to "tanking ANY boss" --
-- wrong the moment two boss units are alive at once and each tank holds a different one
-- (reported live on both The Twin Fangs and The Coiled Altar P2/P3). Mapped to the real
-- npcID straight off BigWigs' own RegisterEnableMob instead, since there is no cast
-- event to key a GUID capture off in the first place.
ns.TANK_ABILITY_OWNER_NPCID = {
    [1288538] = 257368,   -- The Twin Fangs: Stone Breaker (Ithraz)
    [1299680] = 257911,   -- The Coiled Altar: Sever (Zul'jan)
    [1286573] = 259854,   -- The Coiled Altar: Soul Sever (Hex Lord Malacrass)
    [1307279] = 259854,   -- The Coiled Altar: Blighted Sever (Hex Lord Malacrass)
}

