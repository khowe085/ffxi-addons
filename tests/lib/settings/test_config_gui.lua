local config_gui = require('lib.settings.config_gui')

local pass = 0
local fail = 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    io.write('  pass: ' .. name .. '\n')
  else
    fail = fail + 1
    io.write('  FAIL: ' .. name .. '\n    ' .. tostring(err) .. '\n')
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    error(string.format('%s\n    expected: %s\n      actual: %s',
      msg or 'values not equal', tostring(expected), tostring(actual)), 2)
  end
end

local function assert_true(v, msg)
  if not v then error(msg or 'expected true', 2) end
end

local function contains(haystack, needle)
  return (haystack or ''):find(needle, 1, true) ~= nil
end

-- Exact whole-line membership: avoids 'line 1' matching 'line 10'.
local function has_line(body, line)
  for got in (body .. '\n'):gmatch('(.-)\n') do
    if got == line then return true end
  end
  return false
end

-- Build a controller with recorded callback fires.
local function make_gui(opts)
  opts = opts or {}
  local rec = { save = 0, discard = 0, moves = {} }
  local gui = config_gui.new({
    texts      = texts,
    images     = opts.images,
    title      = opts.title or 'Echo',
    on_save    = function() rec.save = rec.save + 1 end,
    on_discard = function() rec.discard = rec.discard + 1 end,
    on_move    = function(x, y) rec.moves[#rec.moves + 1] = { x = x, y = y } end,
    pos        = opts.pos or { x = 100, y = 100 },
    size       = opts.size or { width = 320, height = 160 },
  })
  return gui, rec
end

local function text_tab(title, n)
  local lines = {}
  for i = 1, n do lines[i] = title .. ' line ' .. i end
  return { title = title, lines = lines }
end

-- Center point of an element (uses the mock's tracked geometry).
local function center(el)
  return el._x + math.floor(el._width / 2), el._y + math.floor(el._height / 2)
end

-- Center of a layout hit-rect ({ x, y, w, h } from _rects_for_test()).
local function rect_center(r)
  return r.x + math.floor(r.w / 2), r.y + math.floor(r.h / 2)
end

-- ----

test('construction honors size: window rect matches body + chrome', function()
  -- size describes the BODY area; the total window is body + chrome. For one tab
  -- and body 320x160: total_width = 320+18 = 338, total_height = 18+160+36 = 214.
  local gui = make_gui({ pos = { x = 50, y = 60 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 3) })
  local tw, th = 320 + 18, 18 + 160 + 36
  -- A point at the far corner inside the window is consumed; just outside is not.
  assert_true(gui:handle_mouse(3, 50 + tw - 1, 60 + th - 1), 'inside far corner consumed')
  assert_eq(false, gui:handle_mouse(3, 50 + tw, 60 + th), 'just outside not consumed')
  assert_eq(false, gui:handle_mouse(3, 49, 60), 'just left of window not consumed')
end)

test('construction: footer sits within the window bottom', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 3) })
  -- The footer band is the bottom of the window; clicking the Save button (now a
  -- right-aligned fixed-width chip) fires Save.
  local sx, sy = rect_center(gui:_rects_for_test().save)
  assert_true(gui:handle_mouse(1, sx, sy), 'click on the Save button consumed')
  assert_eq(1, rec.save, 'Save-button click hit Save (footer at window bottom)')
end)

test('show/hide/is_open', function()
  local gui = make_gui()
  assert_eq(false, gui:is_open(), 'closed initially')
  gui:show({ text_tab('General', 2) })
  assert_eq(true, gui:is_open(), 'open after show')
  gui:hide()
  assert_eq(false, gui:is_open(), 'closed after hide')
end)

test('images backdrop is created, sized to the window, and shown/hidden with it', function()
  local gui = make_gui({ pos = { x = 40, y = 50 }, images = images, size = { width = 320, height = 160 } })
  local bg = gui:_bg_for_test()
  assert_true(bg ~= nil, 'backdrop created when images injected')
  gui:show({ text_tab('General', 2) })
  -- size is the body; the backdrop spans the TOTAL window (body + chrome):
  -- width 320+18 = 338, height 18+160+36 = 214.
  assert_eq(40, bg._x, 'backdrop at window x')
  assert_eq(50, bg._y, 'backdrop at window y')
  assert_eq(338, bg._width, 'backdrop spans total window width')
  assert_eq(214, bg._height, 'backdrop spans total window height')
  assert_eq(true, bg._visible, 'backdrop shown with window')
  gui:hide()
  assert_eq(false, bg._visible, 'backdrop hidden with window')
end)

test('construction without images has no backdrop but still blocks clicks', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  assert_eq(nil, gui:_bg_for_test(), 'no backdrop when images omitted')
  gui:show({ text_tab('General', 2) })
  assert_true(gui:handle_mouse(3, 10, 10), 'right-click over window still blocked')
end)

