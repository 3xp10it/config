#Requires AutoHotkey v2.0
#SingleInstance Force
DllCall("SetProcessDPIAware")
; ============================================================
; 全局变量声明（函数外部无需加 global）
; ============================================================

; 调试开关：是否显示监视器窗口（ListView）
showMonitorGui := false   ; 设为 false 时完全不创建 GUI，使用脚本主窗口；true为创建；
msgWindow := 0            ; 消息接收窗口句柄，将在脚本启动时赋值

; ---------- 修饰键双角色相关全局变量 ----------
; 必须在最外层初始化，否则 #HotIf 条件里读到未赋值变量会直接报错
g_capsHeld  := false      ; CapsLock 是否按住
g_capsRepeated := false   ; 本次按住期间是否出现过键盘自动重复
g_mouseUsed := false      ; 按住期间是否点过鼠标（CapsLock / 左 Ctrl 共用）
g_injCtrlUpTick := 0      ; 最近一次 CapsLock 注入 Ctrl up 的时刻（用于忽略对应的 LCtrl Up）
g_ctrlRemapped := false   ; 本次按住 Ctrl/CapsLock 期间是否触发过 Ctrl+J / Ctrl+K 重映射
                          ; （重映射会把 Ctrl 重新按下，A_PriorKey 因此变成 LControl，
                          ;   松开时不能再当轻敲补发 Esc）

; ---------- 同花顺相关全局变量 ----------
cmds_should_show_realnews := "0"
win_ctrl_w_should_close_ths_fenxi_window := "0"

; ---------- 微信相关全局变量 ----------
WeChatExePath := "C:\Program Files\Tencent\Weixin\Weixin.exe"
WeChatMainClass := "Qt51514QWindowIcon"          ; 微信4.x 主窗口类名，版本升级后可能变化（下面有兜底逻辑）
WeChatTitles := ["微信", "Weixin", "WeChat"]     ; 主窗口标题兜底匹配
WeChatRelaunchToRestore := true                  ; 主窗口被彻底销毁时，是否再执行一次 Weixin.exe 让已有实例把窗口弹出来

; 遮罩窗口对象（将由数组管理）
overlays := []

WindowPositionDict := Map()
ok_x := 776
ok_y := 7
ok_w := 1883
ok_h := 1440
right_ok_x := 2653

log_Enabled := true
log_FilePath := "d:\WinHistory.log"
log_MaxSize := 10 * 1024 * 1024



; ---------- 窗口事件监视器相关全局变量 ----------
listview := 0
hookShow := 0                      ;  SHOW 钩子
WinEventProcCallback := 0
history := []                       ; 最近使用窗口历史（包含所有激活，允许重复）
lastBPressTime := 0                  ; 上次按 #b 的时间戳
lastBWindow := 0                     ; 上次 #b 激活的窗口句柄
baseHistory := []                    ; 用于连续 #b 切换的基准历史（副本）



; ---------- 窗口事件监视器常量 ----------
EVENT_OBJECT_SHOW       := 0x8002   ; 窗口显示
WM_APP                  := 0x8000
WM_USER_EVENT           := WM_APP + 1
WS_VISIBLE    := 0x10000000
WS_CHILD      := 0x40000000
TargetProcessId := 0
MinWidth  := 150
;Listary.exe的搜索框是612*100
MinHeight := 100


; Shell 钩子常量
HSHELL_RUDEAPPACTIVATED := 0x8004   ; 窗口激活事件

; 定义在置顶时需要激活的进程名列表（可以根据实际需要扩展）
ActivateProcesses := Map(
    "Thunder.exe", 1,      ; 迅雷
    ; 添加其他需要激活的进程...
)

ignoreShowTitles := Map("EAGrid", 1, "MuMu模拟器", 1)
ignoreActivateTitles := Map("Program Manager", 1, "MuMu模拟器", 1)

PorcessIMEDICT := Map(
    "hexin.exe","英文",
    "tl50v2.exe","英文",
    "WavMain.exe","英文",
    "Listary.exe","英文",
    "explorer.exe","英文",
    "cmd.exe","英文",
    "powershell.exe","英文",
    "xiadan.exe","英文",
    ;注意，Code.exe在初始打开的时候有点慢，要求操作系统设置的默认输入法是"英文".否则如果操作系统设置的默认输入法是"中文"则要求对于Code.exe要加个延时切换，如果操作系统设置的默认输入法是"中文"且对于Code.exe的自动设置输入法的操作不加延时再设置的话，那么初次打开Code.exe时会是"中文"输入法.因此最小动作是设置操作系统的默认输入法是"英文"，这样对于Code.exe就不用延时再自动设置输入法了.
    "Code.exe","英文",
    "Weixin.exe","中文",
    "notepad.exe","中文",
    "chrome.exe","中文",
)


GetImeModeEx(hwnd) {
    ;获取目标窗口当前的输入法
    static WM_IME_CONTROL := 0x283
    static IMC_GETOPENSTATUS := 0x005
    static IMC_GETCONVERSIONMODE := 0x001
    static SMTO_ABORTIFHUNG := 0x0002
    static timeout := 200

    imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if !imeWnd
        return { mode: "英文", openStatus: 0, convMode: 0 }

    openStatus := 0
    DllCall("SendMessageTimeoutW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_GETOPENSTATUS, "Ptr", 0, "UInt", SMTO_ABORTIFHUNG, "UInt", timeout, "UInt*", &openStatus)

    convMode := 0
    DllCall("SendMessageTimeoutW", "Ptr", imeWnd, "UInt", WM_IME_CONTROL, "Ptr", IMC_GETCONVERSIONMODE, "Ptr", 0, "UInt", SMTO_ABORTIFHUNG, "UInt", timeout, "UInt*", &convMode)

    if (openStatus && (convMode & 1))
        mode := "中文"
    else
        mode := "英文"

    return { mode: mode, openStatus: openStatus, convMode: convMode }
}

switchState() {
    ;通过模拟左Shift键来切换输入法
    SendInput("{LShift}")
}

; ============================================================
; 脚本启动时自动执行
; ============================================================

if (showMonitorGui) {
    ; 创建可见的监视器窗口
    MyGui := Gui()
    MyGui.Title := "窗口事件监视器 (激活+显示)"
    MyGui.OnEvent("Close", GuiClose)
    MyGui.OnEvent("Escape", GuiClose)
    listview := MyGui.AddListView("w800 h400", ["事件", "窗口句柄", "类名", "标题"])
    listview.ModifyCol(1, 80)
    listview.ModifyCol(2, 100)
    listview.ModifyCol(3, 150)
    listview.ModifyCol(4, 450)
    MyGui.Show()
    msgWindow := MyGui.Hwnd
} else {
    ; 不创建 GUI，直接使用脚本主窗口
    msgWindow := A_ScriptHwnd
}




; 安装窗口事件钩子（SHOW）
OnMessage(WM_USER_EVENT, EventMessageHandler)
WinEventProcCallback := CallbackCreate(WinEventProc)
hookShow := SetWinEventHook(EVENT_OBJECT_SHOW, EVENT_OBJECT_SHOW, 0, WinEventProcCallback, TargetProcessId, 0, 0)
if !hookShow {
    MsgBox("SHOW 钩子安装失败，请以管理员身份运行。")
    ExitApp
}

; 注册 ShellHook 以接收窗口激活事件
DllCall("RegisterShellHookWindow", "ptr", msgWindow)
WM_SHELLHOOK := DllCall("RegisterWindowMessage", "str", "SHELLHOOK")
OnMessage(WM_SHELLHOOK, ShellMessageHandler)








; 初始化同花顺遮罩
CreateOverlays()

; 启动/重载标记，便于确认当前运行的是哪一版代码
write("=== WindowManager 启动/重载 ===")

; 退出处理
OnExit(ExitFunc)
Persistent()

; ============================================================
; 窗口管理热键定义
; ============================================================

; ----- 应用程序快速切换热键 -----
#g::switchToChrome
#^g::switchToUseChrome
#^e::open_tbjl_bat
#w::switchToWechat
#^b::switchToryij
#f::switchToTHS
#^r::openRiLi
#^f::tide
#a::switchToZNZ
#c::switchToTL50
#s::switchTorealnews
#^t::moveRealnews
#t::switchToGBJC
#x::switchToXIADAN
#z::minimize_current_window
#q::set_current_window_to_top
#^w::ths_fenxi
#Space::show_ths_yujin
#3::open_moniqi
#1::switch_ths_to_paiban
#2::switch_ths_to_fupan
#^s::ths_xiadie_yujin_confirm


#Esc:: {
    ; 检查 WorkBuddy 窗口是否存在
    if WinExist("WorkBuddy AI") {
        ; 如果窗口是最小化状态，先恢复它
        if (WinGetMinMax("WorkBuddy AI") == -1)
            WinRestore("WorkBuddy AI")
            
        ; 激活窗口
        WinActivate("WorkBuddy AI")
    } else {
        ; 没找到窗口时的提示（如果不需要提示可以删掉这行）
        MsgBox("未找到 WorkBuddy 窗口，请确认程序已运行。", "提示", "Icon!")
    }
}

; ----- 同花顺遮罩控制热键 -----
^1::CreateOverlays
^2::DestroyOverlays
^3::minimize_some_windows

; ----- 窗口位置控制热键 -----
^+h::move_current_window_to_left
^+l::move_current_window_to_right
#+f::fullscreen_current_window

; ============================================================
; Ctrl+J / Ctrl+K  →  下 / 上 方向键
;
; 为什么要「抬 Ctrl → 发键 → 还原」：
;   热键触发时 Ctrl 逻辑上按着，直接发 Down 应用会收到 Ctrl+↓
;   （编辑器里是「跳到下一段」），所以必须抬起来再还原。
;
; 【重要】GetKeyState(..., "P") 会被本脚本自己注入的按键改变（实测：
;   Send "{LCtrl down}" 后 P=1，Send "{LCtrl up}" 后 P=0）。所以物理状态
;   必须在注入任何 up/down 之前一次性读出来，注入之后再读就不准了。
;
; 为什么需要 g_ctrlRemapped：
;   注入的 LCtrl down 会把 A_PriorKey 改写成 LControl（本脚本靠
;   A_PriorKey 判断「Ctrl 轻敲 = Esc」），若不管它，Ctrl+J 之后一松 Ctrl
;   就会白白多打一个 Esc。标记位在松开 Ctrl / CapsLock 时消费掉。
;
; 抬/按 Ctrl 全部用 SendLevel 1 注入，不会回头触发本脚本的 LCtrl 热键，
; 也就不会打乱 g_mouseUsed 之类的状态。
; ============================================================

