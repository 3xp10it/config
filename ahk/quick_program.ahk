;注意，本文件要以ansi编码保存，否则与中文相关的操作会失败
;注意，全局变量只能放在文件最前面，否则会出错

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


; 全局变量存储窗口原始位置
global WindowPositionDict := Object()

;中间便看的位置
global ok_x:=776
global ok_y:=8
global ok_w:=1901
global ok_h:=1440



log_Enabled := true                     ; 日志开关 
log_FilePath := "d:\WinHistory.log"  ; 日志路径 
log_MaxSize := 10 * 1024 * 1024         ; 最大10MB 



;以下3个全局变量用于win+b的函数
global g_windowHistory := []        ; 窗口句柄历史栈（最大10条）
global g_maxHistory := 10           ; 历史记录最大长度 
Gui, +LastFound 
hWnd := WinExist()
regResult := DllCall("RegisterShellHookWindow", "UInt", hWnd)
msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
OnMessage(msgNum, "ShellMessage")
; ============================================= 
; 核心函数：处理窗口激活消息 (HSHELL_WINDOWACTIVATED)
; ============================================= 

RemoveToolTip:
    ToolTip ; 清除Tooltip
Return


;=== 新增事件触发源检测函数 === 
GetEventTriggerSource(wParam, lParam) {
    static lastInputTime := 0
    
    ; 1. 用户输入检测系统 
    if (A_TimeIdle < 500) {  ; 500ms内有用户操作
        if (A_PriorKey != "") 
            return "键盘: " A_PriorKey 
        if (A_TimeSincePriorMouse < 500)
            return "鼠标: " A_ThisHotkey
    }
    
    ; 2. 系统事件分析 
    switch wParam 
    {
        case 1:  ; HSHELL_WINDOWCREATED 
            return "系统创建"
        case 2:  ; HSHELL_WINDOWDESTROYED
            return "系统销毁"
        case 4:  ; HSHELL_RUDEAPPACTIVATED
            return WinActive("ahk_class ApplicationFrameWindow") ? "UWP应用" : "系统激活"
        case 32772: ; HSHELL_WINDOWACTIVATED
            return IsAutomatedActivation() ? "程序自动激活" : "用户切换"  ; 自定义函数 
    }
    
    ; 3. 进程间通信检测
    if (DllCall("GetWindowThreadProcessId", "UInt", lParam, "UInt*", pid)) {
        if (pid != DllCall("GetCurrentProcessId")) {
            WinGet, sourceProcess, ProcessName, ahk_pid %pid%
            return "外部进程: " (sourceProcess ? sourceProcess : "PID:" pid)
        }
    }
    
    return "未知来源"
}
 
;=== 辅助函数 ===
GetEventName(wParam) {
    eventNames := {1: "窗口创建", 2: "窗口销毁", 4: "App激活", 32772: "窗口激活"}
    return eventNames.HasKey(wParam) ? eventNames[wParam] : "未知事件"
}
 
IsAutomatedActivation() {
    ; 基于API检测是否自动化激活
    return DllCall("GetForegroundWindow") == DllCall("GetActiveWindow") ? false : true 
}