test('Save click fires on_save and returns true', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('General', 2) })
  -- Save is the left chip of the right-aligned footer pair.
  local sx, sy = rect_center(gui:_rects_for_test().save)
  assert_true(gui:handle_mouse(1, sx, sy), 'save click consumed')
  assert_eq(1, rec.save, 'on_save fired once')
  assert_eq(0, rec.discard, 'discard not fired')
end)

test('Discard click fires on_discard and returns true', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('General', 2) })
  -- Discard is the right chip of the right-aligned footer pair.
  local dx, dy = rect_center(gui:_rects_for_test().discard)
  assert_true(gui:handle_mouse(1, dx, dy), 'discard click consumed')
  assert_eq(1, rec.discard, 'on_discard fired once')
  assert_eq(0, rec.save, 'save not fired')
end)

test('click on empty window space returns true but fires no callback', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('General', 2) })
  -- A point inside the body away from any control.
  assert_true(gui:handle_mouse(1, 60, 50), 'empty-space click consumed')
  assert_eq(0, rec.save, 'no save')
  assert_eq(0, rec.discard, 'no discard')
end)

test('click outside the window returns false', function()
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('General', 2) })
  assert_eq(false, gui:handle_mouse(1, 500, 500), 'click far outside not consumed')
end)

test('right/middle/wheel over window are blocked', function()
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('General', 2) })
  assert_true(gui:handle_mouse(3, 60, 50), 'right-down over window blocked')
  assert_true(gui:handle_mouse(4, 60, 50), 'right-up over window blocked')
  assert_true(gui:handle_mouse(10, 60, 50, 1), 'wheel over window blocked')
  assert_eq(false, gui:handle_mouse(3, 500, 500), 'right-down outside not blocked')
end)

test('handle_mouse on closed window always returns false', function()
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  assert_eq(false, gui:handle_mouse(1, 10, 10), 'closed: no consume')
  assert_eq(false, gui:handle_mouse(2, 10, 10), 'closed: no consume on up')
end)

test('window drag moves all elements together and fires on_move once on release', function()
  local gui, rec = make_gui({ pos = { x = 100, y = 100 }, images = images, size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  gui:show({ text_tab('General', 2) })

  -- Snapshot every chrome rect's top-left before the drag (the rects table is
  -- mutated in place by layout, so copy the values, not the reference).
  local names = { 'panel', 'header', 'body', 'save', 'discard', 'up', 'down' }
  local before = {}
  local rects = gui:_rects_for_test()
  for _, n in ipairs(names) do
    before[n] = { x = rects[n].x, y = rects[n].y }
  end
  local bg = gui:_bg_for_test()
  local bg_before = { x = bg._x, y = bg._y }

  -- Drag the header (row y=100..118 at anchor 100,100) by +30,+40.
  assert_true(gui:handle_mouse(1, 110, 105), 'header left-down starts drag')
  assert_true(gui:handle_mouse(0, 140, 145), 'move re-anchors')
  assert_true(gui:handle_mouse(2, 140, 145), 'release ends drag')

  assert_eq(1, #rec.moves, 'on_move fired exactly once')
  assert_eq(130, rec.moves[1].x, 'new anchor x')
  assert_eq(140, rec.moves[1].y, 'new anchor y')

  -- Every element (incl. the scroll buttons and the images backdrop) shifted by the same delta.
  local after = gui:_rects_for_test()
  for _, n in ipairs(names) do
    assert_eq(before[n].x + 30, after[n].x, n .. ' shifted x by +30')
    assert_eq(before[n].y + 40, after[n].y, n .. ' shifted y by +40')
  end
  assert_eq(bg_before.x + 30, bg._x, 'backdrop shifted x by +30')
  assert_eq(bg_before.y + 40, bg._y, 'backdrop shifted y by +40')
end)

test('window drag re-anchors so the window rect follows', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  gui:show({ text_tab('General', 2) })
  gui:handle_mouse(1, 10, 5)
  gui:handle_mouse(0, 60, 55)
  gui:handle_mouse(2, 60, 55)
  -- Window now at (50,50)..(370,210). Old origin (10,10) is outside.
  assert_eq(false, gui:handle_mouse(1, 10, 10), 'old region no longer over window')
  assert_true(gui:handle_mouse(1, 60, 60), 'new region is over window')
end)

test('set_draggable(false) prevents drag', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 } })
  gui:set_draggable(false)
  gui:show({ text_tab('General', 2) })
  assert_true(gui:handle_mouse(1, 10, 5), 'header click still consumed')
  -- A move event with no active drag, over the window, is consumed but does not re-anchor.
  gui:handle_mouse(0, 60, 55)
  gui:handle_mouse(2, 60, 55)
  assert_eq(0, #rec.moves, 'on_move not fired when not draggable')
  -- Window did not move: original origin still over window.
  assert_true(gui:handle_mouse(1, 10, 10), 'origin still over window')
end)

