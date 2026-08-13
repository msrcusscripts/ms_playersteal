-- ms_playersteal - server
-- All authoritative logic lives here: eligibility, locking, cooldowns,
-- distance checks, death checks through wasabi_ambulance and the inventory
-- access itself. Nothing sent by the robber's client is trusted.

-- Framework access (ESX / QBCore / Qbox) is abstracted away in bridge.lua,
-- which loads before this file and exposes the global Bridge table.

-- State

---Active robberies indexed by victim server id.
local activeByVictim = {}

---Reverse lookup: robber server id -> victim server id.
local activeByRobber = {}

-- Cooldowns are keyed by a persistent identifier (ESX identifier / QB or
-- Qbox citizenid) so reconnecting doesn't reset them.
local robberCooldowns = {} ---@type table<string, number> identifier -> os.time() when free again
local victimCooldowns = {} ---@type table<string, number>

---Victims whose inventory is currently open for a robber: they can't be
---targeted again until that inventory closes (anti-dupe overlap lock).
local lootSessions = {}

---Per-player timestamps and strike counters for event rate limiting.
local rateStamps = {}

-- Network latency allowance when validating the completion time (ms)
local FINISH_TOLERANCE = 1500

-- How often the supervision loop runs while a robbery is active (ms)
local MONITOR_INTERVAL = 500

-- How often the victim's hands-up state is re-verified during a robbery (ms)
local HANDS_RECHECK_INTERVAL = 1000

-- How long the victim's client gets to answer a hands-up check before it
-- counts as "hands not up" (ms)
local HANDS_CALLBACK_TIMEOUT = 2000

-- Minimum time between start requests / finish events per player (ms)
local START_RATE_MS = 750
local FINISH_RATE_MS = 1000

-- Rapid repeats needed before event spam itself is logged as suspicious
local RATE_STRIKES = 5

-- How long a loot lock may outlive the inventory being opened (seconds)
local LOOT_LOCK_SECONDS = 60

-- Helpers

local function notify(playerId, key)
    local data = Config.GetNotification(key)
    if data then
        TriggerClientEvent('ox_lib:notify', playerId, data)
    end
end

---Verbose logging, only active when Config.Debug is enabled.
local function debugLog(msg, ...)
    if Config.Debug then
        print(('[ms_playersteal] ' .. msg):format(...))
    end
end

-- Logging lives in server/logs.lua and is shared through the Logs table.
local function logSuspicious(playerId, reason)
    Logs.Suspicious(playerId, reason)
end

local function finalizeLootSession(victimId)
    local session = lootSessions[victimId]
    if not session then return end

    lootSessions[victimId] = nil

    -- Sessions created while logging was disabled carry no log data
    if not session.logEnabled then return end

    local taken
    if session.snapshot then
        local after = Logs.Snapshot(victimId)
        taken = after and Logs.Diff(session.snapshot, after) or nil
    end

    Logs.SendRobbery({
        robber = session.robberInfo,
        victim = session.victimInfo,
        robberName = session.robberName,
        victimName = session.victimName,
        victimState = session.victimState,
        location = session.location,
        weapon = session.weapon,
        duration = session.duration,
        taken = taken,
    })
end

---Per-player, per-action rate limiter with strike tracking. Sustained spam
---is reported through logSuspicious once per burst.
local function isRateLimited(playerId, action, intervalMs)
    local now = GetGameTimer()
    local stamps = rateStamps[playerId]

    if not stamps then
        stamps = {}
        rateStamps[playerId] = stamps
    end

    local entry = stamps[action]

    if not entry then
        stamps[action] = { last = now, strikes = 0 }
        return false
    end

    local limited = (now - entry.last) < intervalMs
    entry.last = now

    if limited then
        entry.strikes = entry.strikes + 1
        if entry.strikes == RATE_STRIKES then
            logSuspicious(playerId, ('%s event spam'):format(action))
        end
        return true
    end

    entry.strikes = 0
    return false
end

---Death / incapacitation status through wasabi_ambulance.
---Primary source: the official isPlayerDead export. Fallback: the state bags
---wasabi_ambulance syncs for every player ('dead' / 'laststand').
local function getDeathStatus(playerId)
    local ok, result = pcall(function()
        return exports.wasabi_ambulance:isPlayerDead(playerId)
    end)

    if ok then
        if result == 'laststand' then return 'laststand' end
        if result == true or result == 'dead' then return 'dead' end
    end

    -- State bag fallback: false/nil while alive, 'dead' when dead,
    -- 'laststand' while downed (older builds use isDead / laststand keys).
    local state = Player(playerId).state
    local status = state.dead or state.isDead

    if status == 'laststand' or state.laststand then return 'laststand' end
    if status then return 'dead' end

    return nil
end

