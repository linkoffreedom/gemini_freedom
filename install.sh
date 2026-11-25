#!/usr/bin/env bash
set -euo pipefail

# === Настройки репозитория (замени на свой GitHub) ===
GITHUB_REPO="${GITHUB_REPO:-linkoffreedom/gemini_freedom}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
RAW_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${GITHUB_BRANCH}"
RELEASE_BASE="https://github.com/${GITHUB_REPO}/releases/latest/download"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# === Параметры по умолчанию ===
REGION="CH"
SOCKS_PORT="8086"
BOT_TOKEN=""
CHAT_ID=""
NO_TG=0
NON_INTERACTIVE=0
UNINSTALL=0

C_GRN='\033[0;32m'
C_YLW='\033[1;33m'
C_RED='\033[0;31m'
C_CYN='\033[0;36m'
C_RST='\033[0m'

info() { echo -e "${C_CYN}[INFO]${C_RST} $*"; }
ok()   { echo -e "${C_GRN}[OK]${C_RST} $*"; }
warn() { echo -e "${C_YLW}[WARN]${C_RST} $*"; }
err()  { echo -e "${C_RED}[ERR]${C_RST} $*" >&2; exit 1; }

usage() {
  cat <<'HELP'
Установка Psiphon + Watchdog + опциональный Telegram-бот для Gemini/AI на VPS

Использование:
  ./install.sh [флаги]

Флаги:
  --region CH          Стартовая страна (по умолчанию: CH; пул: CH,AT,GB,BE,SE,US)
  --port 8086          Локальный порт SOCKS5 на 127.0.0.1 (по умолчанию: 8086)
  --token TOKEN        Токен Telegram-бота из @BotFather
  --chat ID            Ваш Telegram Chat ID (узнать в @userinfobot)
  --no-tg              Установить без Telegram-бота (без вопросов)
  --yes                Неинтерактивный режим с настройками по умолчанию
  --uninstall          Полностью удалить Psiphon, watchdog и Telegram-бота
  -h, --help           Показать эту справку
HELP
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --region) REGION="${2^^}"; shift 2 ;;
    --port) SOCKS_PORT="$2"; shift 2 ;;
    --token) BOT_TOKEN="$2"; shift 2 ;;
    --chat) CHAT_ID="$2"; shift 2 ;;
    --no-tg) NO_TG=1; shift ;;
    --yes|-y) NON_INTERACTIVE=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "Неизвестный параметр: $1 (см. --help)" ;;
  esac
done

[[ "$EUID" -eq 0 ]] || err "Запустите установщик от root (sudo -i)."

do_uninstall() {
  info "Останавливаю и удаляю службы Psiphon..."
  systemctl disable --now psiphon-tg-bot.service psiphon-watchdog.timer psiphon-watchdog.service psiphon-tunnel.service 2>/dev/null || true
  rm -f \
    /etc/systemd/system/psiphon-tunnel.service \
    /etc/systemd/system/psiphon-watchdog.service \
    /etc/systemd/system/psiphon-watchdog.timer \
    /etc/systemd/system/psiphon-tg-bot.service \
    /usr/local/bin/psiphon-tunnel-core \
    /usr/local/bin/psiphon-watchdog.sh \
    /usr/local/bin/psiphon-tg-bot.py \
    /usr/local/bin/psiphon-ctl \
    /run/psiphon-watchdog.lock
  rm -rf /etc/systemd/system/psiphon-tunnel.service.d /var/lib/psiphon
  systemctl daemon-reload
  ok "Все компоненты Psiphon, watchdog и Telegram-бот полностью удалены."
  echo "Панель 3X-UI не затронута. При необходимости удалите outbound psiphon-out в настройках Xray вручную."
  exit 0
}

[[ "$UNINSTALL" -eq 1 ]] && do_uninstall

ask() {
  local prompt="$1" default="$2" val=""
  if [[ -r /dev/tty ]]; then
    read -r -p "$prompt" val </dev/tty || true
  fi
  echo "${val:-$default}"
}

