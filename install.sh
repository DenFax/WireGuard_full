#!/bin/bash
# WireGuard Full Install Script
# Одна команда для полной настройки VPN сервера с Qwen Code и skill
#
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/USERNAME/WireGuard_full/main/install.sh | sudo bash
#
# С параметрами:
#   curl -fsSL ... | sudo bash -s -- --wg-port 51820 --dashboard-port 10086 --domain vpn.example.com

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Параметры по умолчанию
WG_PORT=51820
DASHBOARD_PORT=10086
DOMAIN=""
INSTALL_QWEN=true
GITHUB_USER=""
GITHUB_REPO="WireGuard_full"
BRANCH="main"

# Логирование
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --wg-port) WG_PORT="$2"; shift 2 ;;
        --dashboard-port) DASHBOARD_PORT="$2"; shift 2 ;;
        --domain) DOMAIN="$2"; shift 2 ;;
        --no-qwen) INSTALL_QWEN=false; shift ;;
        --github-user) GITHUB_USER="$2"; shift 2 ;;
        --github-repo) GITHUB_REPO="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        -h|--help)
            echo "Использование:"
            echo "  curl -fsSL https://raw.githubusercontent.com/USER/WireGuard_full/main/install.sh | sudo bash"
            echo ""
            echo "Параметры:"
            echo "  --wg-port PORT        WireGuard порт (по умолчанию: 51820)"
            echo "  --dashboard-port PORT WGDashboard порт (по умолчанию: 10086)"
            echo "  --domain DOMAIN       Домен для HTTPS (опционально)"
            echo "  --no-qwen             Не устанавливать Qwen Code"
            echo "  --github-user USER    GitHub username"
            echo "  --github-repo REPO    GitHub репозиторий"
            echo "  --branch BRANCH       Ветка GitHub"
            exit 0
            ;;
        *) shift ;;
    esac
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         WireGuard Full Install Script                     ║"
echo "║         WGDashboard + Qwen Code + Skills                  ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Проверка root
if [ "$EUID" -ne 0 ]; then
    log_error "Запускайте от root (sudo)"
    exit 1
fi

# Определение GitHub username
if [ -z "$GITHUB_USER" ]; then
    log_warn "GITHUB_USER не указан. Введите ваш GitHub username:"
    read -r GITHUB_USER
    if [ -z "$GITHUB_USER" ]; then
        log_error "GitHub username обязателен"
        exit 1
    fi
fi

REPO_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

log_info "Репозиторий: ${GITHUB_USER}/${GITHUB_REPO}@${BRANCH}"
log_info "WireGuard порт: ${WG_PORT}"
log_info "Dashboard порт: ${DASHBOARD_PORT}"
[ -n "$DOMAIN" ] && log_info "Домен для HTTPS: ${DOMAIN}"

echo ""
log_info "Начинаем установку..."
echo ""

# ============================================================
# Шаг 1: Обновление системы
# ============================================================
log_info "Обновление пакетов..."
apt update && apt upgrade -y
log_success "Система обновлена"

# ============================================================
# Шаг 2: Установка зависимостей
# ============================================================
log_info "Установка зависимостей..."
apt install -y \
    wireguard \
    wireguard-tools \
    qrencode \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    nginx \
    ufw \
    openssl \
    ca-certificates
log_success "Зависимости установлены"

# ============================================================
# Шаг 3: Включение IP Forwarding
# ============================================================
log_info "Включение IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
log_success "IP forwarding включён"

# ============================================================
# Шаг 4: Настройка брандмауэра
# ============================================================
log_info "Настройка UFW..."
ufw allow 22/tcp || true
ufw allow "${WG_PORT}"/udp
ufw allow "${DASHBOARD_PORT}"/tcp
ufw --force enable || true
log_success "Брандмауэр настроен"

# ============================================================
# Шаг 5: Установка WGDashboard
# ============================================================
log_info "Установка WGDashboard..."
cd /opt
git clone https://github.com/donaldzou/WGDashboard.git 2>/dev/null || true
cd WGDashboard/src
chmod u+x wg-dashboard.sh

