-- Chicken Smash Mod for Trailmakers, ticibi 2022
-- name: Chicken Smash
-- author: ticibi
-- description: 

--[[ 
    Improvements made:
    - Consistent naming conventions.
    - Timer updates are handled once per frame.
    - Utility functions now use ipairs for deterministic iteration.
    - Added duplicate-check when a player joins a match.
    - More inline comments for clarity.
]]

local debug = false
local chickenModel = "PFB_Runner"

local audioCues = {
    finish = "LvlObj_ConfettiCelebration",
    begin  = "LvlObj_BlockHunt_begin",
    boop   = "LvlObj_BlockHunt_Beacon_callingSound",
}

local spawnValueIncrements    = {10, 15, 20, 25}
local radiusValueIncrements   = {50, 75, 100, 150}
local detectionValueIncrements= {1, 2, 3, 4}
local maxValueIncrements      = {50, 100, 150, 200}

local globalTimer = 0
local localTimer  = 0

local playerDataTable = {}
local matchDataTable = {
    players = {},
    entities = {},
    hostId = nil,
    matchTimer = 20,
    matchTimerDefault = 20,
    timer = 12,
    timerDefault = 12,
    hasMatchBeenCreated = false,
    hasMatchFinished = false,
    hasMatchStarted = false,
    isWaitingForPlayersToJoin = false,
    maxEntityCount = 100,
    spawnRadius = 50,
    spawnQuantity = 15,
    spawnInterval = 1,
    entitiesSmashed = 0,
    collisionDetectionThreshold = 2,
}

-------------------- Utility Functions --------------------

-- Normalize playerId (handles both number and table with playerId field)
local function normalizePlayerId(player)
    if type(player) == "number" then 
        return player 
    elseif type(player) == "table" and player.playerId then 
        return player.playerId 
    end
    return nil
end

-- Returns the index of a value in a sequential table using ipairs.
local function getTableValueIndex(tbl, value)
    for i, v in ipairs(tbl) do
        if v == value then
            return i
        end
    end
    return nil
end

