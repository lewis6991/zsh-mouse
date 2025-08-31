set-status() { return $1; }

handle_mouse_event0() {
  local bt=$1 mx=$2 my=$3 last_status=$4

  setopt extendedglob

  print -n '\e[6n' # query cursor position

  local i match mbegin mend buf=

  while read -k i \
    && buf+=$i \
    && [[ $buf != *\[([0-9]##)\;[0-9]##R ]]
  do :; done
  # read response from terminal.
  # note that we may also get a mouse tracking btn-release event,
  # which would then be discarded.

  # Match ANSI cursor position report (ESC [row;colR)
  [[ $buf = (#b)*\[([0-9]##)\;[0-9]##R ]] || return
  local cy=$match[1]

  local cur_prompt

  # trying to guess the current prompt
  case $CONTEXT in
    (vared)
      if [[ $0 = zcalc ]]; then
        cur_prompt=${ZCALCPROMPT-'%1v> '}
        setopt nopromptsubst nopromptbang promptpercent
        # (ZCALCPROMPT is expanded with (%))
      fi;;
      # if vared is passed a prompt, we're lost
    (select) cur_prompt=$PS3;;
    (cont) cur_prompt=$PS2;;
    (start) cur_prompt=$PS1;;
  esac

  # if promptsubst, then we need first to do the expansions (to
  # be able to remove the visual effects) and disable further
  # expansions
  if [[ -o promptsubst ]]; then
    cur_prompt=${${(e)cur_prompt}//(#b)([\\\$\`])/\\$match}
  fi

  # restore the exit status in case $PS<n> relies on it
  set-status $last_status

  # remove the visual effects and do the prompt expansion
  cur_prompt=${(S%%)cur_prompt//(#b)(%([BSUbsu]|{*%})|(%[^BSUbsu{}]))/$match[3]}

  # we're now looping over the whole editing buffer (plus the last
  # line of the prompt) to compute the (x,y) position of each char. We
  # store the characters i for which x(i) <= mx < x(i+1) for every
  # value of y in the pos array. We also get the Y(CURSOR), so that at
  # the end, we're able to say which pos element is the right one

  # array holding the possible positions of the mouse pointer
  local -a pos

  local -i i n x=0 y=1 cursor=$((${#cur_prompt}+$CURSOR+1))
  local Y

  buf=$cur_prompt$BUFFER
  for ((i=1; i<=$#buf; i++)); do
    (( i == cursor )) && Y=$y
    n=0
    case $buf[i] in
      ($'\n') # newline
        : ${pos[y]=$i}
        (( y++, x=0 ));;
      ($'\t') # tab advance til next tab stop
        (( x = x/8*8+8 ));;
      ([$'\0'-$'\037'$'\200'-$'\237'])
        # characters like ^M
        n=2;;
      (*)
        n=1;;
    esac
    while
      (( x >= mx )) && : ${pos[y]=$i}
      (( x >= COLUMNS )) && (( x=0, y++ ))
      (( n > 0 ))
    do
      (( x++, n-- ))
    done
  done
  : ${pos[y]=$i} ${Y:=$y}

  local mouse_CURSOR
  if ((my + Y - cy > y)); then
    mouse_CURSOR=$#BUFFER
  elif ((my + Y - cy < 1)); then
    mouse_CURSOR=0
  else
    mouse_CURSOR=$(($pos[my + Y - cy] - ${#cur_prompt} - 1))
  fi

  case $bt in
    (0)
      # Button 1.  Move cursor.
      CURSOR=$mouse_CURSOR
    ;;

    (1)
      # Button 2.  Insert selection at mouse cursor postion.
      BUFFER=$BUFFER[1,mouse_CURSOR]$CUTBUFFER$BUFFER[mouse_CURSOR+1,-1]
      (( CURSOR = $mouse_CURSOR + $#CUTBUFFER ))
    ;;

    (2)
      # Button 3.  Copy from cursor to mouse to cutbuffer.
      killring=("$CUTBUFFER" "${(@)killring[1,-2]}")
      if (( mouse_CURSOR < CURSOR )); then
        CUTBUFFER=$BUFFER[mouse_CURSOR+1,CURSOR+1]
      else
        CUTBUFFER=$BUFFER[CURSOR+1,mouse_CURSOR+1]
      fi
    ;;
  esac
}

handle_mouse_event() {
  local last_status=$?
  emulate -L zsh
  local bt mx my

  # either xterm mouse tracking or bound xterm event
  # read the event from the terminal
  read -k bt # mouse button, x, y reported after \e[M
  bt=$((#bt & 0x47))

  read -k mx
  read -k my

  # Check if $mx is the ASCII character with code 24 (Ctrl-X)
  if [[ "$mx" == "\x18" ]]; then
    # assume event is \E[M<btn>dired-button()(^X\EG<x><y>)
    read -k mx
    read -k mx
    read -k my
    (( my = #my - 31 ))
    (( mx = #mx - 31 ))
  else
    # that's a VT200 mouse tracking event
    (( my = #my - 32 ))
    (( mx = #mx - 32 ))
  fi

  if [[ $bt -eq 3 ]]; then
    return  # Process on press, discard release
  elif [[ $bt -eq 64 || $bt -eq 65 ]]; then
    # Mouse wheel up/down: fallback to terminal scroll
    # disable mouse reporting. Will be re-enabled in precmd
    print -n '\e[?1000l'
    return
  fi

  handle_mouse_event0 $bt $mx $my $last_status
}

zle -N handle_mouse_event

zmodload -i zsh/parameter # needed for $functions
functions[precmd]+='print -n '\''\e[?1000h'\'
functions[preexec]+='print -n '\''\e[?1000l'\'

bindkey -M emacs '\e[M' handle_mouse_event
bindkey -M viins '\e[M' handle_mouse_event
bindkey -M vicmd '\e[M' handle_mouse_event