^j::SendArrowKey("Down")
^k::SendArrowKey("Up")

SendArrowKey(key) {
    global g_ctrlRemapped, g_capsHeld

    ; 注入之前读物理状态（CapsLock 注入的那个 LCtrl 用 g_capsHeld 兜住）。
    ; 只有会重新按下 LCtrl 时才需要标记位：纯右 Ctrl 不涉及「轻敲 = Esc」。
    restoreL := (g_capsHeld || GetKeyState("LCtrl", "P"))
    restoreR := GetKeyState("RCtrl", "P")
    DiagLog("ARROW key=" key " restoreL=" restoreL " restoreR=" restoreR)
    if restoreL
        g_ctrlRemapped := true

    SendLevel 1
    ; 1) 抬起逻辑上的 Ctrl
    if restoreL
        Send "{Blind}{LCtrl up}"
    if restoreR
        Send "{Blind}{RCtrl up}"
    ; 2) 发方向键：此刻 Ctrl 是抬起的，应用收到的是纯 ↓ / ↑
    Send "{Blind}{" key "}"
    ; 3) 按回去，用上面捕获的状态，不要再读 GetKeyState
    if restoreL
        Send "{Blind}{LCtrl down}"
    if restoreR
        Send "{Blind}{RCtrl down}"
}

; ============================================================
; 窗口历史切换热键（基于基准历史，区分超时）
; ============================================================

#b:: {
    global history, baseHistory, lastBPressTime, lastBWindow

    if (history.Length < 1) {
        ToolTip("历史为空")
        SetTimer () => ToolTip(), -1000
        return
    }

    currentTime := A_TickCount
    timeDiff := currentTime - lastBPressTime

    ; 判断是否超时或首次
    if (lastBPressTime = 0 || timeDiff > 3000) {
        ; 超时或首次：重置基准历史为当前history的副本
        baseHistory := history.Clone()
        ;write("按 #b - 超时/首次，重置基准历史，长度: " baseHistory.Length)
        isTimeout := true
    } else {
        ; 未超时，继续使用现有基准历史
        ;write("按 #b - 未超时，继续使用基准历史，长度: " baseHistory.Length)
        isTimeout := false
    }

    ; 从基准历史构建去重列表（保留每个窗口最后一次出现，顺序为原始顺序中最后出现的位置）
    dedupHistory := []
    seen := Map()
    for hwnd in baseHistory {
        if seen.Has(hwnd) {
            ; 如果已存在，移除旧位置再添加，确保最后出现的位置在末尾
            for i, h in dedupHistory {
                if (h = hwnd) {
                    dedupHistory.RemoveAt(i)
                    break
                }
            }
        }
        seen[hwnd] := true
        dedupHistory.Push(hwnd)
    }
    ; 此时 dedupHistory 按最后出现顺序排列，第一个最早，最后一个最新

    ; 记录日志
    logBase := ""
    for h in baseHistory
        logBase .= Format("0x{:X} ", h)
    ;write("按 #b - 基准历史: " logBase)
    logDedup := ""
    for h in dedupHistory
        logDedup .= Format("0x{:X} ", h)
    ;write("按 #b - 去重 dedupHistory: " logDedup)

    ; 获取当前活动窗口
    currHwnd := WinExist("A")
    if !currHwnd
        currHwnd := 0

    ; 优先处理最新窗口最小化的情况（基于去重后的最新窗口）
    latestHwnd := dedupHistory[dedupHistory.Length]
    if WinExist("ahk_id " latestHwnd) && (WinGetMinMax("ahk_id " latestHwnd) = -1) {
        ; 最新窗口最小化，激活它
        WinRestore("ahk_id " latestHwnd)
        WinActivate("ahk_id " latestHwnd)
        title := WinGetTitle("ahk_id " latestHwnd)
        if CarefullySetTopMost(latestHwnd, title) {
            lastBPressTime := currentTime
            lastBWindow := latestHwnd
            ;write("按 #b - 激活最小化最新窗口: " Format("0x{:X}", latestHwnd))
            return
        }
    }

    ; 确定起始索引
    if (isTimeout) {
        ; 超时：从最新窗口的前一个开始
        startIndex := dedupHistory.Length - 1
        ;write("按 #b - 超时，起始索引: " startIndex)
    } else {
        ; 未超时：从上一次激活的窗口的前一个开始
        lastIndex := 0
        for i, h in dedupHistory {
            if (h = lastBWindow) {
                lastIndex := i
                break
            }
        }
        if (lastIndex = 0) {
            ; 上次窗口不在基准历史中，重置从最新前一个
            startIndex := dedupHistory.Length - 1
            ;write("按 #b - 上次窗口不在基准历史，重置从最新前一个")
        } else {
            startIndex := lastIndex - 1
            ;write("按 #b - 未超时，从上一次窗口 " Format("0x{:X}", lastBWindow) " 的前一个开始，索引: " startIndex)
        }
    }

    ; 向前搜索存在的窗口（跳过当前窗口）
    targetIndex := startIndex
    while (targetIndex >= 1) {
        targetHwnd := dedupHistory[targetIndex]
        if (targetHwnd = currHwnd) {
            targetIndex--
            continue
        }
        if WinExist("ahk_id " targetHwnd) {
            ;write("按 #b - 准备激活目标句柄: " Format("0x{:X}", targetHwnd))
            WinRestore("ahk_id " targetHwnd)
            WinActivate("ahk_id " targetHwnd)
            title := WinGetTitle("ahk_id " targetHwnd)
            if CarefullySetTopMost(targetHwnd, title) {
                lastBPressTime := currentTime
                lastBWindow := targetHwnd
                return
            }
        }
        targetIndex--
    }

    ; 如果未找到，则从末尾重新搜索（跳过当前窗口）
    targetIndex := dedupHistory.Length
    while (targetIndex >= 1) {
        targetHwnd := dedupHistory[targetIndex]
        if (targetHwnd = currHwnd) {
            targetIndex--
            continue
        }
        if WinExist("ahk_id " targetHwnd) {
            ;write("按 #b - 准备激活目标句柄（从末尾）: " Format("0x{:X}", targetHwnd))
            WinRestore("ahk_id " targetHwnd)
            WinActivate("ahk_id " targetHwnd)
            title := WinGetTitle("ahk_id " targetHwnd)
            if CarefullySetTopMost(targetHwnd, title) {
                lastBPressTime := currentTime
                lastBWindow := targetHwnd
                return
            }
        }
        targetIndex--
    }

    ToolTip("没有可切换的窗口")
    SetTimer () => ToolTip(), -1000
}

; ============================================================
; CapsLock 热键映射,按一下为ESC,与其他键组合时为Ctrl
;
; g_capsHeld  : CapsLock 当前是否按住
; g_mouseUsed : 按住期间是否点过鼠标（CapsLock 与左 Ctrl 共用）
; ============================================================

; 临时诊断日志（排查完会删掉）
DiagLog(s) {
    try FileAppend(A_TickCount " " s "`n", "C:\Users\Administrator\AppData\Local\Temp\ahk_diag.log")
}

; 兜底：按住修饰键期间用定时器轮询鼠标按钮状态。
; 不依赖鼠标热键、不依赖钩子，只要按键真的按下过就一定能捕捉到。
WatchMouse() {
    global g_mouseUsed
    if (GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
        || GetKeyState("MButton", "P")
        || GetKeyState("XButton1", "P") || GetKeyState("XButton2", "P"))
        g_mouseUsed := true
}

*CapsLock::{
    global g_capsHeld, g_mouseUsed, g_capsRepeated
    ; 按住不放时键盘会自动重复，这个热键会被反复触发（每 30ms 一次）。
    ; 重复的那几次必须直接忽略，否则会把 g_mouseUsed 清掉、把 A_PriorKey
    ; 重置回 CapsLock，导致「点过鼠标/按过别的键」的判断全部失效。
    if (g_capsHeld) {
        g_capsRepeated := true      ; 出现过重复 = 按住超过系统重复延迟，不可能是轻敲
        return
    }
    g_capsHeld  := true
    g_capsRepeated := false
    g_mouseUsed := false
    DiagLog("CAPS_DOWN")
    SetTimer(WatchMouse, 15)
    SendLevel 1
    Send "{Blind}{LCtrl down}"
}

*CapsLock Up::{
    global g_capsHeld, g_mouseUsed, g_capsRepeated, g_injCtrlUpTick, g_ctrlRemapped
    g_capsHeld := false
    SetTimer(WatchMouse, 0)
    g_injCtrlUpTick := A_TickCount       ; 记下这次注入 Ctrl up 的时间，供 LCtrl Up 忽略
    SendLevel 1
    Send "{Blind}{LCtrl up}"
    ; 注入的 Ctrl down 会把 A_PriorKey 变成 LControl，所以这两个值都算「没按过别的键」
    DiagLog("CAPS_UP prior=[" A_PriorKey "] mouseUsed=" g_mouseUsed " repeated=" g_capsRepeated)
    ; 本次按住期间按过 Ctrl+J / Ctrl+K：重映射结束时把 Ctrl 重新按下了，
    ; A_PriorKey 被改写成 LControl，不能当成轻敲再补发 Esc
    if (g_ctrlRemapped) {
        g_ctrlRemapped := false
        return
    }
    if (!g_capsRepeated && (A_PriorKey = "CapsLock" || A_PriorKey = "LControl") && !g_mouseUsed) {
        DiagLog("  -> SEND_ESC (from CapsLock)")
        Send "{Esc}"
    }
}

; 脚本退出/重载时确保 Ctrl 不会被卡住
OnExit(ReleaseCtrl)

ReleaseCtrl(*) {
    SendLevel 1
    Send "{Blind}{LCtrl up}"
}

; 设置CapsLock状态
SetCapsLockState("AlwaysOff")

; ============================================================
; 左 Ctrl 双角色：轻敲 = Esc，与其他键组合 = 正常 Ctrl
;
; ~ 前缀表示【不拦截】，物理 Ctrl 原样放行，所以 Ctrl+C / Ctrl+V /
; Ctrl+Tab 这些组合完全走系统原生路径，不需要注入、不涉及 SendLevel。
; 松开时用 A_PriorKey 判断这段按住期间有没有按过别的键：
; 没按过 -> 是一次轻敲 -> 补发 Esc。
;
; 注意：A_PriorKey 对鼠标的跟踪并不可靠。所以 Ctrl / CapsLock 按住期间的
; 鼠标点击统一用 g_mouseUsed 标记，松开时不再转 Esc。
; ============================================================

