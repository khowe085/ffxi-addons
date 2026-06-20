-- Stubs for Windower globals required by lib/settings

windower = {
  ffxi = {
    _player = { name = 'TestChar' },
    get_player = function() return windower.ffxi._player end,
  },
}
