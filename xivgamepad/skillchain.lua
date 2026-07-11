-- Skillchain adapter (contract: .planning/xivgamepad-contracts.md,
-- "Crossbar port amendments" -> skillchain). Thin gate in front of the ported
-- resonance state machine (crossbar/skillchain/skillchains.lua): main owns all
-- Windower event registration and forwards events here.
--
-- Enabled gate: init injects a getter for the skillchain_display setting.
-- While disabled -- or before init, or with no player logged in -- every
-- handler is a no-op and every query returns nil. on_logout/on_zone_change
-- are pure state clears and skip only the enabled gate (at logout time the
-- player is already gone, so a logged-in guard would strand stale state).
--
-- on_action forwards the RAW windower 'action' event table unchanged: the
-- ported handler wraps it itself via ActionPacket.new (and also reads
-- act.param directly), so wrapping here would double-wrap.

local skillchains = require('crossbar/skillchain/skillchains')

local enabled_getter = nil

local M = {}

local active, enabled

function M.init(opts)
  enabled_getter = opts and opts.enabled or nil
end

function M.on_action(act)
  if not active() then return end
  skillchains.handle_action(act)
end

function M.on_incoming_chunk(id, data)
  if not active() then return end
  skillchains.incoming_chunk(id, data)
end

function M.on_job_change(job_abbrev)
  if not active() then return end
  skillchains.job_change(job_abbrev)
end

function M.on_login()
  if not active() then return end
  -- login seeds the player identity; load seeds the player's buff table (the
  -- source addon ran both when it started while logged in).
  skillchains.login()
  skillchains.load()
end

function M.on_logout()
  if not enabled() then return end
  skillchains.logout()
end

function M.on_zone_change()
  if not enabled() then return end
  skillchains.zone_change()
end

function M.prop_for(id, res_key)
  if not active() then return nil end
  return skillchains.get_skillchain_result(id, res_key)
end

function M.tick()
  if not active() then return end
  skillchains.prerender()
end

function M.window()
  if not active() then return nil end
  return skillchains.get_skillchain_window()
end

active = function()
  return enabled() and windower.ffxi.get_player() ~= nil
end

enabled = function()
  return enabled_getter ~= nil and not not enabled_getter()
end

return M
