;注意，本文件要以ansi编码保存，否则与中文相关的操作会失败

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

WeChat:="ahk_class WeChatMainWndForPC"
WeChat_path:="D:\Program Files\Tencent\WeChat\WeChat.exe"
if ProcessExist("WeChat.exe")=0
    Run, %WeChat_path%
else
{
    winshow,%WeChat%
    winactivate,%WeChat%
}
}


;win+b 打开tyij.txt
#b::switchTotyij()
switchTotyij()
{
tyij_path:="\\192.168.0.6\news\tyij.txt"
targetWindowTitle := "tyij.txt - 记事本"
if WinExist("tyij.txt - 记事本")
    WinActivate
else
    Run, %tyij_path%
    WinWait, %targetWindowTitle%, , 5

;把tyij.txt移到右上角
if WinExist("tyij.txt - 记事本")
    WinGet,hwnd,ID,%targetWindowTitle%
    WinMove, ahk_id %hwnd%, , 2653, 0, 796, 478
    WinSet, TopMost, Off, ahk_id %hwnd%
    WinSet, TopMost, On, ahk_id %hwnd%
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

 ;win+t打开东方财富股吧和韭菜公社
#t::switchToGBJC()

switchToGBJC()
{

SetTitleMatchMode RegEx
if WinExist("guba_jiucai.*")
{
    WinActivate
    WinSet, AlwaysOnTop, On, guba_jiucai.*
}

;把实时新闻移到右上角
SetTitleMatchMode, 2
WinGet,hwnd,ID,实时新闻
if (hwnd)
{
    WinGet, Style, Style, ahk_id %hwnd%
    if (!(Style & 0x20000000))    ;没有最小化才移动窗口
    {
        WinMove, ahk_id %hwnd%, , 2653, 0, 796, 478
        WinSet, TopMost, Off, ahk_id %hwnd%
        WinSet, TopMost, On, ahk_id %hwnd%
    }
    
}


}
