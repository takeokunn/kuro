#!/usr/bin/env bash
# kuro terminal emulator — comprehensive escape sequence test
# Covers all parser modules:
#   sgr, csi, osc, dec_private, erase, scroll, insert_delete, tabs, dcs(sixel/xtgettcap), apc(kitty)
#
# Usage: bash test/kuro-comprehensive-test.sh
#        bash test/kuro-comprehensive-test.sh --no-interactive

set -euo pipefail
ESC=$'\033'
BEL=$'\007'
ST="${ESC}\\"

INTERACTIVE=true
for arg in "$@"; do
  [[ "$arg" == "--no-interactive" ]] && INTERACTIVE=false
done

# ─── helpers ─────────────────────────────────────────────────────────────────
osc() { printf "${ESC}]%s${BEL}" "$1"; }

RESET="${ESC}[0m"
BOLD="${ESC}[1m"
PASS="${ESC}[92mOK${RESET}"

section() {
  printf "\n${BOLD}${ESC}[96m┌─────────────────────────────────────────────────────────────┐${RESET}\n"
  printf   "${BOLD}${ESC}[96m│ %-61s│${RESET}\n" "$1"
  printf   "${BOLD}${ESC}[96m└─────────────────────────────────────────────────────────────┘${RESET}\n"
}
subsection() { printf "\n${BOLD}${ESC}[33m  ▶ $1${RESET}\n"; }
label()      { printf "  ${ESC}[2m%-45s${RESET}" "$1"; }
ok()         { printf " %s\n" "$PASS"; }
show()       { printf "%s${RESET}  <- %s\n" "$1" "$2"; }

# ═══════════════════════════════════════════════════════════════════════════════
printf "${ESC}[2J${ESC}[H"
printf "${BOLD}${ESC}[97m"
printf "  kuro — comprehensive terminal test\n"
printf "${RESET}${ESC}[2m  All parser modules: sgr csi osc dec_private erase scroll insert_delete tabs dcs apc/kitty${RESET}\n"

# ═══════════════════════════════════════════════════════════════════════════════
# 1. SGR — Select Graphic Rendition  (parser/sgr.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "1. SGR — Select Graphic Rendition (parser/sgr.rs)"

subsection "1.1 Basic attributes (SGR 0-9, 21)"
label "SGR 0  reset";            show "${ESC}[1;31mBOLD RED${ESC}[0m normal" "SGR 0"
label "SGR 1  bold";             show "${ESC}[1mBold${RESET}" "SGR 1"
label "SGR 2  dim";              show "${ESC}[2mDim${RESET}" "SGR 2"
label "SGR 3  italic";           show "${ESC}[3mItalic${RESET}" "SGR 3"
label "SGR 4  underline";        show "${ESC}[4mUnderline${RESET}" "SGR 4"
label "SGR 5  blink slow";       show "${ESC}[5mBlink slow${RESET}" "SGR 5"
label "SGR 6  blink fast";       show "${ESC}[6mBlink fast${RESET}" "SGR 6"
label "SGR 7  inverse";          show "${ESC}[7mInverse${RESET}" "SGR 7"
label "SGR 8  hidden";           show "${ESC}[8mHIDDEN${RESET} (invisible)" "SGR 8"
label "SGR 9  strikethrough";    show "${ESC}[9mStrike${RESET}" "SGR 9"
label "SGR 21 double underline"; show "${ESC}[21mDouble underline${RESET}" "SGR 21"

subsection "1.2 Attribute reset (SGR 22-29)"
label "SGR 22 no bold/dim";      show "${ESC}[1mBOLD${ESC}[22m off${RESET}" "SGR 22"
label "SGR 23 no italic";        show "${ESC}[3mItalic${ESC}[23m off${RESET}" "SGR 23"
label "SGR 24 no underline";     show "${ESC}[4mUnder${ESC}[24m off${RESET}" "SGR 24"
label "SGR 25 no blink";         show "${ESC}[5mBlink${ESC}[25m off${RESET}" "SGR 25"
label "SGR 27 no inverse";       show "${ESC}[7mInv${ESC}[27m off${RESET}" "SGR 27"
label "SGR 28 no hidden";        show "${ESC}[8mHid${ESC}[28m visible${RESET}" "SGR 28"
label "SGR 29 no strikethrough"; show "${ESC}[9mStr${ESC}[29m off${RESET}" "SGR 29"