ShellMessage(wParam, lParam) {
    ; 显示所有事件并写入日志
    WinGetTitle, title, ahk_id %lParam%
    ;WinGet, processName, ProcessName, ahk_id %lParam%
    ;logMessage :=(Join "事件: wParam=" wParam " | 窗口标题=" (title ? title : "N/A") " | 进程名=" (processName ? processName : "N/A") " | 句柄=" lParam)


    ;triggerSource := GetEventTriggerSource(wParam, lParam)  ; 新增函数 
    ; 增强版日志格式 
    ;FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss.fff  
    ;logMessage := Format("{} | 事件: {}({:X}) | 触发者: {} | 窗口: {} | 进程: {} | 句柄: 0x{:X}"
    ;    , timestamp, GetEventName(wParam), wParam, triggerSource 
    ;    , (title ? StrReplace(title, "|", "∣") : "N/A")  ; 防止分隔符冲突 
    ;    , (processName ? processName : "N/A")
    ;    , lParam)
    ;WriteToLog(logMessage)
    ;WinGetTitle, current_title, A
    ;WriteToLog(current_title)


    if (wParam != 32772 || lParam==0) ;HSHELL_RUDEAPPACTIVATED (值=0x8004，也即32772)
        return 
    ; 排除无效窗口（桌面/任务栏/自身窗口）
    WinGetTitle, title, ahk_id %lParam%
    if (title = "" || title = "Program Manager" || InStr(title, "AutoHotkey"))
        return 
    ; 更新历史记录（排除重复激活）
    if (g_windowHistory[1] != lParam) {
        g_windowHistory.InsertAt(1, lParam) ; 插入到栈顶     
        ;WriteToLog(lParam)
        ; 保持历史记录不超过上限 
        if (g_windowHistory.Length() > g_maxHistory)
            ;pop是删除栈底元素
            g_windowHistory.Pop()
    }



    if (InStr(title,"同花顺(")==0)
    {
        ;同花顺的主窗口不置顶，要不然会挡住stockapp的置顶窗口，其他窗口打开的时候都置顶
        WinSet, TopMost, On,ahk_id %lParam%
    }



}



 
; ============================================= 
; 日志写入函数 
; ============================================= 
WriteToLog(message) {
    global log_Enabled, log_FilePath, log_MaxSize 
    
    if !log_Enabled 
        return 
    
    ; 自动创建日志文件 
    if !FileExist(log_FilePath)
        FileAppend,, %log_FilePath%, UTF-8 
    
    ; 检查文件大小 
    FileGetSize, fileSize, %log_FilePath%
    if (fileSize > log_MaxSize) {
        FileDelete, %log_FilePath%.old 
        FileMove, %log_FilePath%, %log_FilePath%.old 
    }
    
    ; 构建日志内容 
    FormatTime, timestamp,, yyyy-MM-dd HH:mm:ss.fff  
    fullMessage := "[" timestamp "] " message "`n"
    
    ; 写入文件 
    FileAppend, %fullMessage%, %log_FilePath%, UTF-8 
}




ProcessExist(exe){          ;一个自定义函数,根据自定义函数的返回值作为#if成立依据原GetPID
    Process, Exist,% exe
    return ErrorLevel
}




#g::switchToChrome()
switchToChrome()
{
SetTitleMatchMode RegEx
if WinExist("guba_jiucai.*")
{
    ;顺便把guba_jiucai窗口最小化
    WinMinimize
}

SetTitleMatchMode, 2
IfWinExist, ahk_exe chrome.exe
{
    WinRestore
    chromeTitle := " - Google Chrome"
    WinMove,%chromeTitle%,,2662,ok_y-1,786,ok_h+1
    WinGet, chrome_hwnd, ID, %chromeTitle%  ; 获取窗口句柄
    WinActivate,ahk_id %chrome_hwnd%
    WinSet, AlwaysOnTop, On, ahk_id %chrome_hwnd%  ; 置顶 
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
    ;顺便把guba_jiucai窗口最小化
    WinMinimize
}

SetTitleMatchMode, 2
IfWinExist, ahk_exe chrome.exe
{
    WinRestore
    chromeTitle := " - Google Chrome"
    WinMove,%chromeTitle%,,ok_x,ok_y,ok_w,ok_h
    WinGet, chrome_hwnd, ID, % chromeTitle  ; 获取窗口句柄 
    WinActivate,ahk_id %chrome_hwnd%
    WinSet, AlwaysOnTop, On, ahk_id %chrome_hwnd%  ; 置顶 
    
}
else
{
    Run, chrome.exe
}

}








 
;win+w 打开微信
#w::switchToWechat()
switchToWechat()
{

;WeChat:="ahk_class Qt51514QWindowIcon"
;WeChat:="ahk_exe Weixin.exe"
WeChat:="微信"
WeChat_path:="D:\Program Files\Tencent\Weixin\Weixin.exe"
if ProcessExist("Weixin.exe")=0
    Run, %WeChat_path%
else
{
if WinExist("ahk_class Qt51514QWindowIcon")
{
WinGet, Style, Style, ahk_class Qt51514QWindowIcon
if ((Style & 0x20000000) or (not WinActive(ahk_class Qt51514QWindowIcon)))    ;最小化了或被挡住了
{
    WinActivate
    WinMove,ahk_class Qt51514QWindowIcon,,ok_x+8,ok_y,ok_w-16,ok_h
    WinSet, TopMost, On, ahk_class Qt51514QWindowIcon
}
else
{
    WinMinimize
}
}
}
}


