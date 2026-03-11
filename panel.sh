#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="panelisimo"
APP_VERSION="0.3.0"
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$APP_DIR/.panelisimo"
CONFIG_FILE="$LOG_DIR/panelisimo.conf"
mkdir -p "$LOG_DIR"

if ! command -v awk >/dev/null 2>&1; then
  echo "awk no esta instalado."
  exit 1
fi

supports_color() {
  [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]
}

if supports_color; then
  C_RESET="$(tput sgr0)"
  C_TITLE="$(tput bold)$(tput setaf 6)"
  C_OK="$(tput setaf 2)"
  C_WARN="$(tput setaf 3)"
  C_ERR="$(tput setaf 1)"
else
  C_RESET=""
  C_TITLE=""
  C_OK=""
  C_WARN=""
  C_ERR=""
fi

print_branding() {
  if supports_color; then
    local c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 r
    c1="$(tput setaf 3)"   # amarillo
    c2="$(tput setaf 2)"   # verde
    c3="$(tput setaf 6)"   # cian
    c4="$(tput setaf 4)"   # azul
    c5="$(tput setaf 5)"   # magenta
    c6="$(tput setaf 1)"   # rojo
    c7="$(tput setaf 3)"   # amarillo
    c8="$(tput setaf 2)"   # verde
    c9="$(tput setaf 6)"   # cian
    c10="$(tput setaf 5)"  # magenta
    r="$(tput sgr0)"

    printf "%s█████▄  %s▄▄▄  %s▄▄  ▄▄ %s▄▄▄▄▄ %s▄▄    %s▄▄  %s▄▄▄▄  %s▄▄▄▄ %s▄▄ ▄▄   %s▄▄  ▄▄▄%s\n" \
      "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9" "$c10" "$r"
    printf "%s██▄▄█▀ %s██▀██ %s███▄██ %s██▄▄  %s██    %s██ %s███▄▄ %s███▄▄ %s██ ██▀▄▀██ %s██▀██%s\n" \
      "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9" "$c10" "$r"
    printf "%s██     %s██▀██ %s██ ▀██ %s██▄▄▄ %s██▄▄▄ %s██ %s▄▄██▀ %s▄▄██▀ %s██ ██   ██ %s▀███▀%s\n" \
      "$c1" "$c2" "$c3" "$c4" "$c5" "$c6" "$c7" "$c8" "$c9" "$c10" "$r"
  else
    cat <<'EOF'
█████▄  ▄▄▄  ▄▄  ▄▄ ▄▄▄▄▄ ▄▄    ▄▄  ▄▄▄▄  ▄▄▄▄ ▄▄ ▄▄   ▄▄  ▄▄▄
██▄▄█▀ ██▀██ ███▄██ ██▄▄  ██    ██ ███▄▄ ███▄▄ ██ ██▀▄▀██ ██▀██
██     ██▀██ ██ ▀██ ██▄▄▄ ██▄▄▄ ██ ▄▄██▀ ▄▄██▀ ██ ██   ██ ▀███▀
EOF
  fi
}

print_title() {
  printf "\n%s== %s ==%s\n" "$C_TITLE" "$1" "$C_RESET"
}

line() {
  printf -- "------------------------------------------------------------\n"
}

pause_enter() {
  read -r -p "Presiona Enter para continuar..." _ || true
}

log_error() {
  local msg="$1"
  local out="$LOG_DIR/errors.log"
  printf "[%s] %s\n" "$(date --iso-8601=seconds)" "$msg" >> "$out"
}

on_unhandled_error() {
  local exit_code="$1"
  local line_no="$2"
  local cmd="$3"
  local msg="ERROR no controlado (exit=$exit_code, linea=$line_no): $cmd"
  echo "${C_ERR}$msg${C_RESET}"
  log_error "$msg"
}
trap 'on_unhandled_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

cfg_get() {
  local key="$1"
  local def="${2:-}"
  local val=""

  if [ -f "$CONFIG_FILE" ]; then
    val="$(awk -F= -v k="$key" '$1==k {print $2}' "$CONFIG_FILE" | tail -n1)"
  fi

  if [ -n "$val" ]; then
    printf "%s" "$val"
  else
    printf "%s" "$def"
  fi
}

cfg_set() {
  local key="$1"
  local val="$2"
  local tmp
  tmp="$(mktemp)"
  touch "$CONFIG_FILE"
  awk -F= -v k="$key" '$1!=k {print $0}' "$CONFIG_FILE" > "$tmp"
  printf "%s=%s\n" "$key" "$val" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "${C_ERR}Necesitas ejecutar esta accion como root (sudo).${C_RESET}"
    return 1
  fi
  return 0
}

