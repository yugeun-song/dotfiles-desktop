<!--
This is a design, not an implementation. Nothing in the repository does any of
it yet. It was written on 2026-08-26 from a survey of every place a colour is
currently written, and it stays here so the survey does not have to be redone.

Implementing it means writing bin/theme and the templates it renders, and
regenerating every consumer from the palette. Until then the colours live where
section 1 says they live, spread across the files listed in the survey.
-->

# 테마 시스템 설계

## 1. 무엇을 만드는가

색을 한 곳에만 적고 나머지 파일은 전부 거기서 만들어 내는 생성기를 만든다. 사람이 손으로 쓰는 것은 팔레트 파일 하나뿐이고, 그 안에는 `#7aa2f7` 같은 값이 "파랑"이라는 이름이 아니라 "주 강조색"이라는 역할 이름으로 들어간다. 생성기는 그 역할표를 읽어 KDE, GTK, hyprlock, Hyprland, kitty, tmux, zsh, fcitx5, swappy, slurp, fuzzel, quickshell 바가 각자 읽는 형식으로 번역한다. 팔레트는 여러 개를 두고 이름으로 고른다. 전환은 저장소를 고치는 일이 아니라 이미 만들어 둔 산출물 묶음 하나를 가리키는 링크를 갈아 끼우는 일이다. matugen처럼 벽지에서 색을 뽑아내는 단계는 없다. 색은 사람이 정하고 기계는 옮겨 적기만 한다.

```
 손으로 씀 (추적됨)
   theme/palettes/spaceduck.json
   theme/palettes/macos-dark.json
   theme/templates/*.in
          │
          │  theme build            팔레트를 읽어 소비자 형식으로 번역한다
          ▼
 생성됨 (추적됨, 마커 있음)
   theme/out/spaceduck/
   theme/out/macos-dark/
     palette.json   kdeglobals        Spaceduck.colors   gtk-colors.css
     gtk4.css       hyprlock.conf     hypr-palette.lua   swappy.config
     slurp.env      fuzzel-theme.ini  kitty.conf         tmux.conf
     fzf.env        fcitx5-theme.conf
          │
          │  theme set <name>       저장소를 건드리지 않는다
          │
          ├─► 링크 하나로 따라오는 소비자
          │     ~/.local/state/theme/current ──► theme/out/<name>/
          │     kitty, tmux, zsh(fzf, caps lock), capture.sh(slurp)
          │
          ├─► 복사해야 하는 소비자
          │     ~/.config/kdeglobals
          │     ~/.config/gtk-3.0/colors.css
          │     ~/.config/gtk-4.0/colors.css
          │     ~/.config/gtk-4.0/gtk.css
          │     ~/.config/hypr/palette.conf
          │     ~/.config/hypr/palette.lua
          │     ~/.config/swappy/config
          │     ~/.config/fuzzel/theme.ini
          │     ~/.local/share/color-schemes/<Label>.colors
          │     ~/.local/share/fcitx5/themes/custom/theme.conf
          │     ~/.local/state/theme/palette.json
          │
          └─► 신호
                plasma-apply-colorscheme   Qt/KDE 앱 즉시 재색칠
                qs ipc call theme reload   quickshell 바 즉시 재색칠
                fcitx5-remote -r           후보창 즉시 재색칠
                tmux source-file           상태줄 즉시 재색칠
                hyprctl eval               창 테두리, 반영 여부 미확인
```

핵심은 `theme build`와 `theme set`을 나눈 것이다. `build`는 팔레트를 고쳤을 때만 돌고 결과를 커밋한다. `set`은 매일 돌지만 저장소에 어떤 변경도 남기지 않는다. 조사에서 걱정한 "테마를 바꿀 때마다 작업 트리가 더러워지는 문제"가 이 분리로 사라진다.

---

## 2. 팔레트 형식

### 2.1 역할을 정하는 기준

역할(role)은 색이 무슨 일을 하는지를 가리키는 이름이다. "파랑"은 생김새이고 "주 강조색"은 역할이다. 생김새로 이름을 붙이면 밝은 테마나 초록 계열 테마로 갈아탈 때 `blue`라는 이름 안에 초록이 들어앉게 되고, 그 순간 이름이 거짓말을 시작한다.

역할은 17개다. 셋으로 나뉜다.

**표면과 글자 7개.** 어떤 테마든 반드시 있어야 하는 뼈대다.

| 역할 | 하는 일 | 지금 값의 출처 |
|---|---|---|
| `bg` | 바탕. 바 배경, 창 배경, 목록 뷰 배경, kitty 배경 | `Theme.qml:84` bg |
| `surface` | 바탕 위에 얹힌 면. 알약, 버튼, 제목 표시줄, 툴팁 테두리 안쪽, 입력란 | `Theme.qml:85` bgAlt |
| `border` | 경계선. GTK `borders_breeze`, hyprlock 입력란 테두리, slurp 선택 테두리, tmux 패널 경계 | `hyprlock.conf:45` |
| `fg` | 바탕 위 글자 | `Theme.qml:86` fg |
| `dim` | 흐린 글자. 비활성 항목, 자리표시자, 꺼진 알약 | `Theme.qml:87` muted |
| `fill` | 뜻 없이 채워진 밝은 면. 툴팁 배경 | `Theme.qml:114` beige |
| `ink` | 색이 칠해진 면 위에 얹는 글자. 알약 글자, 선택 행 글자, 툴팁 글자 | `Theme.qml:115` ink |

`ink`를 `bg`와 따로 두는 이유는 지금 값이 같아서가 아니라 역할이 다르기 때문이다. 밝은 테마에서 `bg`는 흰색 쪽으로 가고 `ink`는 검은색 쪽에 남는다. 참조 횟수도 14회로 두 번째로 많다. `border`를 `dim`과 따로 두는 이유는 테두리를 아예 없앤 테마(경계선을 `bg`와 같게 두는 테마)를 만들 수 있어야 하기 때문이다.

**뜻이 있는 색 4개.** 이 넷은 소비자가 뜻으로 요구한다. `kdeglobals`의 `ForegroundNegative` / `ForegroundNeutral` / `ForegroundPositive`, GTK의 `error_color_breeze` / `warning_color_breeze` / `success_color_breeze`가 이름 그대로 이 셋을 요구하므로 없앨 수 없다.

| 역할 | 하는 일 |
|---|---|
| `accent` | 주 강조. 선택 배경, 포커스 테두리, 링크, Hyprland 활성 창 테두리, 런처 선택 행, 블루투스 연결됨 |
| `positive` | 정상. 네트워크 연결됨, 충전 중, 메뉴 체크 표시, 볼륨 OSD |
| `caution` | 주의. 배터리 30% 이하, 부하 65% 이상, 밝기 OSD, 한글 입력 상태 |
| `critical` | 위험. 배터리 15% 이하, 부하 85% 이상, caps lock, 알람 울림, 전원 메뉴 종료, hyprlock 인증 실패 |

**구별용 색 6개.** 뜻이 없고 임무가 "나란히 놓였을 때 서로 구별되는 것" 하나뿐인 색이다. 상태 알약이 아홉 개 붙어 있는 바에서 이 여섯이 없으면 모든 알약이 같은 색이 된다. 어느 자리에 어느 번호가 가는지는 값이 아니라 규칙이므로 `Theme.qml` 안에 남고 팔레트는 여섯 개의 값만 준다.

| 역할 | 어디에 배정되는가 |
|---|---|
| `tone1` | 미디어 알약, 메모리 부하 기준색, 방문한 링크 |
| `tone2` | 포커스한 창 칩 |
| `tone3` | 워크스페이스 이동 표시 |
| `tone4` | 시계와 시스템 배지, 호버 장식, 링크, hyprlock 인증 확인 표시 |
| `tone5` | CPU 부하 기준색 |
| `tone6` | 조용한 기본 알약, 배터리 정상, hyprlock 날짜 라벨 |

**17개로 줄이면서 사라지는 것.** 지금 `Theme.qml`에 있는 22칸 가운데 다음이 없어진다.

- `red`(88행), `green`(89행), `blue`(91행)은 저장소 어디에서도 참조되지 않는다. 지운다.
- `capsLock`(103행)은 값이 `accentRed`와 같고 `dotfiles-terminal/zsh/config/caps-lock.zsh:111`의 `-b '#f7768e' -f '#0f111b'`와 짝지어 손으로 맞춰 온 것이다. `critical` + `ink`로 대체한다. 생성기가 `caps-lock.zsh`가 읽는 값도 같이 만들므로 두 저장소 사이의 수동 동기화가 통째로 사라진다. `Theme.qml:100-102`의 고백 주석이 없어지는 자리다.
- `accentTeal`(108행)은 볼륨 OSD와 배터리 정상 두 곳에서만 쓴다. 볼륨은 `positive`로, 배터리 정상은 `tone6`으로 나눠 보낸다. 충전 중이 `positive`, 정상이 `tone6`이므로 두 상태는 여전히 구별된다.
- `purple`(92행, 미디어 알약)과 `accentPurple`(111행, 메모리 부하)은 둘 다 보라 계열이고 화면에서 나란히 놓이지 않는다. `tone1` 하나로 합친다.

**역할이 아닌 것 16칸.** ANSI 0번부터 15번까지는 역할이 아니라 계약이다. `ls`, `git`, `vim`이 "색 2번"을 초록이라고 믿고 인덱스로 지목하므로 이 16칸은 역할표에서 유도할 수 없다. 팔레트 파일에 `ansi` 배열로 따로 둔다. kitty만 이것을 소비하고, p10k의 256색 인덱스 가운데 0번부터 15번까지가 여기서 따라온다.

