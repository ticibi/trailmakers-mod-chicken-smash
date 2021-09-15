-- Chicken Smash Minigame
-- by dinoman/ticibi 2021

local audioCues = {
    finish="LvlObj_ConfettiCelebration",
    begin="LvlObj_BlockHunt_begin",
    boop="LvlObj_BlockHunt_Beacon_callingSound",
}
local chickenModel = "PFB_Runner"
local spawnValueIncrements = {10, 15, 20, 25}
local radiusValueIncrements = {50, 75, 100, 150}
local detectionValueIncrements = {1, 2, 3, 4}
local maxValueIncrements = {50, 100, 150, 200}
local globalTimer = 0
local localTimer = 0
local playerDataTable = {}
local matchData = {
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
    initializeUI_AndKeybinds(player.playerId)
    loadCustomResources()
end

function onPlayerLeft(player)
    --tm.os.Log(tm.players.GetPlayerName(player.playerId) .. " left the server")
end

function initializeUI_AndKeybinds(playerId)
    homePage(playerId)
    --tm.input.RegisterFunctionToKeyDownCallback(playerId, "" ,"")
    --tm.input.RegisterFunctionToKeyUpCallback(playerId, "", "")
end

function loadCustomResources()
    --tm.physics.AddMesh("", "")
    --tm.physics.AddTexture("", "")
end

function update()
    local playerList = tm.players.CurrentPlayers()
    for _, player in pairs(playerList) do   
        local playerData = playerDataTable[player.playerId]
        if localTimer > 10 then
            if matchData.isWaitingForPlayersToJoin then
                startLobbyCountdown(player.playerId)
            end
            if matchData.hasMatchStarted then
                startMatchLoop(player.playerId)
            end
            if matchData.hasMatchFinished then
                startMatchEndCountdown(player.playerId)
            end
            localTimer = 0
        end
        if matchData.hasMatchStarted then
            checkForEntityCollision(player.playerId)
        end
        localTimer = localTimer + 1
        globalTimer = globalTimer + 1
        tm.playerUI.SetUIValue(player.playerId, "globaltime", "time: " .. globalTimer/10)
    end
end

tm.players.OnPlayerJoined.add(onPlayerJoined)
tm.players.OnPlayerLeft.add(onPlayerLeft)

-------------------- Game Logic Functions --------------------

function startMatchLoop(playerId)
    if matchData.matchTimer > 1 then
        if #matchData.entities < 1 then
            spawnEntity(playerId, chickenModel, matchData.spawnQuantity)
        end
        matchData.matchTimer = matchData.matchTimer - 1
        tm.playerUI.SetUIValue(playerId, "countdown", matchData.matchTimer .. " seconds remaining!") 
    else
        onMatchFinished()
    end
end

function startLobbyCountdown(playerId)
    if matchData.timer > 1 then
        matchData.timer = matchData.timer - 1
        tm.playerUI.SetUIValue(playerId, "countdown", matchData.timer .. " seconds") 
    else
        tm.audio.PlayAudioAtGameobject(audioCues.begin, tm.players.GetPlayerGameObject(playerId))
        matchData.matchTimer = matchData.matchTimerDefault
        matchData.isWaitingForPlayersToJoin = false
        matchData.hasMatchStarted = true
        matchLobbyPage(playerId)
    end
end

function startMatchEndCountdown(playerId)
    if matchData.timer > 1 then
        matchData.timer = matchData.timer - 1
        tm.playerUI.SetUIValue(playerId, "countdown", matchData.timer .. " seconds") 
    else
        matchData.hasMatchFinished = false
        matchData.matchTimer = matchData.matchTimerDefault
        matchData.timer = matchData.timerDefault
        matchData.hostId = nil
        matchData.entitiesSmashed = 0
        for _, pId in pairs(matchData.players) do
            playerDataTable[pId].score = 0
            homePage(pId)
        end
        matchData.players = {}
        matchData.entities = {}
    end
end 

function onMatchFinished()
    matchData.hasMatchStarted = false
    matchData.hasMatchFinished = true
    matchData.hasMatchBeenCreated = false
    tm.audio.PlayAudioAtPosition(audioCues.finish, tm.vector3.Create(), 1)
    matchData.timer = matchData.timerDefault
    matchData.isWaitingForPlayersToJoin = false
    findWinnerId()
    for _, playerId in pairs(matchData.players) do
        playerDataTable[playerId].stats.matches = playerDataTable[playerId].stats.matches + 1
        if playerDataTable[playerId].score > playerDataTable[playerId].stats.hiscore then
            playerDataTable[playerId].stats.hiscore = playerDataTable[playerId].score
        end
        savePlayerData(playerId)
        matchLobbyPage(playerId)
    end
    --tm.physics.ClearAllSpawns()
    for _, chicken in pairs(matchData.entities) do
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
    --spawnEntity(playerId, chickenModel, matchData.spawnInterval)
    for _, player in pairs(matchData.players) do
        tm.playerUI.SetUIValue(player, "score_" .. playerId, tm.players.GetPlayerName(playerId) .. " - " .. playerData.score .. " pts") 
    end 
end
    
function checkForEntityCollision(playerId)
    if #matchData.entities < 1 then
        return
    end
    for _, chicken in pairs(matchData.entities) do
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        local chickenPos = chicken.GetTransform().GetPosition()
        local deltaPos = tm.vector3.op_Subtraction(playerPos, chickenPos)
        if math.abs(deltaPos.Magnitude()) < matchData.collisionDetectionThreshold then
            onSmashEntity(playerId)
            tm.audio.StopAllAudioAtGameobject(chicken)
            matchData.entitiesSmashed = matchData.entitiesSmashed + 1
        end
    end
end

function spawnEntity(playerId, model, quantity)
    if #matchData.entities < matchData.maxEntityCount then
        local playerPos = tm.players.GetPlayerTransform(playerId).GetPosition()
        for i=1, quantity do
            local variance = varianceVector(matchData.spawnRadius)
            local spawnCoords = tm.vector3.op_Addition(playerPos, variance)
            local chicken = tm.physics.SpawnObject(spawnCoords, model)
            table.insert(matchData.entities, chicken)
        end
    end
end

function findWinnerId()
    local highestScore = 0
    local highestIndex = 0
    for i, playerId in pairs(matchData.players) do
        if playerDataTable[playerId].score > highestScore then
            highestIndex = i
        end
    end
    playerDataTable[matchData.players[highestIndex]].isWinner = true
end

-------------------- UI helpers --------------------

function title(playerId, titleText) -- throwaway label
    tm.playerUI.AddUILabel(playerId, "title", titleText)
end

function rerouteLobby(callbackData)
    matchLobbyPage(callbackData.playerId)
end

function rerouteJoinMatch(callbackData)
    onJoinMatch(callbackData.playerId)
end

function rerouteHomePage(callbackData)
    homePage(callbackData.playerId)
end

-------------------- UI Pages --------------------

function homePage(playerId)
    tm.playerUI.ClearUI(playerId)
    if matchData.hasMatchBeenCreated then
        local hostName = tm.players.GetPlayerName(matchData.hostId)
        tm.playerUI.AddUILabel(playerId, "host", hostName .. " is hosting a match!") 
        tm.playerUI.AddUIButton(playerId, "joinmatch", "join match", rerouteJoinMatch)
    else
        tm.playerUI.AddUIButton(playerId, "makematch", "start a match", onCreateMatch)
    end
    tm.playerUI.AddUIButton(playerId, "mystats", "my stats", statsPage)
    --tm.playerUI.AddUILabel(playerId, "globaltime", "time: " .. globalTimer) 
end

function matchLobbyPage(playerId)
    tm.playerUI.ClearUI(playerId)
    if matchData.isWaitingForPlayersToJoin then
        title(playerId, "Get in your vehicles!")
        title(playerId, "The match will start in...")
    elseif matchData.hasMatchFinished then
        title(playerId, "Match Complete!")
        title(playerId, "Ending in...")
    elseif matchData.hasMatchStarted then
        title(playerId, "SMASH THE CHICKENS!")
    else
        title(playerId, "-")
    end
    if not matchData.hasMatchFinished or matchData.hasMatchFinished then
        tm.playerUI.AddUILabel(playerId, "countdown", matchData.timer .. "s") 
    end
    if matchData.isWaitingForPlayersToJoin then
        title(playerId, "Lobby:")
    elseif matchData.hasMatchFinished then
        title(playerId, "Final Scores:")
    elseif matchData.hasMatchStarted then
        --tm.playerUI.AddUILabel(playerId, "chickencount", #matchData.entities .. " chickens in the arena") 
        title(playerId, "Leaderboard:")
    else
        title(playerId, "-")
    end
    if matchData.isWaitingForPlayersToJoin then
        for _, id in pairs(matchData.players) do
            if id == matchData.hostId then
                tm.playerUI.AddUILabel(playerId, "lobbylist", tm.players.GetPlayerName(id) .. " (host)") 
            else
                if playerDataTable[id].isReady then
                    tm.playerUI.AddUILabel(playerId, "lobbylist", tm.players.GetPlayerName(id)) 
                else
                    tm.playerUI.AddUILabel(playerId, "lobbylist", tm.players.GetPlayerName(id)) 
                end
            end
        end
    else
        for _, id in pairs(matchData.players) do
            local playerData = playerDataTable[id]
            if playerData.isWinner then
                tm.playerUI.AddUILabel(playerId, "score_" .. id, tm.players.GetPlayerName(id) .. " - " .. playerData.score .. " pts HIGHEST SCORE") 
                playerData.isWinner = false
            else
                tm.playerUI.AddUILabel(playerId, "score_" .. id, tm.players.GetPlayerName(id) .. " - " .. playerData.score .. " pts") 
            end
        end
    end
    if playerId == matchData.hostId and matchData.isWaitingForPlayersToJoin then
        tm.playerUI.AddUIButton(playerId, "matchsettings", "match settings", matchSettingsPage)
    end
    --tm.playerUI.AddUIButton(playerId, "readyup", "not ready", onReadyUp)
end

function matchSettingsPage(callbackData)
    local playerId = callbackData.playerId
    tm.playerUI.ClearUI(playerId)
    title(playerId, "Waiting for match to start in...")
    tm.playerUI.AddUILabel(playerId, "countdown", matchData.timer .. "s")
    title(playerId, "Match Settings")
    tm.playerUI.AddUIButton(playerId, "spawnradius", "spawn radius: " .. matchData.spawnRadius, cycleSpawnValues)
    tm.playerUI.AddUIButton(playerId, "spawnquantity", "spawn quantity(per player): " .. matchData.spawnQuantity, cycleSpawnQuantity)
    tm.playerUI.AddUIButton(playerId, "maxentitycount", "max spawns: " .. matchData.maxEntityCount, cycleMaxEntityCount)
    --tm.playerUI.AddUIButton(playerId, "detectionradius", "detection radius: " .. matchData.collisionDetectionThreshold, cycleDetectionThreshold)
    tm.playerUI.AddUIButton(playerId, "matchtimer", "match duration: " .. matchData.matchTimerDefault, cycleMatchTime)
    tm.playerUI.AddUIButton(playerId, "back", "back", rerouteLobby)
end

function statsPage(callbackData)
    local playerId = callbackData.playerId
    local playerData = playerDataTable[playerId]
    tm.playerUI.ClearUI(playerId)
    title(playerId, "My Stats")
    tm.playerUI.AddUILabel(playerId, "hiscore", "hiscore: " .. playerData.stats.hiscore)
    tm.playerUI.AddUILabel(playerId, "smashed", "chickens smashed: " .. playerData.stats.smashed)
    --tm.playerUI.AddUILabel(playerId, "total", "all-time score: " .. playerData.stats.totalScore)
    tm.playerUI.AddUILabel(playerId, "matches", "matches played: " .. playerData.stats.matches)
    tm.playerUI.AddUIButton(playerId, "back", "back", rerouteHomePage)
end

-------------------- Callbacks --------------------
--[[
function onReadyUp(callbackData)
    playerDataTable[callbackData.playerId].isReady = not playerDataTable[callbackData.playerId].isReady
    if playerDataTable[callbackData.playerId].isReady then
        tm.playerUI.SetUIValue(callbackData.playerId, "readyup", "ready")
    else
        tm.playerUI.SetUIValue(callbackData.playerId, "readyup", "unready")
    end
    for _, player in pairs(matchData.players) do
        matchLobbyPage(player.playerId)
    end
end
]]

function cycleDetectionThreshold(callbackData)
    local currentIndex = getTableValueIndex(detectionValueIncrements, matchData.collisionDetectionThreshold)
    local nextIndex = currentIndex % #detectionValueIncrements + 1
    matchData.collisionDetectionThreshold = detectionValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "detectionradius", "detection radius: " .. matchData.collisionDetectionThreshold)
end

function cycleMaxEntityCount(callbackData)
    local currentIndex = getTableValueIndex(maxValueIncrements, matchData.maxEntityCount)
    local nextIndex = currentIndex % #maxValueIncrements + 1
    matchData.maxEntityCount = maxValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "maxentitycount", "max spawns: " .. matchData.maxEntityCount)
