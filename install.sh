#!/bin/bash
# WireGuard Full Install Script
# Одна команда для полной настройки VPN сервера с WGDashboard и Qwen Code
#
# Использование:
#   curl -fsSL https://raw.githubusercontent.com/DenFax/WireGuard_full/main/install.sh | sudo bash
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
GITHUB_USER="DenFax"
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
            echo "  curl -fsSL https://raw.githubusercontent.com/DenFax/WireGuard_full/main/install.sh | sudo bash"
            echo ""
            echo "Параметры:"
            echo "  --wg-port PORT        WireGuard порт (по умолчанию: 51820)"
            echo "  --dashboard-port PORT WGDashboard порт (по умолчанию: 10086)"
            echo "  --domain DOMAIN       Домен для HTTPS (опционально)"
            echo "  --no-qwen             Не устанавливать Qwen Code"
            echo "  --github-user USER    GitHub username"
            exit 0
            ;;
        *) shift ;;
    esac
done

echo ""
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         WireGuard Full Install Script                     ║"
echo "║         WGDashboard (Docker) + Qwen Code + Skills         ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo ""

# Проверка root
if [ "$EUID" -ne 0 ]; then
    log_error "Запускайте от root (sudo)"
    exit 1
fi

log_info "GitHub: ${GITHUB_USER}/${GITHUB_REPO}@${BRANCH}"
log_info "WireGuard порт: ${WG_PORT}/udp"
log_info "Dashboard порт: ${DASHBOARD_PORT}/tcp"
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
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    apt-transport-https \
    ca-certificates \
    gnupg \
    lsb-release \
    ufw \
    software-properties-common
log_success "Зависимости установлены"

# ============================================================
# Шаг 3: Включение IP Forwarding
# ============================================================
log_info "Включение IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf
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
# Шаг 5: Проверка и установка Docker
# ============================================================
log_info "Проверка Docker..."

DOCKER_INSTALLED=false

# Проверка Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    log_success "Docker установлен: ${DOCKER_VERSION}"
    DOCKER_INSTALLED=true
else
    log_warn "Docker не найден"
fi

# Проверка Docker Compose
COMPOSE_CMD=""
if docker compose &>/dev/null; then
    COMPOSE_VERSION=$(docker compose version 2>&1 || echo "unknown")
    log_success "Docker Compose (плагин): ${COMPOSE_VERSION}"
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    log_success "Docker Compose (standalone): ${COMPOSE_VERSION}"
    COMPOSE_CMD="docker-compose"
else
    log_warn "Docker Compose не найден"
fi

# Установка если чего-то нет
if [ "$DOCKER_INSTALLED" = false ] || [ -z "$COMPOSE_CMD" ]; then
    
    if [ "$DOCKER_INSTALLED" = false ]; then
        log_info "Установка Docker..."
    else
        log_info "Установка Docker Compose..."
    fi
    
    # Добавление GPG ключа Docker
    log_info "Добавление репозитория Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.gpg 2>/dev/null || true
    chmod a+r /etc/apt/keyrings/docker.gpg
    
    # Добавление репозитория
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list 2>/dev/null || true
    
    # Обновление и установка
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Добавление пользователя в группу docker
    usermod -aG docker $SUDO_USER 2>/dev/null || true
    
    log_success "Docker и Docker Compose установлены"
    
    COMPOSE_CMD="docker compose"
fi

# Проверка что Docker работает
if ! docker info &>/dev/null; then
    log_error "Docker не работает корректно"
    exit 1
fi

log_success "Docker готов к работе"

# ============================================================
# Шаг 6: Установка WGDashboard через Docker
# ============================================================
log_info "Установка WGDashboard..."

# Создание директории
WGDIR="/root/wgdashboard"
mkdir -p "${WGDIR}"/{conf,data}
cd "${WGDIR}"

# Создание .env файла
cat > .env << EOF
WG_PORT=${WG_PORT}
DASHBOARD_PORT=${DASHBOARD_PORT}
DOMAIN=${DOMAIN:-localhost}
EOF

