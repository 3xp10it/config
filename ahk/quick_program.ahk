;注意，本文件要以ansi编码保存，否则与中文相关的操作会失败
;注意，全局变量只能放在文件最前面，否则会出错
;注意，使用本程序如果安装了迅雷则需要提前在迅雷悬浮球上右键设置悬浮球仅下载时显示，需要设置下载完成后弹窗提示（载完成后弹窗提示是默认的）

#SingleInstance Force  ; 关键防护（防多实例冲突）
#InstallKeybdHook      ; 保障Win+热键可靠性

global thsWindowTitle := ".*9\.30\.72.*"

cmds_should_show_realnews:="0"
win_ctrl_w_should_close_ths_fenxi_window:="0"

global overlay1 := 0  ; 短线精灵标题栏
global overlay2_1 := 0  ; 顶部白条遮罩句柄@left
global overlay2_2 := 0  ; 顶部白条遮罩句柄@right
global overlay3 := 0  ; "上翻 下翻 顶部 底部"
global overlay4 := 0  ; "查看完整报价"
global overlay5 := 0  ; "千档盘口红绿点"
global overlay6 := 0  ; "预警铃铛"
global overlay7 := 0  ; "逐笔成交明细买单卖单"
global overlay8 := 0  ; "逐笔成交明细左边的白框"
global overlay9 := 0  ; "委买队列"
global overlay10 := 0  ; "成交量下拉框背景"
global overlay11 := 0  ; "涨速排名下拉框背景"
global overlay12 := 0  ; "自选股表单设置背景"
global overlay13 := 0 ; 叠 窗 区 信息 的白字

; 全局变量存储窗口原始位置
global WindowPositionDict := Object()

;中间便看的位置
global ok_x:=776
global ok_y:=8
global ok_w:=1892
global ok_h:=1440

log_Enabled := true                     ; 日志开关
log_FilePath := "d:\WinHistory.log"  ; 日志路径
log_MaxSize := 10 * 1024 * 1024         ; 最大10MB

; ----- 窗口历史记录（最近使用列表，唯一化）-----
global g_windowHistory := []        ; 句柄列表，索引1为最近激活
global g_maxHistory   := 50         ; 历史记录最大长度
global g_lastBTime    := 0          ; 上次按 #b 的时间戳
global g_bIndex       := 2          ; 当前遍历索引，默认从上一个窗口开始

; ----- #b 激活忽略标记（精准识别）-----
global g_ignoreHwnd   := 0          ; 要忽略激活事件的窗口句柄
global g_ignoreTime   := 0          ; 设置标记的时间戳
global IGNORE_TIMEOUT := 500        ; 忽略窗口激活的有效时间（毫秒）

; ============================================================
;                      ShellHook 初始化
; ============================================================
Gui, +LastFound
hWnd := WinExist()
regResult := DllCall("RegisterShellHookWindow", "UInt", hWnd)
msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
OnMessage(msgNum, "ShellMessage")

; 脚本启动时自动执行函数
CreateOverlays()

; ============================================================
;                      工具函数
; ============================================================
RemoveToolTip:
    ToolTip
Return

print(string) {
    Tooltip, %string%
    SetTimer, RemoveToolTip, -3000
}

Carefully_set_A_topmost() {
    WinGetActiveTitle, ActiveWindowTitle
    if (InStr(ActiveWindowTitle,"同花顺(")==0 && ActiveWindowTitle!="短线精灵")
    {
        WinSet, AlwaysOnTop, On, A
    }
}

