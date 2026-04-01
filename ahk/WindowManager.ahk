#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================
; 全局变量声明（函数外部无需加 global）
; ============================================================

; ---------- 同花顺相关全局变量 ----------
cmds_should_show_realnews := "0"
win_ctrl_w_should_close_ths_fenxi_window := "0"

; 遮罩窗口对象（将由数组管理）
overlays := []

WindowPositionDict := Map()
ok_x := 776
ok_y := 7
ok_w := 1892
ok_h := 1440

log_Enabled := true
log_FilePath := "d:\WinHistory.log"
log_MaxSize := 10 * 1024 * 1024

; 调试开关：是否显示监视器窗口（ListView）
showMonitorGui := false   ; 设为 false 时完全不创建 GUI，使用脚本主窗口；true为创建；
msgWindow := 0            ; 消息接收窗口句柄，将在脚本启动时赋值

; ---------- 窗口事件监视器相关全局变量 ----------
listview := 0
hookShow := 0                      ; 仅保留 SHOW 钩子
WinEventProcCallback := 0
history := []                       ; 最近使用窗口历史（包含所有激活，允许重复）
ignoreActivate := false             ; 临时忽略下一次激活事件（不再使用，但保留）
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
MinHeight := 150

; Shell 钩子常量
HSHELL_RUDEAPPACTIVATED := 0x8004   ; 窗口激活事件

; 定义在置顶时需要激活的进程名列表（可以根据实际需要扩展）
ActivateProcesses := Map(
    "Thunder.exe", 1,      ; 迅雷
    ; 添加其他需要激活的进程...
)

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

; 安装窗口事件钩子（仅保留 SHOW）
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

; 设置CapsLock状态
SetCapsLockState("AlwaysOff")

; 初始化同花顺遮罩
CreateOverlays()

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

; ----- 同花顺遮罩控制热键 -----
^1::CreateOverlays
^2::DestroyOverlays
^3::minimize_some_windows

; ----- 窗口位置控制热键 -----
^+h::move_current_window_to_left
^+l::move_current_window_to_right
#+f::fullscreen_current_window

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
; CapsLock 热键映射
; ============================================================
CapsLock::Send("{Esc}")