test('an active drag keeps blocking even after the cursor leaves the window', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  gui:show({ text_tab('General', 2) })
  assert_true(gui:handle_mouse(1, 10, 5), 'header left-down starts drag')
  -- Move far outside the original window rect: still consumed because a drag is active.
  assert_true(gui:handle_mouse(0, 5000, 5000), 'move far outside still consumed mid-drag')
  assert_true(gui:handle_mouse(2, 5000, 5000), 'release outside still consumed')
  assert_eq(1, #rec.moves, 'on_move fired once on release')
end)

test('text scrolling: slice respects visible_rows; buttons move the slice', function()
  -- size is the BODY: body 160 => floor(160/18) = 8 rows (independent of the
  -- footer). Provide 10 lines so rows 9-10 start hidden.
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  local tab = text_tab('General', 10)
  gui:show({ tab })
  local body = nil
  -- Find the body element: it is the one whose text contains 'General line 1'
  -- We expose it through handle_mouse-driven scrolling, asserting on the slice.
  local function body_text()
    return gui:_body_text_for_test()
  end
  assert_true(has_line(body_text(), 'General line 1'), 'first line shown')
  assert_true(has_line(body_text(), 'General line 8'), 'eighth line shown')
  assert_eq(false, has_line(body_text(), 'General line 9'), 'ninth line hidden initially')

  gui:scroll(1)
  assert_true(has_line(body_text(), 'General line 2'), 'after scroll, line 2 top')
  assert_eq(false, has_line(body_text(), 'General line 1'), 'line 1 scrolled off')

  -- clamp at bottom
  gui:scroll(100)
  assert_true(has_line(body_text(), 'General line 10'), 'last line visible at bottom')
  gui:scroll(100)
  assert_true(has_line(body_text(), 'General line 10'), 'still clamped at bottom')

  -- clamp at top
  gui:scroll(-100)
  assert_true(has_line(body_text(), 'General line 1'), 'back to top after negative scroll')
  gui:scroll(-100)
  assert_true(has_line(body_text(), 'General line 1'), 'still clamped at top')
end)

test('scroll buttons visible when content overflows, inert/hidden when it fits', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 10) })
  assert_eq(true, gui:_scroll_visible_for_test(), 'scroll shown when overflowing')

  gui:set_tabs({ text_tab('General', 2) })
  assert_eq(false, gui:_scroll_visible_for_test(), 'scroll hidden when content fits')
end)

test('down/up scroll-button clicks advance and reverse the slice', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 10) })
  -- The scroll column is chrome at the right edge of the body: x in [body_w,
  -- body_w + BUTTON_W) == [320, 338). Down is the lower half.
  local up = gui:_rects_for_test().up
  local down = gui:_rects_for_test().down
  local ux, uy = rect_center(up)
  local dx, dy = rect_center(down)
  assert_true(gui:handle_mouse(1, ux, uy), 'up button click consumed')
  -- already at top, slice unchanged
  assert_true(has_line(gui:_body_text_for_test(), 'General line 1'), 'still at top after up')
  assert_true(gui:handle_mouse(1, dx, dy), 'down button click consumed')
  assert_true(has_line(gui:_body_text_for_test(), 'General line 2'), 'down advanced slice')
  assert_eq(false, has_line(gui:_body_text_for_test(), 'General line 1'), 'line 1 gone after down')
  assert_true(gui:handle_mouse(1, ux, uy), 'up button click consumed')
  assert_true(has_line(gui:_body_text_for_test(), 'General line 1'), 'up reversed slice')
end)

test('wheel over text body scrolls', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 10) })
  assert_true(gui:handle_mouse(10, 60, 50, -1), 'wheel down consumed')
  assert_true(has_line(gui:_body_text_for_test(), 'General line 2'), 'wheel down scrolled forward')
  assert_eq(false, has_line(gui:_body_text_for_test(), 'General line 1'), 'line 1 gone on wheel down')
  assert_true(gui:handle_mouse(10, 60, 50, 1), 'wheel up consumed')
  assert_true(has_line(gui:_body_text_for_test(), 'General line 1'), 'wheel up scrolled back')
end)

test('one tab: no tab bar; tab content shown', function()
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  gui:show({ text_tab('Only', 3) })
  assert_eq(false, gui:_has_tab_bar_for_test(), 'no tab bar with one tab')
  assert_true(contains(gui:_body_text_for_test(), 'Only line 1'), 'tab content shown')
end)

test('two tabs: tab bar shown with titles; click tab 2 selects + blocks', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  gui:show({ text_tab('Alpha', 3), text_tab('Beta', 3) })
  assert_eq(true, gui:_has_tab_bar_for_test(), 'tab bar shown with 2 tabs')
  local labels = gui:_tab_labels_for_test()
  assert_eq('Alpha', labels[1]:text(), 'tab 1 title')
  assert_eq('Beta', labels[2]:text(), 'tab 2 title')
  assert_true(contains(gui:_body_text_for_test(), 'Alpha line 1'), 'tab 1 active initially')

  -- Tab bar is the second row (y in [18,36)); tab 2 occupies the right portion.
  local x2 = math.floor(320 / 2) + 5
  assert_true(gui:handle_mouse(1, x2, 25), 'tab 2 click consumed')
  assert_true(contains(gui:_body_text_for_test(), 'Beta line 1'), 'tab 2 now active')
end)