download_asset() {
  local filename="$1" dest="$2"
  # 1. Локальный файл рядом со скриптом (удобно для оффлайн-теста)
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/$filename" ]]; then
    cp -f "$SCRIPT_DIR/$filename" "$dest"
    return 0
  fi
  # 2. GitHub Releases -> 3. Корень или папка bin/ в репозитории
  for url in \
    "${RELEASE_BASE}/${filename}" \
    "${RAW_BASE}/${filename}" \
    "${RAW_BASE}/bin/${filename}"; do
    if curl -fsSL --connect-timeout 10 -o "$dest" "$url" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# === Определение архитектуры ===
RAW_ARCH="$(uname -m)"
case "$RAW_ARCH" in
  x86_64|amd64)  ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) err "Архитектура $RAW_ARCH не поддерживается (нужны x86_64 или arm64)." ;;
esac

# === Интерактивная настройка ===
if [[ "$NON_INTERACTIVE" -eq 0 && -r /dev/tty ]]; then
  echo ""
  echo -e "${C_CYN}=== Установка Psiphon + Watchdog для Gemini (Link Of Freedom) ===${C_RST}"
  echo "Чистые приоритетные страны ЕС: CH, AT, GB, BE, SE (избегайте DE и NL)."
  REGION="$(ask "Стартовая страна [CH]: " "$REGION")"
  REGION="${REGION^^}"

  SOCKS_PORT="$(ask "Локальный порт SOCKS5 на 127.0.0.1 [8086]: " "$SOCKS_PORT")"

  if [[ "$NO_TG" -eq 0 && -z "$BOT_TOKEN" ]]; then
    echo ""
    TG_ANS="$(ask "Включить уведомления и кнопки смены стран в Telegram-боте? [y/N]: " "N")"
    if [[ "${TG_ANS,,}" =~ ^(y|yes|д|да)$ ]]; then
      echo "  Токен создаётся в @BotFather, ваш числовой Chat ID — в @userinfobot."
      BOT_TOKEN="$(ask "  BOT_TOKEN (Enter — пропустить): " "")"
      if [[ -n "$BOT_TOKEN" ]]; then
        CHAT_ID="$(ask "  Ваш CHAT_ID: " "")"
      fi
    fi
  fi
  echo ""
fi

[[ "$REGION" =~ ^[A-Z]{2}$ ]] || err "Некорректный код страны: $REGION (нужны 2 латинские буквы, например CH)."
[[ "$SOCKS_PORT" =~ ^[0-9]+$ ]] && (( SOCKS_PORT >= 1024 && SOCKS_PORT <= 65535 )) || err "Некорректный порт: $SOCKS_PORT"

if [[ "$NO_TG" -eq 1 ]]; then
  BOT_TOKEN=""
  CHAT_ID=""
fi