### 2.2 파일 형식

경로는 `~/workspace/dotfiles-desktop/theme/palettes/<name>.json`이다.

```json
{
  "name": "spaceduck",
  "label": "Spaceduck",
  "scheme": "dark",

  "roles": {
    "bg":       "#0f111b",
    "surface":  "#1b1c36",
    "border":   "#686f9a",
    "fg":       "#ecf0c1",
    "dim":      "#686f9a",
    "fill":     "#ecf0c1",
    "ink":      "#0f111b",

    "accent":   "#7aa2f7",
    "positive": "#9ece6a",
    "caution":  "#e0af68",
    "critical": "#f7768e",

    "tone1":    "#bb9af7",
    "tone2":    "#7a5ccc",
    "tone3":    "#f2ce00",
    "tone4":    "#7dcfff",
    "tone5":    "#ff9e64",
    "tone6":    "#c0caf5"
  },

  "ansi": [
    "#000000", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#686f9a",
    "#686f9a", "#e33400", "#5ccc96", "#b3a1e6",
    "#00a3cc", "#f2ce00", "#7a5ccc", "#f0f1ce"
  ]
}
```

`ansi` 배열의 3번과 5번 자리가 각각 보라와 노랑인 것은 오타가 아니다. `dotfiles-terminal/kitty/spaceduck.conf:13-15`가 밝히듯 원저자가 노랑과 보라를 일부러 맞바꾼 것이고, 그 스왑을 재현하지 않으면 spaceduck이 아니게 된다. 팔레트 파일이 배열이라 스왑이 값 자체로 표현되고 생성기는 그런 사정이 있다는 것을 몰라도 된다.

`scheme`은 `"dark"` 또는 `"light"`다. 값이 `"light"`인 팔레트로 갈아탈 때만 `gsettings set org.gnome.desktop.interface color-scheme default`가 필요하다. 그 외에는 이 필드가 아무 일도 하지 않는다.

`name`은 파일 이름이자 `theme set`의 인자다. `label`은 KDE 색 구성 목록에 보이는 이름이고 `~/.local/share/color-schemes/<label에서 공백 뺀 이름>.colors`의 파일명이 된다.

**팔레트 값의 이동 두 가지를 미리 밝힌다.** `accent`가 `#7aa2f7`이므로 Hyprland 활성 창 테두리가 지금의 `#5ccc96`(`hypr/config/general.lua:25`)에서 바뀐다. 그리고 hyprlock의 caps lock 색이 지금의 `#f2ce00`(`hypr/hyprlock.conf:50`)에서 `critical`인 `#f7768e`로 바뀐다. 둘 다 조사에서 지적된 팔레트 갈라짐을 한쪽으로 정리한 결과다. 반대로 정리하고 싶으면 `accent`를 `#5ccc96`으로 적으면 되고, 그러면 런처 선택 행과 KDE 선택 배경까지 초록으로 따라온다. 그 결정이 바로 역할표가 존재하는 이유다.

---

## 3. 생성기

### 3.1 위치와 인터페이스

파일은 `~/workspace/dotfiles-desktop/bin/theme`다. `bin/bar`와 `bin/unlock` 옆이고 `install.sh`가 `~/.local/bin/theme`로 링크한다.

```
theme list                    팔레트 목록과 현재 선택을 낸다
theme show [name]             역할표를 값과 함께 낸다. 인자가 없으면 현재 테마
theme build [name...]         팔레트에서 theme/out/<name>/ 을 만든다. 저장소를 고친다
theme set <name>              theme/out/<name>/ 을 실제 위치에 걸고 신호를 보낸다
theme check                   생성물이 팔레트와 일치하는지 검사한다. 어긋나면 0이 아닌 값으로 끝난다
theme sync-fallback           theme/palettes/spaceduck.json 에서 Theme.qml 의 바닥값 블록을 다시 쓴다
```

`theme set --reload-hypr`는 `hyprctl reload`를 명시적으로 요구할 때만 쓴다. 기본값이 아닌 이유는 3.6에 적는다.

### 3.2 골격과 팔레트 읽기

```bash
#!/usr/bin/env bash
#
# 팔레트 하나에서 모든 소비자의 색 파일을 만든다.
#
# build 는 저장소를 고치고 set 은 고치지 않는다. 이 구분이 이 스크립트의
# 전부다. 테마를 바꾸는 일이 커밋을 남기는 일이 되면 아무도 안 바꾼다.
#
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
PALETTES="$SRC/theme/palettes"
TEMPLATES="$SRC/theme/templates"
OUT="$SRC/theme/out"

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

ROLE_NAMES=(bg surface border fg dim fill ink
            accent positive caution critical
            tone1 tone2 tone3 tone4 tone5 tone6)

die() { echo "theme: $*" >&2; exit 1; }

# 팔레트를 R_<역할> 셸 변수와 ANSI 배열로 푼다. 누락된 역할은 여기서
# 잡는다. 뒤에서 빈 문자열이 sed 로 흘러들어가면 색이 사라진 파일이
# 조용히 만들어지고, 그것은 화면을 봐야만 알아챌 수 있는 실패다.
load_palette() {
    local file="$PALETTES/$1.json"
    [[ -f "$file" ]] || die "no such palette: $1"

    NAME=$(jq -r '.name' "$file")
    LABEL=$(jq -r '.label' "$file")
    SCHEME=$(jq -r '.scheme' "$file")
    [[ "$NAME" == "$1" ]] || die "$file: name is \"$NAME\", expected \"$1\""

    local role value
    for role in "${ROLE_NAMES[@]}"; do
        value=$(jq -r --arg r "$role" '.roles[$r] // empty' "$file")
        [[ "$value" =~ ^#[0-9a-fA-F]{6}$ ]] \
            || die "$file: role $role is missing or not #rrggbb"
        printf -v "R_$role" '%s' "$value"
    done

    mapfile -t ANSI < <(jq -r '.ansi[]' "$file")
    (( ${#ANSI[@]} == 16 )) || die "$file: ansi must have exactly 16 entries"

    SCHEME_ID=${LABEL// /}
}

# "#rrggbb" -> "r,g,b". kdeglobals 와 .colors 만 십진 RGB 를 쓴다.
rgb() {
    local h="${1#\#}"
    printf '%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}
```

### 3.3 템플릿 치환

색을 단순히 끼워 넣기만 하면 되는 소비자는 전부 하나의 치환 함수로 처리한다. 템플릿에서 `@bg@`는 `#0f111b`으로, `@raw:bg@`는 샵 없는 `0f111b`으로, `@pango:dim@`은 hyprlock 마크업이 요구하는 `##686f9a`로 바뀐다.

```bash
# 템플릿 하나를 표준 출력으로 편다.
render() {
    local src="$1" role args=()
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        args+=(-e "s|@$role@|$value|g")
        args+=(-e "s|@raw:$role@|${value#\#}|g")
        args+=(-e "s|@pango:$role@|#$value|g")
    done
    args+=(-e "s|@name@|$NAME|g" -e "s|@label@|$LABEL|g" -e "s|@scheme@|$SCHEME|g")
    local i
    for i in "${!ANSI[@]}"; do
        args+=(-e "s|@ansi$i@|${ANSI[$i]}|g")
        args+=(-e "s|@raw:ansi$i@|${ANSI[$i]#\#}|g")
    done
    sed "${args[@]}" "$src"
}

# 생성물은 반드시 이 함수를 거쳐 나간다. 머리 세 줄이 마커이고,
# 세 번째 줄의 해시는 본문 전체를 덮는다. 5절이 이 값을 쓴다.
emit() {
    local dest="$1" comment="$2" body
    body=$(cat)
    local sum
    sum=$(printf '%s\n' "$body" | sha256sum | cut -d' ' -f1)
    mkdir -p "$(dirname "$dest")"
    {
        printf '%s generated by bin/theme from theme/palettes/%s.json\n' "$comment" "$NAME"
        printf '%s hand edits are lost on the next build: edit the palette instead\n' "$comment"
        printf '%s theme-body-sha256: %s\n' "$comment" "$sum"
        printf '%s\n' "$body"
    } > "$dest.tmp"
    mv -T "$dest.tmp" "$dest"
}
```

### 3.4 어려운 것 하나: kdeglobals 색 블록

`kde/kdeglobals`의 색 부분은 92칸이지만 서로 다른 값은 10개뿐이고, 일곱 개 블록이 두 칸(`BackgroundNormal`, `BackgroundAlternate`)만 다르고 나머지 열 칸은 완전히 같다. 즉 손으로 쓰기에는 반복이 너무 많고 생성하기에는 규칙이 아주 단순하다. 생성기가 가장 크게 이기는 자리다.

