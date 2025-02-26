;注意，本文件要以ansi编码保存，否则与中文相关的操作会失败
;注意，全局变量只能放在文件最前面，否则会出错

cmds_should_show_realnews:="0"

global overlay1 := 0  ; 标题栏遮罩句柄
global overlay2 := 0  ; 顶部白条遮罩句柄
global overlay3 := 0  ; "上翻 下翻 顶部 底部"
global overlay4 := 0  ; "查看完整报价"
global overlay5 := 0  ; "千档盘口红绿点"
global overlay6 := 0  ; "预警铃铛"
global overlay7 := 0  ; "逐笔成交明细买单卖单"
global overlay8 := 0  ; "逐笔成交明细时间序列"
global overlay9 := 0  ; "委买队列"
global overlay10 := 0  ; "成交量下拉框背景"
global overlay11 := 0  ; "涨速排名下拉框背景"
global overlay12 := 0  ; "自选股表单设置背景"





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
    WinActivate
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

;WeChat:="ahk_class WeChatMainWndForPC"
;WeChat:="ahk_exe WeChat.exe"
WeChat:="微信"
WeChat_path:="D:\Program Files\Tencent\WeChat\WeChat.exe"
if ProcessExist("WeChat.exe")=0
    Run, %WeChat_path%
else
{
if WinExist("ahk_class WeChatLoginWndForPC") or WinExist("ahk_class WeChatMainWndForPC")
{

if WinExist("ahk_class WeChatMainWndForPC")
{
if not WinActive(ahk_class WeChatMainWndForPC)      ;被挡住或最小化了
{
    WinShow
    WinActivate
}
else
{
    WinMinimize
}
}

else
{
if WinExist("ahk_class WeChatLoginWndForPC")
{
if not WinActive(ahk_class WeChatLoginWndForPC)      ;被挡住或最小化了
{
    WinShow
    WinActivate
}
else
{
    WinMinimize
}
}
}

}
}
}


;win+b 打开ryij.txt
#b::switchToryij()
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
if WinExist(".*9\.30\.72.*")
{
WinActivate
}
else
{
Run, %THS_path%
}
if WinExist("guba_jiucai.*")
{
    ;顺便把guba_jiucai窗口最小化
    WinMinimize
}

;把实时新闻移到原来的位置
SetTitleMatchMode, 2
WinGet,hwnd,ID,实时新闻
if (hwnd)
{
    WinGet, Style, Style, ahk_id %hwnd%
    if (!(Style & 0x20000000))    ;没有最小化才移动窗口
    {
        WinMove, ahk_id %hwnd%, , 685, 514, 1232, 601
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
    if WinExist(".*0AMV.*")
    {
    WinActivate
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
cmds_should_show_realnews:="1"
}
else if (cmds_should_show_realnews=="1")
{
    WinActivate
    WinSet, TopMost, On, %targetWindowTitle%
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
        WinMove, ahk_id %hwnd%, , 2665, 0, 784, 452
        WinActivate
        WinSet, TopMost, On, ahk_id %hwnd%
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




; ############## 同花顺遮罩模块 ##############
; 两个全局变量要放在文件最前面，否则会出错

; 创建遮罩热键（可自定义组合键）
#1::  ; win+1 创建遮罩
  DestroyOverlays()
  CreateOverlay(overlay1, 224, 967, 462, 33, 255)  ; 短线精灵标题栏
  CreateOverlay(overlay2, 0, 0, 1766, 21, 255)    ; 顶部长白条
  CreateOverlay(overlay3, 224, 761, 462, 28, 255)    ; "上翻 下翻 顶部 底部"
  CreateOverlay(overlay4, 224, 689, 462, 25, 255)    ; "查看完整报价"
  CreateOverlay(overlay5, 615, 789, 71, 178, 255)    ; "千档盘口红绿点"
  CreateOverlay(overlay6, 667, 667, 18, 20, 150)    ; "预警铃铛"
  CreateOverlay(overlay7, 490, 90, 195, 402, 90)    ; "逐笔成交明细买单卖单"
  CreateOverlay(overlay8, 225, 90, 147, 205, 150)    ;"逐笔成交明细时间序列"
  CreateOverlay(overlay9, 460, 1053, 224, 44, 150)    ;"委买队列"
  CreateOverlay(overlay10, 1757, 443, 107, 20, 225)    ; "成交量下拉框背景"
  CreateOverlay(overlay11, 112, 1201, 107, 18, 225)    ; "涨速排名下拉框背景"
  CreateOverlay(overlay12, 1, 490, 44, 20, 225)    ; "自选股表单设置背景"
return

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
  if (overlay2 != 0) {
    Gui, %overlay2%:Destroy
    overlay2 := 0
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
  if (overlay9 != 0) {
    Gui, %overlay9%:Destroy
    overlay9 := 0
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
}
; ############## 模块结束 ##############