# === 1. Зависимости ===
info "[1/6] Проверка зависимостей..."
NEED=()
command -v curl >/dev/null 2>&1 || NEED+=(curl)
command -v python3 >/dev/null 2>&1 || NEED+=(python3)
command -v flock >/dev/null 2>&1 || NEED+=(util-linux)
[[ -d /etc/ssl/certs ]] || NEED+=(ca-certificates)
if [[ ${#NEED[@]} -gt 0 ]]; then
  apt-get update -qq
  apt-get install -y -qq "${NEED[@]}"
fi

# === 2. Загрузка бинарника Psiphon и базового конфига ===
info "[2/6] Загрузка psiphon-tunnel-core (${ARCH}) и шаблона конфигурации..."
systemctl stop psiphon-tg-bot.service psiphon-watchdog.timer psiphon-tunnel.service 2>/dev/null || true
mkdir -p /usr/local/bin /var/lib/psiphon

download_asset "psiphon-tunnel-core-${ARCH}" /usr/local/bin/psiphon-tunnel-core \
  || err "Не удалось скачать psiphon-tunnel-core-${ARCH} из ${GITHUB_REPO}."
chmod 755 /usr/local/bin/psiphon-tunnel-core

download_asset "psiphon.config.template" /var/lib/psiphon/psiphon.config \
  || err "Не удалось скачать psiphon.config.template из ${GITHUB_REPO}."

python3 - /var/lib/psiphon/psiphon.config "$REGION" "$SOCKS_PORT" <<'PY'
import json, os, sys
cfg_path, region, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(cfg_path, "r", encoding="utf-8") as f:
    d = json.load(f)
d["EgressRegion"] = region
d["DeviceRegion"] = region
d["ListenInterface"] = "127.0.0.1"
d["LocalSocksProxyPort"] = port
tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(d, f, indent=2)
os.replace(tmp, cfg_path)
PY
chmod 600 /var/lib/psiphon/psiphon.config
rm -rf /var/lib/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core

# === 3. Установка Watchdog ===
info "[3/6] Создание /usr/local/bin/psiphon-watchdog.sh..."
cat <<'EOF' > /usr/local/bin/psiphon-watchdog.sh
#!/usr/bin/env bash
export LC_ALL=C

PROXY="127.0.0.1:8086"
SERVICE="psiphon-tunnel.service"
CONFIG_FILE="/var/lib/psiphon/psiphon.config"
CACHE_DIR="/var/lib/psiphon/ca.psiphon.PsiphonTunnel.tunnel-core"
LOCK_FILE="/run/psiphon-watchdog.lock"
REGIONS=("CH" "AT" "GB" "BE" "SE" "US")
MAX_TTFB="2.5"
BOT_TOKEN=""
CHAT_ID=""
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

exec 9>"$LOCK_FILE"
if [[ $# -gt 0 ]]; then
  flock -w 20 9 || { echo "Watchdog занят фоновой проверкой, повторите через несколько секунд."; exit 1; }
else
  flock -n 9 || exit 0
fi

notify() {
  [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]] || return 0
  curl -s -m 5 -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$1" >/dev/null 2>&1
}

get_current_region() {
  python3 -c 'import json, sys; d=json.load(open(sys.argv[1])); print(d.get("EgressRegion",""))' "$CONFIG_FILE" 2>/dev/null
}

set_region() {
  python3 -c 'import json, os, sys; p, r = sys.argv[1], sys.argv[2]; d = json.load(open(p)); d["EgressRegion"] = r; d["DeviceRegion"] = r; t = p + ".tmp"; json.dump(d, open(t, "w"), indent=2); os.replace(t, p)' "$CONFIG_FILE" "$1"
}

next_region() {
  local cur="$1" i
  for i in "${!REGIONS[@]}"; do
    if [[ "${REGIONS[$i]}" == "$cur" ]]; then
      echo "${REGIONS[$(( (i + 1) % ${#REGIONS[@]} ))]}"
      return
    fi
  done
  echo "${REGIONS[0]}"
}

get_ip_meta() {
  local raw parsed
  CUR_IP="unknown"
  CUR_CC="??"
  CUR_ORG=""

  raw=$(curl --socks5-hostname "$PROXY" -s -m 5 https://ipinfo.io/json 2>/dev/null)
  parsed=$(python3 -c 'import json, sys
try:
    d = json.loads(sys.stdin.read())
    if d.get("ip"):
        print(d["ip"]); print(d.get("country","??")); print(d.get("org",""))
except Exception:
    pass' <<< "$raw")

  if [[ -z "$parsed" ]]; then
    raw=$(curl --socks5-hostname "$PROXY" -s -m 5 "http://ip-api.com/json/?fields=query,countryCode,org,as" 2>/dev/null)
    parsed=$(python3 -c 'import json, sys
try:
    d = json.loads(sys.stdin.read())
    if d.get("query"):
        print(d["query"]); print(d.get("countryCode","??")); print(d.get("as") or d.get("org",""))
except Exception:
    pass' <<< "$raw")
  fi

  if [[ -n "$parsed" ]]; then
    { read -r CUR_IP; read -r CUR_CC; read -r CUR_ORG; } <<< "$parsed"
  fi
}

check_once() {
  local res code ttfb eff_url gl
  res=$(curl --socks5-hostname "$PROXY" -A "$UA" -L -o /dev/null -s -m 10 \
    -w "%{http_code} %{time_starttransfer} %{url_effective}" \
    https://gemini.google.com/app 2>/dev/null)

  read -r code ttfb eff_url <<< "$res"

  if [[ "$eff_url" == *"/sorry/"* || "$code" == "429" ]]; then
    REASON="грязный IP (Google /sorry/, HTTP=$code)"
    return 1
  fi

  if [[ "$eff_url" == *"unsupported"* || "$eff_url" == *"/faq"* ]]; then
    REASON="региональная заглушка Gemini"
    return 1
  fi

  if [[ "$code" != "200" ]]; then
    REASON="Gemini недоступен (HTTP=${code:-timeout})"
    return 1
  fi

  if awk -v t="${ttfb:-99}" -v m="$MAX_TTFB" 'BEGIN { exit !(t > m) }'; then
    REASON="высокий TTFB=${ttfb}s (выше ${MAX_TTFB}s)"
    return 1
  fi

  gl=$(curl --socks5-hostname "$PROXY" -A "$UA" -L -b "SOCS=CAI" -s -m 8 https://www.youtube.com/premium 2>/dev/null \
    | grep -o '"INNERTUBE_CONTEXT_GL":"[A-Z]*"' | head -n 1 | cut -d'"' -f4)

  if [[ "$gl" == "RU" ]]; then
    REASON="Google определил регион как RU"
    return 1
  fi

  get_ip_meta
  if [[ "${CUR_ORG,,}" == *"ovh"* ]]; then
    REASON="проблемная подсеть OVH ($CUR_IP)"
    return 1
  fi

  OK_INFO="OK: HTTP=$code, TTFB=${ttfb}s, GL=${gl:-unknown}, IP=${CUR_IP} (${CUR_CC}${CUR_ORG:+, $CUR_ORG})"
  return 0
}

switch_node() {
  local target="$1"
  systemctl stop "$SERVICE"
  set_region "$target"
  rm -rf "$CACHE_DIR"
  systemctl start "$SERVICE"

  local _
  for _ in $(seq 1 8); do
    sleep 2
    if curl --socks5-hostname "$PROXY" -s -m 3 -o /dev/null https://gemini.google.com/app 2>/dev/null; then
      break
    fi
  done
}

rotate_until_clean() {
  local reason="$1" forced="$2"
  local old_reg old_ip target attempt max_attempts=3

  old_reg=$(get_current_region)
  get_ip_meta
  old_ip="$CUR_IP"

  [[ -n "$forced" ]] && max_attempts=1
  target="${forced:-$(next_region "$old_reg")}"

  for attempt in $(seq 1 "$max_attempts"); do
    echo "[$(date '+%F %T')] Попытка $attempt/$max_attempts: $old_reg ($old_ip) -> $target ($reason)"
    switch_node "$target"
    if check_once; then
      echo "[$(date '+%F %T')] Успешно переключено: $OK_INFO"
      notify "🔄 Psiphon на $(hostname) сменил ноду ($reason): ${old_reg:-??} ($old_ip) → $target ($CUR_IP, ${CUR_ORG:-unknown})"
      return 0
    fi
    target=$(next_region "$target")
  done

  echo "[$(date '+%F %T')] Не удалось найти чистую ноду за $max_attempts попыток ($REASON)"
  notify "❌ Psiphon на $(hostname): не удалось подобрать чистую ноду после $max_attempts попыток (причина: $REASON, последняя страна: $(get_current_region))"
  return 1
}

case "${1:-}" in
  --status)
    if check_once; then
      echo "✅ [$(get_current_region)] $OK_INFO"
      exit 0
    else
      echo "⚠️ [$(get_current_region)] Сбой: $REASON"
      exit 1
    fi
    ;;
  --test-tg)
    if check_once; then
      notify "✅ Статус Psiphon на $(hostname) [$(get_current_region)]: $OK_INFO"
      echo "OK: $OK_INFO"
    else
      notify "⚠️ Статус Psiphon на $(hostname) [$(get_current_region)]: $REASON"
      echo "FAIL: $REASON"
    fi
    exit 0
    ;;
  --rotate)
    rotate_until_clean "ручная ротация" ""
    exit $?
    ;;
  --region)
    [[ -z "${2:-}" ]] && { echo "Укажите код страны, например: psiphon-ctl region CH"; exit 1; }
    rotate_until_clean "ручной выбор региона" "${2^^}"
    exit $?
    ;;
esac

if check_once; then
  echo "[$(date '+%F %T')] [$(get_current_region)] $OK_INFO"
  exit 0
fi

sleep 5
if check_once; then
  echo "[$(date '+%F %T')] Восстановилось со 2-й попытки ($OK_INFO)"
  exit 0
fi

rotate_until_clean "$REASON" ""
EOF

# === 4. Установка Telegram-бота ===
info "[4/6] Создание /usr/local/bin/psiphon-tg-bot.py..."
cat <<'EOF' > /usr/local/bin/psiphon-tg-bot.py
#!/usr/bin/env python3
import json
import re
import subprocess
import time
import urllib.error
import urllib.request

BOT_TOKEN = ""
ALLOWED_CHAT_ID = ""
WATCHDOG = "/usr/local/bin/psiphon-watchdog.sh"
CONFIG_FILE = "/var/lib/psiphon/psiphon.config"

KEYBOARD = {
    "keyboard": [
        [{"text": "/status"}, {"text": "/rotate"}],
        [{"text": "/region"}, {"text": "/logs"}],
    ],
    "resize_keyboard": True,
}

REGION_BUTTONS = [
    [("🇨🇭 CH", "CH"), ("🇦🇹 AT", "AT"), ("🇬🇧 GB", "GB")],
    [("🇧🇪 BE", "BE"), ("🇸🇪 SE", "SE"), ("🇺🇸 US", "US")],
    [("🇫🇮 FI", "FI"), ("🇳🇴 NO", "NO"), ("🇫🇷 FR", "FR")],
]

REGION_HELP_BODY = (
    "Нажми на страну ниже или введи вручную: /region КОД\n\n"
    "⭐ Ряд 1–2: основные (CH, AT, GB, BE, SE) и US (ранние фичи AI)\n"
    "🇪🇺 Ряд 3: запасная Европа (FI, NO, FR)\n"
    "⚠️ DE и NL лучше избегать (часто /sorry/ и RU)"
)


def api_call(method, payload=None, timeout=40):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/{method}"
    data = json.dumps(payload or {}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def send_msg(text, reply_markup=None):
    payload = {"chat_id": ALLOWED_CHAT_ID, "text": text[:4000]}
    if reply_markup is not None:
        payload["reply_markup"] = reply_markup
    try:
        api_call("sendMessage", payload, timeout=10)
    except Exception as e:
        print(f"sendMessage error: {e}", flush=True)


def answer_callback(cb_id, text=""):
    if not cb_id:
        return
    try:
        api_call("answerCallbackQuery", {"callback_query_id": cb_id, "text": text[:180]}, timeout=10)
    except Exception as e:
        print(f"answerCallbackQuery error: {e}", flush=True)


def get_current_region():
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            return json.load(f).get("EgressRegion", "??")
    except Exception:
        return "??"


def build_region_inline_keyboard(current_region):
    rows = []
    for row in REGION_BUTTONS:
        btn_row = []
        for label, code in row:
            text = f"✅ {label}" if code == current_region else label
            btn_row.append({"text": text, "callback_data": f"reg:{code}"})
        rows.append(btn_row)
    return {"inline_keyboard": rows}


def run_watchdog(args):
    return subprocess.run(
        [WATCHDOG] + args,
        capture_output=True,
        text=True,
        timeout=95,
    )


def switch_region_action(region):
    send_msg(f"⏳ Переключаю Psiphon на {region}...")
    res = run_watchdog(["--region", region])
    if res.returncode != 0 and "занят" in res.stdout:
        send_msg("⚠️ Watchdog занят фоновой проверкой, повтори через 10 секунд.")


def handle_command(text):
    parts = text.strip().split()
    if not parts:
        return
    cmd = parts[0].split("@")[0].lower()

    if cmd in ("/start", "/help"):
        send_msg(
            "Управление Psiphon на VPS:\n"
            "/status — проверить Gemini, TTFB и текущий IP\n"
            "/rotate — сменить ноду на следующую чистую страну\n"
            "/region — выбрать страну кнопками (или /region CH)\n"
            "/logs — последние 8 записей watchdog",
            reply_markup=KEYBOARD,
        )
        return

    if cmd == "/status":
        send_msg("⏳ Проверяю текущую ноду...")
        res = run_watchdog(["--test-tg"])
        if res.returncode != 0 and "занят" in res.stdout:
            send_msg("⚠️ Watchdog занят фоновой проверкой, повтори через 10 секунд.")
        return

    if cmd == "/rotate":
        send_msg("⏳ Сбрасываю кэш и подбираю новую ноду (10–30 сек)...")
        res = run_watchdog(["--rotate"])
        if res.returncode != 0 and "занят" in res.stdout:
            send_msg("⚠️ Watchdog занят фоновой проверкой, повтори через 10 секунд.")
        return

    if cmd == "/region":
        if len(parts) < 2 or not re.fullmatch(r"[A-Za-z]{2}", parts[1]):
            cur = get_current_region()
            send_msg(
                f"🌍 Текущий регион: {cur}\n\n{REGION_HELP_BODY}",
                reply_markup=build_region_inline_keyboard(cur),
            )
            return
        switch_region_action(parts[1].upper())
        return

    if cmd == "/logs":
        res = subprocess.run(
            ["journalctl", "-u", "psiphon-watchdog.service", "-n", "12", "--no-pager", "-o", "short"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        lines = [ln for ln in res.stdout.splitlines() if "psiphon-watchdog.sh" in ln][-8:]
        send_msg("📋 Последние проверки:\n" + ("\n".join(lines) if lines else "Записей пока нет."))
        return

    send_msg("Неизвестная команда. Жми /help.", reply_markup=KEYBOARD)


def handle_callback(cb):
    cb_id = cb.get("id")
    msg = cb.get("message") or {}
    chat_id = str((msg.get("chat") or {}).get("id", ""))
    from_id = str((cb.get("from") or {}).get("id", ""))
    if chat_id != ALLOWED_CHAT_ID and from_id != ALLOWED_CHAT_ID:
        return

    data = cb.get("data") or ""
    if data.startswith("reg:"):
        region = data.split(":", 1)[1].upper()
        if not re.fullmatch(r"[A-Z]{2}", region):
            answer_callback(cb_id, "Некорректный код страны")
            return
        answer_callback(cb_id, f"Переключаю на {region}...")
        switch_region_action(region)
    else:
        answer_callback(cb_id)


def setup_menu():
    try:
        api_call(
            "setMyCommands",
            {
                "commands": [
                    {"command": "status", "description": "Проверить Gemini, TTFB и IP"},
                    {"command": "rotate", "description": "Сменить ноду на следующую страну"},
                    {"command": "region", "description": "Выбрать страну кнопками"},
                    {"command": "logs", "description": "Последние записи watchdog"},
                    {"command": "help", "description": "Показать нижнюю клавиатуру"},
                ]
            },
            timeout=10,
        )
    except Exception as e:
        print(f"setMyCommands error: {e}", flush=True)


def main():
    if not BOT_TOKEN or not ALLOWED_CHAT_ID:
        print("BOT_TOKEN or ALLOWED_CHAT_ID is empty; exiting.", flush=True)
        return

    setup_menu()
    offset = 0
    allowed = ["message", "callback_query"]

    try:
        init = api_call("getUpdates", {"timeout": 0, "allowed_updates": allowed}, timeout=10)
        results = init.get("result", [])
        if results:
            offset = results[-1]["update_id"] + 1
    except Exception as e:
        print(f"Initial sync error: {e}", flush=True)

    print("psiphon-tg-bot started", flush=True)
    while True:
        try:
            data = api_call(
                "getUpdates",
                {"offset": offset, "timeout": 30, "allowed_updates": allowed},
                timeout=40,
            )
            for upd in data.get("result", []):
                offset = upd["update_id"] + 1

                if "callback_query" in upd:
                    try:
                        handle_callback(upd["callback_query"])
                    except Exception as e:
                        send_msg(f"❌ Ошибка обработки кнопки: {e}")
                    continue

                msg = upd.get("message") or {}
                chat_id = str((msg.get("chat") or {}).get("id", ""))
                text = msg.get("text") or ""
                if chat_id != ALLOWED_CHAT_ID or not text.startswith("/"):
                    continue
                try:
                    handle_command(text)
                except Exception as e:
                    send_msg(f"❌ Ошибка выполнения команды: {e}")
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"Network error: {e}", flush=True)
            time.sleep(5)
        except Exception as e:
            print(f"Loop error: {e}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    main()
EOF

# Подставляем порт, токен и CHAT_ID в скрипты
python3 - "$SOCKS_PORT" "$BOT_TOKEN" "$CHAT_ID" <<'PY'
import re, sys
port, token, chat = sys.argv[1], sys.argv[2], sys.argv[3]

wd = "/usr/local/bin/psiphon-watchdog.sh"
w_txt = open(wd, encoding="utf-8").read()
w_txt = re.sub(r'^PROXY=.*', f'PROXY="127.0.0.1:{port}"', w_txt, flags=re.M)
w_txt = re.sub(r'^BOT_TOKEN=.*', f'BOT_TOKEN="{token}"', w_txt, flags=re.M)
w_txt = re.sub(r'^CHAT_ID=.*', f'CHAT_ID="{chat}"', w_txt, flags=re.M)
open(wd, "w", encoding="utf-8").write(w_txt)

bot = "/usr/local/bin/psiphon-tg-bot.py"
b_txt = open(bot, encoding="utf-8").read()
b_txt = re.sub(r'^BOT_TOKEN\s*=.*', f'BOT_TOKEN = "{token}"', b_txt, flags=re.M)
b_txt = re.sub(r'^ALLOWED_CHAT_ID\s*=.*', f'ALLOWED_CHAT_ID = "{chat}"', b_txt, flags=re.M)
open(bot, "w", encoding="utf-8").write(b_txt)
PY

chmod 700 /usr/local/bin/psiphon-watchdog.sh /usr/local/bin/psiphon-tg-bot.py

# === 5. Утилита управления psiphon-ctl и юниты systemd ===
info "[5/6] Создание psiphon-ctl и служб systemd..."

cat <<'EOF' > /usr/local/bin/psiphon-ctl
#!/usr/bin/env bash
set -euo pipefail

case "${1:-help}" in
  status)
    echo "Службы: tunnel=$(systemctl is-active psiphon-tunnel.service 2>/dev/null || true), watchdog=$(systemctl is-active psiphon-watchdog.timer 2>/dev/null || true), tg-bot=$(systemctl is-active psiphon-tg-bot.service 2>/dev/null || true)"
    exec /usr/local/bin/psiphon-watchdog.sh --status
    ;;
  rotate)
    exec /usr/local/bin/psiphon-watchdog.sh --rotate
    ;;
  region)
    [[ -n "${2:-}" ]] || { echo "Использование: psiphon-ctl region CH  (лучшие: CH, AT, GB, BE, SE, US)"; exit 1; }
    exec /usr/local/bin/psiphon-watchdog.sh --region "$2"
    ;;
  logs)
    journalctl -u psiphon-watchdog.service -n 15 --no-pager -o short
    ;;
  tg-setup)
    read -r -p "BOT_TOKEN (пусто — отключить бота): " tok
    cid=""
    [[ -n "$tok" ]] && read -r -p "Ваш CHAT_ID: " cid
    python3 - "$tok" "$cid" <<'PY'
import re, sys
token, chat = sys.argv[1], sys.argv[2]
for path, pats in [
    ("/usr/local/bin/psiphon-watchdog.sh", [(r'^BOT_TOKEN=.*', f'BOT_TOKEN="{token}"'), (r'^CHAT_ID=.*', f'CHAT_ID="{chat}"')]),
    ("/usr/local/bin/psiphon-tg-bot.py", [(r'^BOT_TOKEN\s*=.*', f'BOT_TOKEN = "{token}"'), (r'^ALLOWED_CHAT_ID\s*=.*', f'ALLOWED_CHAT_ID = "{chat}"')]),
]:
    txt = open(path, encoding="utf-8").read()
    for p, r in pats:
        txt = re.sub(p, r, txt, flags=re.M)
    open(path, "w", encoding="utf-8").write(txt)
PY
    if [[ -n "$tok" && -n "$cid" ]]; then
      systemctl enable --now psiphon-tg-bot.service
      systemctl restart psiphon-tg-bot.service
      echo "✅ Telegram-бот включён. Отправьте /start боту."
    else
      systemctl disable --now psiphon-tg-bot.service 2>/dev/null || true
      echo "ℹ️ Telegram-бот отключён."
    fi
    ;;
  uninstall)
    read -r -p "Полностью удалить Psiphon, watchdog и бота? [y/N]: " ans
    [[ "${ans,,}" =~ ^(y|yes|д|да)$ ]] || { echo "Отменено."; exit 0; }
    systemctl disable --now psiphon-tg-bot.service psiphon-watchdog.timer psiphon-watchdog.service psiphon-tunnel.service 2>/dev/null || true
    rm -f \
      /etc/systemd/system/psiphon-tunnel.service \
      /etc/systemd/system/psiphon-watchdog.service \
      /etc/systemd/system/psiphon-watchdog.timer \
      /etc/systemd/system/psiphon-tg-bot.service \
      /usr/local/bin/psiphon-tunnel-core \
      /usr/local/bin/psiphon-watchdog.sh \
      /usr/local/bin/psiphon-tg-bot.py \
      /usr/local/bin/psiphon-ctl \
      /run/psiphon-watchdog.lock
    rm -rf /etc/systemd/system/psiphon-tunnel.service.d /var/lib/psiphon
    systemctl daemon-reload
    echo "✅ Всё удалено. 3X-UI не затронут."
    ;;
  *)
    cat <<'USAGE'