```bash
# 일곱 블록 가운데 여섯이 이 모양이다. 배경 두 칸만 인자로 받는다.
kde_block() {
    local section="$1" normal="$2" alternate="$3"
    cat <<EOF
[Colors:$section]
BackgroundNormal=$(rgb "$normal")
BackgroundAlternate=$(rgb "$alternate")
DecorationFocus=$(rgb "$R_accent")
DecorationHover=$(rgb "$R_tone4")
ForegroundNormal=$(rgb "$R_fg")
ForegroundActive=$(rgb "$R_accent")
ForegroundInactive=$(rgb "$R_dim")
ForegroundLink=$(rgb "$R_tone4")
ForegroundVisited=$(rgb "$R_tone1")
ForegroundNegative=$(rgb "$R_critical")
ForegroundNeutral=$(rgb "$R_caution")
ForegroundPositive=$(rgb "$R_positive")

EOF
}

# 선택 블록만 다르다. 배경이 강조색으로 칠해지므로 그 위의 글자가
# 전부 ink 로 뒤집힌다. 뜻이 있는 세 색은 뒤집지 않는다. 오류 문구는
# 선택된 행 안에서도 오류로 읽혀야 한다.
kde_selection_block() {
    cat <<EOF
[Colors:Selection]
BackgroundNormal=$(rgb "$R_accent")
BackgroundAlternate=$(rgb "$R_accent")
DecorationFocus=$(rgb "$R_accent")
DecorationHover=$(rgb "$R_tone4")
ForegroundNormal=$(rgb "$R_ink")
ForegroundActive=$(rgb "$R_ink")
ForegroundInactive=$(rgb "$R_ink")
ForegroundLink=$(rgb "$R_ink")
ForegroundVisited=$(rgb "$R_ink")
ForegroundNegative=$(rgb "$R_critical")
ForegroundNeutral=$(rgb "$R_caution")
ForegroundPositive=$(rgb "$R_positive")

EOF
}

# 색 부분 전체. .colors 파일과 kdeglobals 가 같은 함수를 쓴다.
# 조사에서 지적된 "두 파일이 어긋나면 이름으로 다시 적용하는 순간
# 화면이 튄다"는 위험이 구조적으로 사라진다.
kde_colors() {
    cat <<EOF
[General]
ColorScheme=$SCHEME_ID
Name=$LABEL

EOF
    kde_block Window        "$R_bg"      "$R_surface"
    kde_block View          "$R_bg"      "$R_surface"
    kde_block Button        "$R_surface" "$R_bg"
    kde_selection_block
    kde_block Tooltip       "$R_surface" "$R_bg"
    kde_block Complementary "$R_surface" "$R_bg"
    kde_block Header        "$R_surface" "$R_bg"

    cat <<EOF
[WM]
activeBackground=$(rgb "$R_surface")
activeForeground=$(rgb "$R_fg")
inactiveBackground=$(rgb "$R_bg")
inactiveForeground=$(rgb "$R_dim")
activeBlend=$(rgb "$R_accent")
inactiveBlend=$(rgb "$R_dim")

[ColorEffects:Disabled]
Color=$(rgb "$R_dim")
ColorAmount=0
ColorEffect=0
ContrastAmount=0.65
ContrastEffect=1
IntensityAmount=0
IntensityEffect=0

[ColorEffects:Inactive]
ChangeSelectionColor=false
Enable=false
Color=$(rgb "$R_dim")
ColorAmount=0
ColorEffect=0
ContrastAmount=0
ContrastEffect=0
IntensityAmount=0
IntensityEffect=0
EOF
}

# ~/.config/kdeglobals 가 될 파일. 색이 아닌 부분은 템플릿에서 온다.
# theme/templates/kdeglobals.head 에는 지금 kde/kdeglobals 의 1~34행,
# 168~177행이 들어간다. 글꼴, widgetStyle, 아이콘 테마, 소리 테마다.
build_kdeglobals() {
    { cat "$TEMPLATES/kdeglobals.head"; echo; kde_colors; } \
        | emit "$OUT/$NAME/kdeglobals" '#'
}

# 색 구성 등록본. 응용 프로그램은 읽지 않는다. 시스템 설정 목록에
# 이름이 뜨게 하는 것과, plasma-apply-colorscheme 이 이름으로
# 찾아갈 대상이 되는 것, 두 가지 용도뿐이다.
build_kde_scheme() {
    kde_colors | emit "$OUT/$NAME/$SCHEME_ID.colors" '#'
}
```

### 3.5 어려운 것 둘: quickshell 팔레트

바 쪽은 파일을 만들어 내는 일 자체는 가장 싸다. `roles` 객체를 그대로 뽑아 쓰면 된다.

```bash
build_quickshell() {
    jq --arg name "$NAME" --arg scheme "$SCHEME" \
       '{ name: $name, scheme: $scheme, roles: .roles }' \
       "$PALETTES/$NAME.json" > "$OUT/$NAME/palette.json.tmp"
    mv -T "$OUT/$NAME/palette.json.tmp" "$OUT/$NAME/palette.json"
}
```

주석을 넣을 수 없는 형식이므로 마커는 `emit`이 아니라 JSON 키로 넣는다. `jq`에 `_generated` 필드를 하나 더 붙이면 되고 `Theme.qml`은 모르는 키를 무시한다.

어려운 쪽은 `Theme.qml`을 어떻게 고치느냐다. 조사가 권한 대로 런타임 읽기를 택한다. 파일이 없거나 절반만 쓰였을 때의 바닥값은 QML 안에 리터럴로 남기고, 그 리터럴이 `theme/palettes/spaceduck.json`과 어긋나는 것을 막기 위해 마커 블록으로 감싸 생성 대상으로 삼는다. 이 블록만은 `set`이 아니라 `sync-fallback`이 쓰고 커밋된다.

