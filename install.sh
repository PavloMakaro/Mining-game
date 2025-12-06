#!/bin/bash

# === КОНФИГУРАЦИЯ ===
DOMAIN="Vpn.play2go.cloud"
PORT=5321
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E"
REPO_URL="https://github.com/PavloMakaro/Mining-game.git"
INSTALL_DIR="/opt/mining_game"
SERVICE_NAME="mining_game"

if [ "$(id -u)" != "0" ]; then
    echo "❌ Запусти через sudo!"
    exit 1
fi

echo "🚀 Установка для $DOMAIN (Порт $PORT)..."

# 1. Установка пакетов
apt update -y
apt install git python3-full python3-pip python3-venv certbot psmisc -y

# 2. ПОЛНАЯ ОЧИСТКА ПОРТА 80 (Чтобы Certbot точно сработал)
echo "🛑 Освобождаем 80 порт..."
systemctl stop nginx
systemctl disable nginx  # Выключаем Nginx совсем, чтобы не мешал
fuser -k 80/tcp 2>/dev/null

# 3. ПОЛУЧЕНИЕ СЕРТИФИКАТА
echo "🔒 Получаем/Обновляем сертификат..."
# --force-renewal заставит получить новый, даже если старый есть (чтобы починить пути)
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN --force-renewal

# 4. АВТОПОИСК ПУТИ К СЕРТИФИКАТАМ
# Ищем папку, начинающуюся с имени домена
CERT_DIR=$(find /etc/letsencrypt/live -name "$DOMAIN*" -type d | head -n 1)

if [ -z "$CERT_DIR" ]; then
    echo "❌ ОШИБКА: Certbot не создал папку с ключами! Проверь DNS."
    exit 1
fi

echo "✅ Сертификаты найдены в: $CERT_DIR"
PRIVKEY="$CERT_DIR/privkey.pem"
FULLCHAIN="$CERT_DIR/fullchain.pem"

# 5. Установка игры
echo "📂 Ставим игру..."
systemctl stop $SERVICE_NAME 2>/dev/null
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR || exit

# 6. Python + Библиотеки
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install fastapi "uvicorn[standard]" aiogram requests beautifulsoup4 pydantic jinja2 python-multipart

# 7. Токен
if [ -f "main.py" ]; then
    sed -i "s/TOKEN = .*/TOKEN = \"$BOT_TOKEN\"/" main.py
else
    echo "❌ main.py не найден!"
    exit 1
fi

# 8. Создание службы (HTTPS на 5321)
echo "⚙️ Запуск службы..."
cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=Mining Game HTTPS
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
# Прямой SSL через Python
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT --ssl-keyfile $PRIVKEY --ssl-certfile $FULLCHAIN
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

echo "=================================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "Адрес: https://$DOMAIN:$PORT"
echo ""
echo "👉 1. Зайди в бота: @Cryptovalychik_bot"
echo "👉 2. Напиши: /seturl https://$DOMAIN:$PORT"
echo "=================================================="
