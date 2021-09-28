-- Chicken Smash Minigame
-- by dinoman/ticibi 2021

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
        local playerData = playerDataTable[player.playerId]
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
        tm.playerUI.SetUIValue(player.playerId, "globaltime", "time: " .. globalTimer/10)
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
        tm.playerUI.SetUIValue(playerId, "countdown", matchDataTable.matchTimer .. " seconds remaining!") 
    else
        onMatchFinished()
    end
end

function startLobbyCountdown(playerId)
    if matchDataTable.timer > 1 then
        matchDataTable.timer = matchDataTable.timer - 1
        tm.playerUI.SetUIValue(playerId, "countdown", matchDataTable.timer .. " seconds") 
    else
        tm.audio.PlayAudioAtGameobject(audioCues.begin, tm.players.GetPlayerGameObject(playerId))
        matchDataTable.matchTimer = matchDataTable.matchTimerDefault
        matchDataTable.isWaitingForPlayersToJoin = false
        matchDataTable.hasMatchStarted = true
        matchLobbyPage(playerId)
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
            homePage(pId)
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
        matchLobbyPage(playerId)
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
        tm.playerUI.SetUIValue(player, "score_" .. playerId, tm.players.GetPlayerName(playerId) .. " - " .. playerData.score .. " pts") 
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

function homePage(playerId)
    tm.playerUI.ClearUI(playerId)
    if matchDataTable.hasMatchBeenCreated then
        local hostName = tm.players.GetPlayerName(matchDataTable.hostId)
        tm.playerUI.AddUILabel(playerId, "host", hostName .. " is hosting a match!") 
        tm.playerUI.AddUIButton(playerId, "joinmatch", "join match", rerouteJoinMatch)
    else
        tm.playerUI.AddUIButton(playerId, "makematch", "start a match", onCreateMatch)
    end
    tm.playerUI.AddUIButton(playerId, "mystats", "my stats", statsPage)
    if debug then tm.playerUI.AddUILabel(playerId, "globaltime", "time: " .. globalTimer) end
end

function matchLobbyPage(playerId)
    tm.playerUI.ClearUI(playerId)
    if matchDataTable.isWaitingForPlayersToJoin then
        title(playerId, "Get in your vehicles!")
        title(playerId, "The match will start in...")
    elseif matchDataTable.hasMatchFinished then
        title(playerId, "Match Complete!")
        title(playerId, "Ending in...")
    elseif matchDataTable.hasMatchStarted then
        title(playerId, "SMASH THE CHICKENS!")
    else
        title(playerId, "-")
    end
    if not matchDataTable.hasMatchFinished or matchDataTable.hasMatchFinished then
        tm.playerUI.AddUILabel(playerId, "countdown", matchDataTable.timer .. "s") 
    end
    if matchDataTable.isWaitingForPlayersToJoin then
        title(playerId, "Lobby:")
    elseif matchDataTable.hasMatchFinished then
        title(playerId, "Final Scores:")
    elseif matchDataTable.hasMatchStarted then
        title(playerId, "Leaderboard:")
    else
        title(playerId, "-")
    end
    if matchDataTable.isWaitingForPlayersToJoin then
        for _, id in pairs(matchDataTable.players) do
            if id == matchDataTable.hostId then
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
        for _, id in pairs(matchDataTable.players) do
            local playerData = playerDataTable[id]
            if playerData.isWinner then
                tm.playerUI.AddUILabel(playerId, "score_" .. id, tm.players.GetPlayerName(id) .. " - " .. playerData.score .. " pts HIGHEST SCORE") 
                playerData.isWinner = false
            else
                tm.playerUI.AddUILabel(playerId, "score_" .. id, tm.players.GetPlayerName(id) .. " - " .. playerData.score .. " pts") 
            end
        end
    end
    if playerId == matchDataTable.hostId and matchDataTable.isWaitingForPlayersToJoin then
        tm.playerUI.AddUIButton(playerId, "matchsettings", "match settings", matchSettingsPage)
    end
end