`quickshell/bar/services/Theme.qml`의 84행부터 115행이 아래로 바뀐다.

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // 팔레트는 이 저장소의 QML 밖에 산다. 테마 전환이 추적되는 소스를
    // 고치는 일이 아니라 파일 하나를 쓰는 일이 되어야 하기 때문이다.
    // config 가 아니라 state 에 두는 이유는 생성물이기 때문이고, 설정
    // 디렉터리 안에 두면 quickshell 자신의 감시자가 셸 전체를 다시 올린다.
    readonly property string palettePath:
        (Quickshell.env("XDG_STATE_HOME") ?? `${Quickshell.env("HOME")}/.local/state`)
        + "/theme/palette.json"

    // palette 보다 먼저 선언한다. 즉시 평가되는 바인딩이 아직 만들어지지
    // 않은 id 를 참조하는 상황을 아예 만들지 않기 위한 것이다.
    FileView {
        id: paletteFile

        path: root.palettePath
        // 동기로 읽는다. 비동기로 읽으면 첫 프레임이 바닥값으로 그려진
        // 뒤 색 바인딩 85 개가 다시 돌고, Pill.qml:38-43 의 90ms 색
        // 애니메이션 때문에 그것이 시작 직후의 색 번짐으로 보인다.
        blockLoading: true
        watchChanges: true

        onFileChanged: {
            paletteFile.reload();
            root.palette = root.readPalette();
        }

        // 파일이 없다는 것은 theme set 이 아직 한 번도 돌지 않았다는
        // 뜻뿐이다. 그 밖의 실패는 화면의 색을 믿을 수 없다는 뜻이다.
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                console.warn("[theme] palette load failed:", error);
        }
    }

    // bin/theme set 이 파일을 갈아 끼운 직후 부르는 확정 경로.
    // mv -T 는 아이노드를 바꾸므로 감시자가 그것을 따라가는지는
    // 미확인이고, 이 경로가 그 불확실성을 덮는다.
    IpcHandler {
        target: "theme"

        function reload(): void {
            paletteFile.reload();
            root.palette = root.readPalette();
        }
    }

    property var palette: root.readPalette()

    function readPalette(): var {
        try {
            return JSON.parse(paletteFile.text())?.roles ?? ({});
        } catch (e) {
            return ({});
        }
    }

    // ------------------------------------------------------------------
    // 아래 리터럴은 팔레트를 읽지 못했을 때의 바닥값이고, 그 자체로
    // 완결된 spaceduck 한 벌이다. 손으로 고치지 않는다.
    // bin/theme sync-fallback 이 theme/palettes/spaceduck.json 에서
    // 다시 쓰고, bin/theme check 가 어긋남을 잡는다.
    // ------------------------------------------------------------------
    // THEME-FALLBACK-BEGIN
    readonly property color bg:       root.palette.bg       ?? "#0f111b"
    readonly property color surface:  root.palette.surface  ?? "#1b1c36"
    readonly property color border:   root.palette.border   ?? "#686f9a"
    readonly property color fg:       root.palette.fg       ?? "#ecf0c1"
    readonly property color dim:      root.palette.dim      ?? "#686f9a"
    readonly property color fill:     root.palette.fill     ?? "#ecf0c1"
    readonly property color ink:      root.palette.ink      ?? "#0f111b"
    readonly property color accent:   root.palette.accent   ?? "#7aa2f7"
    readonly property color positive: root.palette.positive ?? "#9ece6a"
    readonly property color caution:  root.palette.caution  ?? "#e0af68"
    readonly property color critical: root.palette.critical ?? "#f7768e"
    readonly property color tone1:    root.palette.tone1    ?? "#bb9af7"
    readonly property color tone2:    root.palette.tone2    ?? "#7a5ccc"
    readonly property color tone3:    root.palette.tone3    ?? "#f2ce00"
    readonly property color tone4:    root.palette.tone4    ?? "#7dcfff"
    readonly property color tone5:    root.palette.tone5    ?? "#ff9e64"
    readonly property color tone6:    root.palette.tone6    ?? "#c0caf5"
    // THEME-FALLBACK-END
}
```

바닥값 블록을 다시 쓰는 쪽이다.

```bash
sync_fallback() {
    load_palette spaceduck
    local qml="$SRC/quickshell/bar/services/Theme.qml"
    local body="" role
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        body+=$(printf '    readonly property color %-8s root.palette.%-8s ?? "%s"\n' \
                       "$role:" "$role" "$value")
        body+=$'\n'
    done
    awk -v block="$body" '
        /THEME-FALLBACK-BEGIN/ { print; printf "%s", block; skip = 1; next }
        /THEME-FALLBACK-END/   { skip = 0 }
        !skip                  { print }
    ' "$qml" > "$qml.tmp"
    mv -T "$qml.tmp" "$qml"
}
```

**소비자 QML 18개를 고치는 일이 따로 있다.** 속성 이름이 바뀌므로 `Theme.bgAlt`는 `Theme.surface`로, `Theme.muted`는 `Theme.dim`으로, `Theme.beige`는 `Theme.fill`로, `Theme.accentIndigo`는 `Theme.accent`로 바뀐다. 순수한 이름 바꾸기이고 `sed`로 끝난다. 함께 고쳐야 하는 것이 흰색 리터럴 다섯 곳이다.

```
quickshell/bar/modules/PopupMenu.qml:136   Qt.rgba(1, 1, 1, 0.09)
quickshell/bar/modules/PopupMenu.qml:143   Qt.rgba(1, 1, 1, 0.1)
quickshell/bar/modules/PowerMenu.qml:211   Qt.rgba(1, 1, 1, 0.05)
quickshell/bar/modules/Osd.qml:159         Qt.rgba(1, 1, 1, 0.12)
quickshell/bar/modules/Launcher.qml:322    Qt.rgba(1, 1, 1, 0.08)
```

이 다섯은 "바탕보다 살짝 밝은 면"을 뜻하므로 `Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.09)` 꼴로 바꾼다. 밝은 테마에서 `fg`가 어두워지면 이 면도 같이 어두워져 여전히 대비가 생긴다. 흰색으로 두면 밝은 테마에서 그대로 사라진다.

`Theme.qml:267`의 `batteryColor`와 `312`의 `loadColor`는 손으로 남는다. 값이 아니라 규칙이고, 참조하는 이름만 새 역할 이름으로 바꾸면 된다.

### 3.6 나머지 소비자 전부

| 소비자 | 만드는 파일 | 실제 위치 | 거는 방법 | 반영 |
|---|---|---|---|---|
| Qt / KDE 앱 (Dolphin) | `kdeglobals` | `~/.config/kdeglobals` | 복사 | `plasma-apply-colorscheme` 신호 |
| KDE 색 구성 등록본 | `<Label>.colors` | `~/.local/share/color-schemes/` | 복사 | 없음 |
| GTK3 앱 (swappy) | `gtk-colors.css` | `~/.config/gtk-3.0/colors.css` | 복사 | colorreload 모듈이 즉시 |
| GTK4 앱 | `gtk-colors.css` | `~/.config/gtk-4.0/colors.css` | 복사 | 앱 재시작 |
| libadwaita 앱 | `gtk4.css` | `~/.config/gtk-4.0/gtk.css` | 복사 | 앱 재시작 |
| swappy 주석 색 | `swappy.config` | `~/.config/swappy/config` | 복사 | 다음 실행 |
| slurp 오버레이 | `slurp.env` | 링크 경유 | `capture.sh`가 읽음 | 다음 캡처 |
| hyprlock | `hyprlock.conf` | `~/.config/hypr/palette.conf` | 복사 | 다음 잠금 |
| Hyprland 테두리 | `hypr-palette.lua` | `~/.config/hypr/palette.lua` | 복사 | `hyprctl eval`, 미확인 |
| fuzzel | `fuzzel-theme.ini` | `~/.config/fuzzel/theme.ini` | 복사 | 다음 실행 |
| fcitx5 후보창 | `fcitx5-theme.conf` | `~/.local/share/fcitx5/themes/custom/theme.conf` | 복사 | `fcitx5-remote -r` |
| kitty | `kitty.conf` | 링크 경유 | `include` | 약 0.1초 뒤 자동 |
| tmux | `tmux.conf` | 링크 경유 | `source-file -q` | `tmux source-file` |
| zsh fzf, caps lock | `fzf.env` | 링크 경유 | `zshrc`가 읽음 | 새 셸 |
| quickshell 바 | `palette.json` | `~/.local/state/theme/palette.json` | 복사 | `qs ipc call` |

링크 경유란 `~/.local/state/theme/current`가 `theme/out/<name>/`을 가리키는 심볼릭 링크이고 소비자가 그 아래 절대 경로를 읽는다는 뜻이다. `theme set`이 링크만 갈아 끼우면 그 아래 파일이 통째로 바뀐다.

**복사해야 하는 이유가 소비자마다 다르다.** `~/.config/kdeglobals`는 `plasma-apply-colorscheme`이 KConfig의 `QSaveFile`로 다시 쓰는데 그것이 심볼릭 링크를 따라가는지가 미확인이라, 실파일로 두면 그 미확인 자체가 없어진다. `~/.config/gtk-3.0/colors.css`는 `libcolorreload-gtk-module.so`가 그 경로를 `g_file_monitor_file`로 감시하고 있어서 아이노드가 아니라 경로 자체가 살아 있어야 한다. `~/.config/hypr/palette.lua`는 `hyprland.lua:16`이 계산한 `CONFIG` 아래 고정 경로여야 `load_module`이 찾는다.

**Hyprland 쪽에 필요한 손질.** `hypr/hyprland.lua`의 57행 앞에 팔레트 로딩을 넣는다.

```lua
-- 색은 config/ 밖에서 온다. bin/theme 가 쓰는 유일한 hypr 파일이고,
-- config/ 안에 두면 손으로 쓰는 파일과 생성물이 같은 디렉터리에 섞인다.
local palette = CONFIG .. "/palette.lua"
if file_exists(palette) then
    local chunk = loadfile(palette)
    if chunk ~= nil then
        pcall(chunk)
    end
end
PALETTE = PALETTE or { accent = "rgba(5ccc96ff)", clear = "rgba(00000000)" }

load_module("env")
```

`hypr/config/general.lua:25-26`과 `hypr/config/rules.lua:16`이 그 전역을 쓴다.

```lua
            active_border = PALETTE.accent,
            inactive_border = PALETTE.clear,
```

```lua
hl.window_rule({ match = { pin = true }, border_color = PALETTE.accent .. " " .. PALETTE.clear })
```

**hyprlock 쪽에 필요한 손질.** `hypr/hyprlock.conf` 맨 위에 한 줄을 넣고 13개 리터럴을 변수로 바꾼다.

```
source = ~/.config/hypr/palette.conf
```

생성되는 `~/.config/hypr/palette.conf`는 이렇다. Pango 마크업이 들어가는 두 자리는 값의 일부만 치환하는 대신 문자열 전체를 변수 하나에 담는다. 변수 확장이 문자열 안쪽에서도 도는지가 미확인이므로 확실한 쪽을 고른 것이다.

```
$bgColor        = rgba(@raw:surface@ff)
$fieldOuter     = rgba(@raw:border@ff)
$fieldInner     = rgba(@raw:surface@cc)
$fieldText      = rgba(@raw:fg@ff)
$fieldCheck     = rgba(@raw:tone4@ff)
$fieldFail      = rgba(@raw:critical@ff)
$fieldCapsLock  = rgba(@raw:critical@ff)
$clockColor     = rgba(@raw:fg@ff)
$dateColor      = rgba(@raw:tone6@ff)
$hostColor      = rgba(@raw:dim@ff)
$placeholderText = <span foreground="@pango:dim@">password</span>
$failText        = <span foreground="@pango:critical@">$FAIL</span>
```

**터미널 저장소 쪽에 필요한 손질.** `dotfiles-terminal`은 `dotfiles-desktop`이 없어도 혼자 서야 하므로, 바닥값을 먼저 읽고 생성물을 뒤에 덮는 구조로 만든다.

`kitty/kitty.conf`의 2행 다음에 한 줄을 더한다.

```
include ./spaceduck.conf
include ~/.local/state/theme/current/kitty.conf
```

파일이 없으면 kitty가 stderr에 한 줄을 남기고 넘어가며 spaceduck이 그대로 남는다. `tmux/tmux.conf` 끝에는 `source-file -q`를 쓴다. `-q`가 없는 파일을 조용히 넘긴다.

```
source-file -q ~/.local/state/theme/current/tmux.conf
```

`zsh/zshrc`의 176~177행 Catppuccin 값은 지운다. 두 저장소를 통틀어 팔레트에서 가장 크게 벗어난 자리였다.

```zsh
# fzf 와 caps lock 세그먼트의 색은 데스크톱 저장소의 bin/theme 가 만든다.
# 없으면 색 없이 도는 것이 색이 어긋난 채로 도는 것보다 낫다.
[[ -r ~/.local/state/theme/current/fzf.env ]] && source ~/.local/state/theme/current/fzf.env
```

`zsh/config/caps-lock.zsh:111`이 그 파일이 정의한 변수를 쓴다.

```zsh
  p10k segment -c '$_capslock_on' \
    -b "${THEME_CRITICAL:-#f7768e}" -f "${THEME_INK:-#0f111b}" \
    -i $'\U000F033E' -t 'CAPS LOCK'
```

**capture.sh 쪽에 필요한 손질.** `hypr/scripts/capture.sh:88`의 `slurp -d`가 색 인자를 받는다.

```sh
        # slurp 는 설정 파일이 없고 색을 인자로만 받는다. 파일이 없으면
        # 인자 없이 도는 지금 동작 그대로 남는다.
        slurp_args=(-d)
        if [[ -r "$HOME/.local/state/theme/current/slurp.env" ]]; then
            # shellcheck source=/dev/null
            . "$HOME/.local/state/theme/current/slurp.env"
            slurp_args+=(-b "$SLURP_BG" -c "$SLURP_BORDER" -s "$SLURP_SELECTION" -w 2 -F Inter)
        fi
        geom=$(slurp "${slurp_args[@]}" 2>/dev/null) || exit 0