; ============================================================
;              核心：ShellMessage 窗口事件处理（已修复）
; ============================================================
ShellMessage(wParam, lParam) {
    global g_windowHistory, g_maxHistory, g_bIndex, g_lastBTime
    global g_ignoreHwnd, g_ignoreTime, IGNORE_TIMEOUT

    ; ----- 1. 精准忽略 #b 触发的激活事件 -----
    if (g_ignoreHwnd != 0) {
        if (wParam = 32772) {
            if (lParam = g_ignoreHwnd) && (A_TickCount - g_ignoreTime <= IGNORE_TIMEOUT) {
                ; 完全忽略本次激活，不记录历史、不执行任何后续操作
                g_ignoreHwnd := 0
                g_ignoreTime := 0
                ; 可选调试：write("Ignored #b activation, hwnd=" lParam)
                return
            }
        }
        ; 超时后自动清除标记
        if (A_TickCount - g_ignoreTime > IGNORE_TIMEOUT) {
            g_ignoreHwnd := 0
            g_ignoreTime := 0
        }
    }

    ; ----- 2. 原有日志、广告拦截等功能（完全保留）-----
    WinGetTitle, title, ahk_id %lParam%
    WinGetTitle, current_title, A
    WinGet, processName, ProcessName, ahk_id %lParam%
    triggerSource := GetEventTriggerSource(wParam, lParam)

    logMessage := (Join "事件: wParam=" wParam " | 窗口标题=" (title ? title : "N/A") " | 进程名=" (processName ? processName : "N/A") " | 句柄=" lParam)
    FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss.fff
    logMessage := Format("{} | 事件: {}({:X}) | 触发者: {} | 进程: {} | 句柄: 0x{:X} `n窗口title: {} `n current_title: {}" , timestamp, GetEventName(wParam), wParam, triggerSource, (processName ? processName : "N/A"), lParam, (title ? StrReplace(title, "|", "∣") : "N/A"), current_title)
    


    if (wParam != 2 && wParam != 6) {

        if (processName = "hexin.exe") {
            WinGetClass, class, ahk_id %lParam%
            if (class = "#32770") {
                print(logMessage)
                write(logMessage)

                WinGetPos, X, Y, Width, Height, ahk_id %lParam%
                FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss.fff
                adLog := Format("【疑似广告弹窗】时间: {} | 类: {} | 标题: '{}' | 尺寸: {}x{} | 位置: ({}, {}) | 句柄: 0x{:X}", timestamp, class, title, Width, Height, X, Y, lParam)
                write(adLog)
                print(adLog)

                if (Width = 480 && Height = 360) {
                    write("=== 检测到480x360广告窗口 ===")
                    print("=== 检测到480x360广告窗口 ===")
                    ;PostMessage, 0x10, 0, 0, , ahk_id %lParam%  ; WM_CLOSE
                }
            }
        }
    }

    ; 只处理我们关心的激活/创建事件
    if ((wParam != 32772 && wParam != 32774 && wParam != 1 && wParam != 16) || lParam == 0)
        return

    Sleep, 300
    WinGet, A_hwnd, ID, A
    WinGetTitle, A_title, A
    WinGet, A_processName, ProcessName, A

    ; 排除无效窗口（桌面/任务栏/自身窗口）
    if (title = "Program Manager" || InStr(title, "AutoHotkey"))
        return

    ; ----- 3. 历史记录更新（仅限用户手动激活，已去重）-----
    ; 删除历史中所有与该窗口句柄相同的记录
    i := 1
    while (i <= g_windowHistory.Length()) {
        if (g_windowHistory[i] = A_hwnd) {
            g_windowHistory.RemoveAt(i)
        } else {
            i++
        }
    }

    ; 插入到栈顶
    g_windowHistory.InsertAt(1, A_hwnd)
    ;write("现在在g_windowHistory中插入窗口的title是：" . A_title)

    ; 保持历史长度不超过最大值
    if (g_windowHistory.Length() > g_maxHistory)
        g_windowHistory.Pop()

    ; 重置 #b 索引，从上一个窗口开始
    g_bIndex := 2
    g_lastBTime := 0

    ; ----- 4. 原有置顶逻辑（完全保留）-----
    if (processName = "hexin.exe") {
        if (current_title = "预警结果") {
            WinMove, 预警结果, , 1230, 987, 680, 406
        }
        if (wParam = 1) {
            Carefully_set_A_topmost()
            return
        }
        if (title = current_title) {
            Carefully_set_A_topmost()
            WinSet, AlwaysOnTop, On, 所属板块 ahk_exe hexin.exe
            WinSet, AlwaysOnTop, On, 添加预警 ahk_exe hexin.exe
            WinSet, AlwaysOnTop, On, 大单棱镜 ahk_exe hexin.exe
            WinSet, AlwaysOnTop, On, 预警结果 ahk_exe hexin.exe
            return
        }
        if (InStr(current_title, "同花顺(") == 0) {
            Carefully_set_A_topmost()
            return
        }
    } else if (triggerSource = "外部进程: Thunder.exe") {
            if (wParam=32774)
            {
                ;点击网页中的磁力链接后出的迅雷下载新建任务面板弹窗
                SetTitleMatchMode, 3
                Sleep, 2000
                WinSet, AlwaysOnTop, On, 新建任务面板
                Sleep, 2000
                WinSet, AlwaysOnTop, On, 新建任务面板
                Sleep, 2000
                WinSet, AlwaysOnTop, On, 新建任务面板
                return
            }
            else if (wParam=16)
            {
                ;迅雷完成一个文件的下载后会弹窗提示，对应的消息是0x10，弹出窗口对应的title是“提示框”
                IfWinExist, 提示框 ahk_exe Thunder.exe
                {
                    Sleep,200
                    ;print("存在迅雷下载完成提示框")
                    ;如果存在悬浮球则说明还在下载，如果不存在悬浮球则说明已经没有在下载了为了防止迅雷自行上传p2p流量可以经结束迅雷的相关进程了
                    Sleep,200
                    IfWinNotExist, 悬浮球 ahk_exe Thunder.exe
                    {
                        print("迅雷下载结束，现在结束迅雷相关进程")
                        Run, z:\xthunder.py
                    }
                }
            }
    } else if (InStr(title, "同花顺(") == 0) {
        if (processName = "explorer.exe" && current_title = title && InStr(title, "\\")) {
            WinSet, AlwaysOnTop, On, ahk_class #32768 ahk_exe explorer.exe
        } else if (processName = "Weixin.exe" && title = current_title) {
            WinSet, AlwaysOnTop, On, ahk_id %lParam%
            WinSet, AlwaysOnTop, On, Weixin ahk_class Qt51514QWindowToolSaveBits ahk_exe Weixin.exe
        } else if (processName = "stockapp.exe" && InStr(title, "个股新闻") > 0) {
            return
        } else {
            Carefully_set_A_topmost()
        }
    }
}