Управление Psiphon на VPS:
  psiphon-ctl status           Проверить туннель, Gemini, TTFB, GL и IP
  psiphon-ctl rotate           Сбросить кэш и сменить ноду на следующую страну
  psiphon-ctl region <КОД>     Переключить страну (CH, AT, GB, BE, SE, US)
  psiphon-ctl logs             Последние 15 проверок watchdog
  psiphon-ctl tg-setup         Подключить или отключить Telegram-бота
  psiphon-ctl uninstall        Полностью удалить связку с сервера
USAGE
    ;;
esac
EOF
chmod 755 /usr/local/bin/psiphon-ctl

cat <<'EOF' > /etc/systemd/system/psiphon-tunnel.service
[Unit]
Description=Psiphon Tunnel Core (Local SOCKS5 for AI Routing)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/var/lib/psiphon
ExecStart=/usr/local/bin/psiphon-tunnel-core -config /var/lib/psiphon/psiphon.config
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > /etc/systemd/system/psiphon-watchdog.service
[Unit]
Description=Psiphon Gemini Health Check & Auto-Rotation
After=psiphon-tunnel.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/psiphon-watchdog.sh
EOF

cat <<'EOF' > /etc/systemd/system/psiphon-watchdog.timer
[Unit]
Description=Run Psiphon Watchdog every 3 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=3min
Unit=psiphon-watchdog.service