;win+b打开上一个激活的窗口
#b::switch_to_last_active_window()
switch_to_last_active_window()
{
    
    ; 检查历史记录有效性 
    if (g_windowHistory.Length() < 2) {
        ;MsgBox, 没有可用的历史窗口记录 
        return 
    }
    
    targetHwnd := g_windowHistory[2] ; 获取上一个窗口（栈顶是当前窗口）
    
    ; 检查窗口是否存在 
    if !WinExist("ahk_id " targetHwnd) {
        MsgBox, 目标窗口已关闭 
        g_windowHistory.RemoveAt(2) ; 清理无效记录 
        return 
    }
    
    ; 恢复最小化窗口并激活 
    WinGet, minMax, MinMax, ahk_id %targetHwnd%
    if (minMax = -1) 
        WinRestore, ahk_id %targetHwnd%
    WinActivate, ahk_id %targetHwnd%
    WinGetTitle, title, ahk_id %targetHwnd%
    if (InStr(title,"同花顺(")==0)
    {
        ;同花顺的主窗口不置顶，要不然会挡住stockapp的置顶窗口
        WinSet, TopMost, On,ahk_id %targetHwnd%
    }

}



;win+ctrl+b 打开ryij.txt
#^b::switchToryij()
switchToryij()
{
global cmds_should_show_realnews
ryij_path:="\\192.168.0.6\news\ryij.txt"
if WinExist("ryij.txt - 记事本")
{
    ;MsgBox,"exist ryij.txt - 记事本"
    targetWindowTitle := "ryij.txt - 记事本"
    WinActivate
    WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
    WinSet, TopMost, On, %targetWindowTitle%
}
else if WinExist("ryij - 记事本")
{
    ;MsgBox,"exist ryij - 记事本"
    targetWindowTitle := "ryij - 记事本"
    WinActivate
    WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
    WinSet, TopMost, On, %targetWindowTitle%
}
else if WinExist("*ryij.txt - 记事本") {
    ;MsgBox,"exist *ryij.txt - 记事本"
    targetWindowTitle := "*ryij.txt - 记事本"
    WinActivate
    WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
    WinSet, TopMost, On, %targetWindowTitle%
}
else if WinExist("*ryij - 记事本") {
    ;MsgBox,"exist *ryij - 记事本"
    targetWindowTitle := "*ryij - 记事本"
    WinActivate
    WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
    WinSet, TopMost, On, %targetWindowTitle%
}
else {
    ;MsgBox,"no ryij.txt - 记事本 and no *ryij.txt - 记事本" and no ryij - 记事本 and no *ryij - 记事本"
    Run, %ryij_path%
    SetTitleMatchMode, RegEx
    WinWait,ryij.*记事本, , 2
    if WinExist("ryij.txt - 记事本") {
    targetWindowTitle := "ryij.txt - 记事本"
    }
    else if WinExist("ryij - 记事本") {
    targetWindowTitle := "ryij - 记事本"
    }

    WinMove, %targetWindowTitle%, , 2653, 0, 796, 478
    WinSet, TopMost, On, %targetWindowTitle%
}
cmds_should_show_realnews:="1"

}

DetectHiddenText On

;win+f 打开同花顺
#f::switchToTHS()


switchToTHS()
{
THS_path:="D:\THS\hexin.exe"
;注意：SetTitleMatchMode一定要放在WinExist前面一行，放远了可能不会生效；这里也可以通过使用WinExist("ahk_exe D:\THS\hexin.exe")来获取同花顺的窗口，但这样可能会获取到短线精灵，除了同花顺主界面属于hexin.exe外，弹窗式的短线精灵也属于hexin.exe，所以实际不能使用ahk_exe来获取，只能用窗口特征来获取，还需要注意的是，ahk代码中不支持中文，所以用中文字符串来匹配是无法成功的
SetTitleMatchMode RegEx
if WinExist(thsWindowTitle)
{
WinActivate
;注意，同花顺最大的高度只有1446，设置再大也不会有效，y从1到1446则可保证底部铺满(顶部铺不满)，如果y从0到1446则顶部和底部都铺不满
WinMove, %thsWindowTitle%, , -7, 1, 1968, 1446
CreateOverlays()
}
else
{
Run, %THS_path%
}


; 将遮住同花顺同花顺的窗口最小化
WinGet, ths_hwnd, ID, %thsWindowTitle%
blockers := GetBlockingWindows(ths_hwnd)
if (blockers.Length() > 0) {
    result := "遮挡窗口列表（按Z序从高到低）:`n`n"
    for i, hwnd in blockers {
        WinGetTitle, title, ahk_id %hwnd%
        if (not InStr(title, "短线精灵") && not InStr(title, "股票池") && not InStr(title, "涨停股") && not InStr(title, "实时新闻") && not InStr(title, "大单") && not InStr(title, "排板") && not InStr(inputStr, "个股新闻") && not InStr(title, "概念") && not InStr(title, "下单") && not InStr(title, "风向标") && not InStr(title, "个股新闻") && title!="quick_program.ahk")
        {
                ;result .= "[" i "] 句柄: " Format("0x{:X}", hwnd)
                ;.  "`n标题: " (title ? title : "(无标题)")
                ;.  "`n----------------------`n"
                WinMinimize,ahk_id %hwnd%
        }
    }
    ; 输出结果
    ;MsgBox, % result 
}


;把实时新闻移到原来的位置
SetTitleMatchMode, 2
WinGet,hwnd,ID,实时新闻
if (hwnd)
{
    WinGet, Style, Style, ahk_id %hwnd%
    if (!(Style & 0x20000000))    ;没有最小化才移动窗口
    {
        WinMove, ahk_id %hwnd%, , 784, 466, 1033, 499
    }
    
}

}