is_valid_domain() {
  local domain="$1"
  [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

is_valid_email() {
  local email="$1"
  [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

is_valid_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

is_valid_backend_endpoint() {
  local endpoint="$1"
  local host port
  host="${endpoint%:*}"
  port="${endpoint##*:}"
  [ "$host" != "$endpoint" ] || return 1
  is_valid_port "$port" || return 1
  [[ "$host" =~ ^(localhost|[A-Za-z0-9.-]+)$ ]]
}

run_action() {
  local desc="$1"
  shift
  local rc
  local prev_err_trap

  prev_err_trap="$(trap -p ERR || true)"
  trap - ERR

  set +e
  "$@"
  rc=$?
  set -e

  if [ -n "$prev_err_trap" ]; then
    eval "$prev_err_trap"
  fi

  if [ "$rc" -ne 0 ]; then
    local msg="$desc fallo con exit code $rc"
    echo "${C_ERR}[ERROR]${C_RESET} $msg"
    log_error "$msg"
  else
    echo "${C_OK}[OK]${C_RESET} $desc"
  fi
  return "$rc"
}

run_and_pause() {
  local desc="$1"
  shift
  run_action "$desc" "$@" || true
  pause_enter
  return 0
}

install_packages() {
  require_root || return 1
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  echo "Instalando paquetes: $*"
  apt-get update
  apt-get install -y "$@"
}

is_service_active() {
  local svc="$1"
  systemctl is-active --quiet "$svc" 2>/dev/null
}

is_cmd() {
  command -v "$1" >/dev/null 2>&1
}

yes_no() {
  local q="$1"
  local a
  if ! read -r -p "$q [s/N]: " a; then
    echo
    return 1
  fi
  case "$a" in
    s|S|si|SI|Si|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

human_bytes() {
  local kib="$1"
  awk -v kb="$kib" 'BEGIN {
    b = kb * 1024;
    split("B KB MB GB TB", u, " ");
    i = 1;
    while (b >= 1024 && i < 5) { b /= 1024; i++ }
    printf "%.2f %s", b, u[i]
  }'
}

get_public_ip() {
  local ip=""
  if is_cmd curl; then
    ip="$(curl -4 -fsS --max-time 4 https://api.ipify.org 2>/dev/null || true)"
    [ -n "$ip" ] || ip="$(curl -4 -fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)"
  elif is_cmd wget; then
    ip="$(wget -qO- --timeout=4 https://api.ipify.org 2>/dev/null || true)"
  fi
  printf "%s" "$ip"
}

system_summary() {
  local os kernel uptime load cpu_model cpu_count mem_total_kib mem_avail_kib
  os="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Desconocido}")"
  kernel="$(uname -r)"
  uptime="$(uptime -p 2>/dev/null || true)"
  load="$(awk '{print $1" "$2" "$3}' /proc/loadavg)"
  cpu_model="$(awk -F: '/model name/ {gsub(/^ +/, "", $2); print $2; exit}' /proc/cpuinfo)"
  cpu_count="$(nproc --all 2>/dev/null || echo "?")"
  mem_total_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
  mem_avail_kib="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"

  print_title "Sistema"
  echo "OS:             $os"
  echo "Kernel:         $kernel"
  echo "Uptime:         ${uptime:-N/A}"
  echo "Load avg:       $load"
  echo "CPU:            ${cpu_model:-N/A}"
  echo "vCPU:           $cpu_count"
  echo "RAM total:      $(human_bytes "$mem_total_kib")"
  echo "RAM disponible: $(human_bytes "$mem_avail_kib")"
}

network_summary() {
  local hostname fqdn local_ips default_iface default_gw public_ip
  hostname="$(hostname 2>/dev/null || true)"
  fqdn="$(hostname -f 2>/dev/null || echo "$hostname")"
  local_ips="$(hostname -I 2>/dev/null | xargs || true)"
  default_iface="$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')"
  default_gw="$(ip route 2>/dev/null | awk '/default/ {print $3; exit}')"
  public_ip="$(get_public_ip)"

  print_title "Red y Ubicacion"
  echo "Hostname:       ${hostname:-N/A}"
  echo "FQDN:           ${fqdn:-N/A}"
  echo "IPs locales:    ${local_ips:-N/A}"
  echo "Interfaz WAN:   ${default_iface:-N/A}"
  echo "Gateway:        ${default_gw:-N/A}"
  if [ -n "$public_ip" ]; then
    echo "IP publica:     $public_ip"
  else
    echo "IP publica:     N/A (${C_WARN}sin salida o sin curl/wget${C_RESET})"
  fi
}

disk_summary() {
  print_title "Discos"
  df -hT / | awk 'NR==1 || NR==2 {print}'
}

baseline_checks() {
  print_title "Chequeos Iniciales"

  local ok=0 warn=0
  local mem_total_mib root_free_gib
  mem_total_mib="$(awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo)"
  root_free_gib="$(df -BG / | awk 'NR==2 {gsub("G", "", $4); print $4}')"

  if [ "$mem_total_mib" -ge 1024 ]; then
    echo "${C_OK}[OK]${C_RESET} RAM >= 1GB (${mem_total_mib} MiB)"
    ok=$((ok + 1))
  else
    echo "${C_WARN}[WARN]${C_RESET} RAM baja (${mem_total_mib} MiB). Recomendado >= 1GB"
    warn=$((warn + 1))
  fi

  if [ "$root_free_gib" -ge 5 ]; then
    echo "${C_OK}[OK]${C_RESET} Disco libre >= 5GB (${root_free_gib} GiB)"
    ok=$((ok + 1))
  else
    echo "${C_WARN}[WARN]${C_RESET} Poco disco libre (${root_free_gib} GiB). Recomendado >= 5GB"
    warn=$((warn + 1))
  fi

  if is_service_active ssh || is_service_active sshd; then
    echo "${C_OK}[OK]${C_RESET} SSH activo"
    ok=$((ok + 1))
  else
    echo "${C_WARN}[WARN]${C_RESET} SSH no activo"
    warn=$((warn + 1))
  fi

  if is_cmd nginx; then
    echo "${C_OK}[OK]${C_RESET} Nginx instalado"
    ok=$((ok + 1))
  else
    echo "${C_WARN}[WARN]${C_RESET} Nginx no instalado"
    warn=$((warn + 1))
  fi

  if is_cmd sqlite3; then
    echo "${C_OK}[OK]${C_RESET} SQLite instalado"
    ok=$((ok + 1))
  else
    echo "${C_WARN}[WARN]${C_RESET} SQLite no instalado"
    warn=$((warn + 1))
  fi

  line
  echo "Resultado: OK=$ok WARN=$warn"
}

save_report() {
  local out
  out="$LOG_DIR/diagnostico_$(date +%Y%m%d_%H%M%S).txt"
  {
    echo "$APP_NAME $APP_VERSION"
    echo "Fecha: $(date --iso-8601=seconds)"
    echo "Ruta app: $APP_DIR"
    line
    system_summary
    network_summary
    disk_summary
    baseline_checks
  } | sed 's/\x1b\[[0-9;]*m//g' > "$out"
  echo
  echo "Reporte guardado en: $out"
}

utility_status_line() {
  local name="$1"
  local cmd="$2"
  if is_cmd "$cmd"; then
    echo "${C_OK}[OK]${C_RESET} $name"
  else
    echo "${C_WARN}[PEND]${C_RESET} $name"
  fi
}

utility_status_service() {
  local name="$1"
  local svc="$2"
  if systemctl list-unit-files 2>/dev/null | awk '{print $1}' | grep -qx "${svc}.service"; then
    echo "${C_OK}[OK]${C_RESET} $name"
  else
    echo "${C_WARN}[PEND]${C_RESET} $name"
  fi
}

utility_overview() {
  print_title "Lista de utilidades necesarias"
  utility_status_line "Nginx reverse proxy" nginx
  utility_status_line "Node.js + npm (Express REST + npm server)" node
  utility_status_line "SQLite3" sqlite3
  utility_status_line "Certbot (SSL Let\'s Encrypt)" certbot
  utility_status_line "Firewall UFW" ufw
  utility_status_line "SMTP (Postfix/mailutils)" postfix
  utility_status_line "Git" git
  utility_status_service "FTP (vsftpd)" vsftpd
  line
  echo "DNS del dominio se configura en el proveedor (externo al servidor)."
  echo "Luego se valida aqui con dig/nslookup."
}

configure_dns_domain() {
  local domain www email
  echo "Dominio actual: $(cfg_get DOMAIN "sin-definir")"
  if ! read -r -p "Dominio principal (ej: ejemplo.com): " domain; then return 1; fi
  if [ -n "$domain" ]; then
    if ! is_valid_domain "$domain"; then
      echo "${C_ERR}Dominio invalido.${C_RESET}"
      return 1
    fi
    cfg_set DOMAIN "$domain"
  fi

  if ! read -r -p "Subdominio WWW (ej: www.ejemplo.com, Enter para omitir): " www; then return 1; fi
  if [ -n "$www" ]; then
    if ! is_valid_domain "$www"; then
      echo "${C_ERR}Subdominio WWW invalido.${C_RESET}"
      return 1
    fi
    cfg_set DOMAIN_WWW "$www"
  fi

  if ! read -r -p "Email admin para SSL (ej: admin@ejemplo.com): " email; then return 1; fi
  if [ -n "$email" ]; then
    if ! is_valid_email "$email"; then
      echo "${C_ERR}Email invalido.${C_RESET}"
      return 1
    fi
    cfg_set ADMIN_EMAIL "$email"
  fi

  echo "Configuracion DNS guardada en $CONFIG_FILE"
}

check_dns_records() {
  local domain www public_ip
  domain="$(cfg_get DOMAIN "")"
  www="$(cfg_get DOMAIN_WWW "")"
  public_ip="$(get_public_ip)"

  if [ -z "$domain" ]; then
    echo "Define primero DOMAIN desde este menu."
    return
  fi

  print_title "Chequeo DNS"
  echo "IP publica detectada: ${public_ip:-N/A}"
  echo "A de $domain:"
  if is_cmd dig; then
    dig +short A "$domain" || true
  else
    getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u || true
  fi

  if [ -n "$www" ]; then
    echo
    echo "A/CNAME de $www:"
    if is_cmd dig; then
      dig +short A "$www" || true
      dig +short CNAME "$www" || true
    else
      getent ahostsv4 "$www" 2>/dev/null | awk '{print $1}' | sort -u || true
    fi
  fi
}

domain_points_to_this_server() {
  local domain="$1"
  local public_ip resolved
  public_ip="$(get_public_ip)"
  [ -n "$public_ip" ] || return 1

  if is_cmd dig; then
    resolved="$(dig +short A "$domain" | xargs)"
  else
    resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | xargs)"
  fi

  for ip in $resolved; do
    if [ "$ip" = "$public_ip" ]; then
      return 0
    fi
  done
  return 1
}

page_dns() {
  while true; do
    print_title "DNS y Dominio"
    echo "1) Definir dominio/admin email"
    echo "2) Verificar registros DNS"
    echo "3) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar dominio" configure_dns_domain ;;
      2) run_and_pause "Verificar DNS" check_dns_records ;;
      3) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

nginx_get_lb_info() {
  local enabled algo backends
  enabled="$(cfg_get LB_ENABLED "0")"
  algo="$(cfg_get LB_ALGO "round_robin")"
  backends="$(cfg_get LB_BACKENDS "")"
  if [ "$enabled" = "1" ]; then
    echo "ON ($algo) -> ${backends:-sin-backends}"
  else
    echo "OFF"
  fi
}

nginx_configure_load_balancing() {
  local enable algo backends normalized token first backend_port
  backend_port="$(cfg_get BACKEND_PORT "3000")"

  echo "Balanceo actual: $(nginx_get_lb_info)"
  if ! read -r -p "Habilitar load balancing? [s/N]: " enable; then return 1; fi
  case "$enable" in
    s|S|si|SI|Si|y|Y|yes|YES) cfg_set LB_ENABLED "1" ;;
    *) cfg_set LB_ENABLED "0"; echo "Load balancing deshabilitado."; return 0 ;;
  esac

  echo "Algoritmo actual: $(cfg_get LB_ALGO "round_robin")"
  echo "1) round_robin"
  echo "2) least_conn"
  echo "3) ip_hash"
  if ! read -r -p "Elegi algoritmo [1-3] (default 1): " algo; then return 1; fi
  case "${algo:-1}" in
    1) cfg_set LB_ALGO "round_robin" ;;
    2) cfg_set LB_ALGO "least_conn" ;;
    3) cfg_set LB_ALGO "ip_hash" ;;
    *) echo "Algoritmo invalido."; return 1 ;;
  esac

  echo "Backends actuales: $(cfg_get LB_BACKENDS "127.0.0.1:$backend_port")"
  if ! read -r -p "Backends (host:puerto separados por coma): " backends; then return 1; fi
  backends="${backends:-127.0.0.1:$backend_port}"
  normalized=""
  first=1
  for token in ${backends//,/ }; do
    [ -n "$token" ] || continue
    if ! is_valid_backend_endpoint "$token"; then
      echo "Backend invalido: $token"
      return 1
    fi
    if [ "$first" -eq 1 ]; then
      normalized="$token"
      first=0
    else
      normalized="$normalized,$token"
    fi
  done
  [ -n "$normalized" ] || { echo "Debes indicar al menos un backend."; return 1; }
  cfg_set LB_BACKENDS "$normalized"
  echo "Load balancing guardado: $(nginx_get_lb_info)"
}

