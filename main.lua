-- Chicken Smash Mod for Trailmakers, ticibi 2022
-- name: Chicken Smash
-- author: Thomas Bresee
-- description: 


local debug = false
local chickenModel = "PFB_Runner"
local audioCues = {
    finish="LvlObj_ConfettiCelebration",
    begin="LvlObj_BlockHunt_begin",
    boop="LvlObj_BlockHunt_Beacon_callingSound",
}
local spawnValueIncrements = {10, 15, 20, 25}
local radiusValueIncrements = {50, 75, 100, 150}
local detectionValueIncrements = {1, 2, 3, 4}
local maxValueIncrements = {50, 100, 150, 200}

local globalTimer = 0
local localTimer = 0
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

-------------------- init --------------------

function addPlayerData(playerId)
    playerDataTable[playerId] = {
        isReady = true,
        isWinner = false,
        isInMatch = false,
        hiscore = 0,
        score = 0,
        stats = {smashed=0, totalScore=0, hiscore=0, matches=0},
        prefs = {autoJoin=true},
    }
end

function savePlayerData(playerId)
    local playerData = playerDataTable[playerId]
    local saveData = {
        totalScore = playerData.stats.totalScore,
        matches = playerData.stats.matches,
        hiscore = playerData.stats.hiscore,
        smashed = playerData.stats.smashed,
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
    playerData = playerDataTable[playerId]
    playerData.stats.totalScore = data.totalScore
    playerData.stats.matches = data.matches
    playerData.stats.hiscore = data.hiscore
    playerData.stats.smashed = data.smashed
end

function onPlayerJoined(player)
    tm.os.Log(tm.players.GetPlayerName(player.playerId) .. " joined the server")
    addPlayerData(player.playerId)
    loadPlayerData(player.playerId)
    initializeUI(player.playerId)
end

function initializeUI(playerId)
    homePage(playerId)
end

function update()
    local playerList = tm.players.CurrentPlayers()
    for _, player in pairs(playerList) do
        if localTimer > 10 then
            if matchDataTable.isWaitingForPlayersToJoin then
                startLobbyCountdown(player.playerId)
            end
            if matchDataTable.hasMatchStarted then
                startMatchLoop(player.playerId)
            end
            if matchDataTable.hasMatchFinished then
                startMatchEndCountdown(player.playerId)
            end
            localTimer = 0
        end
        if matchDataTable.hasMatchStarted then
            checkForEntityCollision(player.playerId)
        end
        updateTimers()
    end
end

function updateTimers()
    localTimer = localTimer + 1
    if debug then
        globalTimer = globalTimer + 1
        SetValue(player.playerId, "globaltime", "time: " .. globalTimer/10)
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
        matchDataTable.hasMatchFinished = false
        matchDataTable.matchTimer = matchDataTable.matchTimerDefault
        matchDataTable.timer = matchDataTable.timerDefault
        matchDataTable.hostId = nil
        matchDataTable.entitiesSmashed = 0
        for _, pId in pairs(matchDataTable.players) do
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
    for _, playerId in pairs(matchDataTable.players) do
        playerDataTable[playerId].stats.matches = playerDataTable[playerId].stats.matches + 1
        if playerDataTable[playerId].score > playerDataTable[playerId].stats.hiscore then
            playerDataTable[playerId].stats.hiscore = playerDataTable[playerId].score
        end
        savePlayerData(playerId)
        MatchLobbyPage(playerId)
    end
    for _, chicken in pairs(matchDataTable.entities) do
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
    for _, player in pairs(matchDataTable.players) do
        local name = tm.players.GetPlayerName(playerId)
        tm.playerUI.SetUIValue(player, "score_" .. playerId, name .. " - " .. playerData.score .. " pts") 
    end 
end
    
function checkForEntityCollision(playerId)
    if #matchDataTable.entities < 1 then
        return
    end
    for _, chicken in pairs(matchDataTable.entities) do
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        local chickenPos = chicken.GetTransform().GetPosition()
        local deltaPos = tm.vector3.op_Subtraction(playerPos, chickenPos)
        if math.abs(deltaPos.Magnitude()) < matchDataTable.collisionDetectionThreshold then
            onSmashEntity(playerId)
            tm.audio.StopAllAudioAtGameobject(chicken)
            matchDataTable.entitiesSmashed = matchDataTable.entitiesSmashed + 1
        end
    end
end

function spawnEntity(playerId, model, quantity)
    if #matchDataTable.entities < matchDataTable.maxEntityCount then
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        for i=1, quantity do
            local variance = varianceVector(matchDataTable.spawnRadius)
            local spawnCoords = tm.vector3.op_Addition(playerPos, variance)
            local chicken = tm.physics.SpawnObject(spawnCoords, model)
            table.insert(matchDataTable.entities, chicken)
        end
    end
end

-----------------------------------------------------------------------
-----------------------------------------------------------------------

function SetValue(playerId, key, text)
    tm.playerUI.SetUIValue(playerId, key, text)
end

function Broadcast(key, value)
    for i, player in ipairs(tm.players.CurrentPlayers()) do
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

function HomePage(playerId)
    if type(playerId) ~= "number" then
        playerId = playerId.playerId
    end
    Clear(playerId)
    if matchDataTable.hasMatchBeenCreated then
        local name = tm.players.GetPlayerName(matchDataTable.hostId)
        Label(playerId, "host", name .. " is hosting a match!") 
        Button(playerId, "joinmatch", "join match", MatchLobbyPage)
    else
        Button(playerId, "makematch", "start a match", onCreateMatch)
    end
    Button(playerId, "mystats", "my stats", StatisticsPage)
    if debug then Label(playerId, "globaltime", "time: " .. globalTimer) end
end

function MatchLobbyPage(playerId)
    if type(playerId) ~= "number" then
        playerId = playerId.playerId
    end
    Clear(playerId)
    if matchDataTable.isWaitingForPlayersToJoin then
        Label(playerId, "Get in your vehicles!")
        Label(playerId, "The match will start in...")
    elseif matchDataTable.hasMatchFinished then
        Label(playerId, "Match Complete!")
        Label(playerId, "Ending in...")
    elseif matchDataTable.hasMatchStarted then
        Label(playerId, "SMASH THE CHICKENS!")
    else
        Label(playerId, "-")
    end
    if not matchDataTable.hasMatchFinished or matchDataTable.hasMatchFinished then
        Label(playerId, "countdown", matchDataTable.timer .. "s")
    end
    if matchDataTable.isWaitingForPlayersToJoin then
        Label(playerId, "Lobby:")
    elseif matchDataTable.hasMatchFinished then
        Label(playerId, "Final Scores:")
    elseif matchDataTable.hasMatchStarted then
        Label(playerId, "Leaderboard:")
    else
        Label(playerId, "-")
    end
    if matchDataTable.isWaitingForPlayersToJoin then
        for i, id in ipairs(matchDataTable.players) do
            local name = tm.players.GetPlayerName(id)
            if id == matchDataTable.hostId then
                Label(playerId, "lobbylist", name .. " (host)")
            else
                Label(playerId, "lobbylist", name)
            end
        end
    else
        for i, id in ipairs(matchDataTable.players) do
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

function MatchSettingsPage(callbackData)
    local playerId = callbackData.playerId
    Clear(playerId)
    Label(playerId, "Waiting for match to start in...")
    Label(playerId, "countdown", matchDataTable.timer .. "s")
    Label(playerId, "Match Settings")
    Button(playerId, "spawnradius", "spawn radius: " .. matchDataTable.spawnRadius, cycleSpawnValues)
    Button(playerId, "spawnquantity", "spawn quantity(per player): " .. matchDataTable.spawnQuantity, cycleSpawnQuantity)
    Button(playerId, "maxentitycount", "max spawns: " .. matchDataTable.maxEntityCount, cycleMaxEntityCount)
    Button(playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault, cycleMatchTime)
    Button(playerId, "back", "back", MatchLobbyPage)
end

function StatisticsPage(callbackData)
    local playerId = callbackData.playerId
    local playerData = playerDataTable[playerId]
    Clear(playerId)
    Label(playerId, "My Stats")
    Label(playerId, "hiscore", "hiscore: " .. playerData.stats.hiscore)
    Label(playerId, "smashed", "chickens smashed: " .. playerData.stats.smashed)
    Label(playerId, "matches", "matches played: " .. playerData.stats.matches)
    Button(playerId, "back", "back", HomePage)
end

-------------------- UI Callbacks --------------------

function callbackTemplate(callbackData, table, maxValue, uiTag, uiText)
    local currentIndex = getTableValueIndex(table, maxValue)
    local nextIndex = currentIndex % #table + 1
    maxValue = table[nextIndex]
    SetValue(callbackData.playerId, uiTag, uiText .. maxValue)
end

function cycleDetectionThreshold(callbackData)
    callbackTemplate(
        callbackData, 
        detectionValueIncrements, 
        matchDataTable.collisionDetectionThreshold, 
        "detectionradius", 
        "detection radius: "
    )
end

function cycleMaxEntityCount(callbackData)
    callbackTemplate(
        callbackData, 
        maxValueIncrements, 
        matchDataTable.maxEntityCount, 
        "maxentitycount", 
        "max spawns: "
    )
end

function cycleSpawnValues(callbackData)
    callbackTemplate(
        callbackData, 
        radiusValueIncrements, 
        matchDataTable.spawnRadius, 
        "spawnradius", 
        "spawn radius: "
    )
end

function cycleSpawnQuantity(callbackData)
    callbackTemplate(
        callbackData, 
        spawnValueIncrements, 
        matchDataTable.spawnQuantity, 
        "spawnquantity", 
        "spawn quantity(per player): "
    )
end

function cycleMatchTime(callbackData)
    if matchDataTable.matchTimerDefault < 120 then
        matchDataTable.matchTimerDefault = matchDataTable.matchTimerDefault + 10
    else
        matchDataTable.matchTimerDefault = 10
    end
    SetValue(callbackData.playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault)
end

function onCreateMatch(callbackData)
    if matchDataTable.hostId == nil and not matchDataTable.hasMatchBeenCreated then
        local player = tm.players.GetPlayerGameObject(callbackData.playerId)
        tm.audio.PlayAudioAtGameobject(audioCues.boop, player)
        tm.physics.ClearAllSpawns()
        matchDataTable.hasMatchBeenCreated = true
        matchDataTable.isWaitingForPlayersToJoin = true
        matchDataTable.hostId = callbackData.playerId
        onJoinMatch(callbackData.playerId)
        MatchLobbyPage(callbackData.playerId)
    end
    for _, player in pairs(tm.players.CurrentPlayers()) do
        if player.playerId ~= matchDataTable.hostId and playerDataTable[player.playerId].prefs.autoJoin then
            onJoinMatch(player.playerId)
        end
    end
end

function onJoinMatch(playerId)
    table.insert(matchDataTable.players, playerId)
    local playerObject = tm.players.GetPlayerGameObject(playerId)
    tm.audio.PlayAudioAtGameobject(audioCues.boop, playerObject)
    for i, player in ipairs(tm.players.CurrentPlayers()) do
        MatchLobbyPage(player.playerId)
    end
end

function onEndMatch(callbackData)
    matchDataTable.hostId = nil
    matchDataTable.hasMatchBeenCreated = false
    matchDataTable.isWaitingForPlayersToJoin = false
end

-------------------- Utils --------------------

function getTableValueIndex(table, value)
    for i, v in pairs(table) do
        if v == value then
            return i
        end
    end
end

function randomChoice(table)
    return table[math.random(#table)]
end

function varianceVector(limit)
    return tm.vector3.Create(
        math.random(-limit, limit), 
        0, 
        math.random(-limit, limit)
    )
end
