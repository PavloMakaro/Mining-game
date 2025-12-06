#!/bin/bash

# === КОНФИГУРАЦИЯ ===
DOMAIN="Tgbo1.ignorelist.com"
PORT=5321
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E"
REPO_URL="https://github.com/PavloMakaro/Mining-game.git"
INSTALL_DIR="/opt/mining_game"
SERVICE_NAME="mining_game"

if [ "$(id -u)" != "0" ]; then
    echo "❌ Запусти через sudo!"
    exit 1
fi

echo "🚀 Установка (автопоиск сертификатов)..."

# 1. Установка
apt update -y
apt install git python3-full python3-pip python3-venv certbot psmisc -y

# 2. Освобождаем порт 80 для проверки
systemctl stop nginx
fuser -k 80/tcp 2>/dev/null

# 3. Обновляем/Получаем сертификат
echo "🔒 Проверяем сертификаты..."
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN --keep-until-expiring

# 4. АВТОПОИСК ПУТИ К СЕРТИФИКАТАМ (Фикс проблемы)
# Ищем папку, которая начинается с имени домена (чтобы найти Tgbo1...-0001 если есть)
CERT_DIR=$(find /etc/letsencrypt/live -name "$DOMAIN*" -type d | head -n 1)

if [ -z "$CERT_DIR" ]; then
    echo "❌ ОШИБКА: Сертификаты не найдены вообще!"
    exit 1
fi

echo "✅ Найдены сертификаты в: $CERT_DIR"
PRIVKEY="$CERT_DIR/privkey.pem"
FULLCHAIN="$CERT_DIR/fullchain.pem"

# 5. Пробуем запустить старый Nginx (но не умираем, если не выйдет)
echo "▶️ Запускаем Nginx..."
systemctl start nginx
# Если Nginx упал из-за старого конфига — пофиг, идем дальше, нам он для игры не нужен

# 6. Установка игры
echo "📂 Ставим игру..."
systemctl stop $SERVICE_NAME 2>/dev/null
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR || exit

# 7. Python
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install fastapi "uvicorn[standard]" aiogram requests beautifulsoup4 pydantic jinja2 python-multipart

# 8. Токен
if [ -f "main.py" ]; then
    sed -i "s/TOKEN = .*/TOKEN = \"$BOT_TOKEN\"/" main.py
else
    echo "❌ main.py не найден!"
    exit 1
fi

# 9. Запуск на 5321
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

echo "=================================================="
echo "✅ ИГРА ЗАПУЩЕНА!"
echo "Адрес: https://$DOMAIN:$PORT"
echo "Обязательно напиши боту: /seturl https://$DOMAIN:$PORT"
echo "=================================================="