---Is this player dead enough to be robbed, according to the config?
local function isRobbableDead(playerId)
    local status = getDeathStatus(playerId)
    if not status then return false end
    if status == 'laststand' and not Config.TreatLastStandAsDead then return false end
    return true
end

---Ask the VICTIM'S client whether their hands are up. The robber's client is
---never involved, so it can't be spoofed by the person who benefits from it.
---A client that never answers (crashed or deliberately silent) counts as
---"hands not up" after HANDS_CALLBACK_TIMEOUT instead of hanging the caller.
local function isTargetHandsUp(playerId)
    local p = promise.new()
    local settled = false

    CreateThread(function()
        local ok, handsUp = pcall(function()
            return lib.callback.await('ms_playersteal:handsUp', playerId)
        end)

        if not settled then
            settled = true
            p:resolve(ok and handsUp == true)
        end
    end)

    SetTimeout(HANDS_CALLBACK_TIMEOUT, function()
        if not settled then
            settled = true
            debugLog('hands-up check for %s timed out', playerId)
            p:resolve(false)
        end
    end)

    return Citizen.Await(p)
end

---Is the target currently in a state that allows being robbed?
local function isTargetRobbable(targetId)
    if isRobbableDead(targetId) then
        return Config.AllowRobbingDead
    end

    if Config.RequireHandsUp then
        return isTargetHandsUp(targetId)
    end

    return true
end

---Server-side distance between two players (metres).
local function getDistance(a, b)
    local pedA, pedB = GetPlayerPed(a), GetPlayerPed(b)
    if pedA == 0 or pedB == 0 then return math.huge end
    return #(GetEntityCoords(pedA) - GetEntityCoords(pedB))
end

---Whitelist / blacklist check for the robber's job.
local function isJobAllowed(playerId)
    local job = Bridge.GetJob(playerId)

    if Config.UseJobWhitelist then
        return Config.JobWhitelist[job] == true
    end

    return Config.JobBlacklist[job] ~= true
end

-- State bag keys commonly used by cuff / restraint scripts. Extend this list
-- if your restraint resource uses a different key.
local RESTRAINED_STATES = { 'isCuffed', 'cuffed', 'handcuffed' }

local function isPlayerRestrained(playerId)
    local state = Player(playerId).state

    for i = 1, #RESTRAINED_STATES do
        if state[RESTRAINED_STATES[i]] then
            return true
        end
    end

    return false
end

local unarmedHash = joaat('WEAPON_UNARMED')
local nonFirearmHashes, allowedWeaponHashes

-- Build the weapon hash lookups once, from the configured names.
local function buildWeaponLookups()
    nonFirearmHashes = { [unarmedHash] = true }

    for _, name in ipairs(Config.NonFirearms or {}) do
        nonFirearmHashes[joaat(name)] = true
    end

    allowedWeaponHashes = nil

    if Config.AllowedWeapons and #Config.AllowedWeapons > 0 then
        allowedWeaponHashes = {}
        for _, name in ipairs(Config.AllowedWeapons) do
            allowedWeaponHashes[joaat(name)] = true
        end
    end
end

buildWeaponLookups()

-- Is the player holding a weapon that satisfies Config.RequireWeapon?
local function hasRequiredWeapon(playerId)
    if not Config.RequireWeapon then return true end

    local ped = GetPlayerPed(playerId)
    if ped == 0 then return false end

    local weapon = GetSelectedPedWeapon(ped)
    if not weapon or weapon == unarmedHash then return false end

    if allowedWeaponHashes then
        return allowedWeaponHashes[weapon] == true
    end

    return not nonFirearmHashes[weapon]
end

---A robber must exist, be alive (per wasabi_ambulance), unrestrained and on
---foot. Checked at start, during supervision and again on completion.
local function isRobberValid(playerId)
    local ped = GetPlayerPed(playerId)

    if ped == 0 then return false end
    if getDeathStatus(playerId) then return false end
    if isPlayerRestrained(playerId) then return false end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return false end

    return true
end

local function getIdentifier(playerId)
    return Bridge.GetIdentifier(playerId)
end

local function isOnCooldown(store, identifier)
    local freeAt = store[identifier]
    if not freeAt then return false end

    -- Expired entries are pruned on access so the tables can't grow forever
    if os.time() >= freeAt then
        store[identifier] = nil
        return false
    end

    return true
end

local function setCooldown(store, identifier, seconds)
    if seconds and seconds > 0 then
        store[identifier] = os.time() + seconds
    end
end

-- Robbery lifecycle

---Clears an active robbery. Optionally cancels the robber's progress bar and
---notifies them. A short failed-attempt cooldown prevents progress spamming.
local function stopRobbery(victimId, cancelClient, reasonKey)
    local robbery = activeByVictim[victimId]
    if not robbery then return end

    activeByVictim[victimId] = nil
    activeByRobber[robbery.robber] = nil

    setCooldown(robberCooldowns, getIdentifier(robbery.robber), Config.FailedCooldown)

    if cancelClient and GetPlayerPed(robbery.robber) ~= 0 then
        TriggerClientEvent('ms_playersteal:cancelProgress', robbery.robber)
        if reasonKey then notify(robbery.robber, reasonKey) end
    end