[Install]
WantedBy=timers.target
EOF

cat <<'EOF' > /etc/systemd/system/psiphon-tg-bot.service
[Unit]
Description=Psiphon Telegram Control Bot
After=network-online.target psiphon-tunnel.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/bin/psiphon-tg-bot.py
Environment=PYTHONUNBUFFERED=1
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now psiphon-tunnel.service
systemctl enable --now psiphon-watchdog.timer

if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
  systemctl enable --now psiphon-tg-bot.service
else
  systemctl disable --now psiphon-tg-bot.service 2>/dev/null || true
fi

# === 6. Ожидание туннеля и контрольная проверка ===
info "[6/6] Ожидание поднятия туннеля Psiphon..."
for _ in $(seq 1 12); do
  sleep 2
  if curl --socks5-hostname "127.0.0.1:${SOCKS_PORT}" -s -m 3 -o /dev/null https://gemini.google.com/app 2>/dev/null; then
    break
  fi
done

echo ""
/usr/local/bin/psiphon-watchdog.sh --status || true

echo ""
ok "Установка завершена!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1) Добавь Outbound в 3X-UI (Настройки Xray -> Исходящие):"
echo "   Протокол: socks | Тег: psiphon-out | Адрес: 127.0.0.1 | Порт: ${SOCKS_PORT}"
echo ""
echo "2) Команды управления на VPS:"
echo "   psiphon-ctl status        — статус, TTFB и текущий IP"
echo "   psiphon-ctl rotate        — смена ноды на следующую чистую страну"
echo "   psiphon-ctl region US     — выбор конкретной страны"
echo "   psiphon-ctl tg-setup      — настроить/отключить Telegram-бота"
echo "   psiphon-ctl uninstall     — полное удаление"
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
  echo ""
  echo "3) Telegram-бот запущен — отправь ему /start, чтобы появились кнопки."
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"