nginx_write_site() {
  local domain backend_port root_dir conf profile app_dir
  local lb_enabled lb_algo lb_backends upstream_name lb_algo_line lb_servers proxy_target
  domain="$(cfg_get DOMAIN "")"
  backend_port="$(cfg_get BACKEND_PORT "3000")"
  profile="$(cfg_get APP_PROFILE "")"
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  lb_enabled="$(cfg_get LB_ENABLED "0")"
  lb_algo="$(cfg_get LB_ALGO "round_robin")"
  lb_backends="$(cfg_get LB_BACKENDS "")"
  upstream_name="panelisimo_backend"
  lb_algo_line=""
  lb_servers=""
  proxy_target="http://127.0.0.1:$backend_port"

  if [ -z "$domain" ]; then
    echo "Debes definir DOMAIN en la seccion DNS primero."
    return 1
  fi

  root_dir="/var/www/$domain/public"
  conf="/etc/nginx/sites-available/$domain.conf"
  require_root || return 1
  nginx_backup_site_conf "$domain" || true

  mkdir -p "$root_dir"

  if [ "$profile" = "carthtml" ] && [ "$lb_enabled" = "1" ]; then
    [ -n "$lb_backends" ] || { echo "LB habilitado pero sin backends configurados."; return 1; }
    case "$lb_algo" in
      round_robin) lb_algo_line="" ;;
      least_conn) lb_algo_line="    least_conn;" ;;
      ip_hash) lb_algo_line="    ip_hash;" ;;
      *) echo "Algoritmo LB invalido: $lb_algo"; return 1 ;;
    esac
    for token in ${lb_backends//,/ }; do
      [ -n "$token" ] || continue
      if ! is_valid_backend_endpoint "$token"; then
        echo "Backend LB invalido: $token"
        return 1
      fi
      lb_servers="${lb_servers}    server $token max_fails=3 fail_timeout=10s;"$'\n'
    done
    [ -n "$lb_servers" ] || { echo "No se pudo generar upstream LB."; return 1; }
    proxy_target="http://$upstream_name"
  fi

  if [ "$profile" = "carthtml" ]; then
    if [ "$lb_enabled" = "1" ]; then
      cat > "$conf" <<EOC
upstream $upstream_name {
$lb_algo_line
$lb_servers}

server {
    listen 80;
    server_name $domain $(cfg_get DOMAIN_WWW "");
    root $app_dir/public;

    location ~* \.(css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico|woff|woff2)$ {
        try_files \$uri @app;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        access_log off;
    }

    location /uploads/ {
        try_files \$uri @app;
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
    }

    location ~* \.(html)$ {
        try_files \$uri @app;
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }

    location / {
        try_files \$uri @app;
    }

    location @app {
        proxy_pass $proxy_target;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOC
    else
    cat > "$conf" <<EOC
server {
    listen 80;
    server_name $domain $(cfg_get DOMAIN_WWW "");
    root $app_dir/public;

    location ~* \.(css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico|woff|woff2)$ {
        try_files \$uri @app;
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        access_log off;
    }

    location /uploads/ {
        try_files \$uri @app;
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
    }

    location ~* \.(html)$ {
        try_files \$uri @app;
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }

    location / {
        try_files \$uri @app;
    }

    location @app {
        proxy_pass $proxy_target;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOC
    fi
  else
    cat > "$conf" <<EOC
server {
    listen 80;
    server_name $domain $(cfg_get DOMAIN_WWW "");

    root $root_dir;
    index index.html;

    location ~* \.(css|js|mjs|png|jpg|jpeg|gif|webp|svg|ico|woff|woff2)$ {
        expires 30d;
        add_header Cache-Control "public, max-age=2592000, immutable" always;
        access_log off;
    }

    location /uploads/ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800" always;
    }

    location ~* \.(html)$ {
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate" always;
    }

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:$backend_port/;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOC
  fi

  echo "Archivo generado: $conf"
  if [ "$profile" = "carthtml" ]; then
    if [ "$lb_enabled" = "1" ]; then
      echo "Modo Nginx: load balancing $lb_algo -> $lb_backends"
    else
      echo "Modo Nginx: reverse proxy completo -> 127.0.0.1:$backend_port"
    fi
  else
    echo "Directorio frontend: $root_dir"
  fi
}

nginx_apply_cache_defaults() {
  nginx_write_site
  nginx_enable_site
  echo "Politica de cache aplicada en Nginx."
}

nginx_backup_site_conf() {
  local domain="$1"
  local src backup_dir dst
  src="/etc/nginx/sites-available/$domain.conf"
  backup_dir="$LOG_DIR/nginx-backups/$domain"
  mkdir -p "$backup_dir"
  if [ -f "$src" ]; then
    dst="$backup_dir/${domain}.conf.$(date +%Y%m%d_%H%M%S).bak"
    cp "$src" "$dst"
    echo "Backup Nginx creado: $dst"
  fi
}

nginx_reload_safe() {
  require_root || return 1
  nginx -t
  systemctl reload nginx
}

nginx_restart_service() {
  require_root || return 1
  systemctl restart nginx
}

restart_web_stack() {
  local svc
  svc="$(cfg_get BACKEND_SERVICE "carthtml")"
  require_root || return 1
  nginx -t
  systemctl reload nginx
  systemctl restart "$svc"
}

nginx_emergency_http_restore() {
  local domain www conf backend_port
  domain="$(cfg_get DOMAIN "")"
  www="$(cfg_get DOMAIN_WWW "")"
  backend_port="$(cfg_get BACKEND_PORT "3000")"
  conf="/etc/nginx/sites-available/$domain.conf"

  [ -n "$domain" ] || { echo "Define DOMAIN primero."; return 1; }
  require_root || return 1
  nginx_backup_site_conf "$domain" || true

  cat > "$conf" <<EOC
server {
    listen 80;
    server_name $domain $www;

    location / {
        proxy_pass http://127.0.0.1:$backend_port;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOC

  ln -sf "$conf" "/etc/nginx/sites-enabled/$domain.conf"
  nginx -t
  systemctl reload nginx
  echo "Recovery HTTP aplicado para $domain."
}

nginx_repair_https_certbot() {
  local domain www email
  domain="$(cfg_get DOMAIN "")"
  www="$(cfg_get DOMAIN_WWW "")"
  email="$(cfg_get ADMIN_EMAIL "")"

  [ -n "$domain" ] || { echo "Define DOMAIN primero."; return 1; }
  [ -n "$email" ] || { echo "Define ADMIN_EMAIL primero."; return 1; }
  require_root || return 1
  is_cmd certbot || { echo "certbot no instalado."; return 1; }
  is_cmd nginx || { echo "nginx no instalado."; return 1; }

  if [ -n "$www" ]; then
    certbot --nginx -d "$domain" -d "$www" --agree-tos -m "$email" --redirect --non-interactive
  else
    certbot --nginx -d "$domain" --agree-tos -m "$email" --redirect --non-interactive
  fi
}

nginx_enable_site() {
  local domain conf_link
  domain="$(cfg_get DOMAIN "")"

  if [ -z "$domain" ]; then
    echo "Debes definir DOMAIN primero."
    return 1
  fi

  require_root || return 1
  conf_link="/etc/nginx/sites-enabled/$domain.conf"
  ln -sf "/etc/nginx/sites-available/$domain.conf" "$conf_link"
  nginx -t
  systemctl reload nginx
  echo "Sitio habilitado y Nginx recargado."
}

nginx_rollback_last_conf() {
  local domain backup_dir latest dst
  domain="$(cfg_get DOMAIN "")"
  [ -n "$domain" ] || { echo "Define DOMAIN primero."; return 1; }
  require_root || return 1

  backup_dir="$LOG_DIR/nginx-backups/$domain"
  [ -d "$backup_dir" ] || { echo "No hay carpeta de backups: $backup_dir"; return 1; }

  latest="$(ls -1t "$backup_dir"/*.bak 2>/dev/null | head -n1 || true)"
  [ -n "$latest" ] || { echo "No hay backups para $domain."; return 1; }

  dst="/etc/nginx/sites-available/$domain.conf"
  cp "$latest" "$dst"
  ln -sf "$dst" "/etc/nginx/sites-enabled/$domain.conf"
  nginx -t
  systemctl reload nginx
  echo "Rollback aplicado desde: $latest"
}

page_nginx() {
  while true; do
    print_title "Nginx Reverse Proxy"
    echo "Dominio: $(cfg_get DOMAIN "sin-definir")"
    echo "Puerto backend: $(cfg_get BACKEND_PORT "3000")"
    echo "Load balancing: $(nginx_get_lb_info)"
    line
    echo "1) Instalar Nginx"
    echo "2) Generar server block"
    echo "3) Aplicar cache recomendado (auto)"
    echo "4) Habilitar sitio y recargar Nginx"
    echo "5) Reload Nginx (config test)"
    echo "6) Restart Nginx"
    echo "7) Restart stack web (Nginx + backend)"
    echo "8) Ver estado Nginx"
    echo "9) Recovery HTTP minimo (emergencia)"
    echo "10) Reparar HTTPS con Certbot"
    echo "11) Rollback ultima config Nginx"
    echo "12) Configurar load balancing"
    echo "13) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Instalar Nginx" install_packages nginx ;;
      2) run_and_pause "Generar server block" nginx_write_site ;;
      3) run_and_pause "Aplicar cache recomendado en Nginx" nginx_apply_cache_defaults ;;
      4) run_and_pause "Habilitar sitio Nginx" nginx_enable_site ;;
      5) run_and_pause "Reload Nginx seguro" nginx_reload_safe ;;
      6) run_and_pause "Restart Nginx" nginx_restart_service ;;
      7) run_and_pause "Restart stack web" restart_web_stack ;;
      8) run_and_pause "Ver estado Nginx" systemctl status nginx --no-pager ;;
      9) run_and_pause "Recovery HTTP emergencia" nginx_emergency_http_restore ;;
      10) run_and_pause "Reparar HTTPS con certbot" nginx_repair_https_certbot ;;
      11) run_and_pause "Rollback Nginx" nginx_rollback_last_conf ;;
      12) run_and_pause "Configurar load balancing" nginx_configure_load_balancing ;;
      13) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