;win+ctrl+f打开tide.py
#^f::tide()
tide()
{

dir := "Z:\"
script  = %dir%\tide.py
SetWorkingDir %dir%
Run, %ComSpec% /k python "%script%" && exit
}



;win+a 打开znz
#a::switchToZNZ()
switchToZNZ()
{
znz:="ahk_exe WavMain.exe"
znz_path:="D:\Compass\WavMain\WavMain.exe"

SetTitleMatchMode RegEx

if ProcessExist("WavMain.exe")=0
    Run, %znz_path%
else
{
    SetTitleMatchMode RegEx
    WinGet, znz_hwnd, ID, 指南针全赢决策系统
    WinActivate,ahk_id %znz_hwnd%
    WinSet, TopMost, On, ahk_id %znz_hwnd%
}
}



;win+c 打开tl50
#c::switchToTL50()
switchToTL50()
{

tl50:="ahk_exe tl50v2.exe"
tl50_path:="D:\Program Files\天狼50\天狼50证券分析系统\tl50v2.exe"

SetTitleMatchMode RegEx

if ProcessExist("tl50v2.exe")=0
    Run, %tl50_path%
else
{
    SetTitleMatchMode RegEx
    if WinExist(".*天狼50.*")
    {
    WinActivate
    WinSet, TopMost, On, .*天狼50.*
    }
}


}

;win+s 打开实时新闻
#s::switchTorealnews()
switchTorealnews()
{
SetTitleMatchMode, 2
if WinExist("实时新闻")
{
global cmds_should_show_realnews
;MsgBox,%cmds_should_show_realnews%

WinGet,hwnd,ID,实时新闻
WinGet, Style, Style, ahk_id %hwnd%
if (Style & 0x20000000)    ;最小化了时，可能是人为手动点窗口上的最小化导致也可能是按win+s导致最小化
{
cmds_should_show_realnews:="1"
}

if (cmds_should_show_realnews=="0")
{
WinMinimize
;将涨停股和股票池最小化
WinMinimize,涨停股
WinMinimize,股票池

;将大单窗口移动到短线精灵左边
SetTitleMatchMode RegEx
if WinExist("大单.*")
{
    targetWindowTitle := "大单.*"
    WinMove, %targetWindowTitle%, , 231, 801, 154, 638
    WinGet, targetWindowID, ID, 大单.*
    WinSet, AlwaysOnTop, On, ahk_id %targetWindowID%
    if WinExist("排板")
    {
        ;注意，ths的主窗口title包含“排板”,orderlist的title是“排板”，这里要改为精确匹配否则有时候会将ths置顶
        SetTitleMatchMode, 1
        WinGet, orderlistWindowID, ID, 排板
        WinSet, AlwaysOnTop, Off, ahk_id %orderlistWindowID%
    }

}
cmds_should_show_realnews:="1"
}
else if (cmds_should_show_realnews=="1")
{
    ;打开实时新闻窗口
    WinRestore

    ;打开涨停股和股票池
    WinRestore,涨停股
    WinRestore,股票池

    ;恢复大单窗口原来的位置
    SetTitleMatchMode RegEx
    if WinExist("大单.*")
    {
        ;打开大单窗口        
        WinRestore        
        targetWindowTitle := "大单.*"
        WinMove, %targetWindowTitle%, , 626, 466, 158, 499
        if WinExist("排板")
        {
            ;注意，ths的主窗口title包含“排板”,orderlist的title是“排板”，这里要改为精确匹配否则有时候会将ths置顶
            SetTitleMatchMode, 1
            WinGet, orderlistWindowID, ID, 排板
            WinSet, AlwaysOnTop, On, ahk_id %orderlistWindowID%
        }

    }
    cmds_should_show_realnews:="0"
}
}
else
{
;MsgBox,"realnews window is closed or not open"
whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
whr.SetTimeouts(30000,60000,30000,30000)
whr.Open("GET", "http://192.168.1.7:3333/show_realtime_news_window", true)
whr.Send()
try
{
whr.WaitForResponse()
;MsgBox % whr.ResponseText
}
catch e
{
;MsgBox,"http request error"
}

}
}