test('per-tab scroll offsets are independent', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  gui:show({ text_tab('Alpha', 20), text_tab('Beta', 20) })
  -- size is the BODY: body 200 => floor(200/18) = 11 rows, independent of the
  -- tab bar and footer.
  gui:scroll(3)
  assert_eq(false, has_line(gui:_body_text_for_test(), 'Alpha line 1'), 'alpha scrolled')
  gui:select_tab(2)
  assert_true(has_line(gui:_body_text_for_test(), 'Beta line 1'), 'beta starts at top')
  gui:select_tab(1)
  assert_eq(false, has_line(gui:_body_text_for_test(), 'Alpha line 1'), 'alpha offset preserved')
  assert_true(has_line(gui:_body_text_for_test(), 'Alpha line 4'), 'alpha back at offset 3')
end)

test('set_tabs with fewer tabs re-clamps the active index', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  gui:show({ text_tab('Alpha', 3), text_tab('Beta', 3), text_tab('Gamma', 3) })
  gui:select_tab(3)
  assert_true(contains(gui:_body_text_for_test(), 'Gamma line 1'), 'gamma active')
  gui:set_tabs({ text_tab('Alpha', 3) })
  assert_eq(false, gui:_has_tab_bar_for_test(), 'single tab => no bar')
  assert_true(contains(gui:_body_text_for_test(), 'Alpha line 1'), 'active clamped to tab 1')
end)

test('visible_rows scales with height', function()
  local function count_lines(s)
    local n = 0
    for _ in (s .. '\n'):gmatch('(.-)\n') do n = n + 1 end
    return n
  end
  local small = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  small:show({ text_tab('General', 30) })
  local n_small = count_lines(small:_body_text_for_test())

  local big = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 320 } })
  big:show({ text_tab('General', 30) })
  local n_big = count_lines(big:_body_text_for_test())
  assert_true(n_big > n_small, 'taller window shows more rows (' .. n_big .. ' > ' .. n_small .. ')')
end)

