---
name: wireguard-vpn
description: "Управление WireGuard VPN через WGDashboard API — установка сервера на Ubuntu, создание пиров, блокировка, выдача конфигов. Триггеры: настрой VPN, добавь клиента WireGuard, установи WGDashboard, заблокируй пира"
---

# WGDashboard API Skill

Skill для управления WireGuard VPN через WGDashboard REST API.

---

## 📦 Установка WGDashboard на Ubuntu Server

### Требования
- Ubuntu 20.04+ / 22.04+ / 24.04+
- Root или sudo доступ
- Открытые порты: `51820/udp` (WireGuard), `10086/tcp` (WGDashboard)

### Шаг 1: Обновление системы

```bash
sudo apt update && sudo apt upgrade -y
```

### Шаг 2: Установка WireGuard

```bash
sudo apt install -y wireguard wireguard-tools qrencode
```

### Шаг 3: Клонирование WGDashboard

```bash
cd /opt
sudo git clone https://github.com/donaldzou/WGDashboard.git
cd WGDashboard/src
sudo chmod u+x wg-dashboard.sh
```

### Шаг 4: Запуск установки

```bash
sudo ./wg-dashboard.sh
```

Скрипт предложит:
- Установить WireGuard (если не установлен)
- Установить WGDashboard
- Настроить автозапуск

### Шаг 5: Настройка брандмауэра (UFW)

```bash
# Разрешить SSH (если нужно)
sudo ufw allow 22/tcp

# Разрешить WireGuard
sudo ufw allow 51820/udp

# Разрешить WGDashboard UI
sudo ufw allow 10086/tcp

# Включить UFW
sudo ufw enable
```

### Шаг 6: Включение IP Forwarding

```bash
# Включить немедленно
sudo sysctl -w net.ipv4.ip_forward=1

# Сохранить навсегда
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
```

### Шаг 7: Настройка автозапуска

```bash
# Включить автозапуск WireGuard
sudo systemctl enable wg-quick@wg0

# Включить автозапуск WGDashboard
sudo systemctl enable wg-dashboard

# Запустить службы
sudo systemctl start wg-quick@wg0
sudo systemctl start wg-dashboard
```

### Шаг 8: Проверка статуса

```bash
# Статус WireGuard
sudo systemctl status wg-quick@wg0

# Статус WGDashboard
sudo systemctl status wg-dashboard

# Просмотр интерфейса
sudo wg show
```

### Шаг 9: Доступ к веб-интерфейсу

Откройте в браузере:
```
http://<server-ip>:10086
```

**Первый вход:**
- Логин: `admin`
- Пароль: `admin` (смените сразу!)

---

## 🔧 Настройка сервера (инструмент)

### `setup_server`

Скрипт автоматической установки WGDashboard на Ubuntu.

```bash
#!/bin/bash
# wgdashboard-install.sh

set -e

echo "=== WGDashboard Installation Script ==="

# Проверка root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Обновление
apt update && apt upgrade -y

# Установка зависимостей
apt install -y wireguard wireguard-tools qrencode curl

# Включение IP forwarding
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Клонирование
cd /opt
git clone https://github.com/donaldzou/WGDashboard.git 2>/dev/null || true
cd WGDashboard/src
chmod u+x wg-dashboard.sh

# Установка
./wg-dashboard.sh install

# Настройка брандмауэра
ufw allow 51820/udp
ufw allow 10086/tcp

# Автозапуск
systemctl enable wg-quick@wg0
systemctl enable wg-dashboard
systemctl start wg-quick@wg0
systemctl start wg-dashboard

echo "=== Installation Complete ==="
echo "Access WGDashboard at: http://$(hostname -I | awk '{print $1}'):10086"
echo "Default credentials: admin / admin"
```

**Запуск:**
```bash
curl -O https://raw.githubusercontent.com/donaldzou/WGDashboard/main/src/wg-dashboard.sh
chmod +x wg-dashboard.sh
sudo ./wg-dashboard.sh
```

---

## 🔐 Настройка HTTPS (опционально)

### Через Nginx + Let's Encrypt