configure_backend_vars() {
  local port service_dir service_name
  echo "Puerto backend actual: $(cfg_get BACKEND_PORT "3000")"
  if ! read -r -p "Nuevo puerto backend (default 3000): " port; then return 1; fi
  port="${port:-3000}"
  if ! is_valid_port "$port"; then
    echo "${C_ERR}Puerto invalido: $port${C_RESET}"
    return 1
  fi
  cfg_set BACKEND_PORT "$port"

  echo "Ruta app backend actual: $(cfg_get BACKEND_APP_DIR "/opt/panelisimo/api")"
  if ! read -r -p "Ruta app backend (default /opt/panelisimo/api): " service_dir; then return 1; fi
  service_dir="${service_dir:-/opt/panelisimo/api}"
  cfg_set BACKEND_APP_DIR "$service_dir"

  echo "Servicio systemd actual: $(cfg_get BACKEND_SERVICE "panelisimo-api")"
  if ! read -r -p "Nombre servicio systemd (default panelisimo-api): " service_name; then return 1; fi
  service_name="${service_name:-panelisimo-api}"
  cfg_set BACKEND_SERVICE "$service_name"

  echo "Variables backend guardadas."
}

backend_write_service() {
  local app_dir svc
  app_dir="$(cfg_get BACKEND_APP_DIR "/opt/panelisimo/api")"
  svc="$(cfg_get BACKEND_SERVICE "panelisimo-api")"

  require_root || return 1
  is_cmd npm || { echo "npm no instalado."; return 1; }
  [ -d "$app_dir" ] || { echo "No existe la ruta backend: $app_dir"; return 1; }

  cat > "/etc/systemd/system/$svc.service" <<EOC
[Unit]
Description=Panelisimo Express API
After=network.target

[Service]
Type=simple
WorkingDirectory=$app_dir
Environment=NODE_ENV=production
Environment=PORT=$(cfg_get BACKEND_PORT "3000")
EnvironmentFile=-$app_dir/deploy/env
ExecStart=/usr/bin/npm start
Restart=always
RestartSec=3
User=www-data
Group=www-data

[Install]
WantedBy=multi-user.target
EOC

  systemctl daemon-reload
  systemctl enable "$svc"
  echo "Servicio generado: /etc/systemd/system/$svc.service"
}

restart_backend_service() {
  local svc
  svc="$(cfg_get BACKEND_SERVICE "panelisimo-api")"
  require_root || return 1
  systemctl restart "$svc"
}

backend_service_status() {
  local svc
  svc="$(cfg_get BACKEND_SERVICE "panelisimo-api")"
  systemctl status "$svc" --no-pager
}