; 按住期间的鼠标点击 -> 标记为「已使用」，松开时不再转 Esc。
; ~ 前缀不拦截点击，行为完全正常。
; 这里刻意【不加 #HotIf】：条件式热键在某些情况下不触发，改成无条件注册、
; 在函数内部判断，最可靠。
~*LButton::{
    global g_capsHeld, g_mouseUsed
    DiagLog("LBUTTON capsHeld=" g_capsHeld " lctrlP=" GetKeyState("LCtrl", "P"))
    if (g_capsHeld || GetKeyState("LCtrl", "P"))
        g_mouseUsed := true
}
~*RButton::{
    global g_capsHeld, g_mouseUsed
    if (g_capsHeld || GetKeyState("LCtrl", "P"))
        g_mouseUsed := true
}
~*MButton::{
    global g_capsHeld, g_mouseUsed
    if (g_capsHeld || GetKeyState("LCtrl", "P"))
        g_mouseUsed := true
}

$~*LCtrl::{
    global g_mouseUsed, g_capsHeld
    DiagLog("LCTRL_DOWN capsHeld=" g_capsHeld)
    ; CapsLock 按住期间的那次 Ctrl down 是注入的，不要清掉鼠标标记
    if (g_capsHeld)
        return
    g_mouseUsed := false
    SetTimer(WatchMouse, 15)
}

$~*LCtrl Up::{
    global g_mouseUsed, g_injCtrlUpTick, g_ctrlRemapped
    DiagLog("LCTRL_UP prior=[" A_PriorKey "] mouseUsed=" g_mouseUsed " dt=" (A_TickCount - g_injCtrlUpTick))
    ; CapsLock 松开时注入的那次 Ctrl up 会异步触发到这里，靠时间戳忽略掉
    if (A_TickCount - g_injCtrlUpTick < 250)
        return
    SetTimer(WatchMouse, 0)
    ; 见 SendArrowKey：Ctrl+J / Ctrl+K 结束时会把 Ctrl 重新按下，
    ; A_PriorKey 因此变成 LControl，这里不能当成轻敲
    if (g_ctrlRemapped) {
        g_ctrlRemapped := false
        return
    }
    if (A_PriorKey = "LControl" && !g_mouseUsed) {
        DiagLog("  -> SEND_ESC (from LCtrl)")
        Send "{LCtrl up}{Esc}"
    }
}



; 将窗口从视觉上移动到 x,y 并调整大小为 w,h
; 参数 winTitle 可以是任何 AHK 窗口定位字符串（如 "ahk_id 0x12345"、"ahk_class Notepad"、标题等）
MoveWindowVisually(x, y, w, h, winTitle) {
    ; 1. 获取窗口句柄
    hwnd := WinExist(winTitle)
    if !hwnd
        throw ValueError("找不到窗口: " . winTitle)

    ; 2. 获取当前窗口矩形（不含阴影/扩展边界）
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hwnd)

    ; 3. 尝试获取 DWM 扩展边界（包含阴影/圆角等），以计算四周的偏移量
    marginLeft := 0, marginTop := 0, marginRight := 0, marginBottom := 0
    rect := Buffer(16)                              ; RECT 结构（left, top, right, bottom）
    if DllCall("dwmapi.dll\DwmGetWindowAttribute"
        , "ptr", hwnd
        , "uint", 9                                ; DWMWA_EXTENDED_FRAME_BOUNDS
        , "ptr", rect
        , "uint", 16                               ; sizeof(RECT)
        , "int") = 0 {                             ; S_OK 成功
        extLeft   := NumGet(rect,  0, "int")
        extTop    := NumGet(rect,  4, "int")
        extRight  := NumGet(rect,  8, "int")
        extBottom := NumGet(rect, 12, "int")
        ; 计算视觉边界相对于窗口矩形的外延量
        marginLeft   := wx - extLeft
        marginTop    := wy - extTop
        marginRight  := extRight - (wx + ww)
        marginBottom := extBottom - (wy + wh)
    }
    ; 如果 DWM 调用失败（例如经典主题或无阴影），margin 保留 0，按窗口矩形直接处理

    ; 4. 计算为了达到目标视觉矩形，窗口矩形应设置的位置与大小
    newX := x + marginLeft
    newY := y + marginTop
    newW := w - marginLeft - marginRight
    newH := h - marginTop - marginBottom

    ; 防止负尺寸
    if (newW < 1)
        newW := 1
    if (newH < 1)
        newH := 1

    ; 5. 执行移动
    WinMove(newX, newY, newW, newH, "ahk_id " hwnd)
}

; ============================================================
; 智能关闭窗口热键
; ============================================================
$^w::SmartClose()

; ============================================================
; 应用程序快速切换函数
; ============================================================

; 工具函数
RemoveToolTip() {
    ToolTip()
}

print(str) {
    static nextId := 1          ; 下一个要用的 ToolTip 编号 (1-20)
    static step := 0            ; 当前偏移步数，决定垂直位置

    ; 取一个编号，并循环 1~20
    id := nextId
    nextId := Mod(nextId, 20) + 1

    ; 计算 Y 坐标：从屏幕底部开始，每次向上偏移 30 像素
    x := 10
    y := A_ScreenHeight - 50 - step * 30
    ToolTip(str, x, y, id)      ; 在指定位置用独立编号显示

    ; 步数 +1，最多 20 级（与 20 个 ToolTip 对应），超出后回到底部
    step := Mod(step + 1, 20)

    ; 6 秒后移除这个编号的 ToolTip
    SetTimer(() => ToolTip(,,, id), -6000)
}

print_old(string) {
    ToolTip(string)
    SetTimer RemoveToolTip, -3000
}

write(message) {
    global log_Enabled, log_FilePath, log_MaxSize

    if !log_Enabled
        return

    ; 确保日志文件存在
    if !FileExist(log_FilePath)
        FileAppend "", log_FilePath, "UTF-8"

    ; 获取文件大小，失败时使用默认值 0
    fileSize := 0
    try {
        FileGetSize(&fileSize, log_FilePath)
    } catch {
        ; 忽略错误，保持 fileSize = 0
    }

    ; 如果文件过大，进行轮转
    if (fileSize > log_MaxSize) {
        try FileDelete(log_FilePath . ".old")   ; 删除旧备份（如果存在）
        FileMove(log_FilePath, log_FilePath . ".old", 1)  ; 重命名当前文件
    }

    ; 写入新日志
    timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss.fff")
    fullMessage := "[" timestamp "] " message "`n"
    FileAppend(fullMessage, log_FilePath, "UTF-8")
}

; 检查进程是否存在
CheckProcessExist(exe) {
    return ProcessExist(exe)
}

; 浏览器相关函数
switchToChrome(activate := 1) {
    global ok_x, ok_y, ok_h

    SetTitleMatchMode("RegEx")
    if WinExist("guba_jiucai.*") {
        WinMinimize
    }

    SetTitleMatchMode(2)
    if WinExist("ahk_exe chrome.exe") {
        WinRestore
        chromeTitle := " - Google Chrome"
        WinMove(2652, ok_y, 796, ok_h+1, chromeTitle)
        chrome_hwnd := WinGetID(chromeTitle)
        if (activate) {
            WinActivate("ahk_id " chrome_hwnd)
        }
        WinSetAlwaysOnTop(true, "ahk_id " chrome_hwnd)
    } else {
        Run("chrome.exe")
        ;Run('"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" --user-data-dir="D:\Program Files\chrome_user_data"')
    }

    if (hwnd := WinExist("实时新闻 ahk_exe python.exe")) {
        Style := WinGetStyle("ahk_id " hwnd)
        if (!(Style & 0x20000000)) {
            WinMove(784, 466, 1033, 499, "实时新闻 ahk_exe python.exe")
        }
    }
    if (activate) {
        ;从#f过来的不要再激活同花顺，否则如果在#f后再快速输入股票代码会导致只能输入部分字符串，例如dfcf只会成功输入cf，因为我输入df后就会被因同花顺主窗口被激活而导致键盘精灵失焦
        SetTitleMatchMode("RegEx")
        ths_hwnd := WinExist("同花顺\(.*\).* ahk_exe hexin.exe")               
        if (ths_hwnd) {
            WinActivate("ahk_id " ths_hwnd)
        }
    }

}

switchToUseChrome() {
    global ok_x, ok_y, ok_w, ok_h

    SetTitleMatchMode("RegEx")
    if WinExist("guba_jiucai.*") {
        WinMinimize
    }
    if WinExist(".*天狼50.*") {
        WinMinimize
    }

    SetTitleMatchMode(2)
    if WinExist("ahk_exe chrome.exe") {
        WinRestore
        chromeTitle := " - Google Chrome"
        ;WinMove(ok_x, ok_y, ok_w, ok_h, chromeTitle)
        MoveWindowVisually(ok_x, ok_y, ok_w, ok_h, chromeTitle)
        
        chrome_hwnd := WinGetID(chromeTitle)
        WinActivate("ahk_id " chrome_hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " chrome_hwnd)
    } else {
        Run("chrome.exe")
        ;Run('"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" --user-data-dir="D:\Program Files\chrome_user_data"')
    }


    if (hwnd := WinExist("实时新闻 ahk_exe python.exe")) {
        Style := WinGetStyle("ahk_id " hwnd)
        if (!(Style & 0x20000000)) {
            ;如果实时新闻窗口没有最小化则将该窗口移到右边
            moveRealnews()
        }
    }

}

open_tbjl_bat() {
    Run("z:\tbjl.bat")
}

; ============================================================
; 微信主窗口定位与唤醒
; 覆盖三种状态：
;   1) 窗口可见（含被遮挡、最小化）
;   2) 被 Ctrl+W 关掉 / 隐藏到托盘 —— 进程还在，窗口句柄还在，只是 WS_VISIBLE 被去掉了
;   3) 窗口已被真正销毁 —— 再执行一次 Weixin.exe，靠单实例机制让已有实例把主窗口弹出来
; ============================================================

; 窗口是否真的“看得见”
IsHwndVisible(hwnd) {
    if !hwnd
        return false
    return DllCall("IsWindowVisible", "ptr", hwnd) != 0
}

