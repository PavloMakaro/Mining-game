#!/bin/bash

# === КОНФИГУРАЦИЯ ===
DOMAIN="Tgbo1.ignorelist.com"
PORT=5321
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E"
REPO_URL="https://github.com/PavloMakaro/Mining-game.git"
INSTALL_DIR="/opt/mining_game"
SERVICE_NAME="mining_game"

# Проверка root
if [ "$(id -u)" != "0" ]; then
    echo "❌ Запусти через sudo!"
    exit 1
fi

echo "🚀 Установка на порт $PORT..."

# 1. Установка утилит
apt update -y
apt install git python3-full python3-pip python3-venv certbot psmisc -y

# 2. ОСВОБОЖДАЕМ 80 ПОРТ
echo "🛑 Освобождаем 80 порт..."
# Сначала пробуем по-хорошему
systemctl stop nginx
# Если не помогло — убиваем всё, что сидит на 80 порту
fuser -k 80/tcp 2>/dev/null

# 3. Получаем сертификат (пока порт свободен)
echo "🔒 Получаем сертификат для $DOMAIN..."
certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN

# Пути к ключам
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
PRIVKEY="$CERT_DIR/privkey.pem"
FULLCHAIN="$CERT_DIR/fullchain.pem"

# 4. ЗАПУСКАЕМ СТАРОЕ ОБРАТНО
echo "▶️ Запускаем старый Nginx обратно..."
systemctl start nginx || echo "⚠️ Не удалось запустить Nginx (возможно, ошибка в его конфигах), но идем дальше..."

# Проверка сертификата
if [ ! -f "$PRIVKEY" ]; then
    echo "❌ ОШИБКА: Сертификат не получен. Проверь, что домен $DOMAIN смотрит на этот сервер."
    exit 1
fi

# 5. Чистая установка игры
echo "📂 Устанавливаем игру..."
systemctl stop $SERVICE_NAME 2>/dev/null
rm -rf $INSTALL_DIR
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR || exit

# 6. Библиотеки
echo "🐍 Ставим библиотеки..."
python3 -m venv venv
./venv/bin/pip install --upgrade pip
./venv/bin/pip install fastapi "uvicorn[standard]" aiogram requests beautifulsoup4 pydantic jinja2 python-multipart

# 7. Вписываем токен
if [ -f "main.py" ]; then
    sed -i "s/TOKEN = .*/TOKEN = \"$BOT_TOKEN\"/" main.py
else
    echo "❌ main.py не найден!"
    exit 1
fi

# 8. Запуск игры на 5321 (не мешает 80 порту)
echo "⚙️ Запуск службы..."
cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=Mining Game (Port $PORT)
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
# Слушаем 5321, SSL подключен напрямую
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port $PORT --ssl-keyfile $PRIVKEY --ssl-certfile $FULLCHAIN
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

echo "=================================================="
echo "✅ ГОТОВО!"
echo "1. 80 порт освободили, сертификат взяли."
echo "2. Старый сервис (Nginx) запустили обратно."
echo "3. Игра работает тут: https://$DOMAIN:$PORT"
echo ""
echo "👉 В боте напиши: /seturl https://$DOMAIN:$PORT"
echo "=================================================="