backend_sync_npm_modules() {
  local app_dir
  app_dir="$(cfg_get BACKEND_APP_DIR "/opt/panelisimo/api")"
  [ -f "$app_dir/package.json" ] || { echo "No existe package.json en $app_dir"; return 1; }
  is_cmd npm || { echo "npm no instalado."; return 1; }

  npm --prefix "$app_dir" install
  if grep -q '"icons:vendor"' "$app_dir/package.json"; then
    npm --prefix "$app_dir" run icons:vendor
  fi
  if grep -q '"tw:build"' "$app_dir/package.json"; then
    npm --prefix "$app_dir" run tw:build
  fi
}

backend_apply_express_api_nocache() {
  local app_dir server_file mod_dir mod_file
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  server_file="$app_dir/server.js"
  mod_dir="$app_dir/mod"
  mod_file="$mod_dir/cache_policy.js"

  [ -f "$server_file" ] || { echo "No existe server.js en $app_dir"; return 1; }
  mkdir -p "$mod_dir"

  cat > "$mod_file" <<'EOC'
function applyApiNoCache(app) {
  app.use((req, res, next) => {
    if (req.path && req.path.startsWith("/api/")) {
      res.set("Cache-Control", "no-store, no-cache, must-revalidate, private");
      res.set("Pragma", "no-cache");
      res.set("Expires", "0");
    }
    next();
  });
}

module.exports = { applyApiNoCache };
EOC

  if ! grep -q 'mod/cache_policy' "$server_file"; then
    if grep -q 'const express = require("express");' "$server_file"; then
      sed -i '/const express = require("express");/a const { applyApiNoCache } = require("./mod/cache_policy");' "$server_file"
    elif grep -q "const express = require('express');" "$server_file"; then
      sed -i "/const express = require('express');/a const { applyApiNoCache } = require('./mod/cache_policy');" "$server_file"
    else
      echo 'const { applyApiNoCache } = require("./mod/cache_policy");' | cat - "$server_file" > "$server_file.tmp"
      mv "$server_file.tmp" "$server_file"
    fi
  fi

  if ! grep -q 'applyApiNoCache(app);' "$server_file"; then
    if grep -q 'const app = express();' "$server_file"; then
      sed -i '/const app = express();/a applyApiNoCache(app);' "$server_file"
    elif grep -q 'let app = express();' "$server_file"; then
      sed -i '/let app = express();/a applyApiNoCache(app);' "$server_file"
    else
      echo "No pude ubicar 'app = express()' para inyectar middleware."
      return 1
    fi
  fi

  chown -R www-data:www-data "$mod_dir" "$server_file" 2>/dev/null || true
  echo "Middleware no-cache aplicado para rutas /api/*."
}

page_backend() {
  while true; do
    print_title "Backend REST Express + npm server"
    echo "Puerto: $(cfg_get BACKEND_PORT "3000")"
    echo "App dir: $(cfg_get BACKEND_APP_DIR "/opt/panelisimo/api")"
    echo "Service: $(cfg_get BACKEND_SERVICE "panelisimo-api")"
    line
    echo "1) Definir parametros backend"
    echo "2) Instalar Node.js + npm"
    echo "3) Generar servicio systemd"
    echo "4) Iniciar/Reiniciar servicio"
    echo "5) Ver estado servicio"
    echo "6) Sincronizar modulos npm"
    echo "7) Aplicar no-cache API en Express"
    echo "8) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar backend" configure_backend_vars ;;
      2) run_and_pause "Instalar Node.js y npm" install_packages nodejs npm ;;
      3) run_and_pause "Generar servicio systemd" backend_write_service ;;
      4) run_and_pause "Reiniciar backend" restart_backend_service ;;
      5) run_and_pause "Ver estado backend" backend_service_status ;;
      6) run_and_pause "Sincronizar modulos npm" backend_sync_npm_modules ;;
      7) run_and_pause "Aplicar no-cache API en Express" backend_apply_express_api_nocache ;;
      8) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

configure_sqlite_path() {
  local db
  echo "DB actual: $(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
  if ! read -r -p "Ruta SQLite (default /opt/panelisimo/data/app.db): " db; then return 1; fi
  db="${db:-/opt/panelisimo/data/app.db}"
  cfg_set SQLITE_DB_PATH "$db"
  echo "Ruta SQLite guardada."
}

sqlite_create_db() {
  local db dir
  db="$(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
  dir="$(dirname "$db")"
  require_root || return 1
  is_cmd sqlite3 || { echo "sqlite3 no instalado."; return 1; }
  mkdir -p "$dir"
  sqlite3 "$db" 'PRAGMA journal_mode=WAL;' >/dev/null
  chown -R www-data:www-data "$dir"
  chmod 750 "$dir"
  chmod 640 "$db"
  echo "DB lista en: $db"
}

sqlite_test() {
  local db
  db="$(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
  if [ ! -f "$db" ]; then
    echo "DB no existe: $db"
    return
  fi
  sqlite3 "$db" 'select datetime("now") as now_utc;' || true
}

sqlite_apply_cache_profile() {
  local profile db cache_kib mmap_bytes
  db="$(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
  [ -f "$db" ] || { echo "DB no existe: $db"; return 1; }
  is_cmd sqlite3 || { echo "sqlite3 no instalado."; return 1; }

  echo "Perfiles de cache SQLite:"
  echo "1) suave  (cache 8MB, mmap 128MB)"
  echo "2) medio  (cache 16MB, mmap 256MB)"
  if ! read -r -p "Elegi perfil [1-2]: " profile; then return 1; fi

  case "$profile" in
    1) cache_kib=8192; mmap_bytes=134217728 ;;
    2) cache_kib=16384; mmap_bytes=268435456 ;;
    *) echo "Perfil invalido."; return 1 ;;
  esac

  sqlite3 "$db" <<SQL
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=-$cache_kib;
PRAGMA temp_store=MEMORY;
PRAGMA busy_timeout=5000;
PRAGMA mmap_size=$mmap_bytes;
SQL

  echo "Perfil SQLite aplicado sobre: $db"
}

sqlite_show_tuning() {
  local db
  db="$(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
  [ -f "$db" ] || { echo "DB no existe: $db"; return 1; }
  is_cmd sqlite3 || { echo "sqlite3 no instalado."; return 1; }
  sqlite3 "$db" <<'SQL'
PRAGMA journal_mode;
PRAGMA synchronous;
PRAGMA cache_size;
PRAGMA temp_store;
PRAGMA busy_timeout;
PRAGMA mmap_size;
SQL
}

page_sqlite() {
  while true; do
    print_title "SQLite"
    echo "DB path: $(cfg_get SQLITE_DB_PATH "/opt/panelisimo/data/app.db")"
    line
    echo "1) Definir ruta DB"
    echo "2) Instalar sqlite3"
    echo "3) Crear DB + permisos"
    echo "4) Probar consulta"
    echo "5) Aplicar cache SQLite (suave/medio)"
    echo "6) Ver tuning actual"
    echo "7) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar ruta SQLite" configure_sqlite_path ;;
      2) run_and_pause "Instalar sqlite3" install_packages sqlite3 ;;
      3) run_and_pause "Crear DB SQLite" sqlite_create_db ;;
      4) run_and_pause "Probar SQLite" sqlite_test ;;
      5) run_and_pause "Aplicar cache SQLite" sqlite_apply_cache_profile ;;
      6) run_and_pause "Ver tuning SQLite" sqlite_show_tuning ;;
      7) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

ssl_issue_cert() {
  local domain www email
  domain="$(cfg_get DOMAIN "")"
  www="$(cfg_get DOMAIN_WWW "")"
  email="$(cfg_get ADMIN_EMAIL "")"

  if [ -z "$domain" ] || [ -z "$email" ]; then
    echo "Define DOMAIN y ADMIN_EMAIL primero en DNS y Dominio."
    return 1
  fi

  require_root || return 1
  is_cmd certbot || { echo "certbot no instalado."; return 1; }
  is_cmd nginx || { echo "nginx no instalado."; return 1; }

  if [ -n "$www" ]; then
    certbot --nginx -d "$domain" -d "$www" --agree-tos -m "$email" --redirect --non-interactive
  else
    certbot --nginx -d "$domain" --agree-tos -m "$email" --redirect --non-interactive
  fi
}

