-- ==============================================================
-- 放在 Mac 上：~/.hammerspoon/init.lua
--
-- 单按 Command → 切换 macOS 输入法。
-- 支持两种来源：Mac 物理键盘（Karabiner 处理）、Synergy 转发的 Win 键（本脚本处理）。
--
-- 【为什么不用 hs.eventtap.keyStroke】
--   keyStroke 走 CGEventPost 私有事件源，macOS 的符号快捷键机制
--   （输入法切换在这一层）不认这种来源，发了等于没发。
--   改用 System Events 模拟按键，事件源是会话级，系统正常响应。
--   需要给 Hammerspoon 开「自动化 → System Events」权限。
--
-- 【为什么要挡物理键盘】
--   物理键盘按 Left Command 时也会产生一个 kc=0 事件，若不挡掉会再切一次，
--   与 Karabiner 的切换互相抵消。区分依据：物理键盘一定先来 kc=54/55。
--
-- 另外：eventtap / menubar / hotkey 对象必须挂在全局（hs.xxx），
--      写成 local 会被 Lua 垃圾回收，几秒后就失效。
-- ==============================================================

local T = hs.eventtap.event.types

local PROBE = false           -- 排错时改 true，会把事件显示在屏幕上
local TEST  = false           -- true = 菜单栏「输入法」按钮 + Ctrl+Option+Z 自检

-- 两个输入源的 ID，兜底路径会用到；换输入法的话改这里
local EN = "com.apple.keylayout.US"
local ZH = "com.baidu.inputmethod.BaiduIM.wubi"

local SCRIPT = [[tell application "System Events" to key code 6 using {control down, shift down}]]

local CMD_PRESS_KC   = { [0] = true }                          -- 只认 Synergy
local PHYSICAL_KC    = { [54] = true, [55] = true }            -- 物理键盘
local CMD_RELEASE_KC = { [0] = true, [54] = true, [55] = true }

local pressed = false
local solo    = false
local sending = false
local physicalUntil = 0

if PROBE then
  hs.imeLog = io.open(os.getenv("HOME") .. "/.hammerspoon/synergy-probe.log", "a")
end

local function log(line)
  if not PROBE then return end
  hs.alert.show(line, 1.2)
  if hs.imeLog then
    hs.imeLog:write(os.date("%H:%M:%S ") .. line .. "\n")
    hs.imeLog:flush()
  end
end

local function fire()
  if sending then return end
  sending = true

  local before = hs.keycodes.currentSourceID()
  log("发送 Ctrl+Shift+Z，src=" .. tostring(before))

  hs.osascript.applescript(SCRIPT)

  -- 兜底：万一「自动化」权限失效导致没切过去，直接设置输入源
  hs.timer.doAfter(0.15, function()
    local now = hs.keycodes.currentSourceID()
    if now == before then
      local target = (before == ZH) and EN or ZH
      log("兜底：直接设置 -> " .. target)
      hs.keycodes.currentSourceID(target)
    end
    sending = false
  end)
end

local function release()
  local wasSolo = solo
  pressed = false
  solo = false

  if wasSolo then fire() end
end

local function handle(e)
  if sending then return false end

  local t  = e:getType()
  local kc = e:getKeyCode()
  local f  = e:getFlags()

  if PROBE and t == T.flagsChanged then
    log(string.format("flagsChanged kc=%d cmd=%s", kc, tostring(f.cmd)))
  end

  if t == T.flagsChanged then
    if f.cmd then
      -- 物理键盘的 Command：记一个时间窗，稍后到达的 kc=0 要忽略
      if PHYSICAL_KC[kc] then
        physicalUntil = hs.timer.secondsSinceEpoch() + 0.3
        return false
      end

      if not pressed and CMD_PRESS_KC[kc] then
        if hs.timer.secondsSinceEpoch() < physicalUntil then
          log("忽略：物理键盘的 Command")
          return false
        end

        pressed, solo = true, true
        -- 兜底：万一收不到「松开」事件，3 秒后自动复位
        hs.timer.doAfter(3, function()
          if pressed then pressed, solo = false, false end
        end)
      end
    else
      if pressed then release() end
    end
    return false
  end

  if t == T.keyUp then
    if pressed and CMD_RELEASE_KC[kc] then release() end
    return false
  end

  if t == T.keyDown then
    if not CMD_RELEASE_KC[kc] and pressed then
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