local function randomChoice(tbl)
    return tbl[math.random(#tbl)]
end

local function varianceVector(limit)
    return tm.vector3.Create(
        math.random(-limit, limit), 
        0, 
        math.random(-limit, limit)
    )
end

-------------------- Player Data Management --------------------

function addPlayerData(playerId)
    playerDataTable[playerId] = {
        isReady = true,
        isWinner = false,
        isInMatch = false,
        hiscore = 0,
        score = 0,
        stats = {smashed = 0, totalScore = 0, hiscore = 0, matches = 0},
        prefs = {autoJoin = true},
    }
end

function savePlayerData(playerId)
    local playerData = playerDataTable[playerId]
    local saveData = {
        totalScore = playerData.stats.totalScore,
        matches    = playerData.stats.matches,
        hiscore    = playerData.stats.hiscore,
        smashed    = playerData.stats.smashed,
    }
    local jsonData = json.serialize(saveData)
    tm.os.WriteAllText_Dynamic("myStats", jsonData)
end

function loadPlayerData(playerId)
    local file = tm.os.ReadAllText_Dynamic("myStats")
    if file == "" then
        return
    end
    local data = json.parse(file)
    if data then
        local playerData = playerDataTable[playerId]
        playerData.stats.totalScore = data.totalScore
        playerData.stats.matches    = data.matches
        playerData.stats.hiscore    = data.hiscore
        playerData.stats.smashed    = data.smashed
    end
end

-------------------- Player & UI Initialization --------------------

function onPlayerJoined(player)
    local playerId = player.playerId
    tm.os.Log(tm.players.GetPlayerName(playerId) .. " joined the server")
    addPlayerData(playerId)
    loadPlayerData(playerId)
    initializeUI(playerId)
end

function initializeUI(playerId)
    HomePage(playerId)
end

-------------------- Main Update Loop --------------------

function update()
    local playerList = tm.players.CurrentPlayers()
    -- Update timers once per frame
    updateTimers()
    
    -- Handle match and collision logic per player
    for _, player in pairs(playerList) do
        local playerId = player.playerId
        
        if localTimer > 10 then
            if matchDataTable.isWaitingForPlayersToJoin then
                startLobbyCountdown(playerId)
            end
            if matchDataTable.hasMatchStarted then
                startMatchLoop(playerId)
            end
            if matchDataTable.hasMatchFinished then
                startMatchEndCountdown(playerId)
            end
        end
        
        if matchDataTable.hasMatchStarted then
            checkForEntityCollision(playerId)
        end
    end
end

-- Update timer counters and (if debug) update UI for each player
function updateTimers()
    localTimer = localTimer + 1
    if debug then
        globalTimer = globalTimer + 1
        -- Update global debug info for every current player
        for _, player in ipairs(tm.players.CurrentPlayers()) do
            SetValue(player.playerId, "globaltime", "time: " .. (globalTimer/10))
        end
    end
end

tm.players.OnPlayerJoined.add(onPlayerJoined)

-------------------- Game Logic --------------------

function startMatchLoop(playerId)
    if matchDataTable.matchTimer > 1 then
        if #matchDataTable.entities < 1 then
            spawnEntity(playerId, chickenModel, matchDataTable.spawnQuantity)
        end
        matchDataTable.matchTimer = matchDataTable.matchTimer - 1
        SetValue(playerId, "countdown", matchDataTable.matchTimer .. " seconds remaining!") 
    else
        onMatchFinished()
    end
end

function startLobbyCountdown(playerId)
    if matchDataTable.timer > 1 then
        matchDataTable.timer = matchDataTable.timer - 1
        SetValue(playerId, "countdown", matchDataTable.timer .. " seconds") 
    else
        local player = tm.players.GetPlayerGameObject(playerId)
        tm.audio.PlayAudioAtGameobject(audioCues.begin, player)
        matchDataTable.matchTimer = matchDataTable.matchTimerDefault
        matchDataTable.isWaitingForPlayersToJoin = false
        matchDataTable.hasMatchStarted = true
        MatchLobbyPage(playerId)
    end
end

function startMatchEndCountdown(playerId)
    if matchDataTable.timer > 1 then
        matchDataTable.timer = matchDataTable.timer - 1
        tm.playerUI.SetUIValue(playerId, "countdown", matchDataTable.timer .. " seconds") 
    else
        -- Reset match state and clear players and entities
        matchDataTable.hasMatchFinished = false
        matchDataTable.matchTimer = matchDataTable.matchTimerDefault
        matchDataTable.timer = matchDataTable.timerDefault
        matchDataTable.hostId = nil
        matchDataTable.entitiesSmashed = 0
        for _, pId in ipairs(matchDataTable.players) do
            playerDataTable[pId].score = 0
            HomePage(pId)
        end
        matchDataTable.players = {}
        matchDataTable.entities = {}
    end
end 

function onMatchFinished()
    matchDataTable.hasMatchStarted = false
    matchDataTable.hasMatchFinished = true
    matchDataTable.hasMatchBeenCreated = false
    tm.audio.PlayAudioAtPosition(audioCues.finish, tm.vector3.Create(), 1)
    matchDataTable.timer = matchDataTable.timerDefault
    matchDataTable.isWaitingForPlayersToJoin = false
    
    for _, playerId in ipairs(matchDataTable.players) do
        local playerData = playerDataTable[playerId]
        playerData.stats.matches = playerData.stats.matches + 1
        if playerData.score > playerData.stats.hiscore then
            playerData.stats.hiscore = playerData.score
        end
        savePlayerData(playerId)
        MatchLobbyPage(playerId)
    end

    -- Stop audio and despawn any remaining chicken entities
    for _, chicken in ipairs(matchDataTable.entities) do
        if chicken.Exists() then
            tm.audio.StopAllAudioAtGameobject(chicken)
            chicken.Despawn()
        end
    end
end

function onSmashEntity(playerId)
    local playerData = playerDataTable[playerId]
    playerData.score = playerData.score + 1
    playerData.stats.totalScore = playerData.stats.totalScore + 1
    playerData.stats.smashed = playerData.stats.smashed + 1
    for _, otherPlayer in pairs(matchDataTable.players) do
        local name = tm.players.GetPlayerName(playerId)
        tm.playerUI.SetUIValue(otherPlayer, "score_" .. playerId, name .. " - " .. playerData.score .. " pts") 
    end 
end
    
function checkForEntityCollision(playerId)
    if #matchDataTable.entities < 1 then
        return
    end
    local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
    for _, chicken in ipairs(matchDataTable.entities) do
        local chickenPos = chicken.GetTransform().GetPosition()
        local deltaPos = tm.vector3.op_Subtraction(playerPos, chickenPos)
        if deltaPos.Magnitude() < matchDataTable.collisionDetectionThreshold then
            onSmashEntity(playerId)
            tm.audio.StopAllAudioAtGameobject(chicken)
            matchDataTable.entitiesSmashed = matchDataTable.entitiesSmashed + 1
        end
    end
end

function spawnEntity(playerId, model, quantity)
    if #matchDataTable.entities < matchDataTable.maxEntityCount then
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        for i = 1, quantity do
            local variance = varianceVector(matchDataTable.spawnRadius)
            local spawnCoords = tm.vector3.op_Addition(playerPos, variance)
            local chicken = tm.physics.SpawnObject(spawnCoords, model)
            table.insert(matchDataTable.entities, chicken)
        end
    end
end

-------------------- UI Helper Functions --------------------

function SetValue(playerId, key, text)
    tm.playerUI.SetUIValue(playerId, key, text)
end

function Broadcast(key, value)
    for _, player in ipairs(tm.players.CurrentPlayers()) do
        SetValue(player.playerId, key, value)
    end
end

function Clear(playerId)
    tm.playerUI.ClearUI(playerId)
end

function Label(playerId, key, text)
    tm.playerUI.AddUILabel(playerId, key, text)
end

function Divider(playerId)
    Label(playerId, "divider", "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬")
end

function Button(playerId, key, text, func)
    tm.playerUI.AddUIButton(playerId, key, text, func)
end

-------------------- UI Pages --------------------

function HomePage(player)
    local playerId = normalizePlayerId(player)
    Clear(playerId)
    if matchDataTable.hasMatchBeenCreated then
        local hostName = tm.players.GetPlayerName(matchDataTable.hostId)
        Label(playerId, "host", hostName .. " is hosting a match!")
        Button(playerId, "joinmatch", "join match", MatchLobbyPage)
    else
        Button(playerId, "makematch", "start a match", onCreateMatch)
    end
    Button(playerId, "mystats", "my stats", StatisticsPage)
    if debug then 
        Label(playerId, "globaltime", "time: " .. globalTimer) 
    end
end

function MatchLobbyPage(player)
    local playerId = normalizePlayerId(player)
    Clear(playerId)
    if matchDataTable.isWaitingForPlayersToJoin then
        Label(playerId, "title", "Get in your vehicles!")
        Label(playerId, "subtitle", "The match will start in...")
    elseif matchDataTable.hasMatchFinished then
        Label(playerId, "title", "Match Complete!")
        Label(playerId, "subtitle", "Ending in...")
    elseif matchDataTable.hasMatchStarted then
        Label(playerId, "title", "SMASH THE CHICKENS!")
    else
        Label(playerId, "title", "-")
    end

    if not matchDataTable.hasMatchFinished or matchDataTable.hasMatchFinished then
        Label(playerId, "countdown", matchDataTable.timer .. "s")
    end

    if matchDataTable.isWaitingForPlayersToJoin then
        Label(playerId, "lobbyHeader", "Lobby:")
        for _, id in ipairs(matchDataTable.players) do
            local name = tm.players.GetPlayerName(id)
            if id == matchDataTable.hostId then
                Label(playerId, "lobbylist", name .. " (host)")
            else
                Label(playerId, "lobbylist", name)
            end
        end
    else
        Label(playerId, "scoreHeader", "Leaderboard:")
        for _, id in ipairs(matchDataTable.players) do
            local playerData = playerDataTable[id]
            local name = tm.players.GetPlayerName(id)
            if playerData.isWinner then
                Label(playerId, "score_" .. id, name .. " - " .. playerData.score .. " pts HIGHEST SCORE")
                playerData.isWinner = false
            else
                Label(playerId, "score_" .. id, name .. " - " .. playerData.score .. " pts")
            end
        end
    end

    if playerId == matchDataTable.hostId and matchDataTable.isWaitingForPlayersToJoin then
        Button(playerId, "matchsettings", "match settings", MatchSettingsPage)
    end
end

function StatisticsPage(player)
    local playerId = normalizePlayerId(player)
    local playerData = playerDataTable[playerId]
    Clear(playerId)
    Label(playerId, "My Stats")
    Label(playerId, "hiscore", "hiscore: " .. playerData.stats.hiscore)
    Label(playerId, "smashed", "chickens smashed: " .. playerData.stats.smashed)
    Label(playerId, "matches", "matches played: " .. playerData.stats.matches)
    Button(playerId, "back", "back", HomePage)
end

function MatchSettingsPage(callbackData)
    local playerId = normalizePlayerId(callbackData)
    Clear(playerId)
    Label(playerId, "waiting", "Waiting for match to start in...")
    Label(playerId, "countdown", matchDataTable.timer .. "s")
    Label(playerId, "Match Settings")
    Button(playerId, "spawnradius", "spawn radius: " .. matchDataTable.spawnRadius, cycleSpawnValues)
    Button(playerId, "spawnquantity", "spawn quantity(per player): " .. matchDataTable.spawnQuantity, cycleSpawnQuantity)
    Button(playerId, "maxentitycount", "max spawns: " .. matchDataTable.maxEntityCount, cycleMaxEntityCount)
    Button(playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault, cycleMatchTime)
    Button(playerId, "back", "back", MatchLobbyPage)
end

-------------------- UI Callback Functions --------------------

-- Generic callback template to cycle through preset values.
function callbackTemplate(callbackData, tbl, uiTag, uiText)
    local playerId = normalizePlayerId(callbackData)
    local currentIndex = getTableValueIndex(tbl, matchDataTable[uiTag])
    currentIndex = currentIndex or 0
    local nextIndex = (currentIndex % #tbl) + 1
    matchDataTable[uiTag] = tbl[nextIndex]
    SetValue(playerId, uiTag, uiText .. tbl[nextIndex])
end

function cycleDetectionThreshold(callbackData)
    callbackTemplate(callbackData, detectionValueIncrements, "collisionDetectionThreshold", "detection radius: ")
end

function cycleMaxEntityCount(callbackData)
    callbackTemplate(callbackData, maxValueIncrements, "maxEntityCount", "max spawns: ")
end

function cycleSpawnValues(callbackData)
    callbackTemplate(callbackData, radiusValueIncrements, "spawnRadius", "spawn radius: ")
end

function cycleSpawnQuantity(callbackData)
    callbackTemplate(callbackData, spawnValueIncrements, "spawnQuantity", "spawn quantity(per player): ")
end

function cycleMatchTime(callbackData)
    local playerId = normalizePlayerId(callbackData)
    if matchDataTable.matchTimerDefault < 120 then
        matchDataTable.matchTimerDefault = matchDataTable.matchTimerDefault + 10
    else
        matchDataTable.matchTimerDefault = 10
    end
    SetValue(playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault)
end

function onCreateMatch(callbackData)
    local playerId = normalizePlayerId(callbackData)
    if matchDataTable.hostId == nil and not matchDataTable.hasMatchBeenCreated then
        local playerObject = tm.players.GetPlayerGameObject(playerId)
        tm.audio.PlayAudioAtGameobject(audioCues.boop, playerObject)
        tm.physics.ClearAllSpawns()
        matchDataTable.hasMatchBeenCreated = true
        matchDataTable.isWaitingForPlayersToJoin = true
        matchDataTable.hostId = playerId
        onJoinMatch(playerId)
        MatchLobbyPage(playerId)
    end
    -- Auto join all players with the autoJoin preference (avoid duplicates)
    for _, player in ipairs(tm.players.CurrentPlayers()) do
        local pid = player.playerId
        if pid ~= matchDataTable.hostId and playerDataTable[pid].prefs.autoJoin then
            onJoinMatch(pid)
        end
    end
end

function onJoinMatch(player)
    local playerId = normalizePlayerId(player)
    -- Check if the player is already in the match
    for _, pid in ipairs(matchDataTable.players) do
        if pid == playerId then return end
    end
    table.insert(matchDataTable.players, playerId)
    local playerObject = tm.players.GetPlayerGameObject(playerId)
    tm.audio.PlayAudioAtGameobject(audioCues.boop, playerObject)
    -- Refresh UI for all players
    for _, player in ipairs(tm.players.CurrentPlayers()) do
        MatchLobbyPage(player.playerId)
    end
end

function onEndMatch(callbackData)
    matchDataTable.hostId = nil
    matchDataTable.hasMatchBeenCreated = false
    matchDataTable.isWaitingForPlayersToJoin = false
end