;win+ctrl+t只把实时新闻移到右上角
#^t::moveRealnews()
moveRealnews()
{
;把实时新闻移到右上角
SetTitleMatchMode, 2
WinGet,hwnd,ID,实时新闻
if (hwnd)
{
    WinGet, Style, Style, ahk_id %hwnd%
    if (!(Style & 0x20000000))    ;没有最小化才移动窗口
    {
        ;将chrome取消置顶，否则点一下实时新闻就会和chrome的置顶状态冲突
        chromeTitle := " - Google Chrome"  ; Chrome 窗口标题特征 
        SetTitleMatchMode, 2  ; 设置标题匹配模式为"包含"
        ;检测窗口是否存在 
        if WinExist(chromeTitle) {
            WinGet, hwnd, ID, %chromeTitle%
            WinSet, AlwaysOnTop, Off, ahk_id %hwnd%  ; 取消置顶 
        } 

 
        realnewsTitle := "实时新闻"
        WinMove,%realnewsTitle%, , 2669, ok_y-1, 780, ok_h-2
        WinGet, realnews_hwnd, ID, %realnewsTitle%  ; 获取窗口句柄
        WinSet, AlwaysOnTop, Off, ahk_id %realnews_hwnd%  ; 置顶 
        WinActivate,实时新闻
        WinSet, AlwaysOnTop, On, ahk_id %realnews_hwnd%  ; 置顶 

    }
    
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
    WinSet, TopMost, On, guba_jiucai.*
}
;SetTitleMatchMode, 2

}


;win+x打开同花顺网上股票交易系统
#x::switchToXIADAN()
switchToXIADAN()
{
SetTitleMatchMode, 2
WinGet,xiadan_hwnd,ID,网上股票交易系统5.0
if (xiadan_hwnd)
{
    WinGet, Style, Style, ahk_id %xiadan_hwnd%
    if ((Style & 0x20000000) or (not WinActive("ahk_id " xiadan_hwnd)))    ;最小化了或被挡住了
    {
        Tooltip,最小化或没有激活
        SetTimer, RemoveToolTip, -2500 ; 
        WinActivate,ahk_id %xiadan_hwnd%
        WinMove,ahk_id %xiadan_hwnd%,,ok_x,ok_y,ok_w,ok_h
        WinSet, TopMost, On, ahk_id %xiadan_hwnd%
    }
    else
    {
       Tooltip,已置顶且激活
        SetTimer, RemoveToolTip, -2500 ; 
        WinMinimize,ahk_id %xiadan_hwnd%
    }
}
}

;win+z将当前激活的窗口最小化
#z::minimize_current_window()
minimize_current_window()
{
    WinMinimize,A
}

;win+q将当前激活的窗口置顶
#q::set_current_window_to_top()
set_current_window_to_top()
{
    global WindowPositionDict
    ; 获取当前窗口信息 
    WinGet, hwnd, ID, A
    WinGetTitle, title, ahk_id %hwnd%
    if (InStr(title, "同花顺(") == 1) {
        ;同花顺的主窗口不置顶，要不然会挡住stockapp的置顶窗口
        return
    }
    ; 检查是否已在固定位置 
    WinGetPos, curX, curY, curW, curH, ahk_id %hwnd%
    isAtFixedPos := (curX == ok_x && curY == ok_y && curW == ok_w && curH == ok_h)
    WinGet, ExStyle, ExStyle, A 
    if (isAtFixedPos && (ExStyle & 0x8)) {
        ; 如果已经在目标位置且已经置顶，则还原到原始位置
        if (WindowPositionDict.HasKey(hwnd)) {
            orig := WindowPositionDict[hwnd]
            WinMove, ahk_id %hwnd%,, orig.x, orig.y, orig.w, orig.h
            WindowPositionDict.Delete(hwnd)
        }
    }
    else
    {
        ; 保存当前位置并固定 
        
        WinGetPos, origX, origY, origW, origH, ahk_id %hwnd%
        WindowPositionDict[hwnd] := {x: origX, y: origY, w: origW, h: origH}
        ;ToolTip,保存当前位置并固定
        WinRestore,ahk_id %hwnd%
        WinMove,A,,ok_x,ok_y,ok_w,ok_h
        WinSet, TopMost, On, A
    }

}

