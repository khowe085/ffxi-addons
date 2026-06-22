-- Reusable configuration-window chrome: header, optional tab bar, scrollable body,
-- footer (Save/Discard), right-side scroll buttons, dragging, and click-blocking.
--
-- Registers NO Windower events and holds no addon state. The texts library (and an
-- optional images library) are injected via opts so the module is testable in
-- isolation, mirroring the io_provider dependency injection in settings.lua.

local config_gui = {}

local ROW_HEIGHT = 18
local HEADER_ROWS = 1
local FOOTER_ROWS = 1
local TABBAR_ROWS = 1
local BUTTON_W = 18

local BTN_MARGIN = 4
local BTN_GAP = 6
local BODY_PAD = 4
local BODY_FONT = 'Consolas'
local BODY_FONT_SIZE = 11
local BTN_FONT_SIZE = 11
local GLYPH_W = 7
-- Vertical inset of the centered label text within its full-height button.
local BTN_TEXT_INSET = 2

local DEFAULT_WIDTH = 400
local DEFAULT_HEIGHT = 200

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function sign(n)
  if n > 0 then return 1 end
  if n < 0 then return -1 end
  return 0
end

-- Point-in-rect hit-test. Chrome hit-testing uses this against rects computed in
-- layout() rather than texts:hover, because the real Windower texts:hover tests
-- rendered glyph extents (not the layout regions), which would mis-hit in-game.
local function point_in(r, x, y)
  return r ~= nil and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

-- Lua 5.1 (and Windower) ship no utf8 library, so this falls back to '...'.
local ELLIPSIS = (utf8 and utf8.char(0x2026)) or '...'

-- Truncate a line to `cols` columns, appending ELLIPSIS when it was longer.
local function clip_line(line, cols)
  line = tostring(line or '')
  if #line <= cols then return line end
  local ew = #ELLIPSIS
  if cols <= ew then return line:sub(1, cols) end
  return line:sub(1, cols - ew) .. ELLIPSIS
end

-- Forward declarations of private functions (each takes the state table).
local active_tab
local body_cols
local body_viewport
local has_tab_bar
local hide_all
local install_tabs
local layout
local over_window
local render_active
local update_scroll_chrome
local visible_rows