; 是否被 DWM 隐形（IsWindowVisible 仍为真，但屏幕上看不到，常见于其他虚拟桌面）
IsHwndCloaked(hwnd) {
    static DWMWA_CLOAKED := 14
    cloaked := 0
    if (DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", DWMWA_CLOAKED, "uint*", &cloaked, "uint", 4) = 0)
        return (cloaked != 0)
    return false
}

; 连隐藏窗口一起找微信主窗口：返回句柄，找不到返回 0
GetWeChatHiddenWindow() {
    global WeChatMainClass, WeChatTitles, MinWidth, MinHeight
    oldDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    found := 0
    try {
        ; ① 按类名 + 标题（最准）：微信同时有主窗口「微信」和一个 176x199 的「Weixin」小窗口，
        ;    只按类名会抓错，必须用标题锁定
        for h in WinGetList("ahk_class " WeChatMainClass " ahk_exe Weixin.exe") {
            try t := WinGetTitle("ahk_id " h)
            catch
                continue
            for name in WeChatTitles {
                if (t = name) {
                    found := h
                    break 2
                }
            }
        }

        ; ①b 类名只有一个命中时兜底（标题被改过的情况）
        if !found {
            lst := WinGetList("ahk_class " WeChatMainClass " ahk_exe Weixin.exe")
            if (lst.Length = 1)
                found := lst[1]
        }

        ; ② 按标题兜底（类名随版本变化时），同名窗口取面积最大的那个
        ;    注意：微信还有 176x199 的 "Weixin" 小窗口，必须按面积取最大才拿到主窗口
        if !found {
            bestArea := 0
            for h in WinGetList("ahk_exe Weixin.exe") {
                try {
                    t := WinGetTitle("ahk_id " h)
                    WinGetPos(&px, &py, &pw, &ph, "ahk_id " h)
                } catch {
                    continue
                }
                isMatch := false
                for name in WeChatTitles {
                    if (t = name) {
                        isMatch := true
                        break
                    }
                }
                if (isMatch && pw * ph > bestArea) {
                    bestArea := pw * ph
                    found := h
                }
            }
        }

        ; ③ 最后兜底：Weixin.exe 里“当前不可见”的最大窗口（隐藏到托盘的主窗口）
        if !found {
            bestArea := 0
            for h in WinGetList("ahk_exe Weixin.exe") {
                if IsHwndVisible(h)
                    continue
                try {
                    if (WinGetExStyle("ahk_id " h) & 0x80)   ; WS_EX_TOOLWINDOW 的工具窗口跳过
                        continue
                    WinGetPos(&px, &py, &pw, &ph, "ahk_id " h)
                } catch {
                    continue
                }
                if (pw < MinWidth || ph < MinHeight)
                    continue
                if (pw * ph > bestArea) {
                    bestArea := pw * ph
                    found := h
                }
            }
        }
    }
    DetectHiddenWindows(oldDHW)
    return found
}

; ============================================================
; 微信托盘图标唤起（正解）
; 微信 Ctrl+W 后主窗口只是被隐藏，托盘图标仍在。Explorer 点击图标时会向图标窗口
; 发送微信自己 RegisterWindowMessage 注册的回调消息（wParam=uID，lParam=鼠标消息）。
; 我们自己发这条消息 = 让微信自己把窗口显示出来，微信内部状态与窗口状态一致，
; 唤出后再按 Ctrl+W 依然正常（强行 ShowWindow 会导致 Ctrl+W 失效）。
; 实测：lParam 必须是 WM_LBUTTONDBLCLK(0x203)，WM_LBUTTONUP(0x202) 无效。
; ============================================================

; AHK v2 没有内置 SendMessageTimeout，用 DllCall（带超时，避免 Explorer 卡住拖死脚本）
SendMsgTimeout(hwnd, msg, wParam, lParam, timeout := 1200) {
    res := 0
    DllCall("SendMessageTimeoutW", "ptr", hwnd, "uint", msg, "uptr", wParam, "ptr", lParam
          , "uint", 2, "uint", timeout, "uptr*", &res)
    return res
}

; 递归收集任务栏 / 溢出面板里的 ToolbarWindow32
CollectTrayToolbars(parent, arr, depth := 0) {
    if (depth > 8)
        return
    h := 0
    loop {
        h := DllCall("FindWindowExW", "ptr", parent, "ptr", h, "ptr", 0, "ptr", 0, "ptr")
        if !h
            break
        cls := ""
        try cls := WinGetClass("ahk_id " h)
        if (cls = "ToolbarWindow32")
            arr.Push(h)
        CollectTrayToolbars(h, arr, depth + 1)
    }
}

IsWeixinHwnd(h) {
    if !h
        return false
    try nm := WinGetProcessName("ahk_id " h)
    catch
        return false
    return (nm = "Weixin.exe")
}

; 微信的托盘图标消息窗口（类名 Qt51514WxTrayIconMessageWindowClass）
GetWeChatTrayWnd() {
    t := 0
    oldDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        for h in WinGetList("ahk_exe Weixin.exe") {
            try cls := WinGetClass("ahk_id " h)
            catch
                continue
            if InStr(cls, "WxTrayIcon")
                t := h
        }
    } finally {
        DetectHiddenWindows(oldDHW)
    }
    return t
}

; 从通知区域读出微信图标注册的 (hwnd, uID, uCallbackMessage)
; TRAYDATA 布局：hwnd(0) / uID(8) / uCallbackMessage(12)
; 返回 {hwnd, uID, msg}，找不到返回 0
ReadWeChatTrayInfo() {
    static TB_BUTTONCOUNT := 0x0418, TB_GETBUTTON := 0x0417
    roots := []
    for h in WinGetList("ahk_class Shell_TrayWnd")
        roots.Push(h)
    ov := DllCall("FindWindowW", "wstr", "NotifyIconOverflowWindow", "ptr", 0, "ptr")
    if ov
        roots.Push(ov)

    for root in roots {
        toolbars := []
        CollectTrayToolbars(root, toolbars)
        for tb in toolbars {
            pid := 0
            DllCall("GetWindowThreadProcessId", "ptr", tb, "uint*", &pid)
            if !pid
                continue
            cnt := SendMsgTimeout(tb, TB_BUTTONCOUNT, 0, 0)
            if (cnt <= 0)
                continue
            hProc := DllCall("OpenProcess", "uint", 0x1F0FFF, "int", 0, "uint", pid, "ptr")
            if !hProc
                continue
            addr := DllCall("VirtualAllocEx", "ptr", hProc, "ptr", 0, "uptr", 256, "uint", 0x3000, "uint", 0x04, "ptr")
            if !addr {
                DllCall("CloseHandle", "ptr", hProc)
                continue
            }
            result := 0
            try {
                loop cnt {
                    idx := A_Index - 1
                    SendMsgTimeout(tb, TB_GETBUTTON, idx, addr)
                    btn := Buffer(32, 0)
                    rd := 0
                    if !DllCall("ReadProcessMemory", "ptr", hProc, "ptr", addr, "ptr", btn, "uptr", 32, "uptr*", &rd)
                        continue
                    dwData := NumGet(btn, 16, "Ptr")      ; TBBUTTON.dwData -> TRAYDATA
                    if !dwData
                        continue
                    td := Buffer(64, 0)
                    rd2 := 0
                    if !DllCall("ReadProcessMemory", "ptr", hProc, "ptr", dwData, "ptr", td, "uptr", 64, "uptr*", &rd2)
                        continue
                    iconHwnd := NumGet(td, 0, "Ptr")
                    if IsWeixinHwnd(iconHwnd) {
                        result := {hwnd: iconHwnd, uID: NumGet(td, 8, "UInt"), msg: NumGet(td, 12, "UInt")}
                        break
                    }
                }
            } finally {
                DllCall("VirtualFreeEx", "ptr", hProc, "ptr", addr, "uptr", 0, "uint", 0x8000)
                DllCall("CloseHandle", "ptr", hProc)
            }
            if result
                return result
        }
    }
    return 0
}

; 模拟点击微信托盘图标，让微信自己显示主窗口。返回 true 表示已显示
WakeWeChatByTray() {
    global WeChatMainClass
    trayWnd := GetWeChatTrayWnd()
    info := ReadWeChatTrayInfo()
    if !info && !trayWnd
        return false
    if !info
        info := {hwnd: trayWnd, uID: 0, msg: 0x8385}   ; 读不到托盘数据时的兜底

    DllCall("PostMessageW", "ptr", info.hwnd, "uint", info.msg, "uptr", info.uID, "ptr", 0x0203)
    loop 25 {
        Sleep(100)
        hwnd := WinExist("ahk_class " WeChatMainClass " ahk_exe Weixin.exe")
        if (hwnd && IsHwndVisible(hwnd))
            return true
    }
    return false
}

; 把隐藏的微信主窗口“拉”出来（兜底手段，可能导致 Ctrl+W 失效）
; 注意：必须用 DllCall 的 ShowWindow，AHK 的 WinShow 对这类被应用隐藏的窗口不生效（实测无效）
; 返回 true 表示已成功显示并激活
ShowWeChatWindow(hwnd) {
    global ok_x, ok_y, ok_w, ok_h
    if !hwnd || !DllCall("IsWindow", "ptr", hwnd)
        return false

    ; cloaked 的窗口（例如停留在别的虚拟桌面）先 SW_HIDE 再 SW_SHOW 才会重新上屏
    if IsHwndCloaked(hwnd) {
        DllCall("ShowWindow", "ptr", hwnd, "int", 0)      ; SW_HIDE
        Sleep(30)
    }

    DllCall("ShowWindow", "ptr", hwnd, "int", 9)          ; SW_RESTORE（还原并显示）
    DllCall("ShowWindow", "ptr", hwnd, "int", 5)          ; SW_SHOW（确保 WS_VISIBLE 打开）
    ; SWP_NOSIZE(0x1)|SWP_NOMOVE(0x2)|SWP_NOACTIVATE(0x10)|SWP_SHOWWINDOW(0x40)
    DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x53)
    Sleep(60)

    if !IsHwndVisible(hwnd)      ; 还是不可见，说明应用层把窗口又隐藏了
        return false

    oldDHW := A_DetectHiddenWindows
    DetectHiddenWindows(true)
    try {
        WinActivate("ahk_id " hwnd)
        WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " hwnd)
    } finally {
        DetectHiddenWindows(oldDHW)
    }
    return true
}