end

function cycleSpawnValues(callbackData)
    local currentIndex = getTableValueIndex(radiusValueIncrements, matchData.spawnRadius)
    local nextIndex = currentIndex % #radiusValueIncrements + 1
    matchData.spawnRadius = radiusValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "spawnradius", "spawn radius: " .. matchData.spawnRadius)
end

function cycleSpawnQuantity(callbackData)
    local currentIndex = getTableValueIndex(spawnValueIncrements, matchData.spawnQuantity)
    local nextIndex = currentIndex % #spawnValueIncrements + 1
    matchData.spawnQuantity = spawnValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "spawnquantity", "spawn quantity(per player): " .. matchData.spawnQuantity)
end

function cycleMatchTime(callbackData)
    if matchData.matchTimerDefault < 120 then
        matchData.matchTimerDefault = matchData.matchTimerDefault + 10
    else
        matchData.matchTimerDefault = 10
    end
    tm.playerUI.SetUIValue(callbackData.playerId, "matchtimer", "match duration: " .. matchData.matchTimerDefault)
end

function onCreateMatch(callbackData)
    if matchData.hostId == nil and not matchData.hasMatchBeenCreated then
        tm.audio.PlayAudioAtGameobject(audioCues.boop, tm.players.GetPlayerGameObject(callbackData.playerId))
        tm.physics.ClearAllSpawns()
        matchData.hasMatchBeenCreated = true
        matchData.isWaitingForPlayersToJoin = true
        matchData.hostId = callbackData.playerId
        onJoinMatch(callbackData.playerId)
        matchLobbyPage(callbackData.playerId)
    end
    for _, player in pairs(tm.players.CurrentPlayers()) do
        if player.playerId ~= matchData.hostId and playerDataTable[player.playerId].prefs.autoJoin then
            onJoinMatch(player.playerId)
        end
    end
end

function onJoinMatch(playerId)
    table.insert(matchData.players, playerId)
    tm.audio.PlayAudioAtGameobject(audioCues.boop, tm.players.GetPlayerGameObject(playerId))
    for _, player in pairs(tm.players.CurrentPlayers()) do
        matchLobbyPage(player.playerId) 
    end
end

function onEndMatch(callbackData)
    matchData.hostId = nil
    matchData.hasMatchBeenCreated = false
    matchData.isWaitingForPlayersToJoin = false
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
