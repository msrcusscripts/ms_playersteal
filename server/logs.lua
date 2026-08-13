-- ms_playersteal - Discord logging
-- Server side only. Webhook URLs live in webhooks.lua, which clients never load.

Logs = {}

local function debugLog(msg, ...)
    if Config.Debug then
        print(('[ms_playersteal] ' .. msg):format(...))
    end
end

Logs.Debug = debugLog

-- Discord logging
-- Everything here runs exclusively on the server. Webhook URLs live in
-- webhooks.lua (server-only) so they are never streamed to clients.

local serverName = GetConvar('sv_projectName', '')
if serverName == '' then serverName = GetConvar('sv_hostname', 'FiveM Server') end
serverName = serverName:gsub('%^%d', '')

-- ox_inventory item names treated as currency in the log
local MONEY_ITEMS = { money = 'Cash', black_money = 'Black Money' }

-- Used to turn the equipped weapon hash into a readable name in the embed
local WEAPON_NAMES = {
    'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL',
    'WEAPON_SNSPISTOL', 'WEAPON_SNSPISTOL_MK2', 'WEAPON_HEAVYPISTOL', 'WEAPON_VINTAGEPISTOL',
    'WEAPON_MARKSMANPISTOL', 'WEAPON_REVOLVER', 'WEAPON_REVOLVER_MK2', 'WEAPON_DOUBLEACTION',
    'WEAPON_CERAMICPISTOL', 'WEAPON_NAVYREVOLVER', 'WEAPON_GADGETPISTOL', 'WEAPON_STUNGUN',
    'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW',
    'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG', 'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2',
    'WEAPON_SAWNOFFSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_ASSAULTSHOTGUN', 'WEAPON_HEAVYSHOTGUN',
    'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2',
    'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_BULLPUPRIFLE', 'WEAPON_COMPACTRIFLE',
    'WEAPON_MILITARYRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_SNIPERRIFLE', 'WEAPON_MARKSMANRIFLE',
    'WEAPON_KNIFE', 'WEAPON_BAT', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_CROWBAR',
    'WEAPON_SWITCHBLADE', 'WEAPON_KNUCKLE', 'WEAPON_NIGHTSTICK', 'WEAPON_GOLFCLUB',
}

---Resolves the webhook for a log kind; returns nil when logging is disabled
---or the URL is missing/invalid, so every caller no-ops gracefully.
local function getWebhook(kind)
    if not Config.EnableDiscordLogs then return nil end

    local main = type(Config.DiscordWebhook) == 'string' and Config.DiscordWebhook or ''
    local suspicious = type(Config.DiscordSuspiciousWebhook) == 'string' and Config.DiscordSuspiciousWebhook or ''

    local url = main
    if kind == 'suspicious' and suspicious ~= '' then
        url = suspicious
    end

    if url == '' or not url:find('^https://') then return nil end

    return url
end

---Discord rejects empty and oversized strings; clamp both ends.
-- 1234567 -> 1,234,567
local function comma(n)
    local s = tostring(math.floor(tonumber(n) or 0))
    local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    return (out:gsub('^,', ''))
end

local function clampField(text, limit)
    text = tostring(text or '')
    if text == '' then return '-' end

    limit = limit or 1024
    if #text > limit then
        text = text:sub(1, limit - 3) .. '...'
    end

    return text
end

---Webhook display name: Discord rejects names containing 'discord' or
---'clyde' (case-insensitive), so fall back to a safe default when needed.
local function getBotName()
    local name = type(Config.DiscordBotName) == 'string' and Config.DiscordBotName or ''

    if name == '' or name:lower():find('discord', 1, true) or name:lower():find('clyde', 1, true) then
        return 'Steal Logs'
    end

    return clampField(name, 80)
end