; ============================================================
;              事件触发源检测（您原有的函数，完整保留）
; ============================================================
GetEventTriggerSource(wParam, lParam) {
    static lastInputTime := 0

    if (A_TimeIdle < 500) {
        if (A_PriorKey != "")
            return "键盘: " A_PriorKey
        if (A_TimeSincePriorMouse < 500)
            return "鼠标: " A_ThisHotkey
    }

    switch wParam
    {
        case 1:  return "系统创建"
        case 2:  return "系统销毁"
        case 4:  return WinActive("ahk_class ApplicationFrameWindow") ? "UWP应用" : "系统激活"
        case 32772: return IsAutomatedActivation() ? "程序自动激活" : "用户切换"
    }

    if (DllCall("GetWindowThreadProcessId", "UInt", lParam, "UInt*", pid)) {
        if (pid != DllCall("GetCurrentProcessId")) {
            WinGet, sourceProcess, ProcessName, ahk_pid %pid%
            return "外部进程: " (sourceProcess ? sourceProcess : "PID:" pid)
        }
    }

    return "未知来源"
}

GetEventName(wParam) {
    eventNames := {1: "窗口创建", 2: "窗口销毁", 4: "App激活", 32772: "窗口激活"}
    return eventNames.HasKey(wParam) ? eventNames[wParam] : "未知事件"
}

IsAutomatedActivation() {
    return DllCall("GetForegroundWindow") == DllCall("GetActiveWindow") ? false : true
}

; ============================================================
; 日志写入函数
; ============================================================
write(message) {
    global log_Enabled, log_FilePath, log_MaxSize

    if !log_Enabled
        return

    if !FileExist(log_FilePath)
        FileAppend,, %log_FilePath%, UTF-8

    FileGetSize, fileSize, %log_FilePath%
    if (fileSize > log_MaxSize) {
        FileDelete, %log_FilePath%.old
        FileMove, %log_FilePath%, %log_FilePath%.old
    }

    FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss.fff
    fullMessage := "[" timestamp "] " message "`n"
    FileAppend, %fullMessage%, %log_FilePath%, UTF-8
}

ProcessExist(exe) {
    Process, Exist, % exe
    return ErrorLevel
}

; ============================================================
;                #b 热键：切换上一个窗口（已修复）
; ============================================================
#b::switch_to_last_active_window()
switch_to_last_active_window() {
    global g_windowHistory, g_lastBTime, g_bIndex, g_maxHistory
    global g_ignoreHwnd, g_ignoreTime, IGNORE_TIMEOUT

    ; 检查历史记录是否足够
    if (g_windowHistory.Length() < 2) {
        print("111没有可用的历史窗口记录")
        return
    }

    ; 重置索引逻辑（3秒无操作则从上一个开始）
    currentTime := A_TickCount
    timeDiff := currentTime - g_lastBTime
    if (timeDiff > 3000) {
        g_bIndex := 2
    }
    g_lastBTime := currentTime

    ; 索引边界保护
    if (g_bIndex > g_windowHistory.Length()) {
        g_bIndex := 2
    }

    ; 查找第一个有效的窗口（跳过非最小化的同花顺主窗口/短线精灵）
    foundHwnd := 0
    this_g_bIndex := g_bIndex
    while (g_bIndex <= g_windowHistory.Length()) {
        testHwnd := g_windowHistory[g_bIndex]
        if !WinExist("ahk_id " testHwnd) {
            g_windowHistory.RemoveAt(g_bIndex)
            continue
        }
        WinGetTitle, test_title, ahk_id %testHwnd%
        if ((InStr(test_title, "同花顺(") || test_title = "短线精灵") && !DllCall("IsIconic", "ptr", testHwnd)) {
            g_bIndex += 1
            continue
        }
        foundHwnd := testHwnd
        break
    }

    if !foundHwnd {
        g_bIndex := 2
        ;print("没有可用的历史窗口记录,g_windowHistory长度：" . g_windowHistory.Length() . " this_g_bIndex:" . this_g_bIndex)
        return
    }

    ; ----- 设置忽略标记：接下来的激活事件如果是这个窗口，将被 ShellMessage 忽略 -----
    g_ignoreHwnd := foundHwnd
    g_ignoreTime := A_TickCount
    ; 启动定时器，1秒后强制清除标记（防止意外残留）
    SetTimer, ClearIgnoreFlag, -1000

    ; 恢复最小化窗口并激活
    WinGet, minMax, MinMax, ahk_id %foundHwnd%
    if (minMax = -1)
        WinRestore, ahk_id %foundHwnd%

    ; 激活窗口
    WinActivate, ahk_id %foundHwnd%
    WinGetTitle, title, ahk_id %foundHwnd%
    if (InStr(title, "同花顺(") == 0 && title!="短线精灵") {
        ; 同花顺的主窗口和短线精灵窗口不置顶
        WinSet, AlwaysOnTop, On, ahk_id %foundHwnd%
    }
    else if (InStr(title, "同花顺("))
    {
        ; 同花顺的主窗口通过特殊的方式来打开,switchToTHS()会调整同花顺主窗口的位置
        switchToTHS()
    }
    ;write("现在通过#b完成了激活这个title:" . title)

    ; 索引递增，下次按 #b 时切换到更早的窗口
    g_bIndex += 1
}

; ----- 定时清除忽略标记（防止因异常导致标记永久残留）-----
ClearIgnoreFlag:
    g_ignoreHwnd := 0
    g_ignoreTime := 0
return

; ============================================================
;                   以下为您的所有其他热键和函数
;               （完全保留原样，一字不改）
; ============================================================

