--[[
    ms_playersteal - configuration

    SAFE TO EDIT. This file is excluded from Asset Escrow protection, so
    everything below can be changed freely. All other Lua files are encrypted
    and must not be modified, renamed or removed.

    CONTENTS
        1.  Robbery rules ......... who can be robbed and when
        2.  Interaction ........... distance and ox_target option
        3.  Timing ................ duration, progress bar, animation
        4.  Cooldowns ............. set to 0 to disable
        5.  Weapon requirement .... require a firearm to rob
        6.  Hands up .............. built-in toggle and detection
        7.  Jobs .................. whitelist / blacklist
        8.  Notifications ......... every message, individually toggleable
        9.  Discord logging ....... webhook appearance
        10. Debug ................. console logging
]]

Config = {}

--[[ ============================================================
     1. ROBBERY RULES
     ============================================================ ]]

-- Can dead / incapacitated players (per wasabi_ambulance) be robbed?
Config.AllowRobbingDead = true

-- Treat wasabi's "last stand" (downed and bleeding out, not fully dead)
-- as dead for robbery purposes?
Config.TreatLastStandAsDead = true

-- Must LIVING players have their hands up before they can be robbed?
-- Set false to allow robbing any living player in range.
Config.RequireHandsUp = true

-- Cancel an in-progress robbery if a living victim lowers their hands
Config.CancelIfHandsDown = true

--[[ ============================================================
     2. INTERACTION
     ============================================================ ]]

-- Distance (metres) at which the ox_target option appears
Config.InteractionDistance = 2.0

-- Hard server-side range, checked at the start of a robbery, while it runs
-- and again on completion. Kept slightly larger than InteractionDistance so
-- small movements and desync don't instantly cancel it.
Config.MaxRobberyDistance = 4.0

-- ox_target option appearance
Config.TargetIcon = 'fa-solid fa-sack-dollar'
Config.TargetLabel = 'Rob Player'

--[[ ============================================================
     3. TIMING
     ============================================================ ]]

Config.RobberyDuration = 7500              -- milliseconds
Config.ProgressLabel = 'Robbing player...'
Config.ProgressStyle = 'bar'               -- 'bar' or 'circle'

-- Frisking animation played by the robber while the progress bar runs
Config.RobberAnim = {
    dict = 'mini@repair',
    clip = 'fixing_a_ped',
    flag = 49,
}

--[[ ============================================================
     4. COOLDOWNS (seconds)
     Set any value to 0 to switch that cooldown off completely.
     ============================================================ ]]

Config.RobberCooldown = 60    -- before the same robber can rob again
Config.VictimCooldown = 120   -- before the same victim can be robbed again
Config.FailedCooldown = 10    -- after a cancelled or failed attempt

--[[ ============================================================
     5. WEAPON REQUIREMENT
     ============================================================ ]]

-- Require the robber to be holding a firearm. Verified server side at the
-- start, during the robbery and on completion. Set false to disable.
Config.RequireWeapon = true

-- Leave empty to accept any firearm, or list specific weapons to allow only
-- those, e.g. { 'WEAPON_PISTOL', 'WEAPON_SNSPISTOL' }.
Config.AllowedWeapons = {}

-- Never counted as a firearm, even when AllowedWeapons is empty
Config.NonFirearms = {
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER',
    'WEAPON_BAT', 'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_BOTTLE',
    'WEAPON_DAGGER', 'WEAPON_HATCHET', 'WEAPON_KNUCKLE', 'WEAPON_MACHETE',
    'WEAPON_FLASHLIGHT', 'WEAPON_SWITCHBLADE', 'WEAPON_POOLCUE',
    'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET',
    'WEAPON_PETROLCAN', 'WEAPON_FIREEXTINGUISHER', 'WEAPON_HAZARDCAN',
    'WEAPON_FERTILIZERCAN', 'WEAPON_BALL', 'WEAPON_SNOWBALL',
    'WEAPON_FLARE', 'WEAPON_MOLOTOV',
}

--[[ ============================================================
     6. HANDS UP
     ============================================================ ]]

-- Built-in toggle. Set false if another script (emote menu, etc.) already
-- handles hands up - detection is animation based, so robbery still works.
Config.EnableHandsUpKeybind = true

Config.HandsUpCommand = 'handsup'    -- also usable as /handsup
Config.HandsUpKey = 'X'              -- rebindable in FiveM key bindings
Config.HandsUpBlockInVehicle = true  -- drop hands when entering a vehicle
Config.HandsUpBlendSpeed = 8.0       -- same speed up and down; higher is faster