```

**GTK 쪽에서 정해야 하는 것.** 조사가 낸 선택지 두 개 가운데 B를 택한다. kded6의 gtkconfig 모듈을 끄고 `colors.css`를 우리가 만든다. 이유는 두 가지다. 그 모듈은 `~/.config/gtk-3.0/settings.ini` 링크를 실파일로 갈아치우고(`settings.ini.bak-20260825-190746`이 그 흔적으로 보인다), kdeglobals에서 GTK 이름으로 가는 대응 규칙을 우리가 통제할 수 없다. `install.sh`가 `~/.config/kded6rc`에 다음을 넣는다.

```ini
[Module-gtkconfig]
autoload=false
```

모듈 식별자가 `gtkconfig`인 것은 `/usr/lib/qt6/plugins/kf6/kded/gtkconfig.so`라는 파일 이름에서 추론한 것이고 이 기계에서 확인하지 않았다. `theme set` 뒤 `~/.config/gtk-3.0/settings.ini`가 여전히 링크인지 보면 바로 확인된다.

`theme/templates/gtk-colors.css.in`은 `_breeze` 이름 78개를 정의한다. `/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css`가 그 78개를 선언하고 나머지 4465행이 전부 그 이름을 참조하므로, 이름만 다시 선언하면 규칙을 한 줄도 쓰지 않고 테마 전체가 다시 칠해진다. GTK4판의 이름 집합이 GTK3판과 완전히 같다는 것은 확인했으므로 파일 하나를 두 곳에 복사하면 된다. 대응의 뼈대는 이렇다.

```css
@define-color theme_fg_color_breeze @fg@;
@define-color theme_text_color_breeze @fg@;
@define-color theme_bg_color_breeze @bg@;
@define-color theme_base_color_breeze @bg@;
@define-color content_view_bg_breeze @bg@;
@define-color borders_breeze @border@;
@define-color theme_button_background_normal_breeze @surface@;
@define-color theme_button_foreground_normal_breeze @fg@;
@define-color theme_selected_bg_color_breeze @accent@;
@define-color theme_selected_fg_color_breeze @ink@;
@define-color theme_hovering_selected_bg_color_breeze @tone4@;
@define-color theme_view_hover_decoration_color_breeze @tone4@;
@define-color theme_view_active_decoration_color_breeze @accent@;
@define-color theme_titlebar_background_breeze @surface@;
@define-color theme_titlebar_foreground_breeze @fg@;
@define-color tooltip_background_breeze @surface@;
@define-color tooltip_border_breeze @border@;
@define-color tooltip_text_breeze @fg@;
@define-color link_color_breeze @tone4@;
@define-color link_visited_color_breeze @tone1@;
@define-color error_color_breeze @critical@;
@define-color warning_color_breeze @caution@;
@define-color success_color_breeze @positive@;
@define-color insensitive_fg_color_breeze @dim@;
@define-color insensitive_bg_color_breeze @surface@;
@define-color print_paper_backdrop_breeze @fill@;
/* 나머지 unfocused_*, backdrop_*, insensitive_* 계열은 위 값을 그대로
   되쓴다. 창이 포커스를 잃었다고 글자를 흐리는 동작은 kdeglobals 의
   [ColorEffects:Inactive] 를 끈 것과 같은 이유로 끈다. */
```

지금 살아 있는 `~/.config/gtk-3.0/colors.css`가 정의한 `theme_header_*_breeze` 7개는 현재 Breeze-Dark에 없는 이름이고(지금은 `theme_titlebar_*`다) 아무 효과가 없다. 새 템플릿에는 넣지 않는다.

`theme/templates/gtk4.css.in`은 libadwaita 이름을 따로 선언한다. libadwaita 앱은 `gtk-theme-name`을 아예 무시하고 `_breeze` 이름도 모른다.

```css
@define-color window_bg_color @bg@;
@define-color window_fg_color @fg@;
@define-color view_bg_color @bg@;
@define-color view_fg_color @fg@;
@define-color headerbar_bg_color @surface@;
@define-color headerbar_fg_color @fg@;
@define-color card_bg_color @surface@;
@define-color card_fg_color @fg@;
@define-color sidebar_bg_color @surface@;
@define-color sidebar_fg_color @fg@;
@define-color popover_bg_color @surface@;
@define-color popover_fg_color @fg@;
@define-color dialog_bg_color @surface@;
@define-color dialog_fg_color @fg@;
@define-color accent_bg_color @accent@;
@define-color accent_fg_color @ink@;
@define-color accent_color @accent@;
@define-color destructive_bg_color @critical@;
@define-color destructive_fg_color @ink@;
@define-color warning_bg_color @caution@;
@define-color warning_fg_color @ink@;
@define-color success_bg_color @positive@;
@define-color success_fg_color @ink@;

