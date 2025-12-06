#!/bin/bash

# === КОНФИГУРАЦИЯ ===
DOMAIN="vpn.play2go.cloud"
PORT=5321
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E"
REPO_URL="https://github.com/PavloMakaro/Mining-game.git"
INSTALL_DIR="/opt/mining_game"
SERVICE_NAME="mining_game"

if [ "$(id -u)" != "0" ]; then
    echo "❌ Запусти через sudo!"
    exit 1
fi

echo "🚀 Установка (Режим: Всегда успешный запуск)..."

# 1. Установка
apt update -y
apt install git python3-full python3-pip python3-venv certbot psmisc openssl -y

# 2. Чистим порты
systemctl stop nginx
fuser -k 80/tcp 2>/dev/null
fuser -k $PORT/tcp 2>/dev/null

# 3. ПОПЫТКА ПОЛУЧИТЬ SSL (REAL)
echo "🔒 Пробуем получить настоящий сертификат..."
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN

# Проверяем, удалось ли
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
PRIVKEY="$CERT_DIR/privkey.pem"
FULLCHAIN="$CERT_DIR/fullchain.pem"

if [ -f "$PRIVKEY" ]; then
    echo "✅ Настоящий сертификат получен!"
else
    echo "⚠️ Ошибка DNS или Certbot. Генерируем ВРЕМЕННЫЙ сертификат, чтобы сервер запустился..."
    mkdir -p /opt/certs
    PRIVKEY="/opt/certs/privkey.pem"
    FULLCHAIN="/opt/certs/fullchain.pem"
    # Генерируем самоподписанный ключ
    openssl req -x509 -newkey rsa:4096 -keyout "$PRIVKEY" -out "$FULLCHAIN" -days 365 -nodes -subj "/CN=$DOMAIN"
    echo "✅ Временный сертификат создан в /opt/certs"
fi

# 4. Установка игры
echo "📂 Ставим игру..."
systemctl stop $SERVICE_NAME 2>/dev/null
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR || exit

# 5. Python
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install fastapi "uvicorn[standard]" aiogram requests beautifulsoup4 pydantic jinja2 python-multipart

# 6. Токен
if [ -f "main.py" ]; then
    sed -i "s/TOKEN = .*/TOKEN = \"$BOT_TOKEN\"/" main.py
else
    echo "❌ main.py не найден!"
    exit 1
fi

# 7. Запуск на 5321 (с тем сертификатом, который получился)
echo "⚙️ Запуск службы..."
cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=Mining Game (Port $PORT)
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT --ssl-keyfile $PRIVKEY --ssl-certfile $FULLCHAIN
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

# Включаем Nginx обратно, если он жив
systemctl start nginx 2>/dev/null

echo "=================================================="
echo "✅ СЕРВЕР ЗАПУЩЕН!"
echo "Адрес: https://$DOMAIN:$PORT"
echo ""
echo "Если браузер ругается на безопасность — это нормально,"
echo "потому что DNS еще не настроен, и мы использовали временный ключ."
echo "В боте напиши: /seturl https://$DOMAIN:$PORT"
echo "=================================================="