function matchSettingsPage(callbackData)
    local playerId = callbackData.playerId
    tm.playerUI.ClearUI(playerId)
    title(playerId, "Waiting for match to start in...")
    tm.playerUI.AddUILabel(playerId, "countdown", matchDataTable.timer .. "s")
    title(playerId, "Match Settings")
    tm.playerUI.AddUIButton(playerId, "spawnradius", "spawn radius: " .. matchDataTable.spawnRadius, cycleSpawnValues)
    tm.playerUI.AddUIButton(playerId, "spawnquantity", "spawn quantity(per player): " .. matchDataTable.spawnQuantity, cycleSpawnQuantity)
    tm.playerUI.AddUIButton(playerId, "maxentitycount", "max spawns: " .. matchDataTable.maxEntityCount, cycleMaxEntityCount)
    tm.playerUI.AddUIButton(playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault, cycleMatchTime)
    tm.playerUI.AddUIButton(playerId, "back", "back", rerouteLobby)
end

function statsPage(callbackData)
    local playerId = callbackData.playerId
    local playerData = playerDataTable[playerId]
    tm.playerUI.ClearUI(playerId)
    title(playerId, "My Stats")
    tm.playerUI.AddUILabel(playerId, "hiscore", "hiscore: " .. playerData.stats.hiscore)
    tm.playerUI.AddUILabel(playerId, "smashed", "chickens smashed: " .. playerData.stats.smashed)
    tm.playerUI.AddUILabel(playerId, "matches", "matches played: " .. playerData.stats.matches)
    tm.playerUI.AddUIButton(playerId, "back", "back", rerouteHomePage)
end

-------------------- UI Callbacks --------------------

function cycleDetectionThreshold(callbackData)
    local currentIndex = getTableValueIndex(detectionValueIncrements, matchDataTable.collisionDetectionThreshold)
    local nextIndex = currentIndex % #detectionValueIncrements + 1
    matchDataTable.collisionDetectionThreshold = detectionValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "detectionradius", "detection radius: " .. matchDataTable.collisionDetectionThreshold)
end

function cycleMaxEntityCount(callbackData)
    local currentIndex = getTableValueIndex(maxValueIncrements, matchDataTable.maxEntityCount)
    local nextIndex = currentIndex % #maxValueIncrements + 1
    matchDataTable.maxEntityCount = maxValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "maxentitycount", "max spawns: " .. matchDataTable.maxEntityCount)
end

function cycleSpawnValues(callbackData)
    local currentIndex = getTableValueIndex(radiusValueIncrements, matchDataTable.spawnRadius)
    local nextIndex = currentIndex % #radiusValueIncrements + 1
    matchDataTable.spawnRadius = radiusValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "spawnradius", "spawn radius: " .. matchDataTable.spawnRadius)
end

function cycleSpawnQuantity(callbackData)
    local currentIndex = getTableValueIndex(spawnValueIncrements, matchDataTable.spawnQuantity)
    local nextIndex = currentIndex % #spawnValueIncrements + 1
    matchDataTable.spawnQuantity = spawnValueIncrements[nextIndex]
    tm.playerUI.SetUIValue(callbackData.playerId, "spawnquantity", "spawn quantity(per player): " .. matchDataTable.spawnQuantity)
end

function cycleMatchTime(callbackData)
    if matchDataTable.matchTimerDefault < 120 then
        matchDataTable.matchTimerDefault = matchDataTable.matchTimerDefault + 10
    else
        matchDataTable.matchTimerDefault = 10
    end
    tm.playerUI.SetUIValue(callbackData.playerId, "matchtimer", "match duration: " .. matchDataTable.matchTimerDefault)
end

function onCreateMatch(callbackData)
    if matchDataTable.hostId == nil and not matchDataTable.hasMatchBeenCreated then
        tm.audio.PlayAudioAtGameobject(audioCues.boop, tm.players.GetPlayerGameObject(callbackData.playerId))
        tm.physics.ClearAllSpawns()
        matchDataTable.hasMatchBeenCreated = true
        matchDataTable.isWaitingForPlayersToJoin = true
        matchDataTable.hostId = callbackData.playerId
        onJoinMatch(callbackData.playerId)
        matchLobbyPage(callbackData.playerId)
    end
    for _, player in pairs(tm.players.CurrentPlayers()) do
        if player.playerId ~= matchDataTable.hostId and playerDataTable[player.playerId].prefs.autoJoin then
            onJoinMatch(player.playerId)
        end
    end
end

function onJoinMatch(playerId)
    table.insert(matchDataTable.players, playerId)
    tm.audio.PlayAudioAtGameobject(audioCues.boop, tm.players.GetPlayerGameObject(playerId))
    for _, player in pairs(tm.players.CurrentPlayers()) do
        matchLobbyPage(player.playerId) 
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