test('custom-tab seam: render called on show with viewport and libs', function()
  local rec = { render = {}, mouse = {}, hidden = 0 }
  local fake_images = {}
  local rec_gui, _ = make_gui({ pos = { x = 0, y = 0 }, images = fake_images, size = { width = 320, height = 160 } })
  local tab = {
    title = 'Custom',
    render = function(vp, libs)
      rec.render[#rec.render + 1] = { vp = vp, libs = libs }
    end,
    on_mouse = function(rx, ry, mtype, delta)
      rec.mouse[#rec.mouse + 1] = { rx = rx, ry = ry, mtype = mtype, delta = delta }
    end,
    hide = function() rec.hidden = rec.hidden + 1 end,
  }
  rec_gui:show({ tab })
  assert_eq(1, #rec.render, 'render called once on show')
  local vp = rec.render[1].vp
  assert_true(vp.x ~= nil and vp.y ~= nil and vp.width ~= nil and vp.height ~= nil, 'vp has rect')
  assert_eq(texts, rec.render[1].libs.texts, 'texts injected')
  assert_eq(fake_images, rec.render[1].libs.images, 'images injected')

  -- left-down inside the body viewport forwards body-relative coords and returns true
  assert_true(rec_gui:handle_mouse(1, vp.x + 7, vp.y + 9, 0), 'body click consumed')
  assert_eq(1, #rec.mouse, 'on_mouse forwarded')
  assert_eq(7, rec.mouse[1].rx, 'body-relative x')
  assert_eq(9, rec.mouse[1].ry, 'body-relative y')

  -- chrome scroll buttons hidden for a custom tab
  assert_eq(false, rec_gui:_scroll_visible_for_test(), 'no scroll chrome for custom tab')
end)

test('custom-tab seam: window drag re-calls render with moved viewport', function()
  local renders = {}
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  local tab = {
    title = 'Custom',
    render = function(vp) renders[#renders + 1] = { x = vp.x, y = vp.y } end,
    on_mouse = function() end,
    hide = function() end,
  }
  gui:show({ tab })
  local first = renders[#renders]
  gui:handle_mouse(1, 10, 5)
  gui:handle_mouse(0, 40, 45)
  gui:handle_mouse(2, 40, 45)
  local last = renders[#renders]
  assert_eq(first.x + 30, last.x, 'viewport x shifted by drag delta')
  assert_eq(first.y + 40, last.y, 'viewport y shifted by drag delta')
end)

test('custom-tab seam: render re-called on set_tabs', function()
  local renders = 0
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  local function custom(title)
    return {
      title = title,
      render = function() renders = renders + 1 end,
      on_mouse = function() end,
      hide = function() end,
    }
  end
  gui:show({ custom('A') })
  local after_show = renders
  assert_true(after_show >= 1, 'render called on show')
  gui:set_tabs({ custom('B') })
  assert_true(renders > after_show, 'render re-called on set_tabs')
end)

test('custom-tab seam: switching away calls the tab hide()', function()
  local hidden = 0
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  local custom = {
    title = 'Custom',
    render = function() end,
    on_mouse = function() end,
    hide = function() hidden = hidden + 1 end,
  }
  gui:show({ custom, text_tab('Text', 3) })
  gui:select_tab(2)
  assert_eq(1, hidden, 'custom hide called on switch away')
end)

test('gui:hide calls active custom tab hide()', function()
  local hidden = 0
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  local custom = {
    title = 'Custom',
    render = function() end,
    on_mouse = function() end,
    hide = function() hidden = hidden + 1 end,
  }
  gui:show({ custom })
  gui:hide()
  assert_eq(1, hidden, 'custom hide called on gui:hide')
end)

test('set_tabs updates the active tab content', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('Before', 3) })
  assert_true(contains(gui:_body_text_for_test(), 'Before line 1'), 'initial content')
  gui:set_tabs({ text_tab('After', 3) })
  assert_true(contains(gui:_body_text_for_test(), 'After line 1'), 'content replaced')
end)

test('destroy destroys all chrome elements including tab labels', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  gui:show({ text_tab('Alpha', 3), text_tab('Beta', 3) })
  local labels = gui:_tab_labels_for_test()
  gui:destroy()
  for _, label in ipairs(labels) do
    assert_eq(true, label._destroyed, 'tab label destroyed')
  end
  -- handle_mouse on a destroyed/closed gui returns false
  assert_eq(false, gui:handle_mouse(1, 10, 10), 'destroyed gui consumes nothing')
end)

test('select_tab clamps a too-low index up to tab 1', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 200 } })
  gui:show({ text_tab('Alpha', 3), text_tab('Beta', 3) })
  gui:select_tab(2)
  assert_true(contains(gui:_body_text_for_test(), 'Beta line 1'), 'beta active')
  gui:select_tab(0)
  assert_true(contains(gui:_body_text_for_test(), 'Alpha line 1'), 'index 0 clamps to tab 1')
end)

test('empty tabs list shows nothing and is safe to interact with', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({})
  assert_eq('', gui:_body_text_for_test(), 'empty body with no tabs')
  assert_eq(false, gui:_has_tab_bar_for_test(), 'no tab bar with no tabs')
  assert_eq(false, gui:_scroll_visible_for_test(), 'no scroll chrome with no tabs')
  gui:scroll(1) -- no active tab: must be a safe no-op
  assert_true(gui:handle_mouse(1, 10, 10), 'click over empty window still blocked')
end)

test('scrolling a custom tab is an inert no-op with no scroll chrome', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, images = images, size = { width = 320, height = 160 } })
  local last_vp
  local tab = {
    title = 'Custom',
    render = function(vp) last_vp = vp end,
    on_mouse = function() end,
    hide = function() end,
  }
  gui:show({ tab })
  gui:scroll(3) -- no-op, must not error
  assert_eq(false, gui:_scroll_visible_for_test(), 'custom tab shows no scroll chrome')
  -- wheel over the custom tab is forwarded (consumed) but does not turn on scroll chrome
  assert_true(gui:handle_mouse(10, last_vp.x + 5, last_vp.y + 5, 1), 'wheel over custom tab consumed')
  assert_eq(false, gui:_scroll_visible_for_test(), 'still no scroll chrome after wheel')
end)

test('set_pos while closed updates the anchor without showing', function()
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:set_pos(200, 250) -- closed: no relayout/show
  assert_eq(false, gui:is_open(), 'still closed')
  gui:show({ text_tab('General', 2) })
  -- Window is now anchored at the set position: a click there is consumed, far away is not.
  assert_true(gui:handle_mouse(1, 205, 255), 'click at new anchor consumed')
  assert_eq(false, gui:handle_mouse(1, 10, 10), 'old origin no longer over window')
end)