; ----- 浏览器相关 -----
#g::switchToChrome()
switchToChrome()
{
    SetTitleMatchMode RegEx
    if WinExist("guba_jiucai.*")
    {
        WinMinimize
    }

    SetTitleMatchMode, 2
    IfWinExist, ahk_exe chrome.exe
    {
        WinRestore
        chromeTitle := " - Google Chrome"
        WinMove, %chromeTitle%, , 2653, ok_y-1, 795, ok_h+1
        WinGet, chrome_hwnd, ID, %chromeTitle%
        WinActivate, ahk_id %chrome_hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %chrome_hwnd%
    }
    else
    {
        Run, chrome.exe
    }
}

#^g::switchToUseChrome()
switchToUseChrome()
{
    SetTitleMatchMode RegEx
    if WinExist("guba_jiucai.*")
    {
        WinMinimize
    }

    SetTitleMatchMode, 2
    IfWinExist, ahk_exe chrome.exe
    {
        WinRestore
        chromeTitle := " - Google Chrome"
        WinMove, %chromeTitle%, , ok_x, ok_y, ok_w, ok_h
        WinGet, chrome_hwnd, ID, %chromeTitle%
        WinActivate, ahk_id %chrome_hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %chrome_hwnd%
    }
    else
    {
        Run, chrome.exe
    }
}

;win+ctrl+e 打开tbjl.bat
#^e::open_tbjl_bat()
open_tbjl_bat()
{
    Run, "z:\tbjl.bat"
}

;win+w 打开微信
#w::switchToWechat()
switchToWechat()
{
    WeChat := "微信"
    WeChat_path := "D:\Program Files\Tencent\Weixin\Weixin.exe"
    if ProcessExist("Weixin.exe") = 0
        Run, %WeChat_path%
    else
    {
        if WinExist("ahk_class Qt51514QWindowIcon")
        {
            WinGet, Style, Style, ahk_class Qt51514QWindowIcon
            if ((Style & 0x20000000) or (not WinActive("ahk_class Qt51514QWindowIcon")))
            {
                WinActivate
                WinMove, ahk_class Qt51514QWindowIcon, , ok_x+8, ok_y, ok_w-16, ok_h
                WinSet, AlwaysOnTop, On, ahk_class Qt51514QWindowIcon
            }
            else
            {
                WinMinimize
            }
        }
    }
}

;win+ctrl+b 打开ryij.txt
#^b::switchToryij()
switchToryij()
{
    global cmds_should_show_realnews
    ryij_path := "\\192.168.0.6\news\ryij.txt"
    if WinExist("ryij.txt - 记事本")
    {
        targetWindowTitle := "ryij.txt - 记事本"
        WinActivate
        WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
        WinSet, AlwaysOnTop, On, %targetWindowTitle%
    }
    else if WinExist("ryij - 记事本")
    {
        targetWindowTitle := "ryij - 记事本"
        WinActivate
        WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
        WinSet, AlwaysOnTop, On, %targetWindowTitle%
    }
    else if WinExist("*ryij.txt - 记事本")
    {
        targetWindowTitle := "*ryij.txt - 记事本"
        WinActivate
        WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
        WinSet, AlwaysOnTop, On, %targetWindowTitle%
    }
    else if WinExist("*ryij - 记事本")
    {
        targetWindowTitle := "*ryij - 记事本"
        WinActivate
        WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
        WinSet, AlwaysOnTop, On, %targetWindowTitle%
    }
    else
    {
        Run, %ryij_path%
        SetTitleMatchMode, RegEx
        WinWait, ryij.*记事本, , 2
        if WinExist("ryij.txt - 记事本")
        {
            targetWindowTitle := "ryij.txt - 记事本"
        }
        else if WinExist("ryij - 记事本")
        {
            targetWindowTitle := "ryij - 记事本"
        }
        WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
        WinSet, AlwaysOnTop, On, %targetWindowTitle%
    }
    cmds_should_show_realnews := "1"
}

DetectHiddenText On

;win+f 打开同花顺
#f::switchToTHS()
switchToTHS()
{
    THS_path := "D:\THS\hexin.exe"
    SetTitleMatchMode, RegEx
    if (ths_hwnd := WinExist("同花顺\(.*\).* ahk_exe hexin.exe"))
    {
        WinActivate, ahk_id %ths_hwnd%
        WinMove, ahk_id %ths_hwnd%, , -7, 1, 1968, 1446
    }
    else
    {
        Run, %THS_path%
    }

    ; 将遮住同花顺的窗口最小化
    blockers := GetBlockingWindows(ths_hwnd)
    if (blockers.Length() > 0)
    {
        for i, hwnd in blockers
        {
            WinGetTitle, title, ahk_id %hwnd%
            WinGet, processName, ProcessName, ahk_id %hwnd%
            if (processName != "hexin.exe" && (processName != "stockapp.exe" || InStr(title, "guba_jiucai_xueqiu")) && title != "quick_program.ahk")
            {
                WinMinimize, ahk_id %hwnd%
            }
        }
    }

    ; 把实时新闻移到原来的位置
    SetTitleMatchMode, 2
    WinGet, hwnd, ID, 实时新闻
    if (hwnd)
    {
        WinGet, Style, Style, ahk_id %hwnd%
        if (!(Style & 0x20000000))
        {
            WinGet, Style, Style, 涨停股
            if (!(Style & 0x20000000))
            {
                WinMove, ahk_id %hwnd%, , 784, 466, 1033, 499
            }
            else
            {
                WinMinimize, ahk_id %hwnd%
            }
        }
    }
}

