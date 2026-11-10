-- ==============================================================
-- 放在 Mac 上：~/.hammerspoon/init.lua
--
-- 单按 Command（Synergy 从 Windows 的 Win 键转发而来）
-- → 发送 Ctrl+Shift+Z，切换 macOS 输入法。
--
-- 两个关键点，改动时别弄丢：
--   1. Synergy 注入的 Command 是 flagsChanged 事件但 keycode = 0
--      （不是物理键盘的 55/54），所以只能看 cmd 标志位。
--   2. eventtap / menubar / hotkey 对象必须挂在全局（hs.xxx），
--      写成 local 会被 Lua 垃圾回收，几秒后就失效。
-- ==============================================================

local T = hs.eventtap.event.types

local PROBE = false           -- true = 把收到的事件显示在屏幕上（排查用）
local TEST  = false           -- true = 加菜单栏「输入法」按钮 + Ctrl+Option+Z 自检
local USE_APPLESCRIPT = false -- true = 改用 System Events 模拟按键

-- 这些 keycode 的 keyDown 视为「Command 按下本身」，不算夹带其它键
local CMD_KEYDOWN = { [0] = true, [54] = true, [55] = true }

local pressed = false
local solo    = false
local sending = false

if PROBE then
  hs.imeLog = io.open(os.getenv("HOME") .. "/.hammerspoon/synergy-probe.log", "a")
end

local fire

fire = function()
  if sending then return end
  sending = true

  if PROBE then hs.alert.show("发送 Ctrl+Shift+Z", 0.8) end

  if USE_APPLESCRIPT then
    hs.osascript.applescript(
      [[tell application "System Events" to key code 6 using {control down, shift down}]])
  else
    hs.eventtap.keyStroke({"ctrl", "shift"}, "z")
  end

  hs.timer.doAfter(0.25, function() sending = false end)
end

local function handle(e)
  if sending then return false end

  local t  = e:getType()
  local kc = e:getKeyCode()
  local f  = e:getFlags()

  if PROBE and (t == T.flagsChanged or f.cmd) then
    local line = string.format("%s  kc=%d  cmd=%s  opt=%s  ctrl=%s  shift=%s",
      t, kc, tostring(f.cmd), tostring(f.alt), tostring(f.ctrl), tostring(f.shift))
    hs.alert.show(line, 1.2)
    if hs.imeLog then
      hs.imeLog:write(os.date("%H:%M:%S ") .. line .. "\n")
      hs.imeLog:flush()
    end
  end

  -- 修饰键状态变化：只看 cmd 标志位，不看 keycode
  if t == T.flagsChanged then
    if f.cmd then
      if not pressed then
        pressed, solo = true, true
        -- 兜底：万一收不到「松开」事件，3 秒后自动复位
        hs.timer.doAfter(3, function()
          if pressed then pressed, solo = false, false end
        end)
      end
    else
      if pressed then
        pressed = false
        if solo then fire() end
        solo = false
      end
    end
    return false
  end

  -- 按下任何「真正的」按键，说明不是单按 Command
  if t == T.keyDown then
    if not CMD_KEYDOWN[kc] and pressed then
      solo = false
    end
    return false
  end

  return false
end

-- 挂到全局，避免被垃圾回收
hs.imeTap = hs.eventtap.new({T.flagsChanged, T.keyDown, T.keyUp}, handle)
hs.imeTap:start()

if TEST then
  hs.imeHotkey = hs.hotkey.bind({"ctrl", "alt"}, "z", function() fire() end)

  hs.imeBar = hs.menubar.new()
  if hs.imeBar then
    hs.imeBar:setTitle("输入法")
    hs.imeBar:setClickCallback(function() fire() end)
  end
end

if PROBE then hs.alert.show("已加载（诊断模式）", 1.2) end