test('footer buttons are inset within the window', function()
  local anchor_x, anchor_y = 100, 100
  local body_w, body_h = 320, 160
  local gui = make_gui({ pos = { x = anchor_x, y = anchor_y }, images = images,
    size = { width = body_w, height = body_h } })
  gui:show({ text_tab('General', 3) })
  -- size is the BODY; the total window is body + chrome.
  local total_width = body_w + 18
  local total_height = 18 + body_h + 36
  local rects = gui:_rects_for_test()
  local save, discard = rects.save, rects.discard
  assert_true(save.x > anchor_x, 'save left edge inside the window left border')
  assert_true(discard.x + discard.w < anchor_x + total_width, 'discard right edge inside the window right border')
  assert_true(save.y + save.h <= anchor_y + total_height, 'save bottom edge inside the window bottom border')
  assert_true(discard.y + discard.h <= anchor_y + total_height, 'discard bottom edge inside the window bottom border')
  assert_true(save.y > anchor_y, 'save top edge inside the window')
  -- The pair is right-aligned with the right gap equal to the Save<->Discard gap
  -- (BTN_GAP = 6), and each button is two rows tall (FOOTER_ROWS * ROW_HEIGHT = 36).
  assert_eq(anchor_x + total_width - 6, discard.x + discard.w, 'discard right edge at the window minus BTN_GAP')
  assert_eq(36, save.h, 'save button spans two rows (2 * ROW_HEIGHT)')
  assert_eq(36, discard.h, 'discard button spans two rows (2 * ROW_HEIGHT)')
  assert_true(save.x + save.w <= discard.x, 'Save sits fully left of Discard (no overlap, gap between)')
end)

test('body viewport equals size; footer is additive (does not shrink the body)', function()
  -- The whole point of the body-based model: opts.size IS the body viewport,
  -- and the chrome (incl. the two-row footer) is added around it. So the body
  -- rect equals size exactly and the total height is size.height + chrome.
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 3) })
  local body = gui:_rects_for_test().body
  assert_eq(320, body.w, 'body viewport width equals size.width')
  assert_eq(160, body.h, 'body viewport height equals size.height (NOT reduced by the footer)')
  -- One tab => header(18) + body(160) + footer(36) = 214. Footer is purely
  -- additive: removing it would only shrink the window, never the body.
  local total_height = 18 + 160 + 36
  assert_true(gui:handle_mouse(3, 10, total_height - 1), 'bottom edge of computed total window consumed')
  assert_eq(false, gui:handle_mouse(3, 10, total_height), 'one past the computed total window not consumed')
end)

test('two tabs: tab bar adds one WINDOW row; body still equals size; footer additive', function()
  -- Two tabs => tab bar present (top_rows = 2). The body still equals size; the
  -- extra tab-bar row grows the WINDOW, not the body. With body 320x160 at anchor
  -- (0,0): header(18) + tab bar(18) + body(160) + footer(36) => total_height 232,
  -- which is exactly 18 (one ROW_HEIGHT) greater than the one-tab case (214) above,
  -- proving the tab bar adds exactly one row to the WINDOW, not the body.
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  gui:show({ text_tab('Alpha', 3), text_tab('Beta', 3) })
  local rects = gui:_rects_for_test()
  -- Body unaffected by the tab bar: still equals size exactly.
  assert_eq(320, rects.body.w, 'body width equals size.width (unaffected by the tab bar)')
  assert_eq(160, rects.body.h, 'body height equals size.height (unaffected by the tab bar)')
  -- Body sits below header(18) + tab bar(18) = 2 * ROW_HEIGHT.
  assert_eq(36, rects.body.y, 'body top below header + tab bar (2 * ROW_HEIGHT)')
  -- Footer (2 rows = 36) sits directly below the body.
  assert_eq(196, rects.save.y, 'save top below body (36 + body 160)')
  assert_eq(36, rects.save.h, 'save spans two rows (2 * ROW_HEIGHT)')
  assert_eq(232, rects.save.y + rects.save.h, 'save bottom flush with the window bottom (== total_height)')
  -- total_height = 2*18 (header+tab bar) + 160 (body) + 36 (footer) = 232;
  -- total_width = 320 (body) + 18 (BUTTON_W) = 338.
  local total_width, total_height = 320 + 18, 2 * 18 + 160 + 36
  assert_true(gui:handle_mouse(3, total_width - 1, total_height - 1), 'inside far corner consumed')
  assert_eq(false, gui:handle_mouse(3, total_width, total_height), 'just outside far corner not consumed')
end)