```bash
# Установка Nginx
sudo apt install -y nginx

# Создание конфига
sudo tee /etc/nginx/sites-available/wgdashboard << 'EOF'
server {
    listen 80;
    server_name vpn.yourdomain.com;

    location / {
        proxy_pass http://127.0.0.1:10086;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

# Включение сайта
sudo ln -s /etc/nginx/sites-available/wgdashboard /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Получение SSL сертификата
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d vpn.yourdomain.com
```

---

## 📋 Конфигурация skill

```yaml
base_url: "https://your-wgdashboard-url"
api_password: "your-admin-password"  # Для получения токена
```

---

## Инструменты (OpenAI Tools / JSON Schema)

### 0. `setup_server`

Автоматическая установка и настройка WGDashboard на Ubuntu сервере.

```json
{
  "name": "setup_server",
  "description": "Install and configure WGDashboard on Ubuntu server via SSH",
  "parameters": {
    "type": "object",
    "properties": {
      "server_ip": {
        "type": "string",
        "description": "Server IP address or hostname"
      },
      "ssh_user": {
        "type": "string",
        "description": "SSH username (default: 'root')",
        "default": "root"
      },
      "ssh_port": {
        "type": "integer",
        "description": "SSH port (default: 22)",
        "default": 22
      },
      "wg_port": {
        "type": "integer",
        "description": "WireGuard UDP port (default: 51820)",
        "default": 51820
      },
      "dashboard_port": {
        "type": "integer",
        "description": "WGDashboard HTTP port (default: 10086)",
        "default": 10086
      },
      "setup_https": {
        "type": "boolean",
        "description": "Also configure HTTPS with Let's Encrypt",
        "default": false
      },
      "domain": {
        "type": "string",
        "description": "Domain for HTTPS certificate (required if setup_https=true)"
      }
    },
    "required": ["server_ip"]
  }
}
```

**Скрипт установки:**
```bash
# Выполняется на сервере через SSH
curl -fsSL https://raw.githubusercontent.com/donaldzou/WGDashboard/main/src/wg-dashboard.sh | sudo bash
```

---

### 1. `get_interfaces`

Получить список всех WireGuard интерфейсов (конфигураций).