subsection "1.3 Underline styles — kitty extended (SGR 4:N)"
printf "  "
printf "${ESC}[4:0mNone${RESET}  "
printf "${ESC}[4:1mStraight${RESET}  "
printf "${ESC}[4:2mDouble${RESET}  "
printf "${ESC}[4:3mCurly${RESET}  "
printf "${ESC}[4:4mDotted${RESET}  "
printf "${ESC}[4:5mDashed${RESET}\n"

subsection "1.4 Standard foreground colors (SGR 30-37)"
for c in 30 31 32 33 34 35 36 37; do
  printf "${ESC}[${c}m[${c}]${RESET} "
done
printf "\n"

subsection "1.5 Standard background colors (SGR 40-47)"
for c in 40 41 42 43 44 45 46 47; do
  printf "${ESC}[${c}m[${c}]${RESET} "
done
printf "\n"

subsection "1.6 Bright foreground (SGR 90-97)"
for c in 90 91 92 93 94 95 96 97; do
  printf "${ESC}[${c}m[${c}]${RESET} "
done
printf "\n"

subsection "1.7 Bright background (SGR 100-107)"
for c in 100 101 102 103 104 105 106 107; do
  printf "${ESC}[${c}m[${c}]${RESET} "
done
printf "\n"

subsection "1.8 256-color foreground (SGR 38;5;N)"
printf "  "
for i in $(seq 0 255); do
  printf "${ESC}[38;5;${i}m#${RESET}"
done
printf "\n"

subsection "1.9 256-color background (SGR 48;5;N)"
printf "  "
for i in $(seq 0 255); do
  printf "${ESC}[48;5;${i}m ${RESET}"
done
printf "\n"

subsection "1.10 TrueColor foreground — semicolon form (SGR 38;2;R;G;B)"
printf "  "
for r in 0 32 64 96 128 160 192 224 255; do
  g=$(( 255 - r ))
  b=$(( r / 2 ))
  printf "${ESC}[38;2;${r};${g};${b}m██${RESET}"
done
printf "\n"

subsection "1.11 TrueColor foreground — colon form (SGR 38:2:R:G:B)"
printf "  "
for b in 0 32 64 96 128 160 192 224 255; do
  r=$(( 255 - b ))
  g=$(( b / 2 ))
  printf "${ESC}[38:2:${r}:${g}:${b}m██${RESET}"
done
printf "\n"

subsection "1.12 TrueColor background (SGR 48;2;R;G;B)"
for r in 0 42 85 127 170 212 255; do
  printf "  "
  for g in 0 42 85 127 170 212 255; do
    b=$(( 255 - r ))
    printf "${ESC}[48;2;${r};${g};${b}m  ${RESET}"
  done
  printf "\n"
done

subsection "1.13 Underline color (SGR 58;2;R;G;B / SGR 59)"
printf "  "
printf "${ESC}[4;58;2;255;0;0mRed underline${RESET}  "
printf "${ESC}[4;58;2;0;255;0mGreen underline${RESET}  "
printf "${ESC}[4;58;2;0;0;255mBlue underline${RESET}  "
printf "${ESC}[4;58;5;214mOrange(256)${RESET}\n"

subsection "1.14 Combined attributes"
printf "  "
printf "${ESC}[1;3;4;31mBold+Italic+Under+Red${RESET}  "
printf "${ESC}[2;7;32mDim+Inverse+Green${RESET}  "
printf "${ESC}[1;38;2;255;165;0;48;2;0;0;128mOrange on Navy${RESET}\n"

# ═══════════════════════════════════════════════════════════════════════════════
# 2. CSI cursor (parser/csi.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "2. CSI — Cursor Positioning (parser/csi.rs)"

subsection "2.1 CUU/CUD/CUF/CUB — relative movement"
printf "  [base line]\n"
printf "${ESC}[1A${ESC}[2C${ESC}[92m*CUF+CUU*${RESET}${ESC}[1B${ESC}[1G\n"

subsection "2.2 CUP — Cursor Position (ESC[row;colH)"
printf "  row2col1\n  row3col1\n"
printf "${ESC}[2A${ESC}[12G${ESC}[93m<-CUP${RESET}\n\n"

