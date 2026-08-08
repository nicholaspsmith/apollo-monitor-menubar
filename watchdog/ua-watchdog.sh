#!/bin/zsh
#
# ua-watchdog.sh — kill runaway / wedged Universal Audio processes and
# auto-recover Apollo audio. Fired by a launchd StartInterval timer
# (~60s); one-shot, exits immediately. Runs as the user — no sudo needed
# (all UA helper processes are user-owned).
#
# Detection (per tick):
#   * FAST PATH  — an ORPHANED "UA Mixer Helper" (PPID 1, parent Console
#                  gone) at >= ORPHAN_CPU%  ->  killed immediately.
#                  This is the exact bug that silently kills Apollo audio.
#   * ENGINE     — "UA Mixer Engine" is real-time; higher bar: >= CPU_ENGINE%
#                  sustained across TICKS_ENGINE consecutive ticks.
#   * EVERYTHING ELSE UA (Console, UA Connect, UAD Meter, helpers, GUI) —
#                  >= CPU% sustained across TICKS consecutive ticks.
# On a kill: log it, post a Notification Center alert, and if the victim
# was on the audio path, kickstart the mixer engine so sound comes back.
#
# Thresholds are env-overridable (handy for tuning/testing).

emulate -L zsh
setopt no_nomatch

CPU=${UA_WD_CPU:-90}                 # general sustained threshold (%)
CPU_ENGINE=${UA_WD_CPU_ENGINE:-98}   # real-time mixer engine bar (%)
ORPHAN_CPU=${UA_WD_ORPHAN_CPU:-80}   # orphaned-helper fast-path bar (%)
TICKS=${UA_WD_TICKS:-2}              # consecutive ticks for general
TICKS_ENGINE=${UA_WD_TICKS_ENGINE:-3}

STATE_DIR="$HOME/.local/state"
STATE="$STATE_DIR/ua-watchdog.state"   # "pid=count" debounce carryover
LOG="$STATE_DIR/ua-watchdog.log"
mkdir -p "$STATE_DIR"

logline() { print -r -- "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG" }
notify()  { osascript -e "display notification \"$1\" with title \"UA Watchdog\" sound name \"Funk\"" >/dev/null 2>&1 }

# --- load previous tick's pending counts -----------------------------
typeset -A COUNT NEW
if [[ -f "$STATE" ]]; then
  while IFS='=' read -r k v; do [[ -n "$k" ]] && COUNT[$k]=$v; done < "$STATE"
fi

typeset -a killed_labels
audio_path_killed=0
SELF=$$

# --- scan all processes; command field kept intact via tab delimiter --
while IFS=$'\t' read -r pid ppid cpu command; do
  [[ -z "$pid" || "$pid" == "$SELF" ]] && continue

  # Is this a Universal Audio process? (install dirs + engine/helper token)
  if [[ "$command" != *"/Universal Audio/"* \
     && "$command" != *"UA Connect.app"* \
     && "$command" != *"UA Mixer"* ]]; then
    continue
  fi

  cpu_int=${cpu%%.*}; [[ -z "$cpu_int" ]] && cpu_int=0

  # human label + audio-path classification
  if   [[ "$command" == *"UA Mixer Helper.app"* ]]; then label="UA Mixer Helper"; is_helper=1; is_engine=0
  elif [[ "$command" == *"UA Mixer Engine.app"* ]]; then label="UA Mixer Engine"; is_helper=0; is_engine=1
  elif [[ "$command" == *"UA Connect.app"* ]];      then label="UA Connect";      is_helper=0; is_engine=0
  elif [[ "$command" == *"UAD Meter"* ]];           then label="UAD Meter";       is_helper=0; is_engine=0
  elif [[ "$command" == *"UAD Console.app"* ]];     then label="UAD Console";     is_helper=0; is_engine=0
  else label="${command:t}"; is_helper=0; is_engine=0
  fi

  # FAST PATH: orphaned Mixer Helper (parent Console gone) pegging CPU
  if (( is_helper )) && [[ "$ppid" == "1" ]] && (( cpu_int >= ORPHAN_CPU )); then
    kill -9 "$pid" 2>/dev/null
    logline "KILLED orphaned $label pid=$pid cpu=${cpu}% (fast-path: PPID=1)"
    killed_labels+="$label"; audio_path_killed=1
    continue
  fi

  # DEBOUNCED PATH
  if (( is_engine )); then thr=$CPU_ENGINE; need=$TICKS_ENGINE
  else                     thr=$CPU;        need=$TICKS
  fi

  if (( cpu_int >= thr )); then
    prev=${COUNT[$pid]:-0}
    (( cur = prev + 1 ))
    if (( cur >= need )); then
      kill -9 "$pid" 2>/dev/null
      logline "KILLED runaway $label pid=$pid cpu=${cpu}% (>=${thr}% x ${cur} ticks)"
      killed_labels+="$label"
      (( is_engine || is_helper )) && audio_path_killed=1
    else
      NEW[$pid]=$cur
      logline "WARN $label pid=$pid cpu=${cpu}% (tick ${cur}/${need} >=${thr}%)"
    fi
  fi
done < <(ps -Ao pid=,ppid=,pcpu=,command= \
          | awk '{printf "%s\t%s\t%s\t",$1,$2,$3; for(i=4;i<=NF;i++){printf "%s",$i; if(i<NF)printf " "}; printf "\n"}')

# --- persist pending counts for next tick ----------------------------
: > "$STATE"
for k in ${(k)NEW}; do print -r -- "$k=${NEW[$k]}" >> "$STATE"; done

# --- heartbeat: record that this tick ran (Apollo Monitor's UA Watchdog
#     submenu reads this to show "checked Ns ago"; stale ⇒ it flags a problem) ---
print -r -- "$(date +%s)" > "$STATE_DIR/ua-watchdog.heartbeat"

# --- recover audio + notify if we killed anything --------------------
if (( ${#killed_labels} )); then
  if (( audio_path_killed )); then
    launchctl kickstart -k "gui/$(id -u)/com.uaudio.ua_mixer_engine" 2>/dev/null
    logline "kickstarted UA mixer engine to restore audio path"
    notify "Killed runaway ${killed_labels[1]} — audio restored"
  else
    notify "Killed runaway ${killed_labels[1]}"
  fi
fi