test('native dragging disabled on all chrome', function()
  local gui, rec = make_gui({ pos = { x = 0, y = 0 }, images = images,
    size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  -- Two tabs so a tab bar (and tab labels) exists to check.
  gui:show({ text_tab('Alpha', 2), text_tab('Beta', 2) })

  assert_eq(false, gui:_bg_for_test()._draggable, 'backdrop native drag disabled')

  -- Every image band has native drag disabled.
  for _, n in ipairs({ 'header_bg', 'footer_bg', 'save_bg', 'discard_bg' }) do
    local band = gui:_band_for_test(n)
    assert_true(band ~= nil, n .. ' band exists')
    assert_eq(false, band._draggable, n .. ' native drag disabled')
  end

  -- Every chrome text element has native drag disabled.
  for name, el in pairs(gui:_chrome_for_test()) do
    assert_eq(false, el._draggable, name .. ' native drag disabled')
  end

  -- Every tab label has native drag disabled.
  for i, label in ipairs(gui:_tab_labels_for_test()) do
    assert_eq(false, label._draggable, 'tab label ' .. i .. ' native drag disabled')
  end

  -- A move event over the BODY (not the header), with no active drag, must not
  -- re-anchor the window and must fire no on_move: dragging is header-only.
  gui:handle_mouse(0, 60, 60)
  gui:handle_mouse(2, 60, 60)
  assert_eq(0, #rec.moves, 'body move does not fire on_move')
  -- Window did not move: original origin still over the window.
  assert_true(gui:handle_mouse(1, 10, 10), 'origin still over window (no body-drag re-anchor)')
end)

test('zone bands track the window on a header drag', function()
  local gui, rec = make_gui({ pos = { x = 100, y = 100 }, images = images,
    size = { width = 320, height = 160 } })
  gui:set_draggable(true)
  gui:show({ text_tab('General', 2) })

  local band_names = { 'header_bg', 'footer_bg', 'save_bg', 'discard_bg' }
  local bands = {}
  for _, n in ipairs(band_names) do
    local band = gui:_band_for_test(n)
    assert_true(band ~= nil, n .. ' band created when images injected')
    assert_eq(true, band._visible, n .. ' shown with the window')
    bands[n] = band
  end

  local rects = gui:_rects_for_test()
  local save_before = { x = rects.save.x, y = rects.save.y }
  local discard_before = { x = rects.discard.x, y = rects.discard.y }
  local band_before = {}
  for _, n in ipairs(band_names) do
    band_before[n] = { x = bands[n]._x, y = bands[n]._y }
  end

  -- Drag the header (row y=100..118 at anchor 100,100) by +30,+40.
  assert_true(gui:handle_mouse(1, 110, 105), 'header left-down starts drag')
  assert_true(gui:handle_mouse(0, 140, 145), 'move re-anchors')
  assert_true(gui:handle_mouse(2, 140, 145), 'release ends drag')

  local after = gui:_rects_for_test()
  assert_eq(save_before.x + 30, after.save.x, 'save button shifted x by +30')
  assert_eq(save_before.y + 40, after.save.y, 'save button shifted y by +40')
  assert_eq(discard_before.x + 30, after.discard.x, 'discard button shifted x by +30')
  assert_eq(discard_before.y + 40, after.discard.y, 'discard button shifted y by +40')

  for _, n in ipairs(band_names) do
    assert_eq(band_before[n].x + 30, bands[n]._x, n .. ' shifted x by +30')
    assert_eq(band_before[n].y + 40, bands[n]._y, n .. ' shifted y by +40')
  end

  gui:hide()
  for _, n in ipairs(band_names) do
    assert_eq(false, bands[n]._visible, n .. ' hidden with the window')
  end

  gui:destroy()
  for _, n in ipairs(band_names) do
    assert_eq(true, bands[n]._destroyed, n .. ' destroyed on gui:destroy')
  end
end)

test('monospace body clip: long line truncated with ellipsis, short line verbatim', function()
  -- Mirror the module's fallback so the test stays correct if utf8 ever exists.
  local ellipsis = (utf8 and utf8.char(0x2026)) or '...'
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 320, height = 160 } })
  local cols = gui:_body_cols_for_test()
  local long = string.rep('x', 200)
  gui:show({ { title = 'General', lines = { 'General line 1', long } } })

  local body = gui:_body_text_for_test()
  local last
  for line in (body .. '\n'):gmatch('(.-)\n') do
    assert_true(#line <= cols, 'rendered line within body_cols (' .. #line .. ' <= ' .. cols .. ')')
    last = line
  end
  assert_true(has_line(body, 'General line 1'), 'short line emitted verbatim')
  -- The truncated line is shorter than its source and ends with the module's ellipsis.
  assert_true(#last < #long, 'long line was truncated (' .. #last .. ' < ' .. #long .. ')')
  assert_eq(ellipsis, last:sub(-#ellipsis), 'long line ends with the module ellipsis')
end)

test('narrow window: body_cols clamps to >= 1 and renders a single clipped line', function()
  -- At body width 30, (body_w - 2*BODY_PAD) is small, so body_cols must clamp to
  -- >= 1 and clip_line must take its cols <= #ELLIPSIS branch.
  local gui = make_gui({ pos = { x = 0, y = 0 }, size = { width = 30, height = 160 } })
  local cols = gui:_body_cols_for_test()
  assert_true(cols >= 1, 'body_cols clamps to at least 1 (got ' .. cols .. ')')

  local long = string.rep('x', 200)
  gui:show({ { title = 'General', lines = { long } } })

  local body = gui:_body_text_for_test()
  assert_eq(false, contains(body, '\n'), 'narrow body renders a single line')
  assert_true(#body <= cols, 'clipped line within body_cols (' .. #body .. ' <= ' .. cols .. ')')
  assert_true(#body >= 1, 'clipped line is non-empty')
end)

test('footer buttons fill the footer band height and the whole height is clickable', function()
  -- Bugs 1 & 2: the colored chip / hit-rect span the full footer band
  -- (FOOTER_ROWS * ROW_HEIGHT = 36), so the label cannot spill outside a
  -- clickable strip. Footer band (one tab) is y in [178, 214).
  local gui, rec = make_gui({ pos = { x = 0, y = 0 }, images = images,
    size = { width = 320, height = 160 } })
  gui:show({ text_tab('General', 3) })
  local save = gui:_rects_for_test().save
  assert_eq(36, save.h, 'save hit-rect spans the full footer band (2 * ROW_HEIGHT)')
  assert_eq(178, save.y, 'save top at the footer band top')
  assert_eq(214, save.y + save.h, 'save bottom flush with the window bottom')
  -- A click near the TOP and near the BOTTOM of the button both fire Save.
  local mid_x = save.x + math.floor(save.w / 2)
  assert_true(gui:handle_mouse(1, mid_x, save.y + 1), 'click near footer top consumed')
  assert_eq(1, rec.save, 'top-of-button click fired Save')
  assert_true(gui:handle_mouse(1, mid_x, save.y + save.h - 1), 'click near footer bottom consumed')
  assert_eq(2, rec.save, 'bottom-of-button click fired Save')
end)

test('a window-closing Save swallows the paired mouse-up so it never leaks to the game', function()
  -- Bug 3: a left click is down(1)+up(2). on_save runs on the down and closes the
  -- window; the paired up must still be consumed, not leak through to the game.
  local gui
  local saved = 0
  gui = config_gui.new({
    texts   = texts,
    title   = 'Closer',
    on_save = function()
      saved = saved + 1
      gui:hide()
    end,
    pos     = { x = 0, y = 0 },
    size    = { width = 320, height = 160 },
  })
  gui:show({ text_tab('General', 2) })
  local sx, sy = rect_center(gui:_rects_for_test().save)
  assert_true(gui:handle_mouse(1, sx, sy), 'save down consumed')
  assert_eq(1, saved, 'on_save fired once on the down')
  assert_eq(false, gui:is_open(), 'window closed by on_save')
  -- The window is now closed, but the paired up at the same coords is swallowed.
  assert_true(gui:handle_mouse(2, sx, sy), 'paired up swallowed after window-closing save')
  -- Only that one up is swallowed: a second stray up is no longer consumed.
  assert_eq(false, gui:handle_mouse(2, sx, sy), 'subsequent stray up not consumed')
end)

test('a window-closing Discard swallows the paired mouse-up so it never leaks to the game', function()
  local gui
  local discarded = 0
  gui = config_gui.new({
    texts      = texts,
    title      = 'Closer',
    on_discard = function()
      discarded = discarded + 1
      gui:hide()
    end,
    pos        = { x = 0, y = 0 },
    size       = { width = 320, height = 160 },
  })
  gui:show({ text_tab('General', 2) })
  local dx, dy = rect_center(gui:_rects_for_test().discard)
  assert_true(gui:handle_mouse(1, dx, dy), 'discard down consumed')
  assert_eq(1, discarded, 'on_discard fired once on the down')
  assert_eq(false, gui:is_open(), 'window closed by on_discard')
  assert_true(gui:handle_mouse(2, dx, dy), 'paired up swallowed after window-closing discard')
  assert_eq(false, gui:handle_mouse(2, dx, dy), 'subsequent stray up not consumed')
end)

test('a never-opened gui consumes no stray mouse-up', function()
  -- swallow_up starts false, so a fresh gui returns false for an unpaired up.
  local gui = make_gui({ pos = { x = 0, y = 0 } })
  assert_eq(false, gui:handle_mouse(2, 10, 152), 'never-shown gui does not consume a stray up')
end)

test('a gui built with no callbacks survives clicks and drag without error', function()
  local gui = config_gui.new({
    texts = texts,
    title = 'NoCb',
    pos   = { x = 0, y = 0 },
    size  = { width = 320, height = 160 },
  })
  gui:set_draggable(true)
  gui:show({ text_tab('General', 2) })
  local sx, sy = rect_center(gui:_rects_for_test().save)
  local dx, dy = rect_center(gui:_rects_for_test().discard)
  assert_true(gui:handle_mouse(1, sx, sy), 'save click consumed (no on_save)')
  assert_true(gui:handle_mouse(1, dx, dy), 'discard click consumed (no on_discard)')
  gui:handle_mouse(1, 10, 5)   -- start drag on header
  gui:handle_mouse(0, 40, 45)  -- move
  assert_true(gui:handle_mouse(2, 40, 45), 'release consumed (no on_move)')
end)

-- ----

io.write(string.format('test_config_gui: %d passed, %d failed\n', pass, fail))
if fail > 0 then
  error(fail .. ' test(s) failed in test_config_gui.lua')
end