```json
{
  "name": "get_interfaces",
  "description": "Get list of all WireGuard interfaces/configurations",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**HTTP:** `GET /api/wireguard/interface`

---

### 2. `get_peers`

Получить список всех пиров (клиентов) для указанного интерфейса.

```json
{
  "name": "get_peers",
  "description": "Get list of all peers for a specific WireGuard interface",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface (e.g., 'wg0')"
      }
    },
    "required": ["interface_id"]
  }
}
```

**HTTP:** `GET /api/wireguard/interface/{interface_id}/peers`

---

### 3. `create_peer`

Создать нового пира (VPN-клиента) для указанного интерфейса.

```json
{
  "name": "create_peer",
  "description": "Create a new WireGuard peer (VPN client) for a specific interface",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface (e.g., 'wg0')"
      },
      "peer_name": {
        "type": "string",
        "description": "Name for the peer (e.g., employee name, device name)"
      },
      "allowed_ips": {
        "type": "string",
        "description": "Comma-separated list of allowed IPs (e.g., '10.0.0.5/32' or '192.168.1.0/24')"
      },
      "endpoint": {
        "type": "string",
        "description": "Optional: Remote endpoint IP:port for the peer"
      }
    },
    "required": ["interface_id", "peer_name", "allowed_ips"]
  }
}
```

**HTTP:** `POST /api/wireguard/interface/{interface_id}/peers`

**Политика создания пиров:**
- Запросить у пользователя: имя пира, разрешённые IP (AllowedIPs)
- Опционально: срок действия (если поддерживается), комментарий
- Уточнить интерфейс, если их несколько

---

### 4. `get_peer_config`

Получить конфигурацию пира (для подключения клиента).

```json
{
  "name": "get_peer_config",
  "description": "Get WireGuard configuration for a specific peer (for client setup)",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface"
      },
      "peer_id": {
        "type": "string",
        "description": "The ID of the peer"
      }
    },
    "required": ["interface_id", "peer_id"]
  }
}
```

**HTTP:** `GET /api/wireguard/interface/{interface_id}/peers/{peer_id}/configuration`

---

### 5. `update_peer`

Обновить параметры пира (имя, IP, статус).

```json
{
  "name": "update_peer",
  "description": "Update peer settings (name, allowed IPs, enabled status)",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface"
      },
      "peer_id": {
        "type": "string",
        "description": "The ID of the peer to update"
      },
      "peer_name": {
        "type": "string",
        "description": "New name for the peer"
      },
      "allowed_ips": {
        "type": "string",
        "description": "New allowed IPs (comma-separated)"
      },
      "enabled": {
        "type": "boolean",
        "description": "Enable or disable the peer"
      }
    },
    "required": ["interface_id", "peer_id"]
  }
}
```

**HTTP:** `PUT /api/wireguard/interface/{interface_id}/peers/{peer_id}`

---

### 6. `disable_peer` / `enable_peer`

Включить или отключить пира.

```json
{
  "name": "disable_peer",
  "description": "Disable a WireGuard peer (revoke access without deleting)",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface"
      },
      "peer_id": {
        "type": "string",
        "description": "The ID of the peer to disable"
      }
    },
    "required": ["interface_id", "peer_id"]
  }
}
```

**HTTP:** `PUT /api/wireguard/interface/{interface_id}/peers/{peer_id}` с `enabled: false`

---

### 7. `delete_peer`

Удалить пира безвозвратно.

```json
{
  "name": "delete_peer",
  "description": "Permanently delete a WireGuard peer",
  "parameters": {
    "type": "object",
    "properties": {
      "interface_id": {
        "type": "string",
        "description": "The ID of the WireGuard interface"
      },
      "peer_id": {
        "type": "string",
        "description": "The ID of the peer to delete"
      }
    },
    "required": ["interface_id", "peer_id"]
  }
}
```

**HTTP:** `DELETE /api/wireguard/interface/{interface_id}/peers/{peer_id}`

---

### 8. `get_status`

Получить общую статистику и статус WGDashboard.

```json
{
  "name": "get_status",
  "description": "Get WGDashboard statistics and status information",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**HTTP:** `GET /api/wireguard/statistics`

---

### 9. `get_dashboard_data`

Получить подробные данные дашборда.

```json
{
  "name": "get_dashboard_data",
  "description": "Get detailed WGDashboard data including all interfaces and peers",
  "parameters": {
    "type": "object",
    "properties": {},
    "required": []
  }
}
```

**HTTP:** `GET /api/wireguard/dashboard/data`

---

## Системный промпт для агента

```
Ты — ассистент для управления WireGuard VPN через WGDashboard.

## Политика безопасности:

### Установка сервера:
1. При запросе "установи WGDashboard" / "настрой VPN сервер":
   - Запроси IP сервера и SSH-доступ (ключ или пароль)
   - Уточни порты (по умолчанию 51820/udp, 10086/tcp)
   - Предложи настроить HTTPS (нужен домен)
   - После установки выда URL и учётные данные

### Создание пиров:
1. Всегда запрашивай у пользователя:
   - Имя пира (сотрудник, устройство)
   - AllowedIPs (какие IP будут доступны, например 10.0.0.5/32)
   - Интерфейс (если их несколько)

2. Опционально уточняй:
   - Срок действия (если нужна временная учётная запись)
   - Комментарий/назначение

3. Перед созданием покажи пользователю параметры для подтверждения.

### Блокировка пиров:
- При запросе "заблокировать" используй `disable_peer` (обратимо)
- При запросе "удалить" используй `delete_peer` (необратимо)
- Всегда запрашивай подтверждение на удаление

### Выдача доступа:
- После создания пира используй `get_peer_config` для получения конфига
- Конфиг можно отправить пользователю для импорта в WireGuard-клиент

## Примеры сценариев:

1. "Установи WGDashboard на сервер 203.0.113.50"
   → setup_server(server_ip='203.0.113.50') → выдать URL доступа

2. "Создай VPN для Иванова на месяц"
   → Уточни AllowedIPs → create_peer → get_peer_config → показать конфиг

3. "Заблокируй доступ Петрову"
   → Найти пира по имени → disable_peer → подтвердить

4. "Покажи всех клиентов"
   → get_interfaces → для каждого get_peers

5. "Кто сейчас подключен?"
   → get_dashboard_data или get_status
```

---

## Пример использования (Python)

```python
import requests
import paramiko
from datetime import datetime, timedelta

class WGDashboardClient:
    def __init__(self, base_url: str, password: str):
        self.base_url = base_url.rstrip('/')
        self.token = self._authenticate(password)
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {self.token}',
            'Content-Type': 'application/json'
        })
    
    def _authenticate(self, password: str) -> str:
        resp = requests.post(f'{self.base_url}/api/auth', 
                            json={'password': password})
        resp.raise_for_status()
        return resp.json()['token']
    
    def get_interfaces(self):
        resp = self.session.get(f'{self.base_url}/api/wireguard/interface')
        resp.raise_for_status()
        return resp.json()
    
    def get_peers(self, interface_id: str):
        resp = self.session.get(
            f'{self.base_url}/api/wireguard/interface/{interface_id}/peers'
        )
        resp.raise_for_status()
        return resp.json()
    
    def create_peer(self, interface_id: str, peer_name: str, 
                    allowed_ips: str, endpoint: str = None):
        payload = {
            'peer_name': peer_name,
            'allowed_ips': allowed_ips
        }
        if endpoint:
            payload['endpoint'] = endpoint
        
        resp = self.session.post(
            f'{self.base_url}/api/wireguard/interface/{interface_id}/peers',
            json=payload
        )
        resp.raise_for_status()
        return resp.json()
    
    def get_peer_config(self, interface_id: str, peer_id: str):
        resp = self.session.get(
            f'{self.base_url}/api/wireguard/interface/{interface_id}/'
            f'peers/{peer_id}/configuration'
        )
        resp.raise_for_status()
        return resp.json()
    
    def disable_peer(self, interface_id: str, peer_id: str):
        resp = self.session.put(
            f'{self.base_url}/api/wireguard/interface/{interface_id}/peers/{peer_id}',
            json={'enabled': False}
        )
        resp.raise_for_status()
        return resp.json()
    
    def delete_peer(self, interface_id: str, peer_id: str):
        resp = self.session.delete(
            f'{self.base_url}/api/wireguard/interface/{interface_id}/peers/{peer_id}'
        )
        resp.raise_for_status()
        return resp.json()


class WGDashboardServerSetup:
    """Установка и настройка WGDashboard на Ubuntu сервере через SSH"""
    
    INSTALL_SCRIPT = """
set -e
apt update && apt upgrade -y
apt install -y wireguard wireguard-tools qrencode curl
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
cd /opt
git clone https://github.com/donaldzou/WGDashboard.git 2>/dev/null || true
cd WGDashboard/src
chmod u+x wg-dashboard.sh
./wg-dashboard.sh install
ufw allow 51820/udp
ufw allow 10086/tcp
systemctl enable wg-quick@wg0 2>/dev/null || true
systemctl enable wg-dashboard
systemctl start wg-quick@wg0 2>/dev/null || true
systemctl start wg-dashboard
echo "=== Installation Complete ==="
"""
    
    def __init__(self, server_ip: str, ssh_user: str = 'root', 
                 ssh_port: int = 22, ssh_key: str = None, 
                 ssh_password: str = None):
        self.server_ip = server_ip
        self.ssh_user = ssh_user
        self.ssh_port = ssh_port
        
        self.client = paramiko.SSHClient()
        self.client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        
        if ssh_key:
            self.client.connect(
                server_ip, port=ssh_port, username=ssh_user,
                key_filename=ssh_key
            )
        elif ssh_password:
            self.client.connect(
                server_ip, port=ssh_port, username=ssh_user,
                password=ssh_password
            )
        else:
            # Использовать SSH-агент
            self.client.connect(server_ip, port=ssh_port, username=ssh_user)
    
    def setup_wgdashboard(self, wg_port: int = 51820, 
                          dashboard_port: int = 10086) -> dict:
        """Установить WGDashboard на сервер"""
        
        # Выполнение скрипта установки
        stdin, stdout, stderr = self.client.exec_command(
            f'WG_PORT={wg_port} DASHBOARD_PORT={dashboard_port} bash -s',
            stdin=self.INSTALL_SCRIPT
        )
        
        output = stdout.read().decode('utf-8')
        error = stderr.read().decode('utf-8')
        
        return {
            'success': stdout.channel.recv_exit_status() == 0,
            'output': output,
            'error': error,
            'dashboard_url': f'http://{self.server_ip}:{dashboard_port}'
        }
    
    def setup_https(self, domain: str, email: str = None) -> dict:
        """Настроить HTTPS через Nginx + Let's Encrypt"""
        
        commands = [
            'apt install -y nginx certbot python3-certbot-nginx',
            f'''cat > /etc/nginx/sites-available/wgdashboard << 'EOF'
server {{
    listen 80;
    server_name {domain};
    location / {{
        proxy_pass http://127.0.0.1:10086;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }}
}}
EOF''',
            'ln -sf /etc/nginx/sites-available/wgdashboard /etc/nginx/sites-enabled/',
            'nginx -t && systemctl restart nginx',
            f'certbot --nginx -d {domain} --non-interactive --agree-tos' +
            (f' --email {email}' if email else '')
        ]
        
        output = []
        for cmd in commands:
            stdin, stdout, stderr = self.client.exec_command(cmd)
            result = stdout.read().decode('utf-8')
            output.append(result)
            if stdout.channel.recv_exit_status() != 0:
                return {
                    'success': False,
                    'error': stderr.read().decode('utf-8'),
                    'output': output
                }
        
        return {
            'success': True,
            'output': output,
            'https_url': f'https://{domain}'
        }
    
    def get_server_info(self) -> dict:
        """Получить информацию о сервере"""
        
        commands = {
            'ip': 'hostname -I | awk \'{print $1}\'',
            'os': 'cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2',
            'wg_status': 'systemctl is-active wg-quick@wg0 2>/dev/null || echo "not installed"',
            'dashboard_status': 'systemctl is-active wg-dashboard'
        }
        
        info = {}
        for key, cmd in commands.items():
            stdin, stdout, stderr = self.client.exec_command(cmd)
            info[key] = stdout.read().decode('utf-8').strip()
        
        return info
    
    def close(self):
        self.client.close()


# Пример использования
client = WGDashboardClient(
    base_url='https://vpn.company.com',
    password='admin-password'
)

# Создать пира
interfaces = client.get_interfaces()
wg0 = interfaces[0]['interface_id']

new_peer = client.create_peer(
    interface_id=wg0,
    peer_name='Ivanov-iPhone',
    allowed_ips='10.0.0.15/32'
)

# Получить конфиг для клиента
config = client.get_peer_config(wg0, new_peer['peer_id'])
print(config['configuration'])  # WireGuard конфиг для импорта


# Пример установки на новый сервер
setup = WGDashboardServerSetup(
    server_ip='203.0.113.50',
    ssh_user='root',
    ssh_key='/home/user/.ssh/id_rsa'  # или ssh_password='...'
)

# Получить информацию о сервере
info = setup.get_server_info()
print(f"Server: {info['os']}, IP: {info['ip']}")

# Установить WGDashboard
result = setup.setup_wgdashboard()
if result['success']:
    print(f"Dashboard installed at: {result['dashboard_url']}")
else:
    print(f"Error: {result['error']}")

# Опционально: настроить HTTPS
# https_result = setup.setup_https(domain='vpn.company.com', email='admin@company.com')

setup.close()
```

---

## Интеграция с агент-фреймворками

### Для OpenAI API

```python
tools = [
    {
        "type": "function",
        "function": {
            "name": "create_peer",
            "description": "Create a new WireGuard VPN client",
            "parameters": {
                "type": "object",
                "properties": {
                    "interface_id": {"type": "string"},
                    "peer_name": {"type": "string"},
                    "allowed_ips": {"type": "string"}
                },
                "required": ["interface_id", "peer_name", "allowed_ips"]
            }
        }
    },
    # ... остальные инструменты
]

response = client.chat.completions.create(
    model="gpt-4",
    messages=[
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": "Создай VPN для Иванова"}
    ],
    tools=tools
)
```

### Для LangChain

```python
from langchain.tools import Tool

tools = [
    Tool(
        name="get_peers",
        description="Get all VPN clients for an interface",
        func=lambda interface_id: client.get_peers(interface_id)
    ),
    Tool(
        name="create_peer",
        description="Create new VPN client",
        func=lambda interface_id, peer_name, allowed_ips:
            client.create_peer(interface_id, peer_name, allowed_ips)
    )
]
```
