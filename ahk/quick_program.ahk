;注意，本文件要以ansi编码保存，否则与中文相关的操作会失败

cmds_should_show_realnews:="0"



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
    WinShow
    WinActivate
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
if WinExist(".*v9\.20\.72.*")
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
        WinMove, ahk_id %hwnd%, , 678, 513, 1247, 610
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



;win+z 打开znz
#z::switchToZNZ()
switchToZNZ()
{
znz:="ahk_exe WavMain.exe"
znz_path:="D:\Compass\WavMain\WavMain.exe"

SetTitleMatchMode RegEx

if ProcessExist("WavMain.exe")=0
    Run, %znz_path%
else
{
    winshow,%znz%
    winactivate,%znz%
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
whr.Open("GET", "http://192.168.0.7:3333/show_realtime_news_window", true)
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

 ;win+t打开东方财富股吧和韭菜公社
#t::switchToGBJC()

switchToGBJC()
{

;把实时新闻移到右上角
SetTitleMatchMode, 2
WinGet,hwnd,ID,实时新闻
if (hwnd)
{
    WinGet, Style, Style, ahk_id %hwnd%
    if (!(Style & 0x20000000))    ;没有最小化才移动窗口
    {
        WinMove, ahk_id %hwnd%, , 2653, 0, 796, 478
        WinActivate
        WinSet, TopMost, On, ahk_id %hwnd%
    }
    
}


SetTitleMatchMode RegEx
if WinExist("guba_jiucai.*")
{
    WinActivate
    WinSet, TopMost, On, guba_jiucai.*
}
;SetTitleMatchMode, 2

}
