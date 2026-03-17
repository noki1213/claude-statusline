#!/bin/bash
# Claude Code ステータスライン表示スクリプト（レートリミット表示あり）
# 1行目：モデル名 | コンテキスト使用率 | 編集行数 | ディレクトリ名 | リポジトリ名:ブランチ名
# 2行目：5時間レートリミットのプログレスバー
# 3行目：7日間レートリミットのプログレスバー
#
# 参考：https://github.com/loadbalance-sudachi-kun/claude-code-statusline

input=$(cat)

# ---------- ANSIカラー ----------
GREEN=$'\e[38;2;51;165;165m'
YELLOW=$'\e[38;2;244;201;128m'
RED=$'\e[38;2;252;156;156m'
BLUE=$'\e[38;2;74;143;191m'
CYAN=$'\e[38;2;74;174;200m'
WHITE=$'\e[38;2;196;196;196m'
GRAY=$'\e[38;2;74;88;92m'
RESET=$'\e[0m'
DIM=$'\e[2m'

# ---------- 使用率に応じた色を返す ----------
color_for_pct() {
	local pct="$1"
	if [ -z "$pct" ] || [ "$pct" = "null" ]; then
		printf '%s' "$GRAY"
		return
	fi
	local ipct
	ipct=$(printf "%.0f" "$pct" 2>/dev/null || echo "0")
	if [ "$ipct" -ge 80 ]; then
		printf '%s' "$RED"
	elif [ "$ipct" -ge 50 ]; then
		printf '%s' "$YELLOW"
	else
		printf '%s' "$GREEN"
	fi
}

# ---------- プログレスバー（10セグメント）----------
# $1: 実際の使用率(%)、$2: 理想位置マス番号(1〜10、省略可)
progress_bar() {
	local pct="$1"
	local ideal="${2:-}"
	local filled
	filled=$(awk "BEGIN{printf \"%d\", int($pct / 10 + 0.5)}" 2>/dev/null || echo 0)
	[ "$filled" -gt 10 ] 2>/dev/null && filled=10
	[ "$filled" -lt 0 ] 2>/dev/null && filled=0
	local bar=""
	for i in $(seq 1 10); do
		if [ -n "$ideal" ] && [ "$i" -eq "$ideal" ]; then
			# 理想位置マスは ┃ で上書きする
			bar="${bar}┃"
		elif [ "$i" -le "$filled" ]; then
			bar="${bar}█"
		else
			bar="${bar}░"
		fi
	done
	printf '%s' "$bar"
}