---Fire-and-forget webhook post via PerformHttpRequest. Never throws.
---Delivery failures are ALWAYS logged together with Discord's response body
---(which names the exact rejected field); successes print in debug mode.
local function sendDiscordEmbed(kind, embed)
    local url = getWebhook(kind)
    if not url then
        return debugLog('%s webhook skipped: logging disabled or no valid https URL', kind)
    end

    local icon = type(Config.DiscordAvatar) == 'string' and Config.DiscordAvatar:find('^https://')
        and Config.DiscordAvatar or nil

    embed.footer = {
        text = ('%s • %s'):format(serverName, os.date('%Y-%m-%d %H:%M:%S')),
        icon_url = icon,
    }
    embed.timestamp = os.date('!%Y-%m-%dT%H:%M:%S.000Z') -- ISO-8601 UTC, as Discord expects
    embed.color = tonumber(embed.color) or 15158332

    if icon then
        embed.author = embed.author or {}
        embed.author.icon_url = icon
        embed.thumbnail = embed.thumbnail or { url = icon }
    end

    local payload = {
        username = getBotName(),
        embeds = { embed },
    }

    if icon then
        payload.avatar_url = icon
    end

    local body = json.encode(payload)
    debugLog('%s webhook payload: %s', kind, body)

    PerformHttpRequest(url, function(statusCode, responseBody, _, errorData)
        if statusCode == 200 or statusCode == 204 then
            debugLog('%s webhook delivered (status %s)', kind, statusCode)
        else
            print(('[ms_playersteal] [WEBHOOK] %s webhook failed (status %s): %s'):format(
                kind, statusCode, tostring(responseBody or errorData or 'no response body')))
        end
    end, 'POST', body, { ['Content-Type'] = 'application/json' })
end

---'Name (ID x)' plus an identifier line, for embed fields.
function Logs.DescribePlayer(playerId)
    return ('%s (ID %s)\n`%s`'):format(GetPlayerName(playerId) or 'unknown', playerId, Bridge.GetIdentifier(playerId))
end

local itemDefs

---Label and (optional) configured price for an item, from ox_inventory data.
local function getItemInfo(name)
    if not itemDefs then
        local ok, defs = pcall(function()
            return exports.ox_inventory:Items()
        end)
        itemDefs = ok and type(defs) == 'table' and defs or {}
    end

    local def = itemDefs[name]
    if not def then return name, nil end

    return def.label or name, tonumber(def.price)
end

---Aggregated item name -> count snapshot of a player's inventory.
-- Rough in-world location for the embed
function Logs.DescribeZone(playerId)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return nil end

    local c = GetEntityCoords(ped)
    return ('%.0f, %.0f, %.0f'):format(c.x, c.y, c.z)
end

-- Weapon the robber was holding, as a readable name
function Logs.DescribeWeapon(playerId)
    local ped = GetPlayerPed(playerId)
    if ped == 0 then return nil end

    local hash = GetSelectedPedWeapon(ped)
    if not hash or hash == joaat('WEAPON_UNARMED') then return 'Unarmed' end

    for _, name in ipairs(WEAPON_NAMES) do
        if joaat(name) == hash then
            return (name:gsub('^WEAPON_', ''):gsub('_', ' '):lower():gsub('^%l', string.upper))
        end
    end

    return ('Hash %s'):format(hash)
end

function Logs.Snapshot(playerId)
    local ok, items = pcall(function()
        return exports.ox_inventory:GetInventoryItems(playerId)
    end)

    if not ok or type(items) ~= 'table' then
        -- Fallback for ox_inventory builds without GetInventoryItems
        local ok2, inv = pcall(function()
            return exports.ox_inventory:GetInventory(playerId)
        end)
        items = (ok2 and type(inv) == 'table') and inv.items or nil
    end

    if type(items) ~= 'table' then
        debugLog('inventory snapshot for %s unavailable', playerId)
        return nil
    end

    local snapshot = {}

    for _, item in pairs(items) do
        if type(item) == 'table' and item.name and (item.count or 0) > 0 then
            snapshot[item.name] = (snapshot[item.name] or 0) + item.count
        end
    end

    return snapshot
end

---Everything present in `before` that is missing or reduced in `after`.
function Logs.Diff(before, after)
    local taken = {}

    for name, count in pairs(before) do
        local remaining = after[name] or 0
        if remaining < count then
            taken[name] = count - remaining
        end
    end

    return taken
end

