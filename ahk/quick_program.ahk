ProcessExist(exe){          ;一个自定义函数,根据自定义函数的返回值作为#if成立依据原GetPID
    Process, Exist,% exe
    return ErrorLevel
}



#f::switchToFirefox()
switchToFirefox(){
sendinput, {SC0E8} ;scan code of an unassigned key. Do I NEED this?
IfWinNotExist, ahk_class MozillaWindowClass
	Run, firefox.exe
if WinActive("ahk_exe firefox.exe")
	Send ^{tab}
else
	{
	;WinRestore ahk_exe firefox.exe
	WinActivate ahk_exe firefox.exe
	;sometimes winactivate is not enough. the window is brought to the foreground, but not put into FOCUS.
	;the below code should fix that.
	WinGet, hWnd, ID, ahk_class MozillaWindowClass
	DllCall("SetForegroundWindow", UInt, hWnd) 
	}
}

#g::switchToChrome()
switchToChrome()
{
IfWinNotExist, ahk_exe chrome.exe
	Run, chrome.exe --ignore-certificate-errors

if WinActive("ahk_exe chrome.exe")
	Sendinput ^{tab}
else
	WinActivate ahk_exe chrome.exe
}

#e::switchToExplorer()
switchToExplorer(){
IfWinNotExist, ahk_class CabinetWClass
	Run, explorer.exe
GroupAdd, taranexplorers, ahk_class CabinetWClass
if WinActive("ahk_exe explorer.exe")
	GroupActivate, taranexplorers, r
else
	WinActivate ahk_class CabinetWClass ;you have to use WinActivatebottom if you didn't create a window group.
}




 
;win+m 打开微信
#m::switchToWechat()
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
Bug_path:="\\192.168.50.206\news\bug.txt"
if WinExist("bug.txt -")
    WinActivate
else
    Run, %Bug_path%
}

DetectHiddenText On

;win+t 打开同花顺
#t::switchToTHS()


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
}

