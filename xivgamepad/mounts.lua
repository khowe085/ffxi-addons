-- Owned-mount tracking and roulette adapter (contract:
-- .planning/xivgamepad-contracts.md, "mounts") over the ported
-- crossbar/mountroulette lib. No Windower event registration here: main wires
-- incoming chunk 0x055 -> refresh() and also calls refresh() from init().
-- Every entry point no-ops safely while logged out (get_player() is nil).

local mount_roulette = require('crossbar/mountroulette')
local log = require('log')
local resources = require('resources')

local M = {}

local display_name, logged_in

function M.has_mounts()
  if not logged_in() then return false end
  return #mount_roulette:get_allowed_mounts() > 0
end

function M.list()
  if not logged_in() then return {} end
  local names = {}
  for _, owned in ipairs(mount_roulette:get_allowed_mounts()) do
    local display = display_name(owned)
    if display then
      names[#names + 1] = display
    end
  end
  table.sort(names)
  return names
end

function M.refresh()
  if not logged_in() then return end
  mount_roulette.refresh()
  log.debug('mounts: refreshed, %d owned', #mount_roulette:get_allowed_mounts())
end

function M.ride_random()
  if not logged_in() then return end
  mount_roulette:ride_random_mount()
end

-- Display-name matching rule: the ported lib derives each owned mount by
-- matching a Mounts-category key item ('♪<mount name>...') against res.mounts
-- and stores the res.mounts name LOWERCASED. Reverse that here — the display
-- name is the res.mounts entry whose en, lowercased, equals the lib's stored
-- name — so names always come from res.mounts, never a hardcoded map.
display_name = function(owned)
  for _, mount in pairs(resources.mounts) do
    if mount.en:lower() == owned then
      return mount.en
    end
  end
  log.debug('mounts: no res.mounts display entry for "%s"', tostring(owned))
  return nil
end

logged_in = function()
  return windower.ffxi.get_player() ~= nil
end

return M