;win+ctrl+f打开tide.py
#^f::tide()
tide()
{
    dir := "Z:\"
    script := dir . "\tide.py"
    SetWorkingDir %dir%
    Run, %ComSpec% /k python "%script%" && exit
}

;win+a 打开znz
#a::switchToZNZ()
switchToZNZ()
{
    znz := "ahk_exe WavMain.exe"
    znz_path := "D:\Compass\WavMain\WavMain.exe"

    SetTitleMatchMode RegEx

    if ProcessExist("WavMain.exe") = 0
        Run, %znz_path%
    else
    {
        SetTitleMatchMode RegEx
        WinGet, znz_hwnd, ID, 指南针全赢决策系统
        WinActivate, ahk_id %znz_hwnd%
        WinSet, AlwaysOnTop, On, ahk_id %znz_hwnd%
    }
}

;win+c 打开tl50
#c::switchToTL50()
switchToTL50()
{
    tl50 := "ahk_exe tl50v2.exe"
    tl50_path := "D:\Program Files\天狼50\天狼50证券分析系统\tl50v2.exe"

    SetTitleMatchMode RegEx

    if ProcessExist("tl50v2.exe") = 0
        Run, %tl50_path%
    else
    {
        SetTitleMatchMode RegEx
        if WinExist(".*天狼50.*")
        {
            WinActivate
            WinSet, AlwaysOnTop, On, .*天狼50.*
        }
    }
}

;win+s 打开实时新闻
#s::switchTorealnews()
switchTorealnews()
{
    global cmds_should_show_realnews

    SetTitleMatchMode, 2
    if WinExist("实时新闻")
    {
        WinGet, hwnd, ID, 实时新闻
        WinGet, Style, Style, ahk_id %hwnd%
        if (Style & 0x20000000)
        {
            cmds_should_show_realnews := "1"
        }

        if (cmds_should_show_realnews == "0")
        {
            WinMinimize, 实时新闻 ahk_exe stockapp.exe
            WinMinimize, 涨停股 ahk_exe stockapp.exe
            WinMinimize, 股票池 ahk_exe stockapp.exe
            SetTitleMatchMode RegEx
            WinMinimize, 大单.* ahk_exe stockapp.exe
            cmds_should_show_realnews := "1"
        }
        else if (cmds_should_show_realnews == "1")
        {
            WinRestore, 实时新闻 ahk_exe stockapp.exe
            WinMove, 实时新闻 ahk_exe stockapp.exe, , 784, 466, 1033, 499
            WinRestore, 涨停股 ahk_exe stockapp.exe
            WinRestore, 股票池 ahk_exe stockapp.exe
            SetTitleMatchMode RegEx
            WinRestore, 大单.* ahk_exe stockapp.exe
            cmds_should_show_realnews := "0"
        }
    }
    else
    {
        whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(30000, 60000, 30000, 30000)
        whr.Open("GET", "http://192.168.1.7:3333/show_realtime_news_window", true)
        whr.Send()
        try
        {
            whr.WaitForResponse()
        }
        catch e
        {
        }
    }
}

;win+ctrl+t只把实时新闻移到右上角
#^t::moveRealnews()
moveRealnews()
{
    SetTitleMatchMode, 2
    WinGet, hwnd, ID, 实时新闻
    if (hwnd)
    {
        WinGet, Style, Style, ahk_id %hwnd%
        if (Style & 0x20000000)
        {
            WinRestore, 实时新闻
        }

        realnewsTitle := "实时新闻"
        WinMove, %realnewsTitle%, , 2660, ok_y-1, 789, ok_h-2
        WinGet, realnews_hwnd, ID, %realnewsTitle%
        WinSet, AlwaysOnTop, Off, ahk_id %realnews_hwnd%
        WinActivate, 实时新闻
        WinSet, AlwaysOnTop, On, ahk_id %realnews_hwnd%
    }
}

;win+t打开东方财富股吧和韭菜公社
#t::switchToGBJC()
switchToGBJC()
{
    moveRealnews()

    SetTitleMatchMode RegEx
    if WinExist("guba_jiucai.*")
    {
        WinActivate
        WinSet, AlwaysOnTop, On, guba_jiucai.*
    }
}

;win+x打开同花顺网上股票交易系统
#x::switchToXIADAN()
switchToXIADAN()
{
    SetTitleMatchMode, 2
    WinGet, xiadan_hwnd, ID, 网上股票交易系统5.0
    if (xiadan_hwnd)
    {
        WinGet, Style, Style, ahk_id %xiadan_hwnd%
        if ((Style & 0x20000000) or (not WinActive("ahk_id " xiadan_hwnd)))
        {
            WinActivate, ahk_id %xiadan_hwnd%
            WinMove, ahk_id %xiadan_hwnd%, , ok_x, ok_y, ok_w, ok_h
            WinSet, AlwaysOnTop, On, ahk_id %xiadan_hwnd%
        }
        else
        {
            WinMinimize, ahk_id %xiadan_hwnd%
        }
    }
}

;win+z将当前激活的窗口最小化
#z::minimize_current_window()
minimize_current_window()
{
    WinMinimize, A
}