switchToWechat() {
    global ok_x, ok_y, ok_w, ok_h, WeChatExePath, WeChatMainClass, WeChatRelaunchToRestore

    ; 进程没起来 -> 直接启动
    if (ProcessExist("Weixin.exe") = 0) {
        Run('"' WeChatExePath '"')
        return
    }

    ; ---- ① 正常：主窗口可见 ----
    hwnd := WinExist("ahk_class " WeChatMainClass " ahk_exe Weixin.exe")

    ; ---- ② 主窗口被隐藏（Ctrl+W 关掉 / 隐藏到托盘，进程与句柄都还在）----
    if !hwnd {
        hwnd := GetWeChatHiddenWindow()
        if hwnd {
            write("微信主窗口不可见（句柄 " Format("0x{:X}", hwnd) "），尝试点托盘图标唤出")
            if WakeWeChatByTray() {
                write("已通过托盘图标唤出微信主窗口")
                hwnd := WinExist("ahk_class " WeChatMainClass " ahk_exe Weixin.exe")
                if hwnd {
                    WinActivate("ahk_id " hwnd)
                    WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " hwnd)
                    WinSetAlwaysOnTop(true, "ahk_id " hwnd)
                }
                return
            }
            write("托盘唤出失败，回退 ShowWindow（注意：之后 Ctrl+W 可能失效）")
            if ShowWeChatWindow(hwnd) {
                write("已通过 ShowWindow 恢复微信主窗口")
                return
            }
            write("ShowWindow 也无效，窗口可能已被销毁")
            hwnd := 0
        }
    }

    ; ---- ③ 主窗口已被销毁：再跑一次 Weixin.exe，靠单实例机制唤醒已有实例 ----
    if !hwnd {
        if !WeChatRelaunchToRestore {
            write("未找到微信主窗口，且已禁用重新拉起")
            return
        }
        write("未找到微信主窗口，重新拉起 Weixin.exe 唤醒已有实例")
        Run('"' WeChatExePath '"')
        loop 40 {
            Sleep(100)
            if (hwnd := WinExist("ahk_class " WeChatMainClass " ahk_exe Weixin.exe"))
                break
            if (hwnd := GetWeChatHiddenWindow())
                break
        }
        if !hwnd {
            write("重新拉起后仍未找到微信主窗口")
            return
        }
        if !IsHwndVisible(hwnd) {
            ShowWeChatWindow(hwnd)
            return
        }
    }

    ; ---- ④ 窗口可见：恢复最小化 / 被遮挡就提到前面，否则最小化 ----
    if (WinGetMinMax("ahk_id " hwnd) = -1) {
        WinRestore("ahk_id " hwnd)
        WinActivate("ahk_id " hwnd)
        WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " hwnd)
        return
    }

    if IsWindowCovered("ahk_id " hwnd) {
        WinActivate("ahk_id " hwnd)
        ;WinMove(ok_x+8, ok_y, ok_w-16, ok_h, "ahk_id " hwnd)
        WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " hwnd)
    } else {
        WinMinimize("ahk_id " hwnd)
    }
}

switchToryij() {
    global cmds_should_show_realnews
    ryij_path := "\\192.168.0.6\news\ryij.txt"
    
    SetTitleMatchMode(2)
    
    if WinExist("ryij.txt - 记事本") {
        targetWindowTitle := "ryij.txt - 记事本"
    } else if WinExist("ryij - 记事本") {
        targetWindowTitle := "ryij - 记事本"
    } else if WinExist("*ryij.txt - 记事本") {
        targetWindowTitle := "*ryij.txt - 记事本"
    } else if WinExist("*ryij - 记事本") {
        targetWindowTitle := "*ryij - 记事本"
    } else {
        Run(ryij_path)
        SetTitleMatchMode("RegEx")
        try {
            WinWait("ryij.*记事本",, 2)
        }
        
        if WinExist("ryij.txt - 记事本") {
            targetWindowTitle := "ryij.txt - 记事本"
        } else if WinExist("ryij - 记事本") {
            targetWindowTitle := "ryij - 记事本"
        }
    }
    
    if targetWindowTitle {
        WinActivate
        WinMove(2653, 0, 796, 478, targetWindowTitle)
        
        realnews_hwnd := WinGetID(targetWindowTitle)
        WinSetAlwaysOnTop(true, "ahk_id " realnews_hwnd)
    }
    
    cmds_should_show_realnews := "1"
}

openRiLi() {
    Run "https://www.baidu.com/s?wd=%E6%97%A5%E5%8E%86"   ; 请将网址替换为实际需要打开的链接
}