page_ssl() {
  while true; do
    print_title "SSL / HTTPS"
    echo "Dominio: $(cfg_get DOMAIN "sin-definir")"
    echo "Email:   $(cfg_get ADMIN_EMAIL "sin-definir")"
    line
    echo "1) Instalar Certbot + plugin Nginx"
    echo "2) Emitir certificado"
    echo "3) Ver certificados"
    echo "4) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Instalar Certbot" install_packages certbot python3-certbot-nginx ;;
      2) run_and_pause "Emitir certificado SSL" ssl_issue_cert ;;
      3) run_and_pause "Listar certificados" certbot certificates ;;
      4) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

configure_smtp_vars() {
  local md mh
  echo "Mail domain actual: $(cfg_get MAIL_DOMAIN "sin-definir")"
  if ! read -r -p "MAIL_DOMAIN (ej: ejemplo.com): " md; then return 1; fi
  if [ -n "$md" ]; then
    if ! is_valid_domain "$md"; then
      echo "${C_ERR}MAIL_DOMAIN invalido.${C_RESET}"
      return 1
    fi
    cfg_set MAIL_DOMAIN "$md"
  fi

  echo "Hostname SMTP actual: $(cfg_get MAIL_HOSTNAME "sin-definir")"
  if ! read -r -p "MAIL_HOSTNAME (ej: mail.ejemplo.com): " mh; then return 1; fi
  if [ -n "$mh" ]; then
    if ! is_valid_domain "$mh"; then
      echo "${C_ERR}MAIL_HOSTNAME invalido.${C_RESET}"
      return 1
    fi
    cfg_set MAIL_HOSTNAME "$mh"
  fi

  echo "Variables SMTP guardadas."
}

smtp_apply_postfix_basic() {
  local md mh
  md="$(cfg_get MAIL_DOMAIN "")"
  mh="$(cfg_get MAIL_HOSTNAME "")"
  if [ -z "$md" ] || [ -z "$mh" ]; then
    echo "Define MAIL_DOMAIN y MAIL_HOSTNAME primero."
    return 1
  fi

  require_root || return 1
  is_cmd postconf || { echo "postconf/postfix no instalado."; return 1; }
  postconf -e "myhostname=$mh"
  postconf -e "mydomain=$md"
  postconf -e "myorigin=\$mydomain"
  postconf -e "inet_interfaces=all"
  postconf -e "mydestination=\$myhostname, localhost.\$mydomain, localhost, \$mydomain"
  postconf -e "mynetworks=127.0.0.0/8 [::1]/128"
  systemctl restart postfix
  echo "Postfix configurado (modo basico)."
  echo "Recuerda publicar DNS MX/SPF/DKIM/DMARC en tu proveedor."
}

page_smtp() {
  while true; do
    print_title "SMTP / Correo de dominio"
    echo "MAIL_DOMAIN:   $(cfg_get MAIL_DOMAIN "sin-definir")"
    echo "MAIL_HOSTNAME: $(cfg_get MAIL_HOSTNAME "sin-definir")"
    line
    echo "1) Definir variables SMTP"
    echo "2) Instalar Postfix + mailutils"
    echo "3) Aplicar configuracion basica Postfix"
    echo "4) Ver estado Postfix"
    echo "5) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar SMTP" configure_smtp_vars ;;
      2) run_and_pause "Instalar Postfix y mailutils" install_packages postfix mailutils ;;
      3) run_and_pause "Aplicar configuracion Postfix" smtp_apply_postfix_basic ;;
      4) run_and_pause "Ver estado Postfix" systemctl status postfix --no-pager ;;
      5) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

firewall_apply_basic() {
  require_root || return 1
  is_cmd ufw || { echo "ufw no instalado."; return 1; }
  ufw allow OpenSSH
  ufw allow 80/tcp
  ufw allow 443/tcp
  ufw --force enable
  ufw status verbose
}

page_firewall() {
  while true; do
    print_title "Firewall"
    echo "1) Instalar UFW"
    echo "2) Aplicar reglas basicas (22, 80, 443)"
    echo "3) Ver estado UFW"
    echo "4) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Instalar UFW" install_packages ufw ;;
      2) run_and_pause "Aplicar reglas firewall" firewall_apply_basic ;;
      3) run_and_pause "Ver estado UFW" ufw status verbose ;;
      4) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

configure_git_vars() {
  local repo branch app_dir
  echo "Repo URL actual: $(cfg_get GIT_REPO_URL "sin-definir")"
  if ! read -r -p "GIT_REPO_URL (HTTPS o SSH): " repo; then return 1; fi
  if [ -n "$repo" ]; then
    cfg_set GIT_REPO_URL "$repo"
  fi

  echo "Branch actual: $(cfg_get GIT_BRANCH "main")"
  if ! read -r -p "GIT_BRANCH (default main): " branch; then return 1; fi
  branch="${branch:-main}"
  cfg_set GIT_BRANCH "$branch"

  echo "Directorio app actual: $(cfg_get GIT_APP_DIR "/opt/panelisimo/app")"
  if ! read -r -p "GIT_APP_DIR (default /opt/panelisimo/app): " app_dir; then return 1; fi
  app_dir="${app_dir:-/opt/panelisimo/app}"
  cfg_set GIT_APP_DIR "$app_dir"

  echo "Configuracion Git guardada."
}

git_clone_or_pull() {
  local repo branch app_dir
  repo="$(cfg_get GIT_REPO_URL "")"
  branch="$(cfg_get GIT_BRANCH "main")"
  app_dir="$(cfg_get GIT_APP_DIR "/opt/panelisimo/app")"

  is_cmd git || { echo "git no instalado."; return 1; }
  [ -n "$repo" ] || { echo "Define GIT_REPO_URL primero."; return 1; }

  if [ -d "$app_dir/.git" ]; then
    git -C "$app_dir" fetch --all --prune
    git -C "$app_dir" checkout "$branch"
    git -C "$app_dir" pull --ff-only origin "$branch"
  else
    mkdir -p "$(dirname "$app_dir")"
    git clone --branch "$branch" "$repo" "$app_dir"
  fi

  echo "Codigo listo en: $app_dir"
}

git_repo_status() {
  local app_dir
  app_dir="$(cfg_get GIT_APP_DIR "/opt/panelisimo/app")"
  [ -d "$app_dir/.git" ] || { echo "No hay repo git en $app_dir"; return 1; }
  git -C "$app_dir" status -sb
  git -C "$app_dir" log --oneline -n 5
}

page_git() {
  while true; do
    print_title "Git / Deploy"
    echo "Repo:   $(cfg_get GIT_REPO_URL "sin-definir")"
    echo "Branch: $(cfg_get GIT_BRANCH "main")"
    echo "Dir:    $(cfg_get GIT_APP_DIR "/opt/panelisimo/app")"
    line
    echo "1) Definir parametros Git"
    echo "2) Instalar Git"
    echo "3) Clonar o actualizar repo"
    echo "4) Ver estado del repo"
    echo "5) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar Git" configure_git_vars ;;
      2) run_and_pause "Instalar Git" install_packages git ;;
      3) run_and_pause "Clonar/actualizar repo" git_clone_or_pull ;;
      4) run_and_pause "Estado del repo" git_repo_status ;;
      5) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

