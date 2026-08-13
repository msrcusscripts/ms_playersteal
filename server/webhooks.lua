-- ms_playersteal - webhook URLs (server only)
-- SAFE TO EDIT: this file is excluded from Asset Escrow protection so you
-- can paste your own webhook URLs here.
-- It is intentionally loaded ONLY on the server: anything in a shared file
-- (like config.lua) is downloaded by every client, and a leaked webhook URL
-- lets anyone spam or delete your Discord channel feed.

-- Webhook for completed robbery logs
Config.DiscordWebhook = ''

-- Optional separate webhook for suspicious activity / exploit attempts.
-- Leave empty to send those to Config.DiscordWebhook instead.
Config.DiscordSuspiciousWebhook = ''
