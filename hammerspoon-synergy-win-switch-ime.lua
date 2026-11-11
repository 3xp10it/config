-- ==============================================================
-- 放在 Mac 上：~/.hammerspoon/init.lua
--
-- 单按 Command → 切换 macOS 输入法。
--   · Mac 物理键盘：由 Karabiner 处理，本脚本只负责挡掉它的余波
--   · Synergy 转发的 Win 键：由本脚本处理
--
-- 为什么直接调 TIS API 而不模拟快捷键：
--   模拟快捷键要经 System Events 转发，约 30ms；
--   直接设置输入源约 1ms。
--   （另：hs.eventtap.keyStroke 不可用，私有事件源会被系统忽略）
--
-- 换输入法时改 EN / ZH 两个 ID。
-- ==============================================================

local T = hs.eventtap.event.types

local EN = "com.apple.keylayout.US"
local ZH = "com.baidu.inputmethod.BaiduIM.wubi"

local CMD_PRESS_KC   = { [0] = true }                          -- Synergy 的按下
local PHYSICAL_KC    = { [54] = true, [55] = true }            -- 物理键盘左右 Command
local CMD_RELEASE_KC = { [0] = true, [54] = true, [55] = true }

local pressed = false
local solo    = false          -- 按下期间有没有夹带其它键
local physicalUntil = 0

local function fire()
  hs.timer.doAfter(0, function()
    local cur = hs.keycodes.currentSourceID()
    hs.keycodes.currentSourceID((cur == ZH) and EN or ZH)
  end)
end

local function release()
  local wasSolo = solo
  pressed = false
  solo = false

  if wasSolo then fire() end
end

local function handle(e)
  local t  = e:getType()
  local kc = e:getKeyCode()
  local f  = e:getFlags()

  if t == T.flagsChanged then
    if f.cmd then
      -- 物理键盘的 Command：记一个时间窗，稍后到达的 kc=0 要忽略，
      -- 否则会和 Karabiner 的切换叠加，两次抵消
      if PHYSICAL_KC[kc] then
        physicalUntil = hs.timer.secondsSinceEpoch() + 0.3
        return false
      end

      if not pressed and CMD_PRESS_KC[kc] then
        if hs.timer.secondsSinceEpoch() < physicalUntil then return false end

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
    -- 按下任何「真正的」按键，说明不是单按 Command
    if not CMD_RELEASE_KC[kc] and pressed then
      solo = false
    end
    return false
  end

  return false
end

-- 挂到全局，避免被 Lua 垃圾回收（写成 local 会在几秒后失效）
hs.imeTap = hs.eventtap.new({T.flagsChanged, T.keyDown, T.keyUp}, handle)
hs.imeTap:start()