CapsLock & a::Send("^a")
CapsLock & b::Send("^b")
CapsLock & c::Send("^c")
CapsLock & d::Send("^d")
CapsLock & e::Send("^e")
CapsLock & f::Send("^f")
CapsLock & g::Send("^g")
CapsLock & h::Send("^h")
CapsLock & i::Send("^i")
CapsLock & j::Send("^j")
CapsLock & k::Send("^k")
CapsLock & l::Send("^l")
CapsLock & m::Send("^m")
CapsLock & n::Send("^n")
CapsLock & o::Send("^o")
CapsLock & p::Send("^p")
CapsLock & q::Send("^q")
CapsLock & r::Send("^r")
CapsLock & s::Send("^s")
CapsLock & t::Send("^t")
CapsLock & u::Send("^u")
CapsLock & v::Send("^v")
CapsLock & w::Send("^w")
CapsLock & x::Send("^x")
CapsLock & y::Send("^y")
CapsLock & z::Send("^z")
CapsLock & 0::Send("^0")
CapsLock & 1::Send("^1")
CapsLock & 2::Send("^2")
CapsLock & 3::Send("^3")
CapsLock & 4::Send("^4")
CapsLock & 5::Send("^5")
CapsLock & 6::Send("^6")
CapsLock & 7::Send("^7")
CapsLock & 8::Send("^8")
CapsLock & 9::Send("^9")
CapsLock & '::Send("^'")
CapsLock & ,::Send("^,")
CapsLock & -::Send("^-")
CapsLock & .::Send("^.")
CapsLock & /::Send("^/")
CapsLock & =::Send("^=")
CapsLock & [::Send("^[")
CapsLock & ]::Send("^]")
CapsLock & \::Send("^\")

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

print(string) {
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
switchToChrome() {
    global ok_x, ok_y, ok_h

    SetTitleMatchMode("RegEx")
    if WinExist("guba_jiucai.*") {
        WinMinimize
    }

    SetTitleMatchMode(2)
    if WinExist("ahk_exe chrome.exe") {
        WinRestore
        chromeTitle := " - Google Chrome"
        WinMove(2653, ok_y, 795, ok_h+1, chromeTitle)
        
        chrome_hwnd := WinGetID(chromeTitle)
        WinActivate("ahk_id " chrome_hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " chrome_hwnd)
    } else {
        Run("chrome.exe")
    }
}

switchToUseChrome() {
    global ok_x, ok_y, ok_w, ok_h

    SetTitleMatchMode("RegEx")
    if WinExist("guba_jiucai.*") {
        WinMinimize
    }

    SetTitleMatchMode(2)
    if WinExist("ahk_exe chrome.exe") {
        WinRestore
        chromeTitle := " - Google Chrome"
        WinMove(ok_x, ok_y, ok_w, ok_h, chromeTitle)
        
        chrome_hwnd := WinGetID(chromeTitle)
        WinActivate("ahk_id " chrome_hwnd)
        WinSetAlwaysOnTop(true, "ahk_id " chrome_hwnd)
    } else {
        Run("chrome.exe")
    }
}

open_tbjl_bat() {
    Run("z:\tbjl.bat")
}

switchToWechat() {
    global ok_x, ok_y, ok_w, ok_h

    WeChat_path := "D:\Program Files\Tencent\Weixin\Weixin.exe"
    if CheckProcessExist("Weixin.exe") = 0
        Run(WeChat_path)
    else {
        if WinExist("ahk_class Qt51514QWindowIcon") {
            Style := WinGetStyle("ahk_class Qt51514QWindowIcon")
            if ((Style & 0x20000000) or (!WinActive("ahk_class Qt51514QWindowIcon"))) {
                WinActivate
                WinMove(ok_x+8, ok_y, ok_w-16, ok_h, "ahk_class Qt51514QWindowIcon")
                WinSetAlwaysOnTop(true, "ahk_class Qt51514QWindowIcon")
            } else {
                WinMinimize
            }
        }
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
                    WinMinimize("ahk_id " hwnd)
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
    znz_path := "D:\Compass\WavMain\WavMain.exe"

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
    tl50_path := "D:\Program Files\天狼50\天狼50证券分析系统\tl50v2.exe"

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


switchToXIADAN() {
    global ok_x, ok_y, ok_w, ok_h

    SetTitleMatchMode(2)
    if WinExist("网上股票交易系统5.0") {
        xiadan_hwnd := WinGetID("网上股票交易系统5.0")
        if (xiadan_hwnd) {
            Style := WinGetStyle("ahk_id " xiadan_hwnd)
            if ((Style & 0x20000000) or (!WinActive("ahk_id " xiadan_hwnd))) {
                WinActivate("ahk_id " xiadan_hwnd)
                WinMove(ok_x, ok_y, ok_w, ok_h, "ahk_id " xiadan_hwnd)
                WinSetAlwaysOnTop(true, "ahk_id " xiadan_hwnd)
            } else {
                WinMinimize("ahk_id " xiadan_hwnd)
            }
        }
    }
}

minimize_current_window() {
    WinMinimize("A")
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
        WinMove(ok_x, ok_y, ok_w, ok_h, "A")
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
        WinMove(2657, ok_y, 786, ok_h + 1, windowTitle)
    } else {
        ; 启动模拟器
        ;Run(Format('"{}" control -v 0 launch -pkg com.aiyu.kaipanla', noxPath))
        Run(Format('"{}" control -v 0 launch -pkg com.yzj.kaipanh', noxPath))

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
        CoordMode("Mouse", "Window")
        ControlClick("x233 y1376", windowTitle)
        Sleep(1000)
        ControlClick("x275 y134", windowTitle)
        WinMove(2657, ok_y, 786, ok_h+1, windowTitle)
    }
}

switch_ths_to_paiban() {
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.SetTimeouts(30000, 60000, 30000, 30000)
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.10", true)
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
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.11", true)
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
    if !WinExist("添加预警") {
        switchToTHS()
        CoordMode("Mouse", "Screen")
        Click(1937, 233, "Right")
        Send("+t")
        WinWait("添加预警",, 2)
        WinActivate("添加预警")
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
        Send("!{F4}")
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
    WinMove(-7, 1, 1968, 1446, "A")
}

move_current_window_to_right() {
    global ok_y, ok_h
    restore_current_window()
    WinMove(2653, ok_y, 795, ok_h+1, "A")
}

fullscreen_current_window() {
    if (current_window_is_fullscreen()) {
        restore_current_window()
    } else {
        fullscreen_current_window_forcall()
    }
}

check_to_kill_thunder() {
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

WinEventProc(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
    global msgWindow, WM_USER_EVENT
    if (hwnd = 0 || idObject != 0)
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
    global listview, history, ignoreActivate, ActivateProcesses
    event := wParam
    hwndTarget := lParam

    class := "", title := ""
    try class := WinGetClass("ahk_id " hwndTarget)
    try title := WinGetTitle("ahk_id " hwndTarget)

    if (event == HSHELL_RUDEAPPACTIVATED) {
        if (title="Program Manager") {
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

        ; 无论是否 ignoreActivate，都记录到历史（因为需求是全部记录）
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

    } else if (event == EVENT_OBJECT_SHOW) {
        if (title="EAGrid") {
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
            WinGetPos(&winX, &winY, &winW, &winH, "ahk_id " hwndTarget)
            if (winW==480 && winH==360) {
                ;write("检测到同花顺广告窗口，现在尝试自动关闭")
                WinClose("ahk_id " hwndTarget)
            }
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
    global hookShow, WinEventProcCallback, msgWindow
    if (hookShow)
        UnhookWinEvent(hookShow)
    if (WinEventProcCallback)
        CallbackFree(WinEventProcCallback)
    ; 可选：注销 ShellHook
    ; DllCall("DeregisterShellHookWindow", "ptr", msgWindow)
}