end

---Supervision loop that only runs while this specific robbery is active.
---No global polling: the thread dies as soon as the robbery ends.
local function startMonitor(victimId, robberId)
    CreateThread(function()
        local lastHandsCheck = 0

        while true do
            Wait(MONITOR_INTERVAL)

            local robbery = activeByVictim[victimId]
            if not robbery or robbery.robber ~= robberId then return end

            -- Either side no longer has a ped (disconnect / despawn)
            if GetPlayerPed(robberId) == 0 then
                return stopRobbery(victimId, false)
            end

            if GetPlayerPed(victimId) == 0 then
                return stopRobbery(victimId, true, 'target_left')
            end

            -- The robber died, was downed, got restrained or entered a vehicle
            if not isRobberValid(robberId) then
                return stopRobbery(victimId, true, 'robbery_cancelled')
            end

            if not hasRequiredWeapon(robberId) then
                return stopRobbery(victimId, true, 'need_weapon')
            end

            -- Different instance or too far apart
            if GetPlayerRoutingBucket(robberId) ~= GetPlayerRoutingBucket(victimId)
                or getDistance(robberId, victimId) > Config.MaxRobberyDistance then
                return stopRobbery(victimId, true, 'too_far')
            end

            local victimDead = isRobbableDead(victimId)

            -- Victim died mid-robbery while robbing the dead is disabled
            if victimDead and not Config.AllowRobbingDead then
                return stopRobbery(victimId, true, 'robbery_cancelled')
            end

            -- Living victim lowered their hands
            if not victimDead and Config.RequireHandsUp and Config.CancelIfHandsDown then
                local now = GetGameTimer()
                if now - lastHandsCheck >= HANDS_RECHECK_INTERVAL then
                    lastHandsCheck = now
                    if not isTargetHandsUp(victimId) then
                        return stopRobbery(victimId, true, 'robbery_cancelled')
                    end
                end
            end
        end
    end)
end

-- Start request (ox_lib callback)

lib.callback.register('ms_playersteal:requestStart', function(source, targetId)
    -- Event spam protection
    if isRateLimited(source, 'start', START_RATE_MS) then
        return false
    end

    -- Strict id validation: ox_target can only ever produce a real, foreign
    -- server id, so anything else is a handcrafted event.
    targetId = tonumber(targetId)

    if not targetId or targetId ~= math.floor(targetId) or targetId <= 0 then
        logSuspicious(source, 'start request with malformed target id')
        return false
    end

    if targetId == source then
        logSuspicious(source, 'start request targeting themselves')
        return false
    end

    -- Both players must be fully loaded in the framework
    if not Bridge.GetPlayer(source) or not Bridge.GetPlayer(targetId) then
        return false, 'target_left'
    end

    -- One robbery at a time, per robber and per victim
    if activeByRobber[source] then
        return false, 'robber_busy'
    end

    if activeByVictim[targetId] then
        return false, 'target_busy'
    end

    -- The victim's inventory is still open from a previous robbery
    local session = lootSessions[targetId]
    if session then
        if os.time() < session.expires and GetPlayerPed(session.robber) ~= 0 then
            return false, 'target_busy'
        end
        finalizeLootSession(targetId)
    end

    -- The robber must be alive, uncuffed and on foot
    if not isRobberValid(source) then
        return false, 'cannot_now'
    end

    if not hasRequiredWeapon(source) then
        return false, 'need_weapon'
    end

    -- Job whitelist / blacklist
    if not isJobAllowed(source) then
        return false, 'job_blocked'
    end

    -- Cooldowns (identifier based, survives reconnects)
    if isOnCooldown(robberCooldowns, getIdentifier(source)) then
        return false, 'robber_cooldown'
    end

    if isOnCooldown(victimCooldowns, getIdentifier(targetId)) then
        return false, 'victim_cooldown'
    end

    -- Same instance and within range, verified with server-side coordinates
    if GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(targetId) then
        return false, 'too_far'
    end

    if getDistance(source, targetId) > Config.MaxRobberyDistance then
        return false, 'too_far'
    end

    -- Target must be dead / downed (wasabi_ambulance) or have their hands up
    if not isTargetRobbable(targetId) then
        return false, 'not_robbable'
    end

    -- Lock the pair and start supervising
    activeByVictim[targetId] = { robber = source, startedAt = GetGameTimer() }
    activeByRobber[source] = targetId

    startMonitor(targetId, source)

    debugLog('robbery started: %s -> %s', source, targetId)

    return true
end)