@import 'colors.css';
```

### 3.7 build 와 set

```bash
cmd_build() {
    local names=("$@")
    (( ${#names[@]} )) || mapfile -t names < <(cd "$PALETTES" && ls *.json | sed 's/\.json$//')

    local name
    for name in "${names[@]}"; do
        load_palette "$name"
        mkdir -p "$OUT/$NAME"
        guard_hand_edits "$OUT/$NAME"

        build_kdeglobals
        build_kde_scheme
        build_quickshell
        render "$TEMPLATES/gtk-colors.css.in"    | emit "$OUT/$NAME/gtk-colors.css"     '/*!'
        render "$TEMPLATES/gtk4.css.in"          | emit "$OUT/$NAME/gtk4.css"           '/*!'
        render "$TEMPLATES/hyprlock.conf.in"     | emit "$OUT/$NAME/hyprlock.conf"      '#'
        render "$TEMPLATES/hypr-palette.lua.in"  | emit "$OUT/$NAME/hypr-palette.lua"   '--'
        render "$TEMPLATES/swappy.config.in"     | emit "$OUT/$NAME/swappy.config"      '#'
        render "$TEMPLATES/slurp.env.in"         | emit "$OUT/$NAME/slurp.env"          '#'
        render "$TEMPLATES/fuzzel-theme.ini.in"  | emit "$OUT/$NAME/fuzzel-theme.ini"   '#'
        render "$TEMPLATES/fcitx5-theme.conf.in" | emit "$OUT/$NAME/fcitx5-theme.conf"  '#'
        render "$TEMPLATES/kitty.conf.in"        | emit "$OUT/$NAME/kitty.conf"         '#'
        render "$TEMPLATES/tmux.conf.in"         | emit "$OUT/$NAME/tmux.conf"          '#'
        render "$TEMPLATES/fzf.env.in"           | emit "$OUT/$NAME/fzf.env"            '#'
        echo "built $OUT/$NAME"
    done
}

cmd_set() {
    local name="${1:?theme set <name>}"
    load_palette "$name"
    local out="$OUT/$NAME"
    [[ -d "$out" ]] || die "$out does not exist: run 'theme build $NAME' first"

    # 1. 링크 하나로 따라오는 것들. 원자적이다.
    mkdir -p "$STATE/theme"
    ln -sfn "$out" "$STATE/theme/current.new"
    mv -T "$STATE/theme/current.new" "$STATE/theme/current"

    # 2. 실파일이어야 하는 것들. install 은 mv 와 달리 감시자가 붙어 있는
    #    경로를 유지하면서 내용만 바꾼다.
    install -Dm644 "$out/palette.json"       "$STATE/theme/palette.json"
    install -Dm644 "$out/kdeglobals"         "$CONFIG/kdeglobals"
    install -Dm644 "$out/gtk-colors.css"     "$CONFIG/gtk-3.0/colors.css"
    install -Dm644 "$out/gtk-colors.css"     "$CONFIG/gtk-4.0/colors.css"
    install -Dm644 "$out/gtk4.css"           "$CONFIG/gtk-4.0/gtk.css"
    install -Dm644 "$out/hyprlock.conf"      "$CONFIG/hypr/palette.conf"
    install -Dm644 "$out/hypr-palette.lua"   "$CONFIG/hypr/palette.lua"
    install -Dm644 "$out/swappy.config"      "$CONFIG/swappy/config"
    install -Dm644 "$out/fuzzel-theme.ini"   "$CONFIG/fuzzel/theme.ini"
    install -Dm644 "$out/$SCHEME_ID.colors"  "$DATA/color-schemes/$SCHEME_ID.colors"
    install -Dm644 "$out/fcitx5-theme.conf"  "$DATA/fcitx5/themes/custom/theme.conf"
    local png
    for png in arrow next prev radio; do
        [[ -e "$DATA/fcitx5/themes/custom/$png.png" ]] \
            || cp "/usr/share/fcitx5/themes/default-dark/$png.png" \
                  "$DATA/fcitx5/themes/custom/$png.png"
    done

    printf '%s\n' "$NAME" > "$STATE/theme/name"

    # 3. 신호. 전부 실패해도 무방하다. 다음 실행 때 맞는다.
    qs -p "$CONFIG/quickshell/bar" ipc call theme reload  >/dev/null 2>&1 || true
    plasma-apply-colorscheme "$SCHEME_ID"                 >/dev/null 2>&1 || true
    fcitx5-remote -r                                      >/dev/null 2>&1 || true
    tmux source-file "$STATE/theme/current/tmux.conf"      >/dev/null 2>&1 || true

    # gsettings 는 밝기가 뒤집힐 때만 만진다. 테마 이름은 건드리지 않는다.
    if [[ "$SCHEME" == light ]]; then
        gsettings set org.gnome.desktop.interface color-scheme default  2>/dev/null || true
    else
        gsettings set org.gnome.desktop.interface color-scheme prefer-dark 2>/dev/null || true
    fi

    apply_hypr_border
    echo "theme: $LABEL"
}

# hyprctl keyword 는 이 기계에서 쓸 수 없다. Hyprland 바이너리에
# "keyword can't work with non-legacy parsers. Use eval." 이 들어 있고
# 이 설정은 Lua 다. eval 이 남는 유일한 경로이고, 실행 시점에 실제로
# 반영되는지는 미확인이므로 결과를 읽어서 확인한 뒤 보고한다.
apply_hypr_border() {
    command -v hyprctl >/dev/null 2>&1 || return 0
    hyprctl eval "hl.config({ general = { col = {
        active_border = \"rgba(${R_accent#\#}ff)\",
        inactive_border = \"rgba(00000000)\" } } })" >/dev/null 2>&1 || true

    local got
    got=$(hyprctl getoption general:col.active_border 2>/dev/null | grep -o 'ff[0-9a-f]\{6\}' | head -1)
    if [[ "$got" == "ff${R_accent#\#}" ]]; then
        return 0
    fi
    echo "theme: window border unchanged; run 'hyprctl reload' or relogin" >&2
}
```

### 3.8 스크립트가 하면 안 되는 것

- **`hyprctl reload`를 스스로 부르지 않는다.** `hypr/config/execs.lua:5-7`과 `hypr/scripts/session-autostart.sh:5-10`이 적어 두었듯 리로드는 exec 블록 전체를 다시 돌린다. `hypr/scripts/auto_monitors.sh:39`는 리로드가 꺼 둔 노트북 패널을 다시 켠다고 적는다. 색 두 개를 위해 모니터 구성과 자동 시작을 다시 밟는 것은 비싼 값이다. `--reload-hypr`로 명시적으로 요구할 때만 부른다.
- **모드 설정을 건드리지 않는다.** `hl.monitor`, 해상도, 스케일, 출력 켜고 끄기는 이 스크립트의 관할이 아니다. 이 기계는 `xe` 드라이버의 원자적 커밋 문제로 GRUB 커맨드라인 우회를 걸어 둔 상태이고, 색을 바꾸다가 모드 설정을 밟으면 화면이 죽는다.
- **바를 재시작하지 않는다.** `bin/bar`에는 `--restart`가 없고 `--stop`(`bin/bar:124-158`)은 슈퍼바이저까지 죽인다. IPC 호출이 실패하면 그냥 다음 기동 때 읽히게 둔다.
- **fcitx5를 재시작하지 않는다.** `hypr/scripts/session-autostart.sh:113-115`가 적듯 재시작하면 떠 있는 모든 클라이언트가 입력 컨텍스트를 잃는다. `fcitx5-remote -r`는 재적재이지 재시작이 아니다.
- **`gsettings set gtk-theme` / `icon-theme` / `cursor-theme`를 건드리지 않는다.** 그 셋은 `hypr/scripts/gsettings-apply.sh:44-46`의 관할이고 팔레트와 무관하다. `color-scheme` 한 줄만 예외다.
- **벽지를 바꾸지 않는다.** `hyprpaper.conf`와 `~/Pictures/Wallpapers/current.png`는 사용자 상태다. 벽지에서 색을 뽑는 방향은 이 설계가 명시적으로 거부한 것이다.
- **세션을 끝내지 않는다.** 로그아웃이나 재로그인을 유도하지 않고, 재시작이 필요한 것은 필요하다고 말하고 끝낸다.
- **손으로 고쳐진 생성물을 조용히 덮지 않는다.** 5절의 마커 검사가 걸리면 `build`는 멈춘다.

---

## 4. 전환할 때 실제로 일어나는 일

`theme set macos-dark`를 실행한 순간부터의 순서다.

**0단계, 검증.** 팔레트를 읽고 역할 17개가 전부 `#rrggbb`인지 확인한다. `theme/out/macos-dark/`가 없으면 여기서 멈춘다. 화면에는 아무 변화도 없다.

**1단계, 링크 교체.** `~/.local/state/theme/current`가 `theme/out/macos-dark/`를 가리킨다. `mv -T`라 중간 상태가 없다.

이 순간 **kitty가 바뀐다.** `auto_reload_config`의 기본값이 0.1초이고(`/usr/share/doc/kitty/html/_downloads/433dadebd0bf504f8b008985378086ce/kitty.conf:2113`) 감시 대상은 `include`로 끌어온 파일 전부이므로, 떠 있는 모든 kitty 창이 0.1초 안에 다시 칠해진다. 사용자가 보는 것은 터미널 배경과 프롬프트 색이 한 번에 넘어가는 모습이다. 단서 하나가 있다. kitty가 시작될 때 `kitty.conf`가 이미 있었어야 자동 재적재가 돈다.

다음 캡처부터 **slurp 오버레이**가 새 색으로 뜬다. 이미 떠 있는 선택 오버레이는 없다. slurp는 캡처마다 새로 뜨기 때문이다.

**2단계, 실파일 복사.** 열한 개 파일이 제자리에 놓인다. 복사가 끝나는 순서대로 다음이 일어난다.

`~/.config/gtk-3.0/colors.css`가 바뀌는 순간 **GTK3 앱 전부가 재시작 없이 다시 칠해진다.** `/usr/lib/gtk-3.0/modules/libcolorreload-gtk-module.so`가 그 경로 하나를 `g_file_monitor_file`로 감시하고 있고, `gtk/gtk-3.0-settings.ini:13`의 `gtk-modules=colorreload-gtk-module:...`이 이미 그 모듈을 켜 두었다. **여기가 사용자가 요청한 캡처 GUI가 따라오는 지점이다.** swappy는 `ldd /usr/bin/swappy`가 `libgtk-3.so.0`을 내는 GTK3 응용 프로그램이므로 헤더 바, 도구 패널, 버튼이 전부 이 한 파일을 따라온다. 주석 편집 창이 열려 있는 채로 테마를 바꿔도 그 자리에서 색이 바뀐다.

`~/.local/state/theme/palette.json`이 바뀌면 **quickshell 바**가 따라온다. `FileView.watchChanges`가 아이노드 교체를 잡는지는 미확인이므로 확정 경로는 4단계의 IPC다.

**3단계, 상태 기록.** `~/.local/state/theme/name`에 이름이 적힌다. `theme list`가 다음 실행에서 이 값을 읽는다.

**4단계, 신호 네 개.**

`qs -p ~/.config/quickshell/bar ipc call theme reload` — 바의 `IpcHandler`가 팔레트를 다시 읽고 `root.palette`를 다시 대입한다. 색 바인딩 85개가 재평가되고, `quickshell/bar/modules/Pill.qml:38-43`의 `ColorAnimation duration: 90` 덕분에 알약들이 90ms 크로스페이드로 넘어간다. 창이 다시 만들어지지 않고 "Reloading configuration..." 팝업도 뜨지 않는다. 사용자가 보는 것은 바가 부드럽게 색을 바꾸는 모습이다.

`plasma-apply-colorscheme <SchemeId>` — 이 실행 파일이 `/KGlobalSettings`의 `org.kde.KGlobalSettings.notifyChange`를 발신하고, `KDEPlasmaPlatformTheme6.so`가 그것을 받아 떠 있는 Qt/KDE 앱의 팔레트를 갈아 끼운다. **열려 있던 Dolphin 창이 그 자리에서 다시 칠해진다.** 파일만 고쳐 쓰면 이 일은 일어나지 않는다. KConfig의 `ConfigChanged` 신호는 KConfig API를 거쳐 쓸 때만 나가고, 스크립트가 텍스트를 덮어쓰면 아무 신호도 나가지 않기 때문이다. 이 명령이 `~/.config/kdeglobals`를 KConfig로 다시 쓰지만 내용이 방금 복사한 것과 같으므로 결과는 같다. `/org/kde/KWin/BlendChanges` 호출도 함께 나가는데 KWin 전용이라 Hyprland에서는 조용히 실패한다.

`fcitx5-remote -r` — `org.fcitx.Fcitx.Controller1`의 `ReloadConfig`를 부른다. 재시작이 아니므로 떠 있는 클라이언트의 입력 컨텍스트가 살아남는다. 다음 한글 입력부터 후보창이 새 색으로 뜬다.

`tmux source-file ~/.local/state/theme/current/tmux.conf` — 모든 tmux 세션의 상태줄이 즉시 바뀐다.

**5단계, Hyprland 테두리.** `hyprctl eval 'hl.config({...})'`를 부르고 `hyprctl getoption general:col.active_border`로 결과를 읽어 실제로 반영됐는지 확인한다. **이 경로가 먹히는지는 미확인이다.** `hyprctl keyword`는 이 기계에서 아예 못 쓴다. Hyprland 바이너리에 `keyword can't work with non-legacy parsers. Use eval.`과 `eval is only supported with the lua config manager`가 들어 있고, `parseKeyword`는 `/usr/include/hyprland/src/config/legacy/ConfigManager.hpp:76`에만 있고 Lua 쪽 헤더에는 없기 때문이다. 반영이 확인되지 않으면 스크립트가 그렇게 말하고 끝낸다. 사용자는 창 테두리만 옛 색으로 남은 상태를 본다. `hyprctl reload`나 재로그인으로 맞출 수 있다.

### 재시작 없이는 바뀌지 않는 것

정직하게 적는다.

**GTK4와 libadwaita 앱은 재시작해야 한다.** GTK4는 모듈 체계를 없앴고 `colorreload`에 해당하는 감시자가 패키지에 없다. GTK4 자체가 `~/.config/gtk-4.0/gtk.css`를 감시하는지는 미확인이다. `libgtk-4.so.1`에서 나오는 문자열은 판단 근거가 되지 못한다. 재시작이 필요하다고 보고 설계했다.

**셸은 새로 열어야 한다.** p10k는 셸이 뜰 때 한 번만 설정을 읽고 재적재 경로가 없다. `exec zsh` 또는 새 창이 필요하다. fzf 색도 마찬가지다.

**hyprlock은 다음 잠금부터다.** hyprlock에는 설정 재적재 경로가 없다. 바이너리의 `reload_time`과 `reload_cmd`는 `hyprlock.conf:74`의 `cmd[update:60000]` 같은 라벨 위젯용이고, `Unlocking with a SIGUSR1`은 잠금 해제용이다. 데몬이 상주하지 않으므로 보낼 신호 자체가 없다. 이것은 문제가 아니다. 다음에 잠글 때 맞는다.

**fuzzel과 swappy 주석 색은 다음 실행부터다.** 둘 다 호출마다 새로 뜬다. fuzzel 바이너리에는 `SIGUSR`도 `inotify`도 없다. swappy의 창 자체는 GTK3이라 즉시 따라오지만, `custom_color`(C 키에 묶인 주석 색)만은 시작할 때 읽으므로 다음 실행부터다.

**이미 떠 있는 창 가운데 어느 방식으로도 다시 칠할 수 없는 것이 있다.** 아이콘은 이미 렌더링된 이미지이고, Breeze의 GTK 에셋 PNG는 Breeze 파랑 `#3daee9`로 구워져 있다. 7절이 이 이야기다.

---

## 5. 저장소에 무엇이 커밋되는가

### 5.1 추적되는 것

```
theme/palettes/*.json          손으로 씀. 사람이 고르는 색이다
theme/templates/*.in           손으로 씀. 출력 형식이다
theme/templates/kdeglobals.head 손으로 씀. 글꼴과 widgetStyle 등 색이 아닌 부분
bin/theme                      손으로 씀
theme/default                  손으로 씀. 한 줄. 새 설치가 고르는 팔레트 이름
theme/out/<name>/*             생성됨. 마커가 붙는다
quickshell/bar/services/Theme.qml   손으로 씀 + 바닥값 블록만 생성됨
```

`theme/out/`을 추적하는 이유는 하나다. `install.sh`가 링크를 걸고 파일을 복사하는 순간에 그 내용이 이미 있어야 하고, 새로 체크아웃한 트리에서 `theme build`를 돌리려면 `jq`가 있어야 하는데 그 의존을 설치 단계로 미루면 설치가 실패할 수 있다. 산출물이 트리에 있으면 `install.sh`는 복사만 하면 되고, `theme build`는 팔레트를 고치는 사람만 돌린다.

`install.sh` 끝에 두 줄이 붙는다.

```bash
"$SRC/bin/theme" set "$(cat "$SRC/theme/default")"
"$SRC/bin/theme" check || echo "theme: generated files do not match the palettes" >&2
```

### 5.2 마커

생성된 파일을 누가 손으로 고치면 다음 `theme build`에 그 수정이 사라진다. 흔적도 남지 않는다. 이것이 생성기가 놓는 유일한 함정이고, 함정인 채로 두면 안 된다.

모든 생성물의 머리에 정확히 세 줄이 붙는다. 주석 문자만 형식에 맞춰 다르다.

```
# generated by bin/theme from theme/palettes/spaceduck.json
# hand edits are lost on the next build: edit the palette instead
# theme-body-sha256: 3f1c9a...  (본문 전체의 sha256, 64자)
```

세 번째 줄이 마커의 전부다. `theme build`는 덮어쓰기 전에 기존 파일의 4행 이하를 다시 해싱해서 기록된 값과 비교한다. 다르면 누군가 손으로 고쳤다는 뜻이므로 **멈춘다.**

```bash
# 손으로 고쳐진 생성물이 있으면 build 를 멈춘다. 조용히 덮으면 그 수정이
# 어디로 갔는지 아무도 알 수 없고, 다음에 색이 틀어졌을 때 원인을
# 찾을 실마리가 없다.
guard_hand_edits() {
    local dir="$1" f recorded actual
    shopt -s nullglob
    for f in "$dir"/*; do
        [[ "$(basename "$f")" == palette.json ]] && continue
        recorded=$(sed -n '3s/.*theme-body-sha256: //p' "$f")
        [[ -n "$recorded" ]] || die "$f has no marker: move it aside or delete it"
        actual=$(tail -n +4 "$f" | sha256sum | cut -d' ' -f1)
        if [[ "$recorded" != "$actual" ]]; then
            die "$f was edited by hand.
  the change is not in any palette and would be lost.
  copy what you want into $PALETTES/$NAME.json, then
  'theme build --force $NAME' to discard the file."
        fi
    done
    shopt -u nullglob
}
```

`--force`는 사람이 명시적으로 버리겠다고 말할 때만 통한다.

`palette.json`은 주석을 넣을 수 없는 형식이라 마커가 JSON 키로 들어간다. `_generated` 객체에 같은 세 정보를 담고, `Theme.qml`은 `.roles`만 읽으므로 무시한다.

`quickshell/bar/services/Theme.qml`은 생성물이 아니라 손으로 쓰는 파일이고, 그 안의 `THEME-FALLBACK-BEGIN` / `THEME-FALLBACK-END` 사이 17줄만 생성된다. 여기는 해시 마커 대신 `theme check`가 지킨다. 블록 안의 값과 `theme/palettes/spaceduck.json`의 역할표를 비교해서 다르면 실패한다. 두 번째 진실 원본이 생기는 것을 규율이 아니라 검사로 막는다.

```bash
cmd_check() {
    local failed=0 name
    for name in $(cd "$PALETTES" && ls *.json | sed 's/\.json$//'); do
        load_palette "$name"
        guard_hand_edits "$OUT/$NAME" || failed=1
    done

    # 바닥값 블록이 spaceduck 팔레트와 어긋나면 잡는다. 어긋난 채로 두면
    # 상태 파일을 못 읽은 바만 조용히 옛 색으로 뜨고 아무도 모른다.
    load_palette spaceduck
    local qml="$SRC/quickshell/bar/services/Theme.qml" role
    for role in "${ROLE_NAMES[@]}"; do
        local -n value="R_$role"
        awk -v r="$role" -v v="$value" '
            /THEME-FALLBACK-BEGIN/ { inblock = 1; next }
            /THEME-FALLBACK-END/   { inblock = 0 }
            inblock && $0 ~ ("property color " r ":") {
                found = 1
                if ($0 !~ ("\"" v "\"")) exit 1
            }
            END { if (!found) exit 1 }
        ' "$qml" || { echo "Theme.qml fallback for $role is not $value" >&2; failed=1; }
    done
    return $failed
}
```

### 5.3 추적되지 않는 것

`~/.local/state/theme/` 아래 전부다. `current` 링크, `palette.json`, `name`이 여기 있다. 세 개 모두 순수한 실행 시점 상태이고, 잃어버려도 `theme set`을 한 번 돌리면 복원된다.

### 5.4 삭제되어야 하는 것

matugen 잔존물이 저장소보다 우선하고 있어서 지금 GTK 앱은 저장소가 지시한 팔레트가 아니라 Material You 회보라로 그려진다. `install.sh`가 이 목록을 안내하되 지우지는 않는다. 사용자 파일을 스크립트가 지우는 것은 이 저장소의 성격이 아니다.

```
~/.config/matugen/                 템플릿과 설정. matugen 패키지 자체는 이미 없다
~/.config/gtk-3.0/window_decorations.css 와 assets/
~/.config/gtk-4.0/window_decorations.css 와 assets/
~/.config/fuzzel/fuzzel_theme.ini  새 이름은 theme.ini 다
~/.config/qt5ct/, ~/.config/qt6ct/, ~/.config/Kvantum/
~/.local/share/color-schemes/MaterialYou*.colors   8개
~/.config/xsettingsd/xsettingsd.conf 와 PID 237453 의 xsettingsd
```

`~/.config/gtk-3.0/gtk.css`와 `~/.config/gtk-4.0/colors.css`는 지우지 않는다. `theme set`이 덮어쓴다.

`~/.config/kdedefaults/kdeglobals`의 `ColorScheme=BreezeDark`도 새 이름으로 맞춰야 한다. 지금 `~/.config/kdeglobals`는 `SpaceduckDark`이고 둘이 어긋나 있어서, 무엇이든 이름으로 다시 적용하는 경로가 걸리면 화면 전체가 Breeze 파랑으로 튄다. `theme set`이 이 파일도 갱신하게 두는 것이 안전하다.

---

## 6. 첫 테마 두 개

### 6.1 spaceduck

지금 화면에 있는 색을 역할표로 옮긴 것이다. 전문은 2.2절에 있다. 값의 출처는 이렇다.

| 역할 | 값 | 어디서 왔는가 |
|---|---|---|
| `bg` | `#0f111b` | `Theme.qml:84`, `kitty/spaceduck.conf:17` |
| `surface` | `#1b1c36` | `Theme.qml:85`, `hyprlock.conf:26` |
| `border` | `#686f9a` | `hyprlock.conf:45` |
| `fg` | `#ecf0c1` | `Theme.qml:86`, `kitty/spaceduck.conf:18` |
| `dim` | `#686f9a` | `Theme.qml:87` |
| `fill` | `#ecf0c1` | `Theme.qml:114` beige |
| `ink` | `#0f111b` | `Theme.qml:115` |
| `accent` | `#7aa2f7` | `Theme.qml:110` accentIndigo. Hyprland 테두리가 이 값으로 옮겨 온다 |
| `positive` | `#9ece6a` | `Theme.qml:107` |
| `caution` | `#e0af68` | `Theme.qml:106` |
| `critical` | `#f7768e` | `Theme.qml:104`, `caps-lock.zsh:111` |
| `tone1` | `#bb9af7` | `Theme.qml:111`. `purple`(92행)을 흡수했다 |
| `tone2` | `#7a5ccc` | `Theme.qml:93` violet |
| `tone3` | `#f2ce00` | `Theme.qml:90` yellow |
| `tone4` | `#7dcfff` | `Theme.qml:109` accentSky |
| `tone5` | `#ff9e64` | `Theme.qml:105` accentOrange |
| `tone6` | `#c0caf5` | `Theme.qml:112` accentQuiet. `accentTeal`의 배터리 정상 자리를 넘겨받았다 |

바탕은 spaceduck 원본이고 강조는 Tokyo Night다. 조사가 지적한 두 갈래를 한쪽으로 정리하지 않고 그대로 안고 간다. 지금 화면이 그렇게 생겼고, 그것이 이 테마의 정체이기 때문이다. 정리는 새 테마를 만드는 일이지 spaceduck을 고치는 일이 아니다.

### 6.2 macos-dark

`~/workspace/dotfiles-desktop/theme/palettes/macos-dark.json`이다.

```json
{
  "name": "macos-dark",
  "label": "macOS Dark",
  "scheme": "dark",

  "roles": {
    "bg":       "#1c1c1e",
    "surface":  "#2c2c2e",
    "border":   "#3a3a3c",
    "fg":       "#f2f2f7",
    "dim":      "#8e8e93",
    "fill":     "#f2f2f7",
    "ink":      "#1c1c1e",

    "accent":   "#0a84ff",
    "positive": "#30d158",
    "caution":  "#ff9f0a",
    "critical": "#ff453a",

    "tone1":    "#bf5af2",
    "tone2":    "#5e5ce6",
    "tone3":    "#ffd60a",
    "tone4":    "#64d2ff",
    "tone5":    "#66d4cf",
    "tone6":    "#98989d"
  },

  "ansi": [
    "#1c1c1e", "#ff453a", "#30d158", "#ffd60a",
    "#0a84ff", "#bf5af2", "#64d2ff", "#d1d1d6",
    "#48484a", "#ff6961", "#58e06f", "#ffe14d",
    "#4da3ff", "#d68cf7", "#8fe0ff", "#f2f2f7"
  ]
}
```

spaceduck과 정말로 다르다는 것이 요점이다. 바탕이 남색을 완전히 잃고 중성 그레이파이트로 간다. 전경이 크림색에서 거의 흰색으로 간다. 강조가 인디고에서 시스템 블루로 간다. 그리고 `ansi` 배열에는 spaceduck이 일부러 넣어 둔 노랑과 보라의 스왑이 없다. 3번 자리에 노랑이, 5번 자리에 보라가 제자리로 들어간다. 이 한 가지만으로도 두 테마가 같은 형식을 쓰면서 서로 다른 규약을 담을 수 있는지가 시험된다.

`dim`이 `#8e8e93`, `tone6`이 `#98989d`로 둘 다 회색인 것은 의도한 것이다. macOS는 상태 표시를 색 대신 밝기로 구분하는 성향이 있고, 조용한 알약이 회색으로 앉는 것이 그 성향에 맞는다. `ink`가 `#1c1c1e`이므로 그 위의 글자는 여전히 읽힌다.

밝은 테마를 셋째로 만들 때가 이 설계의 진짜 시험이다. `scheme`을 `"light"`로 두면 `theme set`이 `color-scheme`을 `default`로 뒤집고, `ink`와 `bg`가 처음으로 갈라지며, 5개였던 흰색 리터럴이 이미 `fg` 기반으로 바뀌어 있어서 따라온다.

---

## 7. 무엇을 하지 않는가

정직하게 한계를 적는다. 두 테마가 실제로 얼마나 달라질 수 있는지는 이 목록이 정한다.

**Qt 위젯 스타일은 Breeze로 고정된다.** `kde/kdeglobals:29`의 `widgetStyle=Breeze`가 정하는 것은 색이 아니라 모양이다. 버튼 모서리의 둥근 정도, 스크롤바 두께, 체크박스 크기, 탭 생김새, 애니메이션 곡선이 전부 컴파일된 C++ 안에 있다. 색만 바꿀 수 있고 모양은 못 바꾼다. 공식 저장소에 있으면서 이것을 대체할 스타일은 사실상 없다. Kvantum은 설치되어 있으나 `QT_QPA_PLATFORMTHEME=kde`(`hypr/config/env.lua:20`) 아래에서는 읽히지 않고, 그것을 바꾸면 kdeglobals가 통째로 무시되어 색 체계 전체를 잃는다.

**GTK 테마는 Breeze-Dark로 고정된다.** 같은 이유는 아니다. GTK 테마는 CSS지만 `/usr/share/themes/Breeze-Dark/gtk-3.0/gtk.css`가 4465행이고 그 안의 치수, 모서리 반지름, 여백, 그림자는 색 이름이 아니라 규칙이다. `@define-color` 78개를 다시 선언하는 방식은 색만 갈아 끼우고 규칙은 건드리지 않는다. 규칙까지 바꾸려면 4465행짜리 스타일시트를 테마마다 하나씩 쓰는 일이 되고, 그것은 이 설계가 하려는 일이 아니다.

**아이콘 테마는 생성할 수 없다.** `breeze-dark`는 수천 개의 SVG와 PNG이고 색이 각 파일 안에 들어 있다. 색을 바꾸려면 전부 다시 그려야 한다. matugen도 이것은 못 했고 그래서 end-4 설정도 아이콘 테마만은 통째로 가져다 썼다. 두 테마 모두 `breeze-dark` 아이콘을 쓴다.

**Breeze의 GTK 에셋 PNG는 따라오지 않는다.** `/usr/share/themes/Breeze-Dark/assets/` 아래의 체크 표시와 화살표는 Breeze 파랑 `#3daee9`로 이미 렌더링된 이미지다. `colors.css`를 아무리 고쳐도 이 이미지들은 파랑으로 남는다. 체크박스를 켰을 때의 표시가 테마 강조색이 아니라 Breeze 파랑인 자리가 생긴다.

**p10k 프롬프트는 사실상 팔레트를 따르지 않는다.** `dotfiles-terminal/zsh/p10k.zsh`의 색 지정 228줄 가운데 222줄이 256색 인덱스다. 0번부터 15번까지는 kitty의 `ansi` 배열을 따라오지만, 16번부터 255번까지는 고정 색 큐브 항목이라 팔레트와 무관하다. 이 파일을 진짜로 묶으려면 223개 할당을 전부 생성해야 하고 그것은 GTK 스타일시트를 통째로 쓰는 것과 같은 급의 작업이다. caps lock 세그먼트 하나만 예외로 묶는다. 그 자리가 바와 어긋난다는 사실이 이미 `Theme.qml:100-102`에 주석으로 적혀 있었기 때문이다.

**알림은 칠할 대상이 없다.** 알림 데몬이 설치되어 있지 않다. `pacman -Qq`에 `libnotify`만 있고 dunst, mako, swaync 어느 것도 없다. `capture.sh:36-40`이 `notify-send`를 부르지만 서버가 없으면 그 알림은 아무 데도 뜨지 않는다. 데몬을 고르면 그때 소비자로 추가한다.

**hyprpicker는 색이 없다.** `capture.sh:109`가 `hyprpicker -a -n`으로 부르고, 이 도구는 화면을 확대해 보여 줄 뿐 자기 색을 그리지 않는다. 설정 파일도 없다. 캡처 GUI 셋 가운데 이것만 팔레트 밖에 남는다.

### 그래서 두 테마는 얼마나 다를 수 있는가

**완전히 다를 수 있는 것.** 모든 배경, 모든 글자, 모든 강조, 창 테두리, 선택 배경, 잠금 화면, 터미널 16색, 상태 바의 모든 알약, 후보창, 캡처 편집 창의 모든 면. 어두운 테마에서 밝은 테마로 뒤집는 것도 된다.

**같게 남는 것.** 모든 창의 모서리 둥근 정도, 버튼과 스크롤바와 체크박스의 크기와 생김새, 모든 아이콘, 체크박스 안의 표시, 애니메이션의 길이와 곡선, 글꼴. 글꼴은 `kde/kdeglobals`의 `font=` 다섯 줄과 `fontconfig/local.conf` 체인, `gsettings-apply.sh:48-49`에 함께 묶여 있어서 팔레트로 옮기면 생성기가 fontconfig까지 써야 한다. 1단계에서는 손으로 두고 확장 지점으로만 남긴다.

한 문장으로 요약하면, 두 테마는 **색이 전부 다른 같은 데스크톱**이 된다. 창의 실루엣과 버튼의 손맛은 같고 그 위에 칠해진 것만 바뀐다. macOS를 흉내 내는 팔레트가 macOS처럼 보이지는 않는다. macOS 느낌의 색을 입은 Breeze처럼 보인다. 그 이상을 하려면 위젯 스타일 하나를 새로 쓰는 일이고, 그것은 공식 패키지만 쓴다는 전제와 양립하지 않는다.