subsection "2.3 HVP — Horizontal+Vertical Position (ESC[row;colf)"
printf "  [hvp line]\n"
printf "${ESC}[1A${ESC}[6f${ESC}[95m*HVP*${RESET}\n\n"

subsection "2.4 CHA — Character Position Absolute (ESC[nG)"
printf "  0123456789\n"
printf "${ESC}[1A${ESC}[5G${ESC}[91m^${RESET}\n"

subsection "2.5 VPA — Vertical Position Absolute (ESC[nd)"
printf "  vpa_line1\n  vpa_line2\n  vpa_line3\n"
printf "${ESC}[3A${ESC}[2d${ESC}[12C${ESC}[93m<-VPA2${RESET}\n\n"

subsection "2.6 DSR — Device Status Report (ESC[6n)"
label "DSR query (ESC[6n) — terminal responds ESC[row;colR"
printf "${ESC}[6n"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 3. Erase (parser/erase.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "3. Erase sequences (parser/erase.rs)"

subsection "3.1 EL — Erase in Line"
printf "  XXXXXXXXXX\n"
printf "${ESC}[1A${ESC}[5G${ESC}[0K${ESC}[92m<-EL0 erased right${RESET}\n"

printf "  XXXXXXXXXX\n"
printf "${ESC}[1A${ESC}[6G${ESC}[1K${ESC}[92m<-EL1 erased left${RESET}\n"

printf "  XXXXXXXXXX\n"
printf "${ESC}[1A${ESC}[2K${ESC}[92m<-EL2 erased whole line${RESET}\n"

subsection "3.2 ED — Erase in Display"
label "ED 0  erase below  (ESC[0J)"; printf "${ESC}[0J"; ok
label "ED 1  erase above  (ESC[1J)"; printf "${ESC}[1J"; ok
# ED 2/3 clear full screen — only in interactive mode
if $INTERACTIVE; then
  label "ED 2  erase all    (ESC[2J)"; printf "${ESC}[2J${ESC}[H"; ok
  label "ED 3  erase scroll (ESC[3J)"; printf "${ESC}[3J"; ok
else
  label "ED 2/3 (skipped --no-interactive)"; ok
fi

# ═══════════════════════════════════════════════════════════════════════════════
# 4. Scroll (parser/scroll.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "4. Scroll sequences (parser/scroll.rs)"

subsection "4.1 DECSTBM — Set Scrolling Region (ESC[top;botr)"
label "Set region rows 5-15 (ESC[5;15r)";  printf "${ESC}[5;15r"; ok
label "Reset scroll region  (ESC[r)";       printf "${ESC}[r"; ok

subsection "4.2 SU/SD — Scroll Up / Scroll Down"
label "SU scroll up   2 lines (ESC[2S)"; printf "${ESC}[2S"; ok
label "SD scroll down 2 lines (ESC[2T)"; printf "${ESC}[2T"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 5. Insert/Delete (parser/insert_delete.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "5. Insert/Delete (parser/insert_delete.rs)"

subsection "5.1 ICH — Insert Characters (ESC[n@)"
printf "  ABCDE12345\n"
printf "${ESC}[1A${ESC}[6G${ESC}[3@${ESC}[93m*ICH*${RESET}\n"

subsection "5.2 DCH — Delete Characters (ESC[nP)"
printf "  ABCDE12345\n"
printf "${ESC}[1A${ESC}[3G${ESC}[3P\n"

subsection "5.3 ECH — Erase Characters (ESC[nX)"
printf "  ABCDE12345\n"
printf "${ESC}[1A${ESC}[4G${ESC}[4X\n"

subsection "5.4 IL — Insert Lines (ESC[nL)"
printf "  Line A\n  Line B\n  Line C\n"
printf "${ESC}[3A${ESC}[1L  ${ESC}[93mInserted${RESET}\n\n"

subsection "5.5 DL — Delete Lines (ESC[nM)"
printf "  Line X\n  Line Y\n  Line Z\n"
printf "${ESC}[3A${ESC}[1M\n\n"

# ═══════════════════════════════════════════════════════════════════════════════
# 6. Tab stops (parser/tabs.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "6. Tab stops (parser/tabs.rs)"

subsection "6.1 HT — Horizontal Tab"
printf "  |\t|\t|\t|\t| (default 8-col tabs)\n"

subsection "6.2 HTS — Horizontal Tab Set (ESC H)"
printf "  Set tab at col 5: [1234${ESC}H5678${ESC}H]\n"
printf "  Jump to tabs:     [\t\t]\n"

subsection "6.3 TBC — Tab Clear"
label "TBC 0 clear current stop (ESC[0g)"; printf "${ESC}[0g"; ok
label "TBC 3 clear all stops    (ESC[3g)"; printf "${ESC}[3g"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 7. DEC Private Modes (parser/dec_private.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "7. DEC Private Modes (parser/dec_private.rs)"

subsection "7.1 DECTCEM — Cursor Visibility (?25)"
label "Hide cursor (ESC[?25l)"; printf "${ESC}[?25l"; sleep 0.3; ok
label "Show cursor (ESC[?25h)"; printf "${ESC}[?25h"; ok

subsection "7.2 DECAWM — Auto Wrap (?7)"
label "Disable wrap (ESC[?7l)"; printf "${ESC}[?7l"; ok
printf "  NoWrap: $(printf 'A%.0s' {1..100})\n"
label "Enable wrap  (ESC[?7h)"; printf "${ESC}[?7h"; ok
printf "  Wrap:   $(printf 'B%.0s' {1..100})\n"

subsection "7.3 DECCKM — Application Cursor Keys (?1)"
label "App cursor on  (ESC[?1h)"; printf "${ESC}[?1h"; ok
label "App cursor off (ESC[?1l)"; printf "${ESC}[?1l"; ok

subsection "7.4 DECOM — Origin Mode (?6)"
label "Origin mode on  (ESC[?6h)"; printf "${ESC}[?6h"; ok
label "Origin mode off (ESC[?6l)"; printf "${ESC}[?6l"; ok

subsection "7.5 Alternate Screen Buffer (?1049)"
if $INTERACTIVE; then
  printf "${ESC}[?1049h"
  printf "\n  ${ESC}[93m[ Alternate Screen — should be blank canvas ]${RESET}\n"
  printf "  Content on alternate screen.\n"
  sleep 0.6
  printf "${ESC}[?1049l"
  label "Alt screen enter/leave (?1049h/l)"; ok
else
  label "Alt screen (skipped --no-interactive)"; ok
fi

subsection "7.6 Bracketed Paste Mode (?2004)"
label "Enable  (ESC[?2004h)"; printf "${ESC}[?2004h"; ok
label "Disable (ESC[?2004l)"; printf "${ESC}[?2004l"; ok

subsection "7.7 Focus Events (?1004)"
label "Enable  (ESC[?1004h)"; printf "${ESC}[?1004h"; ok
label "Disable (ESC[?1004l)"; printf "${ESC}[?1004l"; ok

subsection "7.8 Synchronized Output (?2026)"
label "Begin sync (ESC[?2026h)"; printf "${ESC}[?2026h"; ok
label "End sync   (ESC[?2026l)"; printf "${ESC}[?2026l"; ok

subsection "7.9 Mouse Tracking modes"
label "Normal click    (?1000h/l)"; printf "${ESC}[?1000h${ESC}[?1000l"; ok
label "Button-event    (?1002h/l)"; printf "${ESC}[?1002h${ESC}[?1002l"; ok
label "Any-event       (?1003h/l)"; printf "${ESC}[?1003h${ESC}[?1003l"; ok
label "SGR mouse       (?1006h/l)"; printf "${ESC}[?1006h${ESC}[?1006l"; ok
label "Pixel mouse     (?1016h/l)"; printf "${ESC}[?1016h${ESC}[?1016l"; ok

subsection "7.10 DECSCUSR — Cursor Shape (ESC[n SP q)"
declare -A shapes=([1]="blink block" [2]="steady block" [3]="blink underline" [4]="steady underline" [5]="blink bar" [6]="steady bar")
for n in 1 2 3 4 5 6; do
  label "Shape ${n}: ${shapes[$n]}"; printf "${ESC}[${n} q"; sleep 0.15; ok
done
printf "${ESC}[0 q"

subsection "7.11 Application Keypad (ESC= / ESC>)"
label "DECKPAM on  (ESC =)"; printf "${ESC}="; ok
label "DECKPNM off (ESC >)"; printf "${ESC}>"; ok

subsection "7.12 Kitty Keyboard Protocol (CSI >u / CSI <u / CSI ?u)"
label "Push flags=31  (ESC[>31u)"; printf "${ESC}[>31u"; ok
label "Pop  flags     (ESC[<u)";   printf "${ESC}[<u"; ok
label "Query flags    (ESC[?u)";   printf "${ESC}[?u"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 8. OSC sequences (parser/osc.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "8. OSC sequences (parser/osc.rs)"

subsection "8.1 OSC 0/2 — Window title"
label "Set title (OSC 0;title)";    osc "0;kuro test"; ok
label "Set icon+title (OSC 2)";     osc "2;kuro-icon"; ok

subsection "8.2 OSC 4 — Palette color set/query"
label "Set palette[196]=red";       osc "4;196;rgb:ff/00/00"; ok
label "Set palette[46]=green";      osc "4;46;rgb:00/ff/00"; ok
label "Query palette[196] (->resp)";printf "${ESC}]4;196;?${BEL}"; ok

subsection "8.3 OSC 7 — Current Working Directory"
label "Set CWD=file://localhost/home"; osc "7;file://localhost/home"; ok

subsection "8.4 OSC 8 — Hyperlinks"
label "Open  hyperlink"
printf "${ESC}]8;id=test1;https://github.com/takeokunn/kuro${BEL}"
printf "${ESC}[4;94mkuro on GitHub${RESET}"
printf "${ESC}]8;;${BEL}\n"

subsection "8.5 OSC 10/11/12 — Default fg/bg/cursor color"
label "Set fg    (OSC 10;rgb:cc/cc/cc)"; osc "10;rgb:cc/cc/cc"; ok
label "Set bg    (OSC 11;rgb:1a/1a/2e)"; osc "11;rgb:1a/1a/2e"; ok
label "Set cursor(OSC 12;rgb:00/ff/aa)"; osc "12;rgb:00/ff/aa"; ok
label "Query fg  (OSC 10;?)";            printf "${ESC}]10;?${BEL}"; ok
label "Query bg  (OSC 11;?)";            printf "${ESC}]11;?${BEL}"; ok
label "Query cur (OSC 12;?)";            printf "${ESC}]12;?${BEL}"; ok

subsection "8.6 OSC 52 — Clipboard"
CLIP_B64=$(printf "kuro clipboard test" | base64 | tr -d '\n')
label "Write clipboard (OSC 52;c;data)"; osc "52;c;${CLIP_B64}"; ok
label "Query clipboard (OSC 52;c;?)";    printf "${ESC}]52;c;?${BEL}"; ok

subsection "8.7 OSC 104 — Reset palette"
label "Reset palette[196] (OSC 104;196)"; osc "104;196"; ok
label "Reset all palette  (OSC 104)";     osc "104"; ok

subsection "8.8 OSC 133 — Shell integration marks"
label "PromptStart  (OSC 133;A)"; osc "133;A"; ok
label "PromptEnd    (OSC 133;B)"; osc "133;B"; ok
label "CommandStart (OSC 133;C)"; osc "133;C"; ok
label "CommandEnd ok(OSC 133;D;0)"; osc "133;D;0"; ok
label "CommandEnd err(OSC 133;D;1)"; osc "133;D;1"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 9. DCS — Device Control String (parser/dcs.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "9. DCS sequences (parser/dcs.rs)"

subsection "9.1 XTGETTCAP — Terminal capability query (DCS +q HEX ST)"
for cap in "Co" "TN" "RGB" "colors"; do
  hex_cap=$(printf "%s" "$cap" | od -A n -t x1 | tr -d ' \n')
  label "XTGETTCAP '${cap}'"
  printf "${ESC}P+q${hex_cap}${ST}"
  ok
done

subsection "9.2 Sixel graphics (DCS q ... ST)"
# 40x12 pixel color blocks: red / blue / green / yellow rows
printf "${ESC}Pq"
printf '#0;2;0;0;0'
printf '#1;2;100;0;0'
printf '#2;2;0;0;100'
printf '#3;2;0;100;0'
printf '#4;2;100;100;0'
printf '#1!10?#2!10?#3!10?#4!10?'
printf '-'
printf '#2!10?#1!10?#4!10?#3!10?'
printf "${ST}"
printf "\n  ${ESC}[2m^ Sixel: 40x12 px red/blue/green/yellow blocks${RESET}\n"

# ═══════════════════════════════════════════════════════════════════════════════
# 10. Kitty Graphics Protocol (parser/apc.rs + parser/kitty.rs)
# ═══════════════════════════════════════════════════════════════════════════════
section "10. Kitty Graphics Protocol (parser/apc.rs + parser/kitty.rs)"

subsection "10.1 Direct RGBA pixel data (a=T, f=32)"
# 4x4 solid red RGBA (each pixel: R=255 G=0 B=0 A=255)
RGBA_4X4=$(python3 -c "import base64,sys; sys.stdout.write(base64.b64encode(bytes([255,0,0,255]*16)).decode())" 2>/dev/null \
  || printf '/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA/wAA')
label "Transmit 4x4 red RGBA (a=T,f=32,s=4,v=4,I=1)"
printf "${ESC}_Ga=T,f=32,s=4,v=4,I=1;${RGBA_4X4}${ST}"
printf "${ESC}_Ga=p,i=1${ST}"
ok

subsection "10.2 8x8 blue block"
printf "  "
RGBA_8X8=$(python3 -c "import base64,sys; sys.stdout.write(base64.b64encode(bytes([0,0,255,255]*64)).decode())" 2>/dev/null || printf "")
if [[ -n "$RGBA_8X8" ]]; then
  printf "${ESC}_Ga=T,f=32,s=8,v=8,I=42;${RGBA_8X8}${ST}"
  printf "${ESC}_Ga=p,i=42,c=2,r=1${ST}"
  printf "\n  ${ESC}[2m^ 8x8 blue block (id=42)${RESET}\n"
else
  printf "${ESC}[2m(python3 unavailable)${RESET}\n"
fi

subsection "10.3 PNG via Kitty (f=100)"
# Minimal 1x1 white PNG (base64)
PNG_1X1="iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQAABjE+ibYAAAAASUVORK5CYII="
label "Transmit 1x1 PNG (a=T,f=100,I=99)"
printf "${ESC}_Ga=T,f=100,I=99;${PNG_1X1}${ST}"
printf "${ESC}_Ga=p,i=99${ST}"
ok

subsection "10.4 Chunked transmission (m=1 first chunk, m=0 final)"
if [[ -n "${RGBA_4X4:-}" ]]; then
  CHUNK1="${RGBA_4X4:0:20}"
  CHUNK2="${RGBA_4X4:20}"
  label "Chunk 1/2 (m=1)"; printf "${ESC}_Ga=T,f=32,s=4,v=4,I=50,m=1;${CHUNK1}${ST}"; ok
  label "Chunk 2/2 (m=0)"; printf "${ESC}_Gm=0;${CHUNK2}${ST}"; printf "${ESC}_Ga=p,i=50${ST}"; ok
fi

subsection "10.5 Delete image (a=d)"
label "Delete id=1 (a=d,d=i,i=1)"; printf "${ESC}_Ga=d,d=i,i=1${ST}"; ok
label "Delete all   (a=d,d=A)";     printf "${ESC}_Ga=d,d=A${ST}"; ok

# ═══════════════════════════════════════════════════════════════════════════════
# 11. OSC 1337 — iTerm2 Inline Images
# ═══════════════════════════════════════════════════════════════════════════════
section "11. OSC 1337 — iTerm2 Inline Images (parser/osc.rs)"

# 8x8 green PNG (minimal valid)
PNG_8X8="iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAGElEQVQoU2Nk+M9Qz0AEYBxVQF8FAAAzmgED/oBMzQAAAABJRU5ErkJggg=="
label "8x8 inline PNG (OSC 1337;File=inline=1)"
printf "${ESC}]1337;File=inline=1;width=2;height=1:${PNG_8X8}${BEL}"
ok

# ═══════════════════════════════════════════════════════════════════════════════
# 12. Unicode — wide chars, CJK, emoji, combining
# ═══════════════════════════════════════════════════════════════════════════════
section "12. Unicode (wide chars, CJK, emoji, combining)"

subsection "12.1 Box-drawing & block elements"
printf "  ┌──────────────────┐\n"
printf "  │ ░▒▓█ ▀▄▌▐■□◆◇ │\n"
printf "  └──────────────────┘\n"

subsection "12.2 CJK wide characters (cell-width = 2)"
printf "  Japanese: こんにちは世界\n"
printf "  Chinese:  你好世界\n"
printf "  Korean:   안녕하세요\n"

subsection "12.3 Emoji (1F000+ range)"
printf "  Basic:      😀 😂 🥹 🫠 🤔 🎉 🚀 🌈 🔥 💯\n"
printf "  Skin tones: 👋🏻 👋🏼 👋🏽 👋🏾 👋🏿\n"
printf "  ZWJ:        👨‍💻 👩‍🚀 🏳️‍🌈\n"

subsection "12.4 Combining characters"
printf "  e\u0301 a\u0300 n\u0303 o\u0308 (combining diacritics)\n"
printf "  Stacked: a\u0300\u0301\u0308\n"

subsection "12.5 RTL / Bidirectional"
printf "  Arabic: \u0645\u0631\u062d\u0628\u0627  Hebrew: \u05e9\u05dc\u05d5\u05dd\n"

subsection "12.6 Math / Braille / Misc symbols"
printf "  Braille: ⠋⠕⠕⠀⠃⠁⠗\n"
printf "  Math:    ∑ ∏ ∫ ∂ ∇ √ ∞ ≤ ≥ ≠ ≈ ±\n"
printf "  Arrows:  ← → ↑ ↓ ↔ ⇐ ⇒ ⇑ ⇓ ⇔\n"

# ═══════════════════════════════════════════════════════════════════════════════
# 13. Rendering stress
# ═══════════════════════════════════════════════════════════════════════════════
section "13. Rendering stress tests"

subsection "13.1 Rapid scrollback write"
for i in $(seq 1 50); do
  color=$(( (i * 5) % 256 ))
  printf "  ${ESC}[38;5;${color}m[%03d]${RESET} "
  # generate printable random-ish text without using /dev/urandom directly
  printf "%-60s\n" "$(cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9 ' 2>/dev/null | head -c 60 || printf '%060d' $i)"
done

subsection "13.2 Inline progress bar (\\r carriage-return update)"
printf "\n"
for i in $(seq 1 60); do
  pct=$(( i * 100 / 60 ))
  bar=$(printf "%${i}s" | tr ' ' '#')
  spc=$(printf "%$(( 60 - i ))s")
  if   [ $pct -lt 40 ]; then c="${ESC}[92m"
  elif [ $pct -lt 75 ]; then c="${ESC}[93m"
  else                        c="${ESC}[91m"
  fi
  printf "\r  ${c}[${bar}${spc}]${RESET} ${BOLD}%3d%%${RESET}" "$pct"
  sleep 0.01
done
printf "\n  ${ESC}[92mDone${RESET}\n"

subsection "13.3 Insert Mode (IRM ESC[4h / ESC[4l)"
printf "  ORIGINAL_LINE\n"
printf "${ESC}[1A${ESC}[5G${ESC}[4h>>>${ESC}[4l\n"

subsection "13.4 Long line wrap vs no-wrap"
printf "${ESC}[?7h"
printf "  WRAP:   $(printf 'W%.0s' {1..120})\n"
printf "${ESC}[?7l"
printf "  NOWRAP: $(printf 'N%.0s' {1..120})\n"
printf "${ESC}[?7h\n"

# ═══════════════════════════════════════════════════════════════════════════════
# Footer
# ═══════════════════════════════════════════════════════════════════════════════
printf "\n${BOLD}${ESC}[96m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
printf "${BOLD}${ESC}[92m  All test sequences emitted.${RESET}\n"
printf "${ESC}[2m  sgr · csi · erase · scroll · insert_delete · tabs ·${RESET}\n"
printf "${ESC}[2m  dec_private · osc · dcs(sixel+xtgettcap) · apc(kitty) · unicode${RESET}\n"
printf "${BOLD}${ESC}[96m━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"