# ---------- stdin から必要な情報を取得（jq で一括処理）----------
eval "$(echo "$input" | jq -r '
	"model_name=" + (.model.display_name // "Unknown" | @sh),
	"used_pct=" + (.context_window.used_percentage // 0 | tostring),
	"ctx_size=" + (.context_window.context_window_size // 0 | tostring),
	"cwd=" + (.cwd // "" | @sh),
	"cc_version=" + (.version // "0.0.0" | @sh)
' 2>/dev/null)"

# ---------- 現在のディレクトリ（~/省略したフルパス）----------
dir_name=""
if [ -n "$cwd" ]; then
	dir_name=$(echo "$cwd" | sed "s|^/Users/$(whoami)|~|")
fi

# ---------- git リポジトリ名とブランチ名 ----------
git_branch=""
git_repo=""
git_line_color="$GREEN"
git_no_remote=false
git_unpushed=0
git_behind=0
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
	git_branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)
	if [ -n "$git_branch" ]; then
		# git のトップレベルディレクトリ名をリポジトリ名として使う
		git_toplevel=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel 2>/dev/null || true)
		git_repo=$(basename "$git_toplevel")

		# git の状態を調べて色を決める
		porcelain=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null || true)
		# 未ステージの変更がある（新規・編集・削除を含む）か確認する（2文字目がスペース以外）
		has_unstaged=$(echo "$porcelain" | grep -c '^.[^ ]' 2>/dev/null || echo 0)
		# ステージ済みだが未コミットの変更があるか確認する（1文字目が変更あり・2文字目がスペース）
		has_staged=$(echo "$porcelain" | grep -c '^[^ ?] ' 2>/dev/null || echo 0)

		if [ "$has_unstaged" -gt 0 ]; then
			# 未ステージの変更がある（git add が必要）→ 赤
			git_line_color="$RED"
		elif [ "$has_staged" -gt 0 ]; then
			# git add 済みだが未コミット → 黄
			git_line_color="$YELLOW"
		else
			# リモートが設定されているか確認する
			has_remote=$(git -C "$cwd" --no-optional-locks remote 2>/dev/null | wc -l | tr -d ' ')
			if [ "$has_remote" -eq 0 ]; then
				# リモートなし → 青 + ↑✗ マークをつける
				git_line_color="$BLUE"
				git_no_remote=true
			else
				# 未プッシュのコミットがあるか確認する
				git_unpushed=$(git -C "$cwd" --no-optional-locks rev-list "@{u}..HEAD" --count 2>/dev/null || echo 0)
				git_behind=$(git -C "$cwd" --no-optional-locks rev-list "HEAD..@{u}" --count 2>/dev/null || echo 0)
				if [ "$git_unpushed" -gt 0 ]; then
					# 未プッシュのコミットがある → 青
					git_line_color="$BLUE"
				else
					# 完全にきれいな状態 → 緑
					git_line_color="$GREEN"
				fi
			fi
		fi
	fi
fi

# ---------- レートリミット情報（Haiku probe でキャッシュつき取得）----------
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=360
FIVE_HOUR_UTIL=""
FIVE_HOUR_RESET=""
SEVEN_DAY_UTIL=""
SEVEN_DAY_RESET=""

fetch_usage() {
	local token
	token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || true)
	[ -z "$token" ] && return 1

	local access_token
	if echo "$token" | jq -e . >/dev/null 2>&1; then
		access_token=$(echo "$token" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
	else
		access_token="$token"
	fi
	[ -z "$access_token" ] && return 1

	# Haiku に最小リクエストを送ってレートリミットヘッダーを取得する
	local full_response
	full_response=$(curl -sD- --max-time 8 -o /dev/null \
		-H "Authorization: Bearer ${access_token}" \
		-H "Content-Type: application/json" \
		-H "User-Agent: claude-code/${cc_version:-0.0.0}" \
		-H "anthropic-beta: oauth-2025-04-20" \
		-H "anthropic-version: 2023-06-01" \
		-d '{"model":"claude-haiku-4-5-20251001","max_tokens":1,"messages":[{"role":"user","content":"h"}]}' \
		"https://api.anthropic.com/v1/messages" 2>/dev/null || true)
	local headers="$full_response"
	[ -z "$headers" ] && return 1

	# レートリミットヘッダーを抽出する
	local h5_util h5_reset h7_util h7_reset
	h5_util=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-5h-utilization' | tr -d '\r' | awk '{print $2}')
	h5_reset=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-5h-reset' | tr -d '\r' | awk '{print $2}')
	h7_util=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-7d-utilization' | tr -d '\r' | awk '{print $2}')
	h7_reset=$(echo "$headers" | grep -i 'anthropic-ratelimit-unified-7d-reset' | tr -d '\r' | awk '{print $2}')

	[ -z "$h5_util" ] && return 1

	# キャッシュファイルに保存する
	jq -n \
		--arg h5u "$h5_util" --arg h5r "$h5_reset" \
		--arg h7u "$h7_util" --arg h7r "$h7_reset" \
		'{five_hour_util: $h5u, five_hour_reset: $h5r, seven_day_util: $h7u, seven_day_reset: $h7r}' \
		> "$CACHE_FILE"
	return 0
}

load_usage() {
	local data="$1"
	eval "$(echo "$data" | jq -r '
		"FIVE_HOUR_UTIL=" + (.five_hour_util // empty),
		"FIVE_HOUR_RESET=" + (.five_hour_reset // empty),
		"SEVEN_DAY_UTIL=" + (.seven_day_util // empty),
		"SEVEN_DAY_RESET=" + (.seven_day_reset // empty)
	' 2>/dev/null)"
}

# キャッシュの有効期限を確認する
USE_CACHE=false
if [ -f "$CACHE_FILE" ]; then
	cache_age=$(( $(date +%s) - $(stat -f '%m' "$CACHE_FILE" 2>/dev/null || echo 0) ))
	if [ "$cache_age" -lt "$CACHE_TTL" ]; then
		USE_CACHE=true
	fi
fi

if $USE_CACHE; then
	load_usage "$(cat "$CACHE_FILE")"
else
	if fetch_usage; then
		load_usage "$(cat "$CACHE_FILE")"
	elif [ -f "$CACHE_FILE" ]; then
		load_usage "$(cat "$CACHE_FILE")"
	fi
fi

# 使用率を 0.0〜1.0 の小数から % に変換する
to_pct() {
	local val="$1"
	if [ -z "$val" ] || [ "$val" = "null" ] || [ "$val" = "0" ]; then
		echo ""
		return
	fi
	awk "BEGIN{printf \"%.0f\", $val * 100}" 2>/dev/null || echo ""
}

FIVE_HOUR_PCT=$(to_pct "$FIVE_HOUR_UTIL")
SEVEN_DAY_PCT=$(to_pct "$SEVEN_DAY_UTIL")

# ---------- 理想位置マスを計算する（リセット時刻から逆算）----------
# リセット時刻 - ウィンドウ幅 = 開始時刻、現在時刻との差で経過割合を求める
ideal_bar_pos() {
	local reset_epoch="$1"
	local window_sec="$2"
	[ -z "$reset_epoch" ] || [ "$reset_epoch" = "0" ] && echo "" && return
	local now
	now=$(date +%s)
	local start=$(( reset_epoch - window_sec ))
	local elapsed=$(( now - start ))
	[ "$elapsed" -le 0 ] && echo "1" && return
	local pos
	pos=$(awk "BEGIN{printf \"%d\", int($elapsed / $window_sec * 10 + 0.5)}" 2>/dev/null || echo "")
	[ "$pos" -gt 10 ] 2>/dev/null && pos=10
	[ "$pos" -lt 1 ] 2>/dev/null && pos=1
	echo "$pos"
}

IDEAL5=$(ideal_bar_pos "$FIVE_HOUR_RESET" "18000")   # 5時間 = 18000秒
IDEAL7=$(ideal_bar_pos "$SEVEN_DAY_RESET" "604800")  # 7日間 = 604800秒

# ---------- エポック秒から残り時間を Xd XXh XXm 形式に変換する ----------
countdown() {
	local epoch="$1"
	[ -z "$epoch" ] || [ "$epoch" = "0" ] && echo "" && return
	local now
	now=$(date +%s)
	local diff=$(( epoch - now ))
	[ "$diff" -le 0 ] && echo "" && return
	local days=$(( diff / 86400 ))
	local hours=$(( (diff % 86400) / 3600 ))
	local mins=$(( (diff % 3600) / 60 ))
	if [ "$days" -eq 0 ]; then
		printf '  %2dh%2dm' "$hours" "$mins"
	else
		printf '%dd%2dh%2dm' "$days" "$hours" "$mins"
	fi
}

five_reset_display=""
if [ -n "$FIVE_HOUR_RESET" ] && [ "$FIVE_HOUR_RESET" != "0" ]; then
	cd5=$(countdown "$FIVE_HOUR_RESET")
	[ -n "$cd5" ] && five_reset_display="→ ${cd5}"
fi

seven_reset_display=""
if [ -n "$SEVEN_DAY_RESET" ] && [ "$SEVEN_DAY_RESET" != "0" ]; then
	cd7=$(countdown "$SEVEN_DAY_RESET")
	[ -n "$cd7" ] && seven_reset_display="→ ${cd7}"
fi

# ---------- コンテキスト使用率を整数に変換 ----------
ctx_pct_int=0
if [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ "$used_pct" != "0" ]; then
	ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo 0)
fi

# ---------- 1行目の組み立て ----------
SEP="${GRAY} │ ${RESET}"
ctx_color=$(color_for_pct "$ctx_pct_int")

# 1行目：ディレクトリ
line1="${WHITE}󰉋 ${dir_name}${RESET}"

# 2行目：git（リポジトリ内の場合のみ）
line2=""
if [ -n "$git_repo" ] && [ -n "$git_branch" ]; then
	push_mark=""
	if $git_no_remote; then
		push_mark=" ↑✗"
	else
		[ "$git_unpushed" -gt 0 ] && push_mark="${push_mark} ↑${git_unpushed}"
		[ "$git_behind" -gt 0 ] && push_mark="${push_mark} ↓${git_behind}"
	fi
	line2="${git_line_color} ${git_repo} [${git_branch}]${push_mark}${RESET}"
elif [ -n "$git_branch" ]; then
	line2="${git_line_color} [${git_branch}]${push_mark}${RESET}"
fi

# 3行目：モデル名 + CTX
line3="${model_name}${SEP}${ctx_color}CTX ${ctx_pct_int}%${RESET}"

# ---------- 4行目（5時間レートリミット）----------
line4=""
if [ -n "$FIVE_HOUR_PCT" ]; then
	c5=$(color_for_pct "$FIVE_HOUR_PCT")
	bar5=$(progress_bar "$FIVE_HOUR_PCT" "$IDEAL5")
	line4="${c5}5h  ${bar5}  $(printf '%3s' "${FIVE_HOUR_PCT}")%${RESET}"
	[ -n "$five_reset_display" ] && line4+="  ${five_reset_display}"
else
	line4="${GRAY}5h  ░░░░░░░░░░   --%${RESET}"
fi

# ---------- 5行目（7日間レートリミット）----------
line5=""
if [ -n "$SEVEN_DAY_PCT" ]; then
	c7=$(color_for_pct "$SEVEN_DAY_PCT")
	bar7=$(progress_bar "$SEVEN_DAY_PCT" "$IDEAL7")
	line5="${c7}7d  ${bar7}  $(printf '%3s' "${SEVEN_DAY_PCT}")%${RESET}"
	[ -n "$seven_reset_display" ] && line5+="  ${seven_reset_display}"
else
	line5="${GRAY}7d  ░░░░░░░░░░   --%${RESET}"
fi

# ---------- 出力 ----------
printf '%s\n' "$line1"
# git がある場合のみ2行目を出力する
[ -n "$line2" ] && printf '%s\n' "$line2"
printf '%s\n' "$line3"
printf '%s\n' "$line4"
printf '%s' "$line5"