;win+^+w打开同花顺的分析功能
#^w::ths_fenxi()
ths_fenxi()
{
global win_ctrl_w_should_close_ths_fenxi_window
if (win_ctrl_w_should_close_ths_fenxi_window=="0")
{
    WinActivate,同花顺(
    CoordMode, Mouse, Window     ; 使用窗口坐标
    Click, 151, 14, 1             ; 也即单击分析
    Click, 197, 303, 1             ; 在窗口内(129,28)处双击，也即单击历史回忆
    CoordMode, Mouse, Screen      ; 使用屏幕坐标
    Click, 1023,692,1;点击弹出的新窗口的按钮@播放到最后
    win_ctrl_w_should_close_ths_fenxi_window:="1"
}
else
{
    ;应该关闭分析窗口
    CoordMode, Mouse, Screen      ; 使用屏幕坐标
    Click, 1120,668,1;点击分析窗口的关闭按钮
    win_ctrl_w_should_close_ths_fenxi_window:="0"
}
}


; 获取鼠标下方控件的位置数据 
GetControlUnderMousePos(ByRef CtrlX:="", ByRef CtrlY:="", ByRef CtrlW:="", ByRef CtrlH:="") {
    ; 获取鼠标位置下的控件信息
    MouseGetPos, , , WinID, ControlClassNN
    ; 验证是否获取到有效控件 
    ;MsgBox,%ControlClassNN%
    if (ControlClassNN="EditWnd1" || ControlClassNN="EditWnd")
    {
    ; 获取控件位置和尺寸
    ControlGetPos, cX, cY, cW, cH, %ControlClassNN%, ahk_id %WinID%
    ; 返回结果（通过引用参数和返回对象双模式）
    CtrlX := cX, CtrlY := cY, CtrlW := cW, CtrlH := cH
    return { x: cX, y: cY, width: cW, height: cH 
           , control: ControlClassNN, winID: WinID }
    }
    return false
}

;win+^+s同花顺设置预警后确认
#^s::ths_xiadie_yujin_confirm()
ths_xiadie_yujin_confirm()
{
    If not WinExist("添加预警") 
    {
        ;没有添加预警窗口
        switchToTHS()
        CoordMode, Mouse, Screen      ; 使用屏幕坐标
        Click,741,180,Right
        Send, +t
        ;MouseMove,121,175,10,Relative    ;用1的时间移动过去
        ;Click
        WinActivate,添加预警
        if WinExist("添加预警")    
        {
            CoordMode, Mouse, Window     ; 使用窗口坐标
            Click, 182,141,1   ;点击股票下跌到编辑框
            return
        }
        else
        {
            ToolTip,不存在添加预警窗口
            SetTimer, RemoveToolTip, -1000 ; 
        }
    }
    else
    {
        if !WinActive("添加预警")
        {
            ;说明存在添加预警窗口但窗口却没有激活
            switchToTHS()
            WinActivate,添加预警
            if WinExist("添加预警")    
            {
                CoordMode, Mouse, Window     ; 使用窗口坐标
                Click, 182,141,1   ;点击股票下跌到编辑框
                return
            }
            else
            {
                ToolTip,不存在添加预警窗口
                SetTimer, RemoveToolTip, -1000 ; 
            }
        }
        else
        {
            ;说明存在添加预警窗口且窗口已经激活，现在要判断鼠标是不是在该窗口范围内，如果不在则移动到默认位置
            ;  获取窗口的位置和大小（左上角坐标、宽度、高度）
            WinGetPos, WinX, WinY, WinWidth, WinHeight, 添加预警
            ; 计算窗口右下角坐标（用于判断范围）
            WinRight := WinX + WinWidth
            WinBottom := WinY + WinHeight
            ;  获取当前鼠标坐标
            CoordMode, Mouse, Screen     ; 使用屏幕坐标
            MouseGetPos, MouseX, MouseY
           ;  判断鼠标是否在窗口范围内
           ; 鼠标在窗口内的条件：X在[WinX, WinRight]且Y在[WinY, WinBottom]
           IsMouseInWindow := (MouseX >= WinX && MouseX <= WinRight && MouseY >= WinY && MouseY <= WinBottom)
           if !IsMouseInWindow
           {
               ;说明存在添加预警窗口且窗口已激活但鼠标不在该窗口范围内
               ToolTip,存在添加预警窗口且窗口已激活但鼠标不在该窗口范围内
               SetTimer, RemoveToolTip, -1000 ; 
               WinActivate,添加预警
               if WinExist("添加预警")    
               {
                   CoordMode, Mouse, Window     ; 使用窗口坐标
                   Click, 182,141,1   ;点击股票下跌到编辑框
                   return
               }

           }
     
        }
    }


    ;先将鼠标向左边移动15px，防止有时候鼠标太靠右了而不在控件上
    MouseMove, -15, 0, 0, R  ; R表示相对移动
    ;Click
    ctrlInfo := GetControlUnderMousePos(x, y, w, h)

    if (!ctrlInfo)
    {
        ;ToolTip,鼠标下面没有控件，现在向上移动7px
        MouseMove, 0, -7, 0, R  ; R表示相对移动，向上移动7px
        ;Click
        ctrlInfo := GetControlUnderMousePos(x, y, w, h)
        if (!ctrlInfo)
        {
             ;ToolTip,向上移动7px没有找到控件，现在向下移动7px
             MouseMove, 0, 14, 0, R  ; R表示相对移动，向下移动14px
             ;Click
             ctrlInfo := GetControlUnderMousePos(x, y, w, h)
        }
        if (!ctrlInfo) 
        {
            ;ToolTip,向下移动5px后鼠标最终还是没有移动到控件位置
            return false
        }

    }
    ;ToolTip,找到鼠标下面的编辑框控件
    ;SetTimer, RemoveToolTip, -2500 ; 
    WinActivate,添加预警
    newX:=ctrlInfo.x-100
    targetY:=ctrlInfo.y
    CoordMode, Mouse, Window     ; 使用窗口坐标
    Click, %newX%,%targetY%,1     ; 点击打勾
    Click, 173,446,1;点击确定
}




SmartClose() {
    ; 获取当前窗口信息 
    WinGet, hwnd, ID, A 
    WinGet, processName, ProcessName, A
    WinGetClass, winClass, A
    
    ; 浏览器标签页关闭逻辑
    browserProcesses := ["chrome.exe",  "msedge.exe",  "firefox.exe",  "opera.exe",  "vivaldi.exe"] 
    for index, browser in browserProcesses {
        if (processName = browser) {
            Send, ^w  ; 发送 Ctrl+W 关闭标签页 
            return
        }
    }
    
    ; 特殊窗口处理
    if (winClass = "CabinetWClass") {  ; 资源管理器 
        Send, !{F4}  ; Alt+F4 关闭窗口但不终止进程
    } 
    else if (winClass = "ApplicationFrameWindow") {  ; UWP应用 
        PostMessage, 0x112, 0xF060,,, A  ; 发送关闭消息
    } 
    else {
        ; 标准关闭流程
        WinClose, ahk_id %hwnd%
        Sleep, 300 
        if WinExist("ahk_id " hwnd) {
            WinKill, ahk_id %hwnd%  ; 强制关闭残留窗口
        }
    }
}
 
; ===== 热键绑定 ===== 
$^w::SmartClose()  ; 使用 $ 前缀防止热键自触发


; 获取遮挡指定窗口的所有窗口句柄 
GetBlockingWindows(targetHwnd) {
    ; 检查目标窗口有效性 
    if !WinExist("ahk_id " targetHwnd)
        return ["目标窗口不存在"]
    
    ; 获取目标窗口位置和状态 
    WinGetPos, tX, tY, tW, tH, ahk_id %targetHwnd%
    WinGet, tState, MinMax, ahk_id %targetHwnd%
    if (tState = -1) || (tW = 0) || (tH = 0)
        return ["目标窗口已最小化或不可见"]
    
    ; 初始化结果数组 
    blockingWindows := []
    
    ; 获取所有窗口列表（按Z序从顶到底）
    WinGet, winList, List
    Loop, %winList% {
        currentHwnd := winList%A_Index%
        
        ; 跳过目标窗口自身及后续窗口 
        if (currentHwnd = targetHwnd)
            break 
        
        ; 跳过无效窗口
        if !WinExist("ahk_id " currentHwnd)
            continue 
        
        ; 检查窗口状态
        WinGet, style, Style, ahk_id %currentHwnd%
        WinGet, exStyle, ExStyle, ahk_id %currentHwnd%
        WinGet, minMax, MinMax, ahk_id %currentHwnd%
        
        ; 过滤无效窗口条件 
        ;if (minMax = -1) || !(style & 0x10000000)  ; WS_VISIBLE 
         ;   || (exStyle & 0x80) || (exStyle & 0x00000008)  ; WS_EX_TOOLWINDOW/WS_EX_TOPMOST 
          ;  continue
        if (minMax = -1) || !(style & 0x10000000)  ; WS_VISIBLE 
             || (exStyle & 0x80)  ; WS_EX_TOOLWINDOW
            continue

        
        ; 获取当前窗口位置
        WinGetPos, cX, cY, cW, cH, ahk_id %currentHwnd%
        if (cW = 0) || (cH = 0)
            continue 
        
        ; 计算窗口重叠区域 
        left   := Max(tX, cX)
        right  := Min(tX + tW, cX + cW)
        top    := Max(tY, cY)
        bottom := Min(tY + tH, cY + cH)
        
        ; 检测有效遮挡（重叠面积 > 100像素）
        if (left < right) && (top < bottom) {
            overlapArea := (right - left) * (bottom - top)
            if (overlapArea > 100)  ; 过滤微小重叠 
                blockingWindows.Push(currentHwnd)
        }
    }
    
    return blockingWindows 
}
 





; ############## 同花顺遮罩模块 ##############
; 两个全局变量要放在文件最前面，否则会出错

; 创建遮罩热键（可自定义组合键）
#1::CreateOverlays() ; win+1 创建遮罩


CreateOverlays() {
    DestroyOverlays()
    CreateOverlay(overlay1, 383, 995, 242, 31, 255)  ; 短线精灵标题栏
    CreateOverlay(overlay2_1, 0, 8, 128, 21, 255)    ; 顶部长白条@left
    CreateOverlay(overlay2_2, 166, 8, 1598, 21, 255)    ; 顶部长白条@right
    CreateOverlay(overlay3, 233, 778, 392, 23, 255)    ; "上翻 下翻 顶部 底部"
    CreateOverlay(overlay4, 234, 703, 390, 25, 255)    ; "查看完整报价"
    CreateOverlay(overlay5, 567, 803, 58, 190, 255)    ; "千档盘口红绿点"
    CreateOverlay(overlay6, 611, 681, 13, 20, 150)    ; "预警铃铛"
    CreateOverlay(overlay7, 459, 102, 165, 368, 90)    ; "逐笔成交明细买单卖单"
    CreateOverlay(overlay8, 233, 58, 14, 21, 255)    ;"逐笔成交明细左边的白框"
    ;CreateOverlay(overlay9, 460, 1053, 224, 44, 150)    ;"委买队列"
    CreateOverlay(overlay10, 1793, 404, 108, 20, 225)    ; "成交量下拉框背景"
    CreateOverlay(overlay11, 120, 1246, 108,18, 225)    ; "涨速排名下拉框背景"
    CreateOverlay(overlay12, 1, 508, 44, 20, 225)    ; "自选股表单设置背景"
}

#2::DestroyOverlays()  ; win+2 移除遮罩

CreateOverlay(ByRef hwnd, x, y, w, h, transparency) {
  Gui, New, +HwndguiHwnd
  hwnd := guiHwnd
  Gui, Color, cce8cf
  Gui, +ToolWindow -Caption +AlwaysOnTop +E0x20  ; +E0x20允许鼠标穿透
  Gui, Show, x%x% y%y% w%w% h%h% NA
  WinSet, Transparent, %transparency%, ahk_id %guiHwnd%
}

DestroyOverlays() {
  global overlay1, overlay2, overlay3
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
  if (overlay8 != 0) {
    Gui, %overlay8%:Destroy
    overlay8 := 0
  }
  ;if (overlay9 != 0) {
    ;Gui, %overlay9%:Destroy
    ;overlay9 := 0
  ;}
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
}
; ############## 模块结束 ##############