# Создание docker-compose.yaml
cat > docker-compose.yaml << EOF
services:
  wgdashboard:
    image: ghcr.io/wgdashboard/wgdashboard:latest
    container_name: wgdashboard
    hostname: wgdashboard
    ports:
      - "${DASHBOARD_PORT}:10086"
      - "${WG_PORT}:51820/udp"
    volumes:
      - "./conf:/etc/wireguard"
      - "./data:/data"
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
    restart: unless-stopped
EOF

# Запуск контейнера
log_info "Запуск WGDashboard..."
$COMPOSE_CMD up -d

# Проверка запуска
sleep 5
if $COMPOSE_CMD ps | grep -q "Up"; then
    log_success "WGDashboard запущен"
else
    log_error "Не удалось запустить WGDashboard"
    $COMPOSE_CMD logs
    exit 1
fi

# ============================================================
# Шаг 7: Настройка HTTPS (если указан домен)
# ============================================================
if [ -n "$DOMAIN" ]; then
    log_info "Настройка HTTPS для ${DOMAIN}..."
    
    # Установка Nginx
    apt install -y nginx
    
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
# Шаг 8: Установка Qwen Code (опционально)
# ============================================================
if [ "$INSTALL_QWEN" = true ]; then
    log_info "Установка Qwen Code..."
    
    # Проверка Node.js
    if ! command -v node &> /dev/null; then
        log_info "Установка Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt install -y nodejs
        log_success "Node.js установлен"
    else
        log_success "Node.js уже установлен"
    fi
    
    # Установка Qwen Code через npm
    log_info "Установка Qwen Code..."
    npm install -g @qwen-code/qwen-code@latest
    
    # Создание директории для skills
    mkdir -p /root/.qwen/skills
    
    # Скачивание skills из репозитория
    log_info "Скачивание skills из репозитория..."
    cd /root/.qwen/skills
    git clone "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git" temp_skills
    if [ -d "temp_skills/skills/wireguard-vpn" ]; then
        cp -r temp_skills/skills/wireguard-vpn wireguard-vpn
        log_success "Skills установлены"
    else
        log_warn "Skills не найдены в репозитории"
    fi
    rm -rf temp_skills
    
    log_success "Qwen Code установлен"
fi

# ============================================================
# Шаг 9: Получение информации о сервере
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
echo "   Конфиг: ${WGDIR}/conf/wg0.conf"
echo ""
echo "🐳 Docker:"
echo "   Контейнер: wgdashboard"
echo "   Команды:"
echo "     $COMPOSE_CMD ps     — статус"
echo "     $COMPOSE_CMD logs   — логи"
echo "     $COMPOSE_CMD restart — перезапуск"
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
echo "   $COMPOSE_CMD ps        — статус WGDashboard"
echo "   $COMPOSE_CMD logs      — логи"
echo "   $COMPOSE_CMD restart   — перезапуск"
echo "   docker ps              — список контейнеров"
echo "   qwen                   — запустить Qwen Code"
echo ""

# Сохранение информации в файл
cat > "${WGDIR}/info.txt" << EOF
WireGuard Full Install - Информация
====================================
Дата установки: $(date)

WGDashboard:
  URL: $([ -n "$DOMAIN" ] && echo "https://${DOMAIN}" || echo "http://${SERVER_IP}:${DASHBOARD_PORT}")
  Логин: admin
  Пароль: admin (СМЕНИТЕ!)

WireGuard:
  Порт: ${WG_PORT}/udp
  Конфиг: ${WGDIR}/conf/wg0.conf

Docker:
  Контейнер: wgdashboard
  Директория: ${WGDIR}
  Compose: ${COMPOSE_CMD}

Qwen Code:
  Установлен: ${INSTALL_QWEN}
  Skills: /root/.qwen/skills/wireguard-vpn/

Команды:
  ${COMPOSE_CMD} ps
  ${COMPOSE_CMD} logs
  ${COMPOSE_CMD} restart
  docker ps
  qwen
EOF

log_success "Информация сохранена в ${WGDIR}/info.txt"
echo ""
