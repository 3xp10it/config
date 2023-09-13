ProcessExist(exe){          ;一个自定义函数,根据自定义函数的返回值作为#if成立依据原GetPID
    Process, Exist,% exe
    return ErrorLevel
}





#g::switchToChrome()
switchToChrome()
{
IfWinNotExist, ahk_exe chrome.exe
	Run, chrome.exe

if WinActive("ahk_exe chrome.exe")
	Sendinput ^{tab}
else
	WinActivate ahk_exe chrome.exe
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


;win+b 打开bug
#b::switchToBug()
switchToBug()
{
Bug_path:="\\192.168.0.6\news\bug.txt"
SetTitleMatchMode RegEx
if WinExist(".*bug.txt.*")
    WinActivate
else
    Run, %Bug_path%
}

DetectHiddenText On

;win+f 打开同花顺
#f::switchToTHS()


switchToTHS()
{
THS_path:="D:\THS\hexin.exe"
;注意：SetTitleMatchMode一定要放在WinExist前面一行，放远了可能不会生效；这里也可以通过使用WinExist("ahk_exe D:\THS\hexin.exe")来获取同花顺的窗口，但这样可能会获取到短线精灵，除了同花顺主界面属于hexin.exe外，弹窗式的短线精灵也属于hexin.exe，所以实际不能使用ahk_exe来获取，只能用窗口特征来获取，还需要注意的是，ahk代码中不支持中文，所以用中文字符串来匹配是无法成功的
SetTitleMatchMode RegEx
if WinExist(".*v8\.90\.71.*")
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

;ctrl+t 打开tl50
^t::switchToTL50()
switchToTL50()
{
tl50_path:="D:\Program Files\tl50\tl50v2.exe"
SetTitleMatchMode RegEx
if WinExist(".*1817355*")
{
WinActivate
}
else
{
Run, %tl50_path%
}
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
}
}