configure_ftp_vars() {
  local user dir pmin pmax
  echo "FTP_USER actual: $(cfg_get FTP_USER "ftpapp")"
  if ! read -r -p "FTP_USER (default ftpapp): " user; then return 1; fi
  user="${user:-ftpapp}"
  cfg_set FTP_USER "$user"

  echo "FTP_DIR actual: $(cfg_get FTP_DIR "/var/www/ftp")"
  if ! read -r -p "FTP_DIR (default /var/www/ftp): " dir; then return 1; fi
  dir="${dir:-/var/www/ftp}"
  cfg_set FTP_DIR "$dir"

  echo "PASV min actual: $(cfg_get FTP_PASV_MIN "30000")"
  if ! read -r -p "FTP_PASV_MIN (default 30000): " pmin; then return 1; fi
  pmin="${pmin:-30000}"
  if ! is_valid_port "$pmin"; then
    echo "${C_ERR}Puerto PASV minimo invalido.${C_RESET}"
    return 1
  fi
  cfg_set FTP_PASV_MIN "$pmin"

  echo "PASV max actual: $(cfg_get FTP_PASV_MAX "30100")"
  if ! read -r -p "FTP_PASV_MAX (default 30100): " pmax; then return 1; fi
  pmax="${pmax:-30100}"
  if ! is_valid_port "$pmax"; then
    echo "${C_ERR}Puerto PASV maximo invalido.${C_RESET}"
    return 1
  fi
  if [ "$pmax" -lt "$pmin" ]; then
    echo "${C_ERR}FTP_PASV_MAX debe ser >= FTP_PASV_MIN.${C_RESET}"
    return 1
  fi
  cfg_set FTP_PASV_MAX "$pmax"

  echo "Configuracion FTP guardada."
}

ftp_create_user() {
  local user dir passwd
  user="$(cfg_get FTP_USER "ftpapp")"
  dir="$(cfg_get FTP_DIR "/var/www/ftp")"
  require_root || return 1

  if ! id "$user" >/dev/null 2>&1; then
    useradd -m -d "$dir" -s /usr/sbin/nologin "$user"
  fi

  mkdir -p "$dir"
  chown "$user":"$user" "$dir"
  chmod 750 "$dir"

  read -r -s -p "Password para $user: " passwd
  echo
  [ -n "$passwd" ] || { echo "Password vacio."; return 1; }
  echo "$user:$passwd" | chpasswd
  echo "Usuario FTP listo: $user"
}

ftp_apply_vsftpd_basic() {
  local pmin pmax conf pub_ip
  pmin="$(cfg_get FTP_PASV_MIN "30000")"
  pmax="$(cfg_get FTP_PASV_MAX "30100")"
  pub_ip="$(get_public_ip)"
  conf="/etc/vsftpd.conf"

  require_root || return 1
  is_cmd vsftpd || { echo "vsftpd no instalado."; return 1; }

  if [ -f "$conf" ]; then
    cp "$conf" "${conf}.bak.$(date +%Y%m%d_%H%M%S)"
  fi

  cat > "$conf" <<EOC
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
pam_service_name=vsftpd
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
pasv_enable=YES
pasv_min_port=$pmin
pasv_max_port=$pmax
EOC

  if [ -n "$pub_ip" ]; then
    echo "pasv_address=$pub_ip" >> "$conf"
  fi

  : > /etc/vsftpd.userlist
  echo "$(cfg_get FTP_USER "ftpapp")" >> /etc/vsftpd.userlist

  systemctl enable vsftpd
  systemctl restart vsftpd
  echo "vsftpd configurado y activo."
}

ftp_open_firewall() {
  local pmin pmax
  pmin="$(cfg_get FTP_PASV_MIN "30000")"
  pmax="$(cfg_get FTP_PASV_MAX "30100")"
  require_root || return 1
  is_cmd ufw || { echo "ufw no instalado."; return 1; }
  ufw allow 21/tcp
  ufw allow "$pmin":"$pmax"/tcp
  ufw status verbose
}

page_ftp() {
  while true; do
    print_title "FTP / vsftpd"
    echo "FTP_USER:   $(cfg_get FTP_USER "ftpapp")"
    echo "FTP_DIR:    $(cfg_get FTP_DIR "/var/www/ftp")"
    echo "PASV range: $(cfg_get FTP_PASV_MIN "30000")-$(cfg_get FTP_PASV_MAX "30100")"
    line
    echo "1) Definir parametros FTP"
    echo "2) Instalar vsftpd"
    echo "3) Crear usuario FTP"
    echo "4) Aplicar configuracion basica vsftpd"
    echo "5) Abrir puertos FTP en UFW"
    echo "6) Ver estado vsftpd"
    echo "7) Volver"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) run_and_pause "Configurar FTP" configure_ftp_vars ;;
      2) run_and_pause "Instalar vsftpd" install_packages vsftpd ;;
      3) run_and_pause "Crear usuario FTP" ftp_create_user ;;
      4) run_and_pause "Configurar vsftpd" ftp_apply_vsftpd_basic ;;
      5) run_and_pause "Abrir puertos FTP" ftp_open_firewall ;;
      6) run_and_pause "Ver estado vsftpd" systemctl status vsftpd --no-pager ;;
      7) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

autowizard_collect_inputs() {
  local domain www email port local_repo default_local

  print_title "Asistente Automatico (next-next)"
  echo "Despliegue guiado para carthtml."
  echo "Completa lo minimo. El resto usa defaults seguros."
  line

  if ! read -r -p "Dominio principal (ej: ejemplo.com): " domain; then return 1; fi
  if ! is_valid_domain "$domain"; then
    echo "${C_ERR}Dominio invalido.${C_RESET}"
    return 1
  fi
  cfg_set DOMAIN "$domain"

  if ! read -r -p "Usar www.$domain tambien? [S/n]: " www; then return 1; fi
  case "$www" in
    n|N|no|NO) cfg_set DOMAIN_WWW "" ;;
    *) cfg_set DOMAIN_WWW "www.$domain" ;;
  esac

  if ! read -r -p "Email admin SSL (default admin@$domain): " email; then return 1; fi
  email="${email:-admin@$domain}"
  if ! is_valid_email "$email"; then
    echo "${C_ERR}Email invalido.${C_RESET}"
    return 1
  fi
  cfg_set ADMIN_EMAIL "$email"

  if ! read -r -p "Puerto backend Express (default 3000): " port; then return 1; fi
  port="${port:-3000}"
  if ! is_valid_port "$port"; then
    echo "${C_ERR}Puerto invalido.${C_RESET}"
    return 1
  fi
  cfg_set BACKEND_PORT "$port"

  cfg_set APP_PROFILE "carthtml"
  cfg_set BACKEND_APP_DIR "/var/www/carthtml"
  cfg_set BACKEND_SERVICE "carthtml"
  cfg_set SQLITE_DB_PATH "/var/www/carthtml/data/store.sqlite"
  cfg_set GIT_REPO_URL "$(cfg_get GIT_REPO_URL "https://github.com/MartinAlejandroOviedo/carthtml.git")"
  cfg_set GIT_BRANCH "$(cfg_get GIT_BRANCH "main")"

  default_local="/home/martin/Documentos/GitHub/carthtml"
  local_repo="$(cfg_get SOURCE_REPO_PATH "$default_local")"
  if [ -d "$local_repo" ] && [ -f "$local_repo/package.json" ]; then
    cfg_set SOURCE_REPO_PATH "$local_repo"
  else
    cfg_set SOURCE_REPO_PATH ""
  fi

  cfg_set FTP_USER "$(cfg_get FTP_USER "ftpapp")"
  cfg_set FTP_DIR "$(cfg_get FTP_DIR "/var/www/ftp")"
  cfg_set FTP_PASV_MIN "$(cfg_get FTP_PASV_MIN "30000")"
  cfg_set FTP_PASV_MAX "$(cfg_get FTP_PASV_MAX "30100")"
}