switchToTHS() {
    THS_path := "D:\THS\hexin.exe"
    SetTitleMatchMode("RegEx")
    
    ths_hwnd := WinExist("同花顺\(.*\).* ahk_exe hexin.exe")
    if (ths_hwnd) {
        WinActivate("ahk_id " ths_hwnd)
        WinMove(-7, 1, 1968, 1446, "ahk_id " ths_hwnd)
    } else {
        Run(THS_path)
    }

    blockers := GetBlockingWindows(ths_hwnd)
    if (blockers.Length > 0) {
        for hwnd in blockers {
            if WinExist("ahk_id " hwnd) {
                title := WinGetTitle("ahk_id " hwnd)
                processName := WinGetProcessName("ahk_id " hwnd)
                ;if (processName != "hexin.exe" && (processName != "stockapp.exe" || InStr(title, "guba_jiucai_xueqiu")) && title != "quick_program.ahk") {
                if (processName != "hexin.exe" && (title != "陈小群" && title != "下单" && title != "排板" && title != "大单异动" && title != "实时新闻" && title != "涨停股" && title != "股票池" && title != "概念" && title != "风向标" && title != "个股新闻") && title != "quick_program.ahk") {
                    if (processName == "chrome.exe") {
                        Style := WinGetStyle("ahk_id " hwnd)
                        if (!(Style & 0x20000000)) {
                            ;switchToChrome之后会导致焦点移动到chrome上，如果再快速切换到hexin.exe后再快速输入股票代码会导致只能输入部分字符串，例如dfcf只会成功输入cf，所以这里不能激活chrome只能把它移个位置
                            switchToChrome(0)
                        }
                    } else {
                        WinMinimize("ahk_id " hwnd)
                    }

                }
            }
        }
    }

    SetTitleMatchMode(2)
    if WinExist("实时新闻") {
        hwnd := WinGetID("实时新闻")
        if (hwnd) {
            Style := WinGetStyle("ahk_id " hwnd)
            if (!(Style & 0x20000000)) {
                Style2 := WinGetStyle("涨停股")
                if (!(Style2 & 0x20000000)) {
                    WinMove(784, 466, 1033, 499, "ahk_id " hwnd)
                } else {
                    WinMinimize("ahk_id " hwnd)
                }
            }
        }
    }
}

tide() {
    dir := "Z:\"
    script := dir . "\tide.py"
    SetWorkingDir(dir)
    Run(A_ComSpec " /k python " Chr(34) script Chr(34) " && exit")
}

switchToZNZ() {
    znz_path := "C:\Compass\WavMain\WavMain.exe"

    SetTitleMatchMode("RegEx")

    if CheckProcessExist("WavMain.exe") = 0
        Run(znz_path)
    else {
        SetTitleMatchMode("RegEx")
        if WinExist("指南针全赢决策系统") {
            znz_hwnd := WinGetID("指南针全赢决策系统")
            WinActivate("ahk_id " znz_hwnd)
            WinSetAlwaysOnTop(true, "ahk_id " znz_hwnd)
        }
    }
}

switchToTL50() {
    tl50_path := "D:\Program Files\tl50\tl50v2.exe"
    

    SetTitleMatchMode("RegEx")

    if CheckProcessExist("tl50v2.exe") = 0
        Run(tl50_path)
    else {
        SetTitleMatchMode("RegEx")
        if WinExist(".*天狼50.*") {
            WinActivate
            WinSetAlwaysOnTop(true, ".*天狼50.*")
        }
    }
}

switchTorealnews() {
    global cmds_should_show_realnews

    SetTitleMatchMode(2)
    if WinExist("实时新闻") {
        hwnd := WinGetID("实时新闻")
        if (hwnd) {
            Style := WinGetStyle("ahk_id " hwnd)
            if (Style & 0x20000000) {
                cmds_should_show_realnews := "1"
            }

            if (cmds_should_show_realnews == "0") {
                WinMinimize("实时新闻 ahk_exe python.exe")
                WinMinimize("涨停股 ahk_exe python.exe")
                WinMinimize("股票池 ahk_exe python.exe")
                SetTitleMatchMode("RegEx")
                WinMinimize("大单.* ahk_exe python.exe")
                cmds_should_show_realnews := "1"
            } else if (cmds_should_show_realnews == "1") {
                WinRestore("实时新闻 ahk_exe python.exe")
                WinMove(784, 466, 1033, 499, "实时新闻 ahk_exe python.exe")
                WinRestore("涨停股 ahk_exe python.exe")
                WinRestore("股票池 ahk_exe python.exe")
                SetTitleMatchMode("RegEx")
                WinRestore("大单.* ahk_exe python.exe")
                cmds_should_show_realnews := "0"
            }
        }
    } else {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(30000, 60000, 30000, 30000)
        whr.Open("GET", "http://192.168.1.7:3333/show_realtime_news_window", true)
        whr.Send()
        try {
            whr.WaitForResponse()
        } catch Error as e {
        }
    }
}

moveRealnews() {
    global ok_x, ok_y, ok_w, ok_h
    SetTitleMatchMode(2)
    if WinExist("实时新闻") {
        hwnd := WinGetID("实时新闻")
        if (hwnd) {
            Style := WinGetStyle("ahk_id " hwnd)
            if (Style & 0x20000000) {
                WinRestore("实时新闻")
            }

            realnewsTitle := "实时新闻"
            WinMove(2660, ok_y, 789, ok_h-2, realnewsTitle)
            realnews_hwnd := WinGetID(realnewsTitle)
            WinSetAlwaysOnTop(false, "ahk_id " realnews_hwnd)
            WinActivate("实时新闻")
            WinSetAlwaysOnTop(true, "ahk_id " realnews_hwnd)
        }
    }
}



switchToGBJC_old() {
    static guba_hwnd := 0, jiucai_hwnd := 0, xueqiu_hwnd := 0

    ; 更新句柄（仅在无效时重新查找）
    if !guba_hwnd || !WinExist("ahk_id " guba_hwnd)
        guba_hwnd := WinExist("guba ahk_exe python.exe")
    if !jiucai_hwnd || !WinExist("ahk_id " jiucai_hwnd)
        jiucai_hwnd := WinExist("jiucai ahk_exe python.exe")
    if !xueqiu_hwnd || !WinExist("ahk_id " xueqiu_hwnd)
        xueqiu_hwnd := WinExist("xueqiu ahk_exe python.exe")

    if jiucai_hwnd
        WinActivate("ahk_id " jiucai_hwnd)
    if xueqiu_hwnd
        WinActivate("ahk_id " xueqiu_hwnd)
    if guba_hwnd
        WinActivate("ahk_id " guba_hwnd)

    if guba_hwnd
        WinSetAlwaysOnTop(1, "ahk_id " guba_hwnd)
    if jiucai_hwnd
        WinSetAlwaysOnTop(1, "ahk_id " jiucai_hwnd)
    if xueqiu_hwnd
        WinSetAlwaysOnTop(1, "ahk_id " xueqiu_hwnd)

    moveRealnews()
}

switchToGBJC() {
    static guba_hwnd := 0, jiucai_hwnd := 0, xueqiu_hwnd := 0

    ; 恢复最小化窗口
    if WinExist("ahk_id " jiucai_hwnd)
        WinRestore("ahk_id " jiucai_hwnd)
    else
        jiucai_hwnd := WinExist("jiucai ahk_exe python.exe")
        if jiucai_hwnd
            WinRestore("ahk_id " jiucai_hwnd)

    if WinExist("ahk_id " xueqiu_hwnd)
        WinRestore("ahk_id " xueqiu_hwnd)
    else
        xueqiu_hwnd := WinExist("xueqiu ahk_exe python.exe")
        if xueqiu_hwnd
            WinRestore("ahk_id " xueqiu_hwnd)

    if WinExist("ahk_id " guba_hwnd)
        WinRestore("ahk_id " guba_hwnd)
    else
        guba_hwnd := WinExist("guba ahk_exe python.exe")
        if guba_hwnd
            WinRestore("ahk_id " guba_hwnd)

    if WinExist("ahk_id " jiucai_hwnd)
        WinSetAlwaysOnTop(1, "ahk_id " jiucai_hwnd)
    if WinExist("ahk_id " xueqiu_hwnd)
        WinSetAlwaysOnTop(1, "ahk_id " xueqiu_hwnd)
    if WinExist("ahk_id " guba_hwnd)
        WinSetAlwaysOnTop(1, "ahk_id " guba_hwnd)


    moveRealnews()
}

; 用法：IsWindowCoveredFast("记事本") 或 IsWindowCoveredFast("ahk_id " hWnd)
; 返回：true = 被遮挡，false = 完全可见
IsWindowCovered(WinTitle) {
    hWnd := WinExist(WinTitle)
    if !hWnd
        return true   ; 不存在视为遮挡

    ; 不可见或最小化 -> 遮挡
    if !DllCall("IsWindowVisible", "Ptr", hWnd) || (WinGetMinMax(hWnd) = -1)
        return true

    ; --- 获取目标窗口的屏幕矩形（使用原生 API 更快）---
    tRect := Buffer(16)   ; RECT: left, top, right, bottom (各 4 字节 Int)
    if !DllCall("GetWindowRect", "Ptr", hWnd, "Ptr", tRect, "Int")
        return true
    tLeft   := NumGet(tRect,  0, "Int")
    tTop    := NumGet(tRect,  4, "Int")
    tRight  := NumGet(tRect,  8, "Int")
    tBottom := NumGet(tRect, 12, "Int")
    ; 无效面积
    if (tRight <= tLeft || tBottom <= tTop)
        return true

    ; --- 从 Z 序向上遍历，检查所有可见的前置窗口 ---
    aRect := Buffer(16)   ; 复用缓冲区，每次覆盖即可
    hAbove := DllCall("GetWindow", "Ptr", hWnd, "UInt", 3, "Ptr")  ; GW_HWNDPREV = 3
    while hAbove {
        ; 只检查可见的窗口
        if DllCall("IsWindowVisible", "Ptr", hAbove) {
            DllCall("GetWindowRect", "Ptr", hAbove, "Ptr", aRect)
            aLeft   := NumGet(aRect,  0, "Int")
            aTop    := NumGet(aRect,  4, "Int")
            aRight  := NumGet(aRect,  8, "Int")
            aBottom := NumGet(aRect, 12, "Int")

            ; 如果有任何重叠，立即判定为被遮挡
            if (tLeft < aRight && tRight > aLeft && tTop < aBottom && tBottom > aTop)
                return true
        }
        ; 继续向上一级
        hAbove := DllCall("GetWindow", "Ptr", hAbove, "UInt", 3, "Ptr")
    }

    return false  ; 检查完所有上方窗口，没有遮挡
}

switchToXIADAN() {
    global ok_x, ok_y, ok_w, ok_h

    SetTitleMatchMode(2)
    if WinExist("网上股票交易系统5.0") {
        xiadan_hwnd := WinGetID("网上股票交易系统5.0")
        if (xiadan_hwnd) {
            Style := WinGetStyle("ahk_id " xiadan_hwnd)
            ;if ((Style & 0x20000000) or (!WinActive("ahk_id " xiadan_hwnd))) {
            if IsWindowCovered("ahk_id " xiadan_hwnd) {
                WinActivate("ahk_id " xiadan_hwnd)
                ;WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " xiadan_hwnd)
                MoveWindowVisually(ok_x, ok_y, ok_w, ok_h, "ahk_id " xiadan_hwnd)
                WinSetAlwaysOnTop(true, "ahk_id " xiadan_hwnd)
            } else {
                WinMinimize("ahk_id " xiadan_hwnd)
            }
        }
    }
}

minimize_current_window() {
    try WinMinimize("A")
}

set_current_window_to_top() {
    global WindowPositionDict, ok_x, ok_y, ok_w, ok_h
    hwnd := WinGetID("A")
    title := WinGetTitle("ahk_id " hwnd)
    if (SubStr(title, 1, 4)=="同花顺(") {
        return
    }
    curX := 0, curY := 0, curW := 0, curH := 0
    WinGetPos(&curX, &curY, &curW, &curH, "ahk_id " hwnd)
    isAtFixedPos := (curX == ok_x && curY == ok_y && curW == ok_w && curH == ok_h)
    ExStyle := WinGetExStyle("A")
    if (isAtFixedPos && (ExStyle & 0x8)) {
        if (WindowPositionDict.Has(hwnd)) {
            orig := WindowPositionDict[hwnd]
            WinMove(orig.x, orig.y, orig.w, orig.h, "ahk_id " hwnd)
            WindowPositionDict.Delete(hwnd)
        }
    } else {
        origX := 0, origY := 0, origW := 0, origH := 0
        WinGetPos(&origX, &origY, &origW, &origH, "ahk_id " hwnd)
        WindowPositionDict[hwnd] := {x: origX, y: origY, w: origW, h: origH}
        WinRestore("ahk_id " hwnd)
        ;WinMove(ok_x, ok_y, ok_w, ok_h, "A")
        MoveWindowVisually(ok_x, ok_y, ok_w, ok_h, "A")
        WinSetAlwaysOnTop(true, "A")
    }
}

set_fenxi_top() {
    hwnds := WinGetList("ahk_class #32770 ahk_exe hexin.exe")
    targetHwnd := 0
    for hwnd in hwnds {
        try {
            title := WinGetTitle("ahk_id " hwnd)
            if (title = "") {
                WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwnd)
                if (winW == 314 && winH == 116) {
                    targetHwnd := hwnd
                    break
                }
            }
        } catch {
            continue
        }
    }
    if (targetHwnd) {
        WinActivate("ahk_id " targetHwnd)
        WinSetAlwaysOnTop(1, "ahk_id " targetHwnd)
        ;write("置顶了同花顺分析对话框（标题为空，尺寸314x116）")
    }
}

ths_fenxi() {
    global win_ctrl_w_should_close_ths_fenxi_window
    if (win_ctrl_w_should_close_ths_fenxi_window == "0") {
        WinActivate("同花顺(")
        CoordMode("Mouse", "Window")
        Click(151, 14, 1)
        Click(197, 303, 1)
        CoordMode("Mouse", "Screen")
        Click(1023, 692, 1)
        win_ctrl_w_should_close_ths_fenxi_window := "1"

        ; 延迟50ms后置顶弹出的对话框（类名 #32770，进程 hexin.exe）
        SetTimer(set_fenxi_top, -50)

    } else {
        CoordMode("Mouse", "Screen")
        Click(1120, 668, 1)
        win_ctrl_w_should_close_ths_fenxi_window := "0"
    }
}

GetControlUnderMousePos(&CtrlX?, &CtrlY?, &CtrlW?, &CtrlH?) {
    MouseGetPos(,, &WinID, &ControlClassNN)
    if (ControlClassNN = "EditWnd1" || ControlClassNN = "EditWnd") {
        ControlGetPos(&cX, &cY, &cW, &cH, ControlClassNN, "ahk_id " WinID)
        CtrlX := cX, CtrlY := cY, CtrlW := cW, CtrlH := cH
        return {x: cX, y: cY, width: cW, height: cH, control: ControlClassNN, winID: WinID}
    }
    return false
}

show_ths_yujin() {
    if WinExist("预警结果") {
        WinActivate("预警结果")
        WinSetAlwaysOnTop(true, "预警结果")
    }
}

open_moniqi(retryCount := 0) {
    global ok_y, ok_h
    windowTitle := "MuMu安卓设备"
    noxPath := "D:\\Program Files\\Netease\\MuMu\\nx_main\\MuMuManager.exe"

    if WinExist(windowTitle) {
        WinActivate(windowTitle)
        WinMove(2656, ok_y, 786, ok_h + 1, windowTitle)
    } else {
        ; 启动模拟器
        Run(Format('"{}" control -v 0 launch', noxPath))
        Sleep(5000)
        Run(Format('"{}" control -v 0 app launch -pkg com.yzj.kaipanh', noxPath))

        ; 等待窗口出现
        if !WinWait(windowTitle,, 30) {
            MsgBox("等待窗口超时，请检查模拟器是否正常启动")
            return
        }
        WinActivate(windowTitle)

        Sleep(25000)

        ; 检查崩溃（窗口可能消失，且崩溃报告器出现）
        if !WinExist(windowTitle) && WinExist("MuMuNxCrashReporter ahk_exe MuMuNxCrashReporter.exe") {
            WinClose("MuMuNxCrashReporter ahk_exe MuMuNxCrashReporter.exe")
            Sleep(1000)
            if (retryCount < 3)
                return open_moniqi(retryCount + 1)
            else {
                MsgBox("模拟器多次崩溃，请手动检查")
                return
            }
        }

        WinSetAlwaysOnTop(true, windowTitle)
        ;“行情”需要点2次，因为有时候会有弹窗，点第一次相当于关闭弹窗，点第二次才是真的点到了行情
        CoordMode("Mouse", "Window")
        ControlClick("x236 y1365", windowTitle)
        Sleep(1000)
        CoordMode("Mouse", "Window")
        ControlClick("x236 y1365", windowTitle)
        Sleep(1000)
        ControlClick("x349 y132", windowTitle)
        WinActivate(windowTitle)
        WinMove(2656, ok_y, 786, ok_h+1, windowTitle)
    }
}

switch_ths_to_paiban() {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.SetTimeouts(30000, 60000, 30000, 30000)
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.10&callback=lala", true)
    whr.Send()
    try {
        whr.WaitForResponse()
    } catch Error as e {
    }
    CreateOverlays()
}

switch_ths_to_fupan() {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.SetTimeouts(30000, 60000, 30000, 30000)
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.11&callback=lala", true)
    whr.Send()
    try {
        whr.WaitForResponse()
    } catch Error as e {
    }
    DestroyOverlays()
    if WinExist("股票池") {
        Style := WinGetStyle("股票池")
        if (!(Style & 0x20000000)) {
            switchTorealnews()
        }
    }
}

ths_xiadie_yujin_confirm() {
    ; 关键步骤：在系统看到按键组合前，先发送 Win 和 Ctrl 的抬起事件，避免触发系统自带的win+ctrl的快捷键（对应音频识别）。后来发现是微信的快捷键，在微信中设置取消这个快捷键即可。
    ;Send "{Blind}{LWin up}{RWin up}{LCtrl up}{RCtrl up}"

    if !WinExist("添加预警") {
        switchToTHS()
        CoordMode("Mouse", "Screen")
        Click(990, 65, "Right")
        Send("+t")
        WinWait("添加预警",, 2)
        try WinActivate("添加预警")
        if WinExist("添加预警") {
            CoordMode("Mouse", "Window")
            Click(182, 141, 1)
            return
        } else {
            ToolTip("不存在添加预警窗口@111")
            SetTimer RemoveToolTip, -1000
        }
    } else {
        if !WinActive("添加预警") {
            switchToTHS()
            WinActivate("添加预警")
            WinWait("添加预警",, 2)
            if WinExist("添加预警") {
                CoordMode("Mouse", "Window")
                Click(182, 141, 1)
                return
            } else {
                ToolTip("不存在添加预警窗口@222")
                SetTimer RemoveToolTip, -1000
            }
        } else {
            WinGetPos(&WinX, &WinY, &WinWidth, &WinHeight, "添加预警")
            WinRight := WinX + WinWidth
            WinBottom := WinY + WinHeight
            CoordMode("Mouse", "Screen")
            MouseGetPos(&MouseX, &MouseY)
            IsMouseInWindow := (MouseX >= WinX && MouseX <= WinRight && MouseY >= WinY && MouseY <= WinBottom)
            if !IsMouseInWindow {
                ToolTip("存在添加预警窗口且窗口已激活但鼠标不在该窗口范围内")
                SetTimer RemoveToolTip, -1000
                WinActivate("添加预警")
                WinWait("添加预警",, 2)
                if WinExist("添加预警") {
                    CoordMode("Mouse", "Window")
                    Click(182, 141, 1)
                    return
                }
            }
        }
    }

    MouseMove(-15, 0, 0, "R")
    ctrlInfo := GetControlUnderMousePos(&x, &y, &w, &h)

    if (!ctrlInfo) {
        MouseMove(0, -7, 0, "R")
        ctrlInfo := GetControlUnderMousePos(&x, &y, &w, &h)
        if (!ctrlInfo) {
            MouseMove(0, 14, 0, "R")
            ctrlInfo := GetControlUnderMousePos(&x, &y, &w, &h)
        }
        if (!ctrlInfo) {
            return false
        }
    }

    WinActivate("添加预警")
    WinWait("添加预警",, 2)

    newX := ctrlInfo.x - 100
    targetY := ctrlInfo.y + 9
    CoordMode("Mouse", "Window")

    ControlClick("x" newX " y" targetY, "添加预警")
    ControlClick("x173 y446", "添加预警")
}



SmartClose() {
    if !WinExist("A")      ; 检查是否有活动窗口
        return             ; 没有则直接退出，避免错误
    hwnd := WinGetID("A")
    processName := WinGetProcessName("A")
    winClass := WinGetClass("A")
    currentTitle := WinGetTitle("A")

    browserProcesses := ["chrome.exe", "msedge.exe", "firefox.exe", "opera.exe", "vivaldi.exe"]
    for browser in browserProcesses {
        if (processName = browser) {
            Send("^w")
            return
        }
    }

    if (winClass = "CabinetWClass") {
        ; 不能用 Send("!{F4}")：CapsLock 充当 Ctrl 时 Ctrl 仍被按住，
        ; 发出去的会变成 Ctrl+Alt+F4，资源管理器不响应。
        ; 改用窗口消息，绕开键盘状态。
        WinClose("ahk_id " hwnd)
    } else if (winClass = "ApplicationFrameWindow") {
        PostMessage(0x112, 0xF060, , , "A")
    } else if (processName = "hexin.exe" && currentTitle = "添加预警") {
        ControlClick("x450 y16", "ahk_id " hwnd)
    } else if (processName = "hexin.exe" && currentTitle = "预警结果") {
        ControlClick("x659 y16", "ahk_id " hwnd)
    } else {
        WinClose("ahk_id " hwnd)
        Sleep(300)
        if WinExist("ahk_id " hwnd) {
            WinKill("ahk_id " hwnd)
        }
    }
}

GetBlockingWindows(targetHwnd) {
    if !WinExist("ahk_id " targetHwnd)
        return ["目标窗口不存在"]

    WinGetPos(&tX, &tY, &tW, &tH, "ahk_id " targetHwnd)
    tState := WinGetMinMax("ahk_id " targetHwnd)
    if (tState = -1) || (tW = 0) || (tH = 0)
        return ["目标窗口已最小化或不可见"]

    blockingWindows := []
    winList := WinGetList()
    for currentHwnd in winList {
        if (currentHwnd = targetHwnd)
            break

        if !WinExist("ahk_id " currentHwnd)
            continue

        style := WinGetStyle("ahk_id " currentHwnd)
        exStyle := WinGetExStyle("ahk_id " currentHwnd)
        minMax := WinGetMinMax("ahk_id " currentHwnd)

        if (minMax = -1) || !(style & 0x10000000) || (exStyle & 0x80)
            continue

        WinGetPos(&cX, &cY, &cW, &cH, "ahk_id " currentHwnd)
        if (cW = 0) || (cH = 0)
            continue

        left   := Max(tX, cX)
        right  := Min(tX + tW, cX + cW)
        top    := Max(tY, cY)
        bottom := Min(tY + tH, cY + cH)

        if (left < right) && (top < bottom) {
            overlapArea := (right - left) * (bottom - top)
            if (overlapArea > 100)
                blockingWindows.Push(currentHwnd)
        }
    }

    return blockingWindows
}

CreateOverlays() {
    global overlays
    DestroyOverlays()          ; 先销毁旧的
    overlays := []
    
    ; 定义静态遮罩（无论排板窗口状态都创建的）
    staticDefs := [
        [0, 8, 128, 21, 255],       ; 顶部白条遮罩句柄@left
        [166, 8, 1598, 21, 255],    ; 顶部白条遮罩句柄@right
        [233, 778, 392, 23, 255],   ; 上翻 下翻 顶部 底部
        [234, 703, 390, 25, 255],   ; 查看完整报价
        [567, 803, 58, 190, 255],   ; 千档盘口红绿点
        [612, 681, 13, 20, 150],    ; 预警铃铛
        [459, 102, 165, 368, 90],   ; 逐笔成交明细买单卖单
        [1793, 402, 108, 21, 225],  ; 成交量下拉框背景
        [120, 1246, 110, 18, 225],  ; 涨速排名下拉框背景
        [1, 508, 44, 20, 225],      ; 自选股表单设置背景
        [1814, 57, 87, 19, 250]     ; 叠 窗 区 信息 的白字
    ]
    
    ; 条件遮罩 overlay1（根据排板窗口状态选择位置）
    hwnd := WinExist("排板 ahk_exe python.exe")
    if (hwnd && !DllCall("IsIconic", "ptr", hwnd)) {
        overlay1_def := [386, 995, 239, 31, 255]   ;短版短线精灵护罩
    } else {
        overlay1_def := [234, 995, 391, 31, 255]   ;长版短线精灵护罩
    }
    
    ; 合并所有遮罩定义（先加条件遮罩，再加静态遮罩）
    allDefs := [overlay1_def]
    allDefs.Push(staticDefs*)
    
    for def in allDefs {
        overlays.Push(CreateOverlay(def[1], def[2], def[3], def[4], def[5]))
    }
}

DestroyOverlays() {
    global overlays
    for gui in overlays {
        try gui.Destroy()
    }
    overlays := []
}

CreateOverlay(x, y, w, h, transparency) {
    myGui := Gui("+ToolWindow -Caption +AlwaysOnTop +E0x20")
    myGui.BackColor := "e8e3ce"
    myGui.Show("x" x " y" y " w" w " h" h " NA")
    hwnd := myGui.Hwnd
    WinSetTransparent(transparency, "ahk_id " hwnd)
    return myGui
}

minimize_some_windows() {
    DestroyOverlays()
    if WinExist("下单") {
        WinMinimize
    }
    if WinExist("排板") {
        WinMinimize
    }
    if WinExist("短线精灵") {
        WinMinimize
    }
    if WinExist("大单") {
        WinMinimize
    }
    if WinExist("实时新闻") {
        WinMinimize
    }
    if WinExist("陈小群") {
        WinMinimize
    }
    if WinExist("涨停股") {
        WinMinimize
    }
    if WinExist("股票池") {
        WinMinimize
    }
}

restore_current_window() {
    CurrentWindow := "A"
    WindowTitle := WinGetTitle(CurrentWindow)
    if (InStr(WindowTitle, "VLC media player") > 0) {
        WindowProcess := WinGetProcessName(CurrentWindow)
        if (WindowProcess = "vlc.exe") {
            SendInput("{Esc}")
            Sleep(100)
        }
    } else {
        WinRestore(CurrentWindow)
    }
}

current_window_is_fullscreen() {
    ScreenWidth := SysGet(0)
    ScreenHeight := SysGet(1)
    WinGetPos(&WinX, &WinY, &WinW, &WinH, "A")
    WinState := WinGetMinMax("A")

    Tolerance := 18
    XMatch := (Abs(WinX) <= Tolerance)
    YMatch := (Abs(WinY) <= Tolerance)
    WidthMatch := (Abs(WinW - ScreenWidth) <= Tolerance)
    HeightMatch := (Abs(WinH - ScreenHeight) <= Tolerance)
    IsFullScreen := XMatch && YMatch && WidthMatch && HeightMatch && (WinState != -1)
    return IsFullScreen
}

fullscreen_current_window_forcall() {
    WindowProcess := WinGetProcessName("A")
    if (WindowProcess = "vlc.exe") {
        WinActivate("A")
        Sleep(100)
        SendInput("!v")
        Sleep(100)
        SendInput("f")
    } else {
        WinMaximize("A")
    }
}

move_current_window_to_left() {
    restore_current_window()
    ;WinMove(-7, 1, 1968, 1446, "A")
    MoveWindowVisually(0, 8, 1954, 1446, "A")
}

move_current_window_to_right() {
    global ok_y, ok_h
    restore_current_window()
    WinMove(right_ok_x, ok_y, 795, ok_h+1, "A")
}

fullscreen_current_window() {
    if (current_window_is_fullscreen()) {
        restore_current_window()
    } else {
        fullscreen_current_window_forcall()
    }
}

check_to_kill_thunder() {
    ;需要在迅雷中设置悬浮球仅在下载时显示
    if !WinExist("悬浮球 ahk_exe Thunder.exe") {
        print("迅雷下载结束，现在结束迅雷相关进程")
        Run("z:\xthunder.py")
    }
}

; ============================================================
; 窗口事件监视器函数
; ============================================================

SetWinEventHook(eventMin, eventMax, hmod, lpfn, idProcess, idThread, dwFlags) {
    return DllCall("SetWinEventHook", "uint", eventMin, "uint", eventMax, "ptr", hmod
        , "ptr", lpfn, "uint", idProcess, "uint", idThread, "uint", dwFlags, "ptr")
}

UnhookWinEvent(hHook) {
    return DllCall("UnhookWinEvent", "ptr", hHook)
}

IsUsableWindowStrict(hwnd) {
    global MinWidth, MinHeight
    style := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr")
    if !(style & WS_VISIBLE) || (style & WS_CHILD)
        return false

    local rect := Buffer(16)
    if !DllCall("GetWindowRect", "ptr", hwnd, "ptr", rect.Ptr)
        return false
    width := NumGet(rect, 8, "int") - NumGet(rect, 0, "int")
    height := NumGet(rect, 12, "int") - NumGet(rect, 4, "int")
    return (width >= MinWidth && height >= MinHeight)
}

IsUsableWindowModerate(hwnd) {
    style := DllCall("GetWindowLongPtr", "ptr", hwnd, "int", -16, "ptr")
    if !(style & WS_VISIBLE) || (style & WS_CHILD)
        return false

    if DllCall("GetParent", "ptr", hwnd) != 0
        return false

    return true
}

CarefullySetTopMost(hwnd, title) {
    ; 注意，当前函数是不激活目标进程，只是对目标窗口设置置顶
    if SubStr(title, 1, 4)=="同花顺(" or title="短线精灵"
        return false
    if !WinExist("ahk_id " hwnd)
        return false
    try {
        WinSetAlwaysOnTop(1, "ahk_id " hwnd)
        return true
    } catch Error as e {
        try {
            className := WinGetClass("ahk_id " hwnd)
        } catch {
            className := "获取失败"
        }
        try {
            procName := WinGetProcessName("ahk_id " hwnd)
        } catch {
            procName := "获取失败"
        }
        try {
            procId := WinGetPID("ahk_id " hwnd)
        } catch {
            procId := 0
        }
        write("无法设置置顶 - 句柄: " Format("0x{:X}", hwnd) 
            . ", 标题: " title 
            . ", 类名: " className 
            . ", 进程: " procName 
            . ", PID: " procId 
            . ", 错误: " e.Message)
        return false
    }
}

; 处理自动切换输入法：先判断要不要自动切换，如果需要则切换
HandleAutoIme_old(hwnd, procName) {
    if !WinExist("ahk_id " hwnd)
        return
    currentMode := GetImeModeEx(hwnd).mode
    targetMode := PorcessIMEDICT[procName]
    print(procName " 此前的输入法是： " currentMode)
    if (currentMode != targetMode) {
        print(procName " 切换输入法到 " targetMode)
        switchState()
    }
}
; 主切换函数（重试入口）
HandleAutoIme(hwnd, procName, retryCount := 3) {
    if !WinExist("ahk_id " hwnd)
        return
    currentMode := GetImeModeEx(hwnd).mode
    targetMode := PorcessIMEDICT[procName]
    if (currentMode = targetMode)
        return  ; 已处于目标模式，无需切换

    ; 执行切换
    ;print(procName " 切换输入法到 " targetMode)
    switchState()

    ; 若还有重试机会，则延迟 150ms 进行检查
    if (retryCount > 0)
        SetTimer(CheckAndRetryIme.Bind(hwnd, procName, retryCount - 1), -150)
}

; 延迟检查函数：若仍未成功，则进行下一次重试
CheckAndRetryIme(hwnd, procName, retriesLeft) {
    if !WinExist("ahk_id " hwnd)
        return
    currentMode := GetImeModeEx(hwnd).mode
    targetMode := PorcessIMEDICT[procName]
    if (currentMode = targetMode)
        return  ; 切换成功，不再重试

    ; 仍然不匹配，消耗一次重试机会
    ;print(procName " 输入法仍未切换，重试剩余 " retriesLeft " 次")
    HandleAutoIme(hwnd, procName, retriesLeft)
}

WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global msgWindow, WM_USER_EVENT
    ;if (hwnd = 0 || idObject != 0)
    if (hwnd==0)
        return
    if (event == EVENT_OBJECT_SHOW) {
        if !IsUsableWindowStrict(hwnd)
            return
    } else {
        return
    }

    DllCall("PostMessage", "ptr", msgWindow, "uint", WM_USER_EVENT, "ptr", event, "ptr", hwnd)
}



