-- ms_playersteal - hands up
-- Built-in hands up toggle so the resource does not depend on an emote menu.
-- Purely cosmetic on this side: the server still verifies the animation on
-- the victim's own client before allowing a robbery, so nothing here grants
-- any authority.
-- Anticheat notes: the animation is started with TaskPlayAnim (upper body,
-- looped) and stopped with StopAnimTask. No ClearPedTasks / ClearPedTasksImmediately,
-- no weapon give/remove, no health or invincibility natives, no entity
-- creation - all of which are common anticheat detections.

local handsUp = false

---Conditions under which hands up may not be raised or must drop.
local function canHoldHandsUp()
    local ped = cache.ped

    if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then return false end
    if Config.HandsUpBlockInVehicle and cache.vehicle then return false end

    return true
end

---Stops the animation and releases the control lock.
local function lowerHands()
    if not handsUp then return end
    handsUp = false

    local anim = Config.HandsUpAnim

    -- Same blend value as going up, so hands drop exactly as fast as they rise
    StopAnimTask(cache.ped, anim.dict, anim.clip, Config.HandsUpBlendSpeed)
end

---Starts the animation and the control-disable loop. The loop exits as soon
---as hands go down, so there is no idle cost when nobody has their hands up.
local function raiseHands()
    if handsUp or not canHoldHandsUp() then return end

    local anim = Config.HandsUpAnim

    if not lib.requestAnimDict(anim.dict, 1000) then return end

    handsUp = true

    local blend = Config.HandsUpBlendSpeed

    TaskPlayAnim(cache.ped, anim.dict, anim.clip, blend, -blend, -1, 50, 0, false, false, false)

    CreateThread(function()
        local frames = 0

        while handsUp do
            -- Can't shoot or aim with your hands in the air
            DisablePlayerFiring(cache.playerId, true)
            DisableControlAction(0, 24, true)  -- attack
            DisableControlAction(0, 25, true)  -- aim
            DisableControlAction(0, 47, true)  -- weapon
            DisableControlAction(0, 257, true) -- attack 2
            DisableControlAction(0, 263, true) -- melee attack 1

            frames = frames + 1

            -- Roughly twice a second: drop the pose if the situation changed
            -- and restart the clip if something else interrupted it.
            if frames >= 30 then
                frames = 0

                if not canHoldHandsUp() then
                    lowerHands()
                    break
                end

                if not IsEntityPlayingAnim(cache.ped, anim.dict, anim.clip, 3) then
                    TaskPlayAnim(cache.ped, anim.dict, anim.clip, blend, -blend, -1, 50, 0, false, false, false)
                end
            end

            Wait(0)
        end
    end)
end

local function toggleHandsUp()
    if handsUp then
        lowerHands()
    else
        raiseHands()
    end
end

-- Keybind / command

if Config.EnableHandsUpKeybind then
    RegisterCommand(Config.HandsUpCommand, function()
        toggleHandsUp()
    end, false)

    -- Players can rebind this under Settings > Key Bindings > FiveM
    RegisterKeyMapping(Config.HandsUpCommand, 'Hands up', 'keyboard', Config.HandsUpKey)
end

-- Safety

-- Drop the pose on death so the animation can't linger through a respawn
AddEventHandler('gameEventTriggered', function(name, args)
    if name == 'CEventNetworkEntityDamage' and handsUp then
        local victim, died = args[1], args[6]
        if died == 1 and victim == cache.ped then
            lowerHands()
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        lowerHands()
    end
end)

---Other resources can query or drive the pose:
---exports.ms_playersteal:IsHandsUp() / :SetHandsUp(true|false)
exports('IsHandsUp', function()
    return handsUp
end)

exports('SetHandsUp', function(state)
    if state then raiseHands() else lowerHands() end
end)
