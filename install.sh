#!/bin/bash

# === НАСТРОЙКИ (ВСЁ ВШИТО) ===
DOMAIN="Tgbo1.ignorelist.com"
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E"
REPO_URL="https://github.com/PavloMakaro/Mining-game.git"
INSTALL_DIR="/opt/mining_game"
SERVICE_NAME="mining_game"

# Проверка прав root
if [ "$(id -u)" != "0" ]; then
    echo "❌ Запустите скрипт через sudo!"
    exit 1
fi

echo "🚀 НАЧИНАЕМ УСТАНОВКУ..."

# 1. Установка системных утилит (Nginx, Certbot, Python)
echo "📦 Устанавливаем пакеты..."
apt update -y
apt install git python3-full python3-pip python3-venv nginx certbot python3-certbot-nginx -y

# 2. Остановка старых процессов
systemctl stop $SERVICE_NAME 2>/dev/null
# Удаляем старую папку, чтобы скачать свежую версию с Гитхаба
rm -rf $INSTALL_DIR

# 3. Скачивание проекта
echo "📂 Клонируем репозиторий с GitHub..."
git clone $REPO_URL $INSTALL_DIR
cd $INSTALL_DIR || exit

# 4. Настройка Python
echo "🐍 Создаем виртуальное окружение..."
python3 -m venv venv
./venv/bin/pip install --upgrade pip
# Устанавливаем библиотеки (на случай если requirements.txt старый, пропишем явно)
./venv/bin/pip install fastapi "uvicorn[standard]" aiogram requests beautifulsoup4 pydantic jinja2 python-multipart

# 5. Жесткая прописка Токена в main.py
echo "🔑 Прописываем токен..."
# Ищем строку TOKEN = "..." и меняем на твой токен
if [ -f "main.py" ]; then
    sed -i "s/TOKEN = .*/TOKEN = \"$BOT_TOKEN\"/" main.py
else
    echo "⚠️ main.py не найден, проверьте репозиторий!"
fi

# 6. Настройка Systemd (автозапуск)
echo "⚙️ Настраиваем сервис..."
cat <<EOF > "/etc/systemd/system/$SERVICE_NAME.service"
[Unit]
Description=Crypto Mining Game
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

# 7. Настройка Nginx (Веб-сервер)
echo "🌐 Настраиваем Nginx для $DOMAIN..."
NGINX_CONF="/etc/nginx/sites-available/$SERVICE_NAME"

cat <<EOF > "$NGINX_CONF"
server {
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Включаем конфиг
ln -s "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
rm /etc/nginx/sites-enabled/default 2>/dev/null
nginx -t && systemctl reload nginx

# 8. Получение SSL (HTTPS)
echo "🔒 Получаем SSL сертификат..."
# --non-interactive: не задавать вопросов
# --agree-tos: согласиться с правилами
# -m ...: почта (формальность)
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@$DOMAIN --redirect

echo "=================================================="
echo "✅ ГОТОВО! ИГРА УСТАНОВЛЕНА."
echo "Адрес: https://$DOMAIN"
echo "Бот работает. Зайди в бота и нажми /seturl https://$DOMAIN"
echo "=================================================="