---Builds and ships the completed-robbery embed.
---data = { robber, victim, victimState: string, taken: table|nil } where
---`taken` is an aggregated name -> count table (nil = couldn't be read).
function Logs.SendRobbery(data)
    if not getWebhook('robbery') then return end

    local itemLines, moneyLines = {}, {}
    local totalValue, hasValue = 0, false

    if data.taken then
        for name, count in pairs(data.taken) do
            if MONEY_ITEMS[name] then
                moneyLines[#moneyLines + 1] = ('%s: **$%s**'):format(MONEY_ITEMS[name], comma(count))
                totalValue = totalValue + count
                hasValue = true
            else
                local label, price = getItemInfo(name)
                itemLines[#itemLines + 1] = ('`%sx` %s'):format(count, label)

                if price then
                    totalValue = totalValue + price * count
                    hasValue = true
                end
            end
        end
    end

    table.sort(itemLines)
    table.sort(moneyLines)

    -- Keep the items field under Discord's 1024 character limit
    local itemsText
    if not data.taken then
        itemsText = 'Unavailable'
    elseif #itemLines == 0 then
        itemsText = 'None'
    else
        itemsText = table.concat(itemLines, '\n')

        if #itemsText > 1000 then
            local shown, length = {}, 0
            for i = 1, #itemLines do
                length = length + #itemLines[i] + 1
                if length > 950 then
                    shown[#shown + 1] = ('...and %s more'):format(#itemLines - i + 1)
                    break
                end
                shown[#shown + 1] = itemLines[i]
            end
            itemsText = table.concat(shown, '\n')
        end
    end

    local itemCount = 0
    for _, count in pairs(data.taken or {}) do itemCount = itemCount + count end

    local fields = {
        { name = '🔫 Robber', value = clampField(data.robber), inline = true },
        { name = '🎯 Victim', value = clampField(data.victim), inline = true },
        { name = '📍 State', value = clampField(data.victimState), inline = true },
    }

    if data.location then
        fields[#fields + 1] = { name = '🗺️ Location', value = clampField(data.location), inline = true }
    end

    if data.weapon then
        fields[#fields + 1] = { name = '🔪 Weapon Used', value = clampField(data.weapon), inline = true }
    end

    fields[#fields + 1] = { name = '⏱️ Duration', value = clampField(data.duration or 'N/A'), inline = true }
    fields[#fields + 1] = { name = ('🎒 Items Taken (%s)'):format(itemCount), value = clampField(itemsText), inline = false }
    fields[#fields + 1] = { name = '💵 Money Taken', value = clampField(#moneyLines > 0 and table.concat(moneyLines, '\n') or 'None'), inline = true }
    fields[#fields + 1] = { name = '💰 Estimated Value', value = clampField(hasValue and ('$%s'):format(comma(totalValue)) or 'N/A'), inline = true }

    sendDiscordEmbed('robbery', {
        title = '💰 Robbery Completed',
        description = ('**%s** robbed **%s**'):format(
            data.robberName or 'Unknown', data.victimName or 'Unknown'),
        color = tonumber(Config.DiscordColor) or 15158332,
        fields = fields,
    })
end

---Ends a loot session: works out what was taken and ships the log. Safe to
---call for any victim id; does nothing when no session exists.

if Config.EnableDiscordLogs and not getWebhook('robbery') then
    print('[ms_playersteal] Discord logs are enabled but no valid https webhook URL is set in webhooks.lua')
end

---Console test: run `ms_webhook_test` in the server console (players need
---the command.ms_webhook_test ace) to send a test embed to both webhooks.
RegisterCommand('ms_webhook_test', function()
    if not getWebhook('robbery') then
        print('[ms_playersteal] [WEBHOOK] test aborted: enable Config.EnableDiscordLogs and set a valid https URL in webhooks.lua')
        return
    end

    sendDiscordEmbed('robbery', {
        title = 'Webhook Test',
        color = tonumber(Config.DiscordColor) or 15158332,
        description = 'If you can read this, robbery logging is delivering correctly.',
        fields = {
            { name = 'Resource', value = 'ms_playersteal', inline = true },
            { name = 'Sent', value = os.date('%Y-%m-%d %H:%M:%S'), inline = true },
        },
    })

    if type(Config.DiscordSuspiciousWebhook) == 'string' and Config.DiscordSuspiciousWebhook ~= '' then
        sendDiscordEmbed('suspicious', {
            title = 'Webhook Test (Suspicious Channel)',
            color = tonumber(Config.DiscordSuspiciousColor) or 15105570,
            description = 'If you can read this, suspicious-activity logging is delivering correctly.',
        })
    end

    print('[ms_playersteal] [WEBHOOK] test sent - check Discord; any failure is printed here with the reason')
end, true)

---Always logged: things a legitimate client can't normally produce. Also
---shipped to the suspicious-activity Discord webhook when configured.
function Logs.Suspicious(playerId, reason)
    print(('[ms_playersteal] [SECURITY] %s (id %s): %s'):format(
        GetPlayerName(playerId) or 'unknown', playerId, reason))

    sendDiscordEmbed('suspicious', {
        title = '⚠️ Suspicious Activity',
        color = tonumber(Config.DiscordSuspiciousColor) or 15105570,
        fields = {
            { name = '👤 Player', value = clampField(('%s (ID %s)'):format(GetPlayerName(playerId) or 'unknown', playerId)), inline = true },
            { name = '🆔 Identifier', value = clampField(('`%s`'):format(Bridge.GetIdentifier(playerId))), inline = true },
            { name = '📝 Detection', value = clampField(reason), inline = false },
        },
    })
end