function config_gui.new(opts)
  opts = opts or {}
  assert(opts.texts, 'config_gui.new requires opts.texts')

  local size = opts.size or {}
  local pos  = opts.pos or {}

  local state = {
    texts       = opts.texts,
    images      = opts.images,
    title       = opts.title or '',
    on_save     = opts.on_save,
    on_discard  = opts.on_discard,
    on_move     = opts.on_move,
    width       = size.width or DEFAULT_WIDTH,
    height      = size.height or DEFAULT_HEIGHT,
    anchor_x    = pos.x or 0,
    anchor_y    = pos.y or 0,
    open        = false,
    draggable   = false,
    dragging    = false,
    drag_dx     = 0,
    drag_dy     = 0,
    -- A left click is a down (mtype 1) + up (mtype 2) pair. When the down over
    -- Save/Discard closes the window, the paired up would otherwise hit the
    -- `not state.open` guard and leak to the game. This flag remembers to swallow
    -- exactly that one orphaned up so every event over the window stays consumed.
    swallow_up  = false,
    tabs        = {},
    active      = 1,
    offsets     = {},
    tab_labels  = {},
    prev_custom = nil,
    win         = { x = 0, y = 0, width = 0, height = 0 },
    rects       = { tabs = {} },
  }

  local txt = state.texts

  -- Solid window backdrop. A texts element cannot draw a fixed-size rectangle
  -- (its bg sizes to content), so the backdrop is drawn with the injected images
  -- library when available; otherwise the window is chromeless but still blocks
  -- clicks via the over_window rect.
  if state.images and state.images.new then
    state.bg = state.images.new({
      pos   = { x = 0, y = 0 },
      size  = { width = state.width, height = state.height },
      color = { alpha = 200, red = 0, green = 0, blue = 0 },
      flags = { draggable = false },
    })
    -- Created after bg so these draw on top of it. Re-sized/positioned in layout.
    state.header_bg = state.images.new({
      pos   = { x = 0, y = 0 },
      size  = { width = state.width, height = ROW_HEIGHT },
      color = { alpha = 235, red = 30, green = 40, blue = 60 },
      flags = { draggable = false },
    })
    state.footer_bg = state.images.new({
      pos   = { x = 0, y = 0 },
      size  = { width = state.width, height = ROW_HEIGHT },
      color = { alpha = 235, red = 30, green = 40, blue = 60 },
      flags = { draggable = false },
    })
    state.save_bg = state.images.new({
      pos   = { x = 0, y = 0 },
      size  = { width = ROW_HEIGHT, height = ROW_HEIGHT },
      color = { alpha = 255, red = 40, green = 70, blue = 110 },
      flags = { draggable = false },
    })
    state.discard_bg = state.images.new({
      pos   = { x = 0, y = 0 },
      size  = { width = ROW_HEIGHT, height = ROW_HEIGHT },
      color = { alpha = 255, red = 110, green = 45, blue = 45 },
      flags = { draggable = false },
    })
  end

  state.panel   = txt.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
  state.header  = txt.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
  state.body    = txt.new('', {
    pos   = { x = 0, y = 0 },
    text  = { font = BODY_FONT, size = BODY_FONT_SIZE },
    flags = { draggable = false },
  })
  -- Footer button labels: explicit monospace font/size so glyph width is known
  -- and predictable (GLYPH_W) and the text never renders at Windower's default
  -- size and overflow the colored button background. A transparent text bg lets
  -- the save_bg/discard_bg image show through behind the centered label.
  state.save    = txt.new('', {
    pos     = { x = 0, y = 0 },
    text    = { font = BODY_FONT, size = BTN_FONT_SIZE },
    bg      = { visible = false },
    padding = 0,
    flags   = { draggable = false },
  })
  state.discard = txt.new('', {
    pos     = { x = 0, y = 0 },
    text    = { font = BODY_FONT, size = BTN_FONT_SIZE },
    bg      = { visible = false },
    padding = 0,
    flags   = { draggable = false },
  })
  state.up      = txt.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
  state.down    = txt.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })

  state.header:text(state.title)
  state.save:text('Save')
  state.discard:text('Discard')
  state.up:text(utf8 and utf8.char(0x25B2) or '^')
  state.down:text(utf8 and utf8.char(0x25BC) or 'v')

  -- Disable native dragging on every chrome element so the window moves ONLY via
  -- the helper's synthetic header drag. Windower images/texts honor native drag
  -- unless :draggable(false) is also called (flags.draggable is not enough).
  if state.bg then state.bg:draggable(false) end
  if state.header_bg then state.header_bg:draggable(false) end
  if state.footer_bg then state.footer_bg:draggable(false) end
  if state.save_bg then state.save_bg:draggable(false) end
  if state.discard_bg then state.discard_bg:draggable(false) end
  state.panel:draggable(false)
  state.header:draggable(false)
  state.body:draggable(false)
  state.save:draggable(false)
  state.discard:draggable(false)
  state.up:draggable(false)
  state.down:draggable(false)

  local gui = {}

  -- Public methods (alphabetical)

  function gui:destroy()
    state.open = false
    state.dragging = false
    for _, label in ipairs(state.tab_labels) do
      label:destroy()
    end
    state.tab_labels = {}
    if state.bg then state.bg:destroy() end
    if state.header_bg then state.header_bg:destroy() end
    if state.footer_bg then state.footer_bg:destroy() end
    if state.save_bg then state.save_bg:destroy() end
    if state.discard_bg then state.discard_bg:destroy() end
    state.panel:destroy()
    state.header:destroy()
    state.body:destroy()
    state.save:destroy()
    state.discard:destroy()
    state.up:destroy()
    state.down:destroy()
  end

  function gui:handle_mouse(mtype, x, y, delta)
    -- A window-closing Save/Discard ran on the paired DOWN, so the matching UP
    -- arrives after state.open is already false. Consume that one orphaned up
    -- here (before the open guard) so it never leaks through to the game.
    -- This swallows the next mouse-up regardless of intervening events; the OS
    -- click down/up are adjacent in practice, so consuming the next up is safe.
    if mtype == 2 and state.swallow_up then
      state.swallow_up = false
      return true
    end
    if not state.open then return false end

    if state.dragging then
      if mtype == 0 then
        layout(state, x - state.drag_dx, y - state.drag_dy)
        render_active(state)
        return true
      elseif mtype == 2 then
        state.dragging = false
        if state.on_move then state.on_move(state.anchor_x, state.anchor_y) end
        return true
      end
      return true
    end

    if not over_window(state, x, y) then return false end

    if mtype == 1 then
      if point_in(state.rects.save, x, y) then
        if state.on_save then state.on_save() end
        if not state.open then state.swallow_up = true end
        return true
      end
      if point_in(state.rects.discard, x, y) then
        if state.on_discard then state.on_discard() end
        if not state.open then state.swallow_up = true end
        return true
      end
      if has_tab_bar(state) then
        for i = 1, #state.rects.tabs do
          if point_in(state.rects.tabs[i], x, y) then
            gui:select_tab(i)
            return true
          end
        end
      end
      local active = active_tab(state)
      local is_custom = active and active.render ~= nil
      if not is_custom then
        if point_in(state.rects.up, x, y) then
          gui:scroll(-1)
          return true
        end
        if point_in(state.rects.down, x, y) then
          gui:scroll(1)
          return true
        end
      end
      if state.draggable and point_in(state.rects.header, x, y) then
        state.dragging = true
        state.drag_dx = x - state.anchor_x
        state.drag_dy = y - state.anchor_y
        return true
      end
    end

    local active = active_tab(state)
    local vp = body_viewport(state)
    if active and active.render and active.on_mouse then
      if x >= vp.x and x < vp.x + vp.width and y >= vp.y and y < vp.y + vp.height then
        active.on_mouse(x - vp.x, y - vp.y, mtype, delta)
        return true
      end
    elseif mtype == 10 and active and not active.render then
      gui:scroll(-sign(delta or 0))
      return true
    end

    return true
  end

  function gui:hide()
    if state.prev_custom and state.prev_custom.hide then
      state.prev_custom.hide()
    end
    state.prev_custom = nil
    state.open = false
    state.dragging = false
    hide_all(state)
  end

  function gui:is_open()
    return state.open
  end

  function gui:scroll(delta)
    local active = active_tab(state)
    if not active or active.render then return end
    local lines = active.lines or {}
    local max_off = math.max(0, #lines - visible_rows(state))
    local cur = state.offsets[state.active] or 0
    state.offsets[state.active] = clamp(cur + delta, 0, max_off)
    render_active(state)
  end

  function gui:select_tab(i)
    i = clamp(i, 1, math.max(1, #state.tabs))
    if state.prev_custom and state.prev_custom ~= state.tabs[i] and state.prev_custom.hide then
      state.prev_custom.hide()
      state.prev_custom = nil
    end
    state.active = i
    render_active(state)
  end

  function gui:set_draggable(b)
    state.draggable = b and true or false
    if not state.draggable then
      state.dragging = false
    end
  end

  function gui:set_pos(x, y)
    state.anchor_x = x
    state.anchor_y = y
    if state.open then
      layout(state, x, y)
      render_active(state)
    end
  end

  function gui:set_tabs(tabs)
    install_tabs(state, tabs)
    if state.open then
      layout(state, state.anchor_x, state.anchor_y)
      render_active(state)
    end
  end

  function gui:show(tabs)
    install_tabs(state, tabs)
    state.open = true
    state.swallow_up = false
    layout(state, state.anchor_x, state.anchor_y)
    if state.bg then state.bg:show() end
    if state.header_bg then state.header_bg:show() end
    if state.footer_bg then state.footer_bg:show() end
    if state.save_bg then state.save_bg:show() end
    if state.discard_bg then state.discard_bg:show() end
    state.panel:show()
    state.header:show()
    state.save:show()
    state.discard:show()
    if has_tab_bar(state) then
      for _, label in ipairs(state.tab_labels) do
        label:show()
      end
    end
    render_active(state)
  end

  -- Test-only accessors

  function gui:_body_text_for_test()
    return state.body:text()
  end

  function gui:_scroll_visible_for_test()
    return state.scroll_visible == true
  end

  function gui:_has_tab_bar_for_test()
    return has_tab_bar(state)
  end

  function gui:_tab_labels_for_test()
    return state.tab_labels
  end

  function gui:_bg_for_test()
    return state.bg
  end

  function gui:_band_for_test(name)
    return state[name]
  end

  function gui:_chrome_for_test()
    return {
      panel   = state.panel,
      header  = state.header,
      body    = state.body,
      save    = state.save,
      discard = state.discard,
      up      = state.up,
      down    = state.down,
    }
  end

  function gui:_rects_for_test()
    return state.rects
  end

  function gui:_body_cols_for_test()
    return body_cols(state)
  end

  return gui
end

-- Private functions (alphabetical)

function active_tab(state)
  return state.tabs[state.active]
end

function body_cols(state)
  return math.max(1, math.floor((state.width - BUTTON_W - 2 * BODY_PAD) / GLYPH_W))
end

function body_viewport(state)
  local top_rows = HEADER_ROWS + (has_tab_bar(state) and TABBAR_ROWS or 0)
  local x = state.anchor_x
  local y = state.anchor_y + top_rows * ROW_HEIGHT
  local width = state.width - BUTTON_W
  local height = state.height - (top_rows + FOOTER_ROWS) * ROW_HEIGHT
  return { x = x, y = y, width = width, height = height }
end

function has_tab_bar(state)
  return #state.tabs > 1
end

function hide_all(state)
  if state.bg then state.bg:hide() end
  if state.header_bg then state.header_bg:hide() end
  if state.footer_bg then state.footer_bg:hide() end
  if state.save_bg then state.save_bg:hide() end
  if state.discard_bg then state.discard_bg:hide() end
  state.panel:hide()
  state.header:hide()
  state.body:hide()
  state.save:hide()
  state.discard:hide()
  state.up:hide()
  state.down:hide()
  for _, label in ipairs(state.tab_labels) do
    label:hide()
  end
end

function install_tabs(state, tabs)
  tabs = tabs or {}
  for _, label in ipairs(state.tab_labels) do
    label:destroy()
  end
  state.tab_labels = {}
  state.tabs = tabs
  state.active = clamp(state.active, 1, math.max(1, #tabs))
  local new_offsets = {}
  for i, tab in ipairs(tabs) do
    new_offsets[i] = state.offsets[i] or 0
    local label = state.texts.new('', { pos = { x = 0, y = 0 }, flags = { draggable = false } })
    label:text(tab.title or ('Tab ' .. i))
    label:draggable(false)
    state.tab_labels[i] = label
  end
  state.offsets = new_offsets
end

function layout(state, anchor_x, anchor_y)
  state.anchor_x = anchor_x
  state.anchor_y = anchor_y
  state.win.x = anchor_x
  state.win.y = anchor_y
  state.win.width = state.width
  state.win.height = state.height

  -- Position an element and record its hit-rect under state.rects[name].
  local set = function(el, name, dx, dy, w, h)
    el:pos(anchor_x + dx, anchor_y + dy)
    el._width = w
    el._height = h
    if name then
      state.rects[name] = { x = anchor_x + dx, y = anchor_y + dy, w = w, h = h }
    end
  end

  -- One shared button rect per footer button drives the colored background, the
  -- hit-rect, AND the centered label so all three always coincide. The buttons
  -- fill the full footer ROW_HEIGHT (not a 12px inset) keeping only the
  -- horizontal BTN_MARGIN/BTN_GAP insets, so the visible blue/red strip is the
  -- whole clickable area and the label never spills past the colored chip.
  -- btn_y = footer_y keeps the top edge below the window top (footer_y > 0) and
  -- the bottom edge (btn_y + btn_h) flush with, never past, the window bottom.
  local footer_y = state.height - FOOTER_ROWS * ROW_HEIGHT
  local half_w = math.floor(state.width / 2)
  local g = math.floor(BTN_GAP / 2)
  local btn_y = footer_y
  local btn_h = FOOTER_ROWS * ROW_HEIGHT
  local save_x = BTN_MARGIN
  local save_w = (half_w - g) - BTN_MARGIN
  local discard_x = half_w + g
  local discard_w = (state.width - BTN_MARGIN) - (half_w + g)

  if state.bg then
    state.bg:pos(anchor_x, anchor_y)
    state.bg:size(state.width, state.height)
  end

  if state.header_bg then
    state.header_bg:pos(anchor_x, anchor_y)
    state.header_bg:size(state.width, HEADER_ROWS * ROW_HEIGHT)
  end
  if state.footer_bg then
    state.footer_bg:pos(anchor_x, anchor_y + footer_y)
    state.footer_bg:size(state.width, FOOTER_ROWS * ROW_HEIGHT)
  end
  if state.save_bg then
    state.save_bg:pos(anchor_x + save_x, anchor_y + btn_y)
    state.save_bg:size(save_w, btn_h)
  end
  if state.discard_bg then
    state.discard_bg:pos(anchor_x + discard_x, anchor_y + btn_y)
    state.discard_bg:size(discard_w, btn_h)
  end

  set(state.panel, 'panel', 0, 0, state.width, state.height)
  set(state.header, 'header', 0, 0, state.width, ROW_HEIGHT)

  state.rects.tabs = {}
  local top_rows = HEADER_ROWS
  if has_tab_bar(state) then
    local label_w = math.floor((state.width - BUTTON_W) / #state.tabs)
    local label_y = HEADER_ROWS * ROW_HEIGHT
    for i, label in ipairs(state.tab_labels) do
      local lx = (i - 1) * label_w
      label:pos(anchor_x + lx, anchor_y + label_y)
      label._width = label_w
      label._height = ROW_HEIGHT
      state.rects.tabs[i] = { x = anchor_x + lx, y = anchor_y + label_y, w = label_w, h = ROW_HEIGHT }
    end
    top_rows = top_rows + TABBAR_ROWS
  end

  local body_top = top_rows * ROW_HEIGHT
  local body_h = state.height - (top_rows + FOOTER_ROWS) * ROW_HEIGHT
  set(state.body, 'body', 0, body_top, state.width - BUTTON_W, body_h)

  local half = math.floor(body_h / 2)
  set(state.up, 'up', state.width - BUTTON_W, body_top, BUTTON_W, half)
  set(state.down, 'down', state.width - BUTTON_W, body_top + half, BUTTON_W, body_h - half)

  -- Footer buttons: record the FULL-button hit-rect (the whole colored chip is
  -- clickable) while positioning the label text at a horizontally centered offset
  -- inside that rect. set() would force the text to the rect's top-left, so the
  -- text :pos() and the rect assignment are done separately here. The label width
  -- is the known monospace glyph width times the character count.
  local place_button = function(el, name, bx, bw)
    local label = el:text()
    local text_w = GLYPH_W * #label
    local tx = bx + math.max(0, math.floor((bw - text_w) / 2))
    el:pos(anchor_x + tx, anchor_y + btn_y + BTN_TEXT_INSET)
    el._width = bw
    el._height = btn_h
    state.rects[name] = { x = anchor_x + bx, y = anchor_y + btn_y, w = bw, h = btn_h }
  end
  place_button(state.save, 'save', save_x, save_w)
  place_button(state.discard, 'discard', discard_x, discard_w)
end

function over_window(state, x, y)
  local w = state.win
  return x >= w.x and x < w.x + w.width and y >= w.y and y < w.y + w.height
end

function render_active(state)
  local active = active_tab(state)
  if not active then
    state.body:text('')
    update_scroll_chrome(state)
    return
  end
  if active.render then
    state.body:hide()
    update_scroll_chrome(state)
    local vp = body_viewport(state)
    active.render(vp, { texts = state.texts, images = state.images })
    state.prev_custom = active
    return
  end
  if state.prev_custom and state.prev_custom ~= active and state.prev_custom.hide then
    state.prev_custom.hide()
  end
  state.prev_custom = nil
  local lines = active.lines or {}
  local offset = state.offsets[state.active] or 0
  local rows = visible_rows(state)
  local cols = body_cols(state)
  local slice = {}
  for i = offset + 1, math.min(#lines, offset + rows) do
    slice[#slice + 1] = clip_line(lines[i], cols)
  end
  state.body:text(table.concat(slice, '\n'))
  if state.open then state.body:show() end
  update_scroll_chrome(state)
end

function update_scroll_chrome(state)
  local active = active_tab(state)
  local show_scroll = false
  if active and not active.render then
    local lines = active.lines or {}
    show_scroll = #lines > visible_rows(state)
  end
  if state.open and show_scroll then
    state.up:show()
    state.down:show()
  else
    state.up:hide()
    state.down:hide()
  end
  state.scroll_visible = show_scroll
end

function visible_rows(state)
  local top_rows = HEADER_ROWS + (has_tab_bar(state) and TABBAR_ROWS or 0)
  local body_h = state.height - (top_rows + FOOTER_ROWS) * ROW_HEIGHT
  return math.max(1, math.floor(body_h / ROW_HEIGHT))
end

return config_gui
