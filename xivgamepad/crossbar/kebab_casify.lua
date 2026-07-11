-- PORT: from xivcrossbar/libs/kebab_casify.lua (xivgamepad crossbar port;
-- see .planning/xivgamepad-contracts.md, "crossbar/ subtree rule").
-- Edits: none -- ported verbatim (this comment block and CRLF endings only).

local kebab_casify = function(str)
    return str:lower():gsub('?', 'QMARK'):gsub('/', '\n'):gsub(':', ''):gsub('-', ' '):gsub('%p', ''):gsub(' ', '-'):gsub('\n', '/'):gsub('QMARK', '?')
end

return kebab_casify