;win+q将当前激活的窗口置顶
#q::set_current_window_to_top()
set_current_window_to_top()
{
    global WindowPositionDict
    WinGet, hwnd, ID, A
    WinGetTitle, title, ahk_id %hwnd%
    if (InStr(title, "同花顺(") == 1)
    {
        return
    }
    WinGetPos, curX, curY, curW, curH, ahk_id %hwnd%
    isAtFixedPos := (curX == ok_x && curY == ok_y && curW == ok_w && curH == ok_h)
    WinGet, ExStyle, ExStyle, A
    if (isAtFixedPos && (ExStyle & 0x8))
    {
        if (WindowPositionDict.HasKey(hwnd))
        {
            orig := WindowPositionDict[hwnd]
            WinMove, ahk_id %hwnd%, , orig.x, orig.y, orig.w, orig.h
            WindowPositionDict.Delete(hwnd)
        }
    }
    else
    {
        WinGetPos, origX, origY, origW, origH, ahk_id %hwnd%
        WindowPositionDict[hwnd] := {x: origX, y: origY, w: origW, h: origH}
        WinRestore, ahk_id %hwnd%
        WinMove, A, , ok_x, ok_y, ok_w, ok_h
        WinSet, AlwaysOnTop, On, A
    }
}

;win+^+w打开同花顺的分析功能
#^w::ths_fenxi()
ths_fenxi()
{
    global win_ctrl_w_should_close_ths_fenxi_window
    if (win_ctrl_w_should_close_ths_fenxi_window == "0")
    {
        WinActivate, 同花顺(
        CoordMode, Mouse, Window
        Click, 151, 14, 1
        Click, 197, 303, 1
        CoordMode, Mouse, Screen
        Click, 1023, 692, 1
        win_ctrl_w_should_close_ths_fenxi_window := "1"
    }
    else
    {
        CoordMode, Mouse, Screen
        Click, 1120, 668, 1
        win_ctrl_w_should_close_ths_fenxi_window := "0"
    }
}

; 获取鼠标下方控件的位置数据
GetControlUnderMousePos(ByRef CtrlX:="", ByRef CtrlY:="", ByRef CtrlW:="", ByRef CtrlH:="")
{
    MouseGetPos, , , WinID, ControlClassNN
    if (ControlClassNN = "EditWnd1" || ControlClassNN = "EditWnd")
    {
        ControlGetPos, cX, cY, cW, cH, %ControlClassNN%, ahk_id %WinID%
        CtrlX := cX, CtrlY := cY, CtrlW := cW, CtrlH := cH
        return {x: cX, y: cY, width: cW, height: cH, control: ControlClassNN, winID: WinID}
    }
    return false
}

;win+空格打开同花顺股票预警结果窗口
#Space::show_ths_yujin()
show_ths_yujin()
{
    if WinExist("预警结果")
    {
        WinActivate, 预警结果
        WinSet, AlwaysOnTop, On, 预警结果
    }
}

;win+3打开模拟器
#3::open_moniqi()
open_moniqi()
{
    windowTitle := "MuMu安卓设备"
    noxPath := "D:\Program Files\Netease\MuMu\nx_main\MuMuManager.exe"

    if WinExist(windowTitle)
    {
        WinActivate, %windowTitle%
        WinMove, %windowTitle%, , 2657, ok_y-1, 786, ok_h+1
    }
    else
    {
        Run, "%noxPath%" control -v 0  launch -pkg com.aiyu.kaipanla
        WinWait, %windowTitle%, , 30
        WinActivate, %windowTitle%
        Sleep, 25000
        WinSet, AlwaysOnTop, On, %windowTitle%
        CoordMode, Mouse, Window
        ControlClick, x233 y1376, %windowTitle%, , , , NA
        Sleep, 1000
        ControlClick, x275 y134, %windowTitle%, , , , NA
        WinMove, %windowTitle%, , 2657, ok_y-1, 786, ok_h+1
    }
}

;win+1 将同花顺切换到排板页面
#1::switch_ths_to_paiban()
switch_ths_to_paiban()
{
    whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    whr.SetTimeouts(30000, 60000, 30000, 30000)
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.10", true)
    whr.Send()
    try
    {
        whr.WaitForResponse()
    }
    catch e
    {
    }
    CreateOverlays()
}

;win+2 将同花顺切换到复盘页面
#2::switch_ths_to_fupan()
switch_ths_to_fupan()
{
    whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
    whr.SetTimeouts(30000, 60000, 30000, 30000)
    whr.Open("GET", "http://192.168.1.7:7777/set_stock_code_to_ths?stock_code=.11", true)
    whr.Send()
    try
    {
        whr.WaitForResponse()
    }
    catch e
    {
    }
    DestroyOverlays()
    WinGet, Style, Style, 股票池
    if (!(Style & 0x20000000))
    {
        switchTorealnews()
    }
}

;win+^+s同花顺设置预警后确认
#^s::ths_xiadie_yujin_confirm()
ths_xiadie_yujin_confirm()
{
    If not WinExist("添加预警")
    {
        switchToTHS()
        CoordMode, Mouse, Screen
        Click, 1937, 233, Right
        Send, +t
        WinActivate, 添加预警
        WinWait, 添加预警, , 2
        if WinExist("添加预警")
        {
            CoordMode, Mouse, Window
            Click, 182, 141, 1
            return
        }
        else
        {
            ToolTip, 不存在添加预警窗口@111
            SetTimer, RemoveToolTip, -1000
        }
    }
    else
    {
        if !WinActive("添加预警")
        {
            switchToTHS()
            WinActivate, 添加预警
            WinWait, 添加预警, , 2
            if WinExist("添加预警")
            {
                CoordMode, Mouse, Window
                Click, 182, 141, 1
                return
            }
            else
            {
                ToolTip, 不存在添加预警窗口@222
                SetTimer, RemoveToolTip, -1000
            }
        }
        else
        {
            WinGetPos, WinX, WinY, WinWidth, WinHeight, 添加预警
            WinRight := WinX + WinWidth
            WinBottom := WinY + WinHeight
            CoordMode, Mouse, Screen
            MouseGetPos, MouseX, MouseY
            IsMouseInWindow := (MouseX >= WinX && MouseX <= WinRight && MouseY >= WinY && MouseY <= WinBottom)
            if !IsMouseInWindow
            {
                ToolTip, 存在添加预警窗口且窗口已激活但鼠标不在该窗口范围内
                SetTimer, RemoveToolTip, -1000
                WinActivate, 添加预警
                WinWait, 添加预警, , 2
                if WinExist("添加预警")
                {
                    CoordMode, Mouse, Window
                    Click, 182, 141, 1
                    return
                }
            }
        }
    }

    MouseMove, -15, 0, 0, R
    ctrlInfo := GetControlUnderMousePos(x, y, w, h)

    if (!ctrlInfo)
    {
        MouseMove, 0, -7, 0, R
        ctrlInfo := GetControlUnderMousePos(x, y, w, h)
        if (!ctrlInfo)
        {
            MouseMove, 0, 14, 0, R
            ctrlInfo := GetControlUnderMousePos(x, y, w, h)
        }
        if (!ctrlInfo)
        {
            return false
        }
    }

    WinActivate, 添加预警
    WinWait, 添加预警, , 2
    newX := ctrlInfo.x - 100
    targetY := ctrlInfo.y
    CoordMode, Mouse, Window
    ControlClick, x%newX% y%targetY%, 添加预警, , , , NA
    ControlClick, x173 y446, 添加预警, , , , NA
}

; ===== 智能关闭窗口 =====
SmartClose() {
    WinGet, hwnd, ID, A
    WinGet, processName, ProcessName, A
    WinGetClass, winClass, A
    WinGetTitle, currentTitle, A

    browserProcesses := ["chrome.exe", "msedge.exe", "firefox.exe", "opera.exe", "vivaldi.exe"]
    for index, browser in browserProcesses {
        if (processName = browser) {
            Send, ^w
            return
        }
    }

    if (winClass = "CabinetWClass") {
        Send, !{F4}
    }
    else if (winClass = "ApplicationFrameWindow") {
        PostMessage, 0x112, 0xF060, , , A
    }
    else if (processName = "hexin.exe" && currentTitle = "添加预警") {
        ControlClick, x450 y16, ahk_id %hwnd%, , , , NA
    }
    else if (processName = "hexin.exe" && currentTitle = "预警结果") {
        ControlClick, x659 y16, ahk_id %hwnd%, , , , NA
    }
    else {
        WinClose, ahk_id %hwnd%
        Sleep, 300
        if WinExist("ahk_id " hwnd) {
            WinKill, ahk_id %hwnd%
        }
    }
}

$^w::SmartClose()

; 获取遮挡指定窗口的所有窗口句柄
GetBlockingWindows(targetHwnd) {
    if !WinExist("ahk_id " targetHwnd)
        return ["目标窗口不存在"]

    WinGetPos, tX, tY, tW, tH, ahk_id %targetHwnd%
    WinGet, tState, MinMax, ahk_id %targetHwnd%
    if (tState = -1) || (tW = 0) || (tH = 0)
        return ["目标窗口已最小化或不可见"]

    blockingWindows := []
    WinGet, winList, List
    Loop, %winList% {
        currentHwnd := winList%A_Index%

        if (currentHwnd = targetHwnd)
            break

        if !WinExist("ahk_id " currentHwnd)
            continue

        WinGet, style, Style, ahk_id %currentHwnd%
        WinGet, exStyle, ExStyle, ahk_id %currentHwnd%
        WinGet, minMax, MinMax, ahk_id %currentHwnd%

        if (minMax = -1) || !(style & 0x10000000) || (exStyle & 0x80)
            continue

        WinGetPos, cX, cY, cW, cH, ahk_id %currentHwnd%
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

; ############## 同花顺遮罩模块 ##############
^1::CreateOverlays()
CreateOverlays() {
    DestroyOverlays()

    if (hwnd := WinExist("排板 ahk_exe stockapp.exe")) && !DllCall("IsIconic", "ptr", hwnd)
    {
        ;短版短线精灵护罩
        CreateOverlay(overlay1, 385, 995, 240, 31, 255)
    }
    else
    {
        ;长版短线精灵护罩
        CreateOverlay(overlay1, 232, 995, 393, 31, 255)
    }

    CreateOverlay(overlay2_1, 0, 8, 128, 21, 255)
    CreateOverlay(overlay2_2, 166, 8, 1598, 21, 255)
    CreateOverlay(overlay3, 233, 778, 392, 23, 255)
    CreateOverlay(overlay4, 234, 703, 390, 25, 255)
    CreateOverlay(overlay5, 567, 803, 58, 190, 255)
    CreateOverlay(overlay6, 611, 681, 13, 20, 150)
    CreateOverlay(overlay7, 459, 102, 165, 368, 90)
    ;CreateOverlay(overlay8, 233, 58, 14, 21, 255)
    ;CreateOverlay(overlay9, 460, 1053, 224, 44, 150)
    CreateOverlay(overlay10, 1793, 402, 108, 21, 225)
    CreateOverlay(overlay11, 120, 1246, 108, 18, 225)
    CreateOverlay(overlay12, 1, 508, 44, 20, 225)
    CreateOverlay(overlay13, 1814, 57, 87, 19, 250)
}

^2::DestroyOverlays()
DestroyOverlays() {
    global overlay1, overlay2_1, overlay2_2, overlay3, overlay4, overlay5, overlay6, overlay7, overlay10, overlay11, overlay12, overlay13
    if (overlay1 != 0) {
        Gui, %overlay1%:Destroy
        overlay1 := 0
    }
    if (overlay2_1 != 0) {
        Gui, %overlay2_1%:Destroy
        overlay2_1 := 0
    }
    if (overlay2_2 != 0) {
        Gui, %overlay2_2%:Destroy
        overlay2_2 := 0
    }
    if (overlay3 != 0) {
        Gui, %overlay3%:Destroy
        overlay3 := 0
    }
    if (overlay4 != 0) {
        Gui, %overlay4%:Destroy
        overlay4 := 0
    }
    if (overlay5 != 0) {
        Gui, %overlay5%:Destroy
        overlay5 := 0
    }
    if (overlay6 != 0) {
        Gui, %overlay6%:Destroy
        overlay6 := 0
    }
    if (overlay7 != 0) {
        Gui, %overlay7%:Destroy
        overlay7 := 0
    }
    if (overlay10 != 0) {
        Gui, %overlay10%:Destroy
        overlay10 := 0
    }
    if (overlay11 != 0) {
        Gui, %overlay11%:Destroy
        overlay11 := 0
    }
    if (overlay12 != 0) {
        Gui, %overlay12%:Destroy
        overlay12 := 0
    }
    if (overlay13 != 0) {
        Gui, %overlay13%:Destroy
        overlay13 := 0
    }
}

CreateOverlay(ByRef hwnd, x, y, w, h, transparency) {
    Gui, New, +HwndguiHwnd
    hwnd := guiHwnd
    Gui, Color, e8e3ce
    Gui, +ToolWindow -Caption +AlwaysOnTop +E0x20
    Gui, Show, x%x% y%y% w%w% h%h% NA
    WinSet, Transparent, %transparency%, ahk_id %guiHwnd%
}

^3::minimize_some_windows()
minimize_some_windows() {
    DestroyOverlays()
    IfWinExist, 下单
    {
        WinMinimize
    }
    IfWinExist, 排板
    {
        WinMinimize
    }
    IfWinExist, 短线精灵
    {
        WinMinimize
    }
    IfWinExist, 大单
    {
        WinMinimize
    }
    IfWinExist, 实时新闻
    {
        WinMinimize
    }
    IfWinExist, 陈小群
    {
        WinMinimize
    }
    IfWinExist, 涨停股
    {
        WinMinimize
    }
    IfWinExist, 股票池
    {
        WinMinimize
    }
}

restore_current_window()
{
    CurrentWindow := "A"
    WinGetTitle, WindowTitle, %CurrentWindow%
    if (InStr(WindowTitle, "VLC media player") > 0)
    {
        WinGet, WindowProcess, ProcessName, %CurrentWindow%
        if (WindowProcess = "vlc.exe")
        {
            SendInput, {Esc}
            Sleep, 100
        }
    }
    else
    {
        WinRestore, A
    }
}

current_window_is_fullscreen()
{
    SysGet, ScreenWidth, 0
    SysGet, ScreenHeight, 1
    WinGetPos, WinX, WinY, WinW, WinH, A
    WinGet, WinState, MinMax, A

    Tolerance := 18
    XMatch := (Abs(WinX) <= Tolerance)
    YMatch := (Abs(WinY) <= Tolerance)
    WidthMatch := (Abs(WinW - ScreenWidth) <= Tolerance)
    HeightMatch := (Abs(WinH - ScreenHeight) <= Tolerance)
    IsFullScreen := XMatch && YMatch && WidthMatch && HeightMatch && (WinState != -1)
    return IsFullScreen
}

fullscreen_current_window_forcall() {
    WinGet, WindowProcess, ProcessName, A
    if (WindowProcess = "vlc.exe")
    {
        WinActivate, A
        Sleep, 100
        SendInput, !v
        Sleep, 100
        SendInput, f
    }
    else
    {
        WinMaximize, A
    }
}

^+h::move_current_window_to_left()
move_current_window_to_left() {
    restore_current_window()
    WinMove, A, , -7, 1, 1968, 1446
}

^+l::move_current_window_to_right()
move_current_window_to_right() {
    restore_current_window()
    WinMove, A, , 2653, ok_y-1, 795, ok_h+1
}

#+f::fullscreen_current_window()
fullscreen_current_window() {
    if (current_window_is_fullscreen())
    {
        restore_current_window()
    }
    else
    {
        fullscreen_current_window_forcall()
    }
}

; ############## 模块结束 ##############

