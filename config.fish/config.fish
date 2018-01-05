if status is-interactive 
and not set -q TMUX
    exec tmux
end

export LC_ALL=zh_CN.UTF-8
export LANG=zh_CN.UTF-8
[ -f /usr/local/share/autojump/autojump.fish ]; and . /usr/local/share/autojump/autojump.fish
alias ll='ls -al'
alias la='ls -A'
alias l='ls -CF'
alias vi='vim'
alias 2sqlmap='cd /usr/share/sqlmap'
alias 2tamper='nautilus /usr/share/sqlmap/tamper'
alias pg='ping www.google.com'
alias pb='ping www.baidu.com'
alias 2output='nautilus ~/.sqlmap/output' 
alias 2log='cd ~/.sqlmap/output; and ls -al' 
alias 2images='nautilus /usr/share/images'
alias 2tamper1='cd /usr/share/sqlmap/tamper'
alias Cknife='java -jar /usr/share/Cknife/Cknife.jar'
alias vs='vim ~/myblog/_posts/2016-09-25-notes.md'
alias z='cd ~/Desktop; or cd ~/桌面'
alias v="vim ~/tmp.txt"
alias c="rm ~/.vimswap/tmp.txt.swp"
alias b='cd ~/myblog'
alias p='cd ~/myblog/_posts; and ls -lh'
alias 2tamper="cd /usr/share/sqlmap/tamper; and ls -al"
alias mt="cd ~/mytools; and ls -al"
alias jt="python3 /usr/share/mytools/mysnippingtool.py"
alias upa="bash /usr/share/mytools/up.sh"
alias macosbak="bash /usr/share/mytools/macosbak.sh"
alias bl="python3 /usr/share/mytools/blog.py"
alias sm="sqlmap --smart --threads 4 --random-agent -v 3 --batch -u "
alias smt="sqlmap --smart --threads 4 --random-agent -v 3 --batch --tamper='randomcase,between,space2dash' -u "
alias smc="sqlmap --smart --threads 4 --random-agent -v 3 --batch --crawl=3 -u "
alias smct="sqlmap --smart --threads 4 --random-agent -v 3 --batch --crawl=3 --tamper='randomcase,between,space2dash' -u "
alias ns="python3 /usr/share/mytools/newscript.py"
alias py="cd ~/exp10it/; and ls -al"
alias s0="shutdown -r +0"
alias pj="pkill jekyll;pkill ruby"
alias ip="ifconfig | ack '(?<=inet )(.*)(?= netmask)' -o"
alias od='tmux splitw -h -p 38; and tmux splitw -v -p 30; and tmux selectp -L; and tmux splitw -v -p 30; and tmux selectp -t 1; and zsh'
alias pp='pkill -9 python'
alias 2p="cd (pip3 show exp10it | egrep 'Location:' | egrep -o '/.*')"

alias mvim='/Applications/MacVim.app/Contents/MacOS/Vim'
alias vim='mvim'
alias py2="python2"
alias py3="python3"
alias giu="python3 ~/mytools/GitTool.py --update"
alias gic="python3 ~/mytools/GitTool.py --commit"
export EDITOR=vim
export THEOS=/opt/theos
set PATH $THEOS $PATH 
set PATH /opt/theos/bin/ $PATH