autowizard_prepare_carthtml_source() {
  local app_dir source_dir repo_url branch
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  source_dir="$(cfg_get SOURCE_REPO_PATH "")"
  repo_url="$(cfg_get GIT_REPO_URL "")"
  branch="$(cfg_get GIT_BRANCH "main")"

  require_root || return 1
  mkdir -p "$(dirname "$app_dir")"

  if [ -n "$source_dir" ] && [ -d "$source_dir" ] && [ -f "$source_dir/package.json" ]; then
    is_cmd rsync || { echo "rsync no instalado."; return 1; }
    mkdir -p "$app_dir"
    rsync -a --delete \
      --exclude ".git/" \
      --exclude "node_modules/" \
      --exclude ".env" \
      "$source_dir"/ "$app_dir"/
    echo "Codigo sincronizado desde path local: $source_dir -> $app_dir"
    return 0
  fi

  [ -n "$repo_url" ] || { echo "GIT_REPO_URL no definido."; return 1; }
  if [ -d "$app_dir/.git" ]; then
    git -C "$app_dir" fetch --all --prune
    git -C "$app_dir" checkout "$branch"
    git -C "$app_dir" pull --ff-only origin "$branch"
    echo "Repo actualizado en $app_dir"
  else
    git clone --branch "$branch" "$repo_url" "$app_dir"
    echo "Repo clonado en $app_dir"
  fi
}

autowizard_prepare_runtime_dirs() {
  local app_dir db_dir uploads_dir
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  db_dir="$(dirname "$(cfg_get SQLITE_DB_PATH "/var/www/carthtml/data/store.sqlite")")"
  uploads_dir="$app_dir/public/uploads"

  require_root || return 1
  mkdir -p "$db_dir" "$uploads_dir"
  chown -R www-data:www-data "$app_dir" "$db_dir"
  find "$app_dir" -type d -exec chmod 755 {} + 2>/dev/null || true
  find "$app_dir" -type f -exec chmod 644 {} + 2>/dev/null || true
}

autowizard_build_carthtml() {
  local app_dir
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  [ -f "$app_dir/package.json" ] || { echo "No existe package.json en $app_dir"; return 1; }
  npm --prefix "$app_dir" install
  npm --prefix "$app_dir" run icons:vendor
  npm --prefix "$app_dir" run tw:build
}

autowizard_write_env_file() {
  local app_dir env_file
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  env_file="$app_dir/deploy/env"

  require_root || return 1
  mkdir -p "$app_dir/deploy"
  cat > "$env_file" <<EOC
NODE_ENV=production
PORT=$(cfg_get BACKEND_PORT "3000")
PANEL_SERVICE_NAME=$(cfg_get BACKEND_SERVICE "carthtml")
EOC
  chown www-data:www-data "$env_file"
  chmod 640 "$env_file"
}

autowizard_ssl_if_ready() {
  local domain www email
  domain="$(cfg_get DOMAIN "")"
  www="$(cfg_get DOMAIN_WWW "")"
  email="$(cfg_get ADMIN_EMAIL "")"

  if ! domain_points_to_this_server "$domain"; then
    echo "${C_WARN}[WARN]${C_RESET} DNS de $domain aun no apunta a este servidor. SSL omitido por ahora."
    return 0
  fi

  if [ -n "$www" ] && ! domain_points_to_this_server "$www"; then
    echo "${C_WARN}[WARN]${C_RESET} DNS de $www no apunta a este servidor. Emitiendo solo para $domain."
    www=""
  fi

  if [ -n "$www" ]; then
    certbot --nginx -d "$domain" -d "$www" --agree-tos -m "$email" --redirect --non-interactive
  else
    certbot --nginx -d "$domain" --agree-tos -m "$email" --redirect --non-interactive
  fi
}

autowizard_run_all() {
  local app_dir
  app_dir="$(cfg_get BACKEND_APP_DIR "/var/www/carthtml")"
  print_title "Ejecucion automatica"
  run_action "Instalar paquetes base" install_packages ca-certificates curl python3 build-essential rsync nginx certbot python3-certbot-nginx sqlite3 ufw nodejs npm git
  run_action "Sincronizar codigo carthtml" autowizard_prepare_carthtml_source
  run_action "Preparar permisos y directorios runtime" autowizard_prepare_runtime_dirs
  run_action "Instalar dependencias y build" autowizard_build_carthtml
  run_action "Escribir archivo deploy/env" autowizard_write_env_file
  run_action "Crear DB SQLite" sqlite_create_db
  run_action "Generar server block Nginx" nginx_write_site
  run_action "Habilitar sitio Nginx" nginx_enable_site
  run_action "Generar servicio backend" backend_write_service
  run_action "Reiniciar backend" restart_backend_service
  run_action "Aplicar firewall web" firewall_apply_basic
  run_action "Intentar emitir SSL (si DNS esta listo)" autowizard_ssl_if_ready

  line
  echo "${C_OK}Asistente finalizado.${C_RESET}"
  echo "Resumen:"
  echo "- Dominio: $(cfg_get DOMAIN "") $(cfg_get DOMAIN_WWW "")"
  echo "- App dir:  $app_dir"
  echo "- Frontend: $app_dir/public"
  echo "- Service:  $(cfg_get BACKEND_SERVICE "carthtml")"
  echo "- DB:       $(cfg_get SQLITE_DB_PATH "/var/www/carthtml/data/store.sqlite")"
  echo "- Errores:  $LOG_DIR/errors.log (si hubo)"
}

page_autowizard() {
  if run_action "Recolectar datos asistente" autowizard_collect_inputs; then
    pause_enter
  else
    pause_enter
    return
  fi
  if yes_no "Iniciar instalacion automatica ahora?"; then
    run_and_pause "Instalador automatico" autowizard_run_all
  fi
}

option_instalacion() {
  while true; do
    print_title "Paso 2: Instalacion y Configuracion"
    echo "1) Asistente automatico (next-next)"
    echo "2) Ver lista de utilidades necesarias"
    echo "3) DNS y dominio"
    echo "4) Nginx reverse proxy"
    echo "5) Backend REST Express + npm"
    echo "6) SQLite"
    echo "7) SSL / HTTPS"
    echo "8) SMTP dominio"
    echo "9) Firewall"
    echo "10) Git / Deploy"
    echo "11) FTP / Transferencia"
    echo "12) Volver al menu principal"
    line
    if ! read -r -p "Opcion: " opt; then return; fi
    case "$opt" in
      1) page_autowizard ;;
      2) run_and_pause "Ver utilidades requeridas" utility_overview ;;
      3) page_dns ;;
      4) page_nginx ;;
      5) page_backend ;;
      6) page_sqlite ;;
      7) page_ssl ;;
      8) page_smtp ;;
      9) page_firewall ;;
      10) page_git ;;
      11) page_ftp ;;
      12) return ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

offer_step2_or_exit() {
  line
  if yes_no "Pasar ahora al Paso 2 (instalacion/configuracion)?"; then
    option_instalacion
  else
    if yes_no "Quieres salir de panelisimo?"; then
      exit 0
    fi
  fi
}

option_diagnostico_inicial() {
  print_title "Diagnostico Inicial"
  echo "App:            $APP_NAME v$APP_VERSION"
  echo "Ruta app:       $APP_DIR"
  echo "Usuario actual: $(whoami)"
  echo "Fecha:          $(date --iso-8601=seconds)"
  line

  system_summary
  network_summary
  disk_summary
  baseline_checks
  save_report
  offer_step2_or_exit
}

show_menu() {
  echo
  print_branding
  echo "$APP_NAME v$APP_VERSION"
  line
  echo "1) Paso 1 - Diagnostico inicial (detectar entorno y recursos)"
  echo "2) Paso 2 - Instalacion y configuracion"
  echo "3) Salir"
  line
}

main() {
  while true; do
    show_menu
    if ! read -r -p "Elegi una opcion: " opt; then exit 0; fi
    case "$opt" in
      1) option_diagnostico_inicial ;;
      2) option_instalacion ;;
      3) exit 0 ;;
      *) echo "Opcion invalida" ;;
    esac
  done
}

main "$@"