# Запуск установки WGDashboard
export WG_PORT="${WG_PORT}"
export DASHBOARD_PORT="${DASHBOARD_PORT}"
./wg-dashboard.sh install

# Автозапуск
systemctl enable wg-quick@wg0 2>/dev/null || true
systemctl enable wg-dashboard
systemctl start wg-quick@wg0 2>/dev/null || true
systemctl start wg-dashboard

log_success "WGDashboard установлен"

# ============================================================
# Шаг 6: Настройка HTTPS (если указан домен)
# ============================================================
if [ -n "$DOMAIN" ]; then
    log_info "Настройка HTTPS для ${DOMAIN}..."
    
    # Конфиг Nginx
    cat > /etc/nginx/sites-available/wgdashboard << EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${DASHBOARD_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    ln -sf /etc/nginx/sites-available/wgdashboard /etc/nginx/sites-enabled/
    nginx -t && systemctl restart nginx
    
    # Let's Encrypt
    apt install -y certbot python3-certbot-nginx
    certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email admin@"${DOMAIN}"
    
    log_success "HTTPS настроен: https://${DOMAIN}"
fi

# ============================================================
# Шаг 7: Установка Qwen Code (опционально)
# ============================================================
if [ "$INSTALL_QWEN" = true ]; then
    log_info "Установка Qwen Code..."
    
    # Установка Node.js (если нет)
    if ! command -v node &> /dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
    fi
    
    # Установка Qwen Code через npm
    npm install -g @anthropic/qwen-code
    
    # Создание директории для skills
    mkdir -p /root/.qwen/skills
    
    # Скачивание skills из репозитория
    log_info "Скачивание skills из репозитория..."
    cd /root/.qwen/skills
    git clone "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git" temp_skills
    cp -r temp_skills/skills/wireguard-vpn wireguard-vpn 2>/dev/null || true
    rm -rf temp_skills
    
    log_success "Qwen Code установлен с skills"
fi

# ============================================================
# Шаг 8: Получение информации о сервере
# ============================================================
SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  Установка завершена!                     ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 WGDashboard:"
if [ -n "$DOMAIN" ]; then
    echo "   URL: https://${DOMAIN}"
else
    echo "   URL: http://${SERVER_IP}:${DASHBOARD_PORT}"
fi
echo "   Логин: admin"
echo "   Пароль: admin (смените при первом входе!)"
echo ""
echo "🔧 WireGuard:"
echo "   Порт: ${WG_PORT}/udp"
echo "   Конфиг: /etc/wireguard/wg0.conf"
echo ""
echo "🤖 Qwen Code:"
if [ "$INSTALL_QWEN" = true ]; then
    echo "   Установлен: Да"
    echo "   Skills: /root/.qwen/skills/wireguard-vpn/"
    echo "   Запуск: qwen"
else
    echo "   Установлен: Нет (использовано --no-qwen)"
fi
echo ""
echo "📋 Полезные команды:"
echo "   wg show              — статус WireGuard"
echo "   systemctl status wg-dashboard — статус панели"
echo "   qwen                 — запустить Qwen Code"
echo ""

# Сохранение информации в файл
cat > /root/wgdashboard-info.txt << EOF
WireGuard Full Install - Информация
====================================
Дата установки: $(date)

WGDashboard:
  URL: $([ -n "$DOMAIN" ] && echo "https://${DOMAIN}" || echo "http://${SERVER_IP}:${DASHBOARD_PORT}")
  Логин: admin
  Пароль: admin (СМЕНИТЕ!)

WireGuard:
  Порт: ${WG_PORT}/udp
  Конфиг: /etc/wireguard/wg0.conf

Qwen Code:
  Установлен: ${INSTALL_QWEN}
  Skills: /root/.qwen/skills/wireguard-vpn/

Команды:
  wg show
  systemctl status wg-dashboard
  qwen
EOF

log_success "Информация сохранена в /root/wgdashboard-info.txt"
echo ""