-- Completion / cancellation

RegisterNetEvent('ms_playersteal:finish', function(clientSuccess)
    local source = source

    -- Event spam protection
    if isRateLimited(source, 'finish', FINISH_RATE_MS) then
        return
    end

    local victimId = activeByRobber[source]

    -- No robbery registered for this player. This also happens legitimately
    -- when the server cancelled the robbery an instant earlier, so it's only
    -- logged in debug mode.
    if not victimId then
        return debugLog('finish from %s with no active robbery', source)
    end

    local robbery = activeByVictim[victimId]
    if not robbery or robbery.robber ~= source then return end

    -- The client reported a cancel
    if clientSuccess ~= true then
        stopRobbery(victimId, false)
        notify(source, 'robbery_cancelled')
        return
    end

    -- Completion is only valid once the configured duration really elapsed:
    -- a client claiming instant success is treated as an exploit attempt.
    local elapsed = GetGameTimer() - robbery.startedAt
    if elapsed + FINISH_TOLERANCE < Config.RobberyDuration then
        logSuspicious(source, ('claimed success after %sms of a %sms robbery'):format(elapsed, Config.RobberyDuration))
        stopRobbery(victimId, false)
        return
    end

    -- Full re-validation at the exact moment of completion
    if not Bridge.GetPlayer(victimId)
        or not isRobberValid(source)
        or not hasRequiredWeapon(source)
        or GetPlayerRoutingBucket(source) ~= GetPlayerRoutingBucket(victimId)
        or getDistance(source, victimId) > Config.MaxRobberyDistance
        or not isTargetRobbable(victimId) then
        stopRobbery(victimId, false)
        notify(source, 'robbery_cancelled')
        return
    end

    -- Success: release the lock, start both cooldowns and give the robber
    -- access to the victim's inventory. Every item movement from here on is
    -- handled by ox_inventory entirely on the server.
    activeByVictim[victimId] = nil
    activeByRobber[source] = nil

    setCooldown(robberCooldowns, getIdentifier(source), Config.RobberCooldown)
    setCooldown(victimCooldowns, getIdentifier(victimId), Config.VictimCooldown)

    -- Lock the victim against overlapping robberies until the robber closes
    -- their inventory (with an expiry fallback), then open it. Every item
    -- movement is still processed by ox_inventory on the server. The session
    -- also carries everything the Discord log needs, including a pre-loot
    -- inventory snapshot used to work out what was taken.
    local victimDead = isRobbableDead(victimId)

    local session = {
        robber = source,
        expires = os.time() + LOOT_LOCK_SECONDS,
        logEnabled = Config.EnableDiscordLogs == true,
        snapshot = Config.EnableDiscordLogs and Logs.Snapshot(victimId) or nil,
        robberInfo = Logs.DescribePlayer(source),
        victimInfo = Logs.DescribePlayer(victimId),
        robberName = GetPlayerName(source),
        victimName = GetPlayerName(victimId),
        location = Logs.DescribeZone(source),
        weapon = Logs.DescribeWeapon(source),
        duration = ('%.1fs'):format(elapsed / 1000),
        victimState = victimDead and 'Dead / downed'
            or (Config.RequireHandsUp and 'Alive (hands up)' or 'Alive'),
    }

    lootSessions[victimId] = session

    -- Guaranteed log delivery: even if the inventory-close event never fires
    -- on this ox_inventory build, the session finalizes (and its log ships)
    -- when the loot lock expires.
    SetTimeout(LOOT_LOCK_SECONDS * 1000, function()
        if lootSessions[victimId] == session then
            finalizeLootSession(victimId)
        end
    end)

    notify(source, 'robbery_success')
    notify(victimId, 'being_robbed')

    debugLog('robbery completed: %s looted %s', source, victimId)

    exports.ox_inventory:forceOpenInventory(source, 'player', victimId)
end)

-- Release a robber's loot lock as soon as they close an inventory, diffing
-- the victim's pockets against the pre-loot snapshot and shipping the log.
AddEventHandler('ox_inventory:closedInventory', function(playerId)
    for victimId, session in pairs(lootSessions) do
        if session.robber == playerId then
            finalizeLootSession(victimId)
        end
    end
end)

-- Cleanup

AddEventHandler('playerDropped', function()
    local source = source

    -- Robber left mid-robbery
    local victimId = activeByRobber[source]
    if victimId then
        stopRobbery(victimId, false)
    end

    -- Victim left mid-robbery
    if activeByVictim[source] then
        stopRobbery(source, true, 'target_left')
    end

    -- Free any loot locks (shipping their pending logs) and limiter state
    finalizeLootSession(source)

    for victimId2, session in pairs(lootSessions) do
        if session.robber == source then
            finalizeLootSession(victimId2)
        end
    end

    rateStamps[source] = nil
end)
