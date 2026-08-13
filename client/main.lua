-- ms_playersteal - client
-- The client only handles targeting, animations and the progress bar.
-- Every decision that matters (who may rob whom, when, and the inventory
-- access itself) is validated and executed on the server.

local robbing = false

-- Helpers

---Is a ped currently playing one of the configured hands-up animations?
local function isPedHandsUp(ped)
    for i = 1, #Config.HandsUpAnims do
        local anim = Config.HandsUpAnims[i]
        if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
            return true
        end
    end
    return false
end

---Visual-only check used to decide when to display the target option on a ped
---that looks dead / downed. Combines native death checks, the state bags that
---wasabi_ambulance syncs for every player and a few downed animations.
---The authoritative check is always done server-side.
local function looksDead(ped, serverId)
    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) or IsPedFatallyInjured(ped) then
        return true
    end

    -- wasabi_ambulance state bags: false/nil while alive, 'dead' when dead,
    -- 'laststand' while downed (older builds use isDead / laststand keys).
    local state = Player(serverId).state
    if state.dead or state.isDead or state.laststand then
        return true
    end

    for i = 1, #Config.DownedAnims do
        local anim = Config.DownedAnims[i]
        if IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then
            return true
        end
    end

    return false
end

---Resolve the server id behind a player ped. Returns nil for invalid peds,
---NPCs and the local player.
local function getServerIdFromPed(entity)
    if not entity or entity == 0 or not IsPedAPlayer(entity) then return nil end

    local playerIndex = NetworkGetPlayerIndexFromPed(entity)
    if not playerIndex or playerIndex == -1 then return nil end

    local serverId = GetPlayerServerId(playerIndex)
    if not serverId or serverId == 0 or serverId == cache.serverId then return nil end

    return serverId
end

local function notify(key)
    local data = Config.GetNotification(key)
    if data then lib.notify(data) end
end

-- Robbery flow

---Lightweight watcher that only runs while a robbery is in progress:
---being ragdolled (shot, tased, rammed...) or dying interrupts the robbery.
local function watchInterruptions()
    CreateThread(function()
        while robbing do
            if IsPedRagdoll(cache.ped) or IsEntityDead(cache.ped) then
                lib.cancelProgress()
                break
            end
            Wait(250)
        end
    end)
end

local function startRobbery(entity)
    if robbing then return end

    local targetId = getServerIdFromPed(entity)
    if not targetId then return end

    -- The server decides whether this robbery may start (state, distance,
    -- locks, cooldowns, job...). The client never assumes anything.
    local approved, reason = lib.callback.await('ms_playersteal:requestStart', false, targetId)

    if not approved then
        if reason then notify(reason) end
        return
    end

    robbing = true
    watchInterruptions()

    local progress = Config.ProgressStyle == 'circle' and lib.progressCircle or lib.progressBar
    local finished = progress({
        duration = Config.RobberyDuration,
        label = Config.ProgressLabel,
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = Config.RobberAnim.dict,
            clip = Config.RobberAnim.clip,
            flag = Config.RobberAnim.flag or 49,
        },
    })

    robbing = false

    -- The server re-validates timing, distance and the target's state before
    -- granting access to the victim's inventory.
    TriggerServerEvent('ms_playersteal:finish', finished == true)
end

-- Callbacks / events

-- Called by the server ON THE VICTIM'S client to confirm the hands-up state.
-- A robber can never fake this for somebody else.
lib.callback.register('ms_playersteal:handsUp', function()
    return isPedHandsUp(cache.ped)
end)

-- The server cancels our in-progress robbery (victim ran away, disconnected,
-- lowered their hands, we got downed...).
RegisterNetEvent('ms_playersteal:cancelProgress', function()
    if robbing then
        lib.cancelProgress()
    end
end)

-- Target option

exports.ox_target:addGlobalPlayer({
    {
        name = 'ms_playersteal:rob',
        icon = Config.TargetIcon,
        label = Config.TargetLabel,
        distance = Config.InteractionDistance,
        canInteract = function(entity)
            if robbing then return false end

            local serverId = getServerIdFromPed(entity)
            if not serverId then return false end

            -- Display filter only: the final validation is server-side.
            if looksDead(entity, serverId) then
                return Config.AllowRobbingDead
            end

            if Config.RequireHandsUp then
                return isPedHandsUp(entity)
            end

            return true
        end,
        onSelect = function(data)
            startRobbery(data.entity)
        end,
    },
})