-- Pose used by the built-in toggle. Must also appear in HandsUpAnims below.
Config.HandsUpAnim = { dict = 'random@mugging3', clip = 'handsup_standing_base' }

-- Animations that count as "hands up". Add your emote resource's animation
-- here if you disabled the built-in toggle.
Config.HandsUpAnims = {
    { dict = 'random@mugging3',     clip = 'handsup_standing_base' },
    { dict = 'missminuteman_1ig_2', clip = 'handsup_base' },
    { dict = 'missminuteman_1ig_2', clip = 'handsup_enter' },
}

-- Visual only: helps ox_target decide when to SHOW the option on peds that
-- look downed. The real death check always happens server side.
Config.DownedAnims = {
    { dict = 'dead',                 clip = 'dead_a' },
    { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
    { dict = 'missfinale_c1@',       clip = 'lying_dead_player0' },
}

--[[ ============================================================
     7. JOBS
     ============================================================ ]]

-- When true, ONLY jobs in JobWhitelist may rob (JobBlacklist is ignored).
Config.UseJobWhitelist = false

Config.JobWhitelist = {
    -- ['gangster'] = true,
}

-- Jobs that may never rob players (used when UseJobWhitelist is false)
Config.JobBlacklist = {
    ['police'] = true,
    ['sheriff'] = true,
    ['ambulance'] = true,
}

--[[ ============================================================
     8. NOTIFICATIONS
     Passed straight to lib.notify. EnableNotifications turns every message
     off at once; each entry can also be switched off with its own `enabled`
     flag. Disabling a message never changes gameplay behaviour.
     ============================================================ ]]

Config.EnableNotifications = true

Config.Notifications = {
    -- Success
    robbery_success   = { enabled = true, title = 'Robbery', description = 'You rummage through their pockets.', type = 'success' },
    being_robbed      = { enabled = true, title = 'Robbery', description = 'You are being robbed!', type = 'error' },

    -- Blocked before starting
    not_robbable      = { enabled = true, title = 'Robbery', description = 'You can\'t rob this person right now.', type = 'error' },
    need_weapon       = { enabled = true, title = 'Robbery', description = 'You need a weapon in hand.', type = 'error' },
    job_blocked       = { enabled = true, title = 'Robbery', description = 'Your job does not allow this.', type = 'error' },
    robber_cooldown   = { enabled = true, title = 'Robbery', description = 'You need to lay low for a while.', type = 'error' },
    victim_cooldown   = { enabled = true, title = 'Robbery', description = 'This person has already been shaken down.', type = 'error' },
    target_busy       = { enabled = true, title = 'Robbery', description = 'Someone is already robbing this player.', type = 'error' },
    robber_busy       = { enabled = true, title = 'Robbery', description = 'You are already busy.', type = 'error' },
    cannot_now        = { enabled = true, title = 'Robbery', description = 'You can\'t do that right now.', type = 'error' },

    -- Interrupted mid-robbery
    robbery_cancelled = { enabled = true, title = 'Robbery', description = 'Robbery cancelled.', type = 'error' },
    too_far           = { enabled = true, title = 'Robbery', description = 'You moved too far away.', type = 'error' },
    target_left       = { enabled = true, title = 'Robbery', description = 'Your target is gone.', type = 'error' },
}

--[[ ============================================================
     9. DISCORD LOGGING
     Webhook URLs live in server/webhooks.lua, which only the server loads.
     Never put a webhook URL in this file - shared config is downloaded by
     every client.
     ============================================================ ]]

Config.EnableDiscordLogs = false

Config.DiscordBotName = 'Steal Logs'

-- Upload steal_logs.png somewhere public (Discord, imgur, your own host) and
-- paste the direct https URL here. Used for the webhook avatar, the embed
-- author icon and the embed thumbnail.
Config.DiscordAvatar = ''

Config.DiscordColor = 15158332            -- robbery embeds (red)
Config.DiscordSuspiciousColor = 15105570  -- suspicious activity embeds (orange)

--[[ ============================================================
     10. DEBUG
     ============================================================ ]]

-- Verbose validation logging in the server console. Suspicious activity is
-- always logged regardless of this setting.
Config.Debug = false

--[[ ============================================================
     Internal - no need to edit below this line
     ============================================================ ]]

-- Returns a notification, or nil when it is disabled globally or per entry.
function Config.GetNotification(key)
    if not Config.EnableNotifications then return nil end

    local data = Config.Notifications[key]
    if not data or data.enabled == false then return nil end

    return data
end