ShellMessageHandler(wParam, lParam, msg, hwnd) {
    if (wParam = HSHELL_RUDEAPPACTIVATED) {
        if !IsUsableWindowModerate(lParam)
            return
        EventMessageHandler(HSHELL_RUDEAPPACTIVATED, lParam, msg, hwnd)
    }
}

EventMessageHandler(wParam, lParam, msg, hwnd) {
    global listview, history, ActivateProcesses
    event := wParam
    hwndTarget := lParam

    class := "", title := ""
    try class := WinGetClass("ahk_id " hwndTarget)
    try title := WinGetTitle("ahk_id " hwndTarget)

    if (event == HSHELL_RUDEAPPACTIVATED) {
        if (ignoreActivateTitles.Has(title)) {
            return
        }
        eventName := "ACTIVATED"

        try {
            procName := WinGetProcessName("ahk_id " hwndTarget)
        } catch {
            procName := ""
        }

        ; 如果窗口信息为空，可能还在初始化，延迟置顶
        if (title=="" && class=="" && procName=="") {
            SetTimer(() => CarefullySetTopMost(hwndTarget, title), -500)
        } else {
            CarefullySetTopMost(hwndTarget, title)
        }

        if (history.Length >= 20)
            history.RemoveAt(1)
        history.Push(hwndTarget)

        ; 同花顺子窗口自动置顶
        if (procName=="hexin.exe" && SubStr(title, 1, 4)=="同花顺(") {
            try WinSetAlwaysOnTop(1, "所属板块 ahk_exe hexin.exe")
            try WinSetAlwaysOnTop(1, "添加预警 ahk_exe hexin.exe")
            try WinSetAlwaysOnTop(1, "大单棱镜 ahk_exe hexin.exe")
            try WinSetAlwaysOnTop(1, "预警结果 ahk_exe hexin.exe")
        }


        if PorcessIMEDICT.Has(procName) {
            ;这里要延时50ms后再进行HandleAutoIme处理，因为HandleAutoIme中的获取目标句柄当前输入法需要延时50ms才能准确获取，否则在窗口初始化的时候可能会获取到错误的值,例如win+r可复现
            SetTimer(HandleAutoIme.Bind(hwndTarget, procName), -50)
            ;HandleAutoIme(hwndTarget, procName)
        }

    } else if (event == EVENT_OBJECT_SHOW) {
        if (class == "SysShadow" || ignoreShowTitles.Has(title)) {
            return
        }
    
        eventName := "SHOW"

        try {
            procName := WinGetProcessName("ahk_id " hwndTarget)
        } catch {
            procName := ""
        }

        if ActivateProcesses.Has(procName) {
            WinActivate("ahk_id " hwndTarget)
        }
        CarefullySetTopMost(hwndTarget, title)

        ; 迅雷下载完成检测
        if (title=="提示框" && procName=="Thunder.exe") {
            SetTimer(check_to_kill_thunder, -1000)
        } else if (procName=="hexin.exe" && class=="#32770") {
            try {
                WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwndTarget)
                write("hexin.exe #32770 window:" . winX . "," . winY . "," . winW . "," . winH)
                if (winW==480 && winH==360) {
                    WinClose("ahk_id " hwndTarget)
                } else if (winW==280 && winH==180) {
                    ; 右下角弹窗新闻
                } else {
                    WinActivate("ahk_id " hwndTarget)
                    CarefullySetTopMost(hwndTarget, title)
                }
            } catch as err {
                write("错误消息：" err.Message "`n"
                . "所在函数/命令：" err.What "`n"
                . "额外信息：" (err.Extra ? err.Extra : "无") "`n"
                . "行号：" err.Line)
            }
        }


        if PorcessIMEDICT.Has(procName) {
            ;这里要延时50ms后再进行HandleAutoIme处理，因为HandleAutoIme中的获取目标句柄当前输入法需要延时50ms才能准确获取，否则在窗口初始化的时候可能会获取到错误的值,例如win+r可复现
            SetTimer(HandleAutoIme.Bind(hwndTarget, procName), -50)
            ;HandleAutoIme(hwndTarget, procName)
        }

    } else {
        eventName := "UNKNOWN"
    }

    if (listview)
        listview.Insert(1, , eventName, Format("0x{:X}", hwndTarget), class, title)
}

GuiClose(*) {
    ExitApp
}

ExitFunc(*) {
    global hookShow, WinEventProcCallback
    if (hookShow)
        UnhookWinEvent(hookShow)
    if (WinEventProcCallback)
        CallbackFree(WinEventProcCallback)
}
