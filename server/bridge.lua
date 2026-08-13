-- ms_playersteal - framework bridge (server)
-- Detects and wraps the running framework so the rest of the resource stays
-- framework-agnostic. Supported: ESX (es_extended), QBCore (qb-core) and
-- Qbox (qbx_core). To add another framework, extend the three functions below.

Bridge = {}

local framework
local core

if GetResourceState('es_extended') == 'started' then
    framework = 'esx'

    -- Modern ESX exposes the shared object as an export; keep a fallback for
    -- older builds so the resource runs on any ESX version.
    local ok, obj = pcall(function()
        return exports['es_extended']:getSharedObject()
    end)

    if ok and obj then
        core = obj
    else
        TriggerEvent('esx:getSharedObject', function(o) core = o end)
    end
elseif GetResourceState('qbx_core') == 'started' then
    -- Checked before qb-core on purpose: Qbox servers often run a qb-core
    -- compatibility bridge as well, and the native qbx_core exports are
    -- preferred in that case.
    framework = 'qbox'
elseif GetResourceState('qb-core') == 'started' then
    framework = 'qbcore'
    core = exports['qb-core']:GetCoreObject()
end

Bridge.Framework = framework

if framework then
    print(('[ms_playersteal] framework detected: %s'):format(framework))
else
    print('[ms_playersteal] ^1no supported framework found (es_extended / qbx_core / qb-core) - start one of them before this resource^0')
end

---Returns the framework player object, or nil when the player isn't loaded.
function Bridge.GetPlayer(playerId)
    if framework == 'esx' then
        if not core then return nil end
        return core.GetPlayerFromId(playerId)
    elseif framework == 'qbox' then
        return exports.qbx_core:GetPlayer(playerId)
    elseif framework == 'qbcore' then
        if not core then return nil end
        return core.Functions.GetPlayer(playerId)
    end

    return nil
end

---Returns the player's current job name ('unemployed' when unknown).
function Bridge.GetJob(playerId)
    local player = Bridge.GetPlayer(playerId)
    if not player then return 'unemployed' end

    if framework == 'esx' then
        return player.job and player.job.name or 'unemployed'
    end

    -- qbox and qbcore share the PlayerData layout
    local job = player.PlayerData and player.PlayerData.job
    return job and job.name or 'unemployed'
end

---Returns a persistent per-character identifier used for cooldown storage:
---the ESX identifier or the QB/Qbox citizenid. Falls back to the server id
---when the player object is unavailable.
function Bridge.GetIdentifier(playerId)
    local player = Bridge.GetPlayer(playerId)

    if player then
        if framework == 'esx' then
            if player.identifier then return player.identifier end
        elseif player.PlayerData and player.PlayerData.citizenid then
            return player.PlayerData.citizenid
        end
    end

    return ('src:%s'):format(playerId)
end
