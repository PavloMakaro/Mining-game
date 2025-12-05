#!/bin/bash

# === КОНФИГУРАЦИЯ ===
INSTALL_DIR="/opt/crypto_game"
BOT_TOKEN="8532885249:AAGvoZB9KHB79hVpy0suYLvF6J7ZIdkgZ2E" # Твой токен
SERVICE_NAME="crypto_miner"

# Проверка root
if [ "$(id -u)" != "0" ]; then
    echo "Запустите скрипт с sudo!"
    exit 1
fi

echo "🚀 Начало установки Crypto Miner..."

# 1. Подготовка системы
echo "📦 Установка системных пакетов..."
apt update -y
apt install python3-full python3-pip python3-venv -y

# 2. Создание директории
echo "📂 Создание папки $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR/static"
cd "$INSTALL_DIR" || exit

# 3. Создание виртуального окружения
echo "🐍 Настройка Python venv..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

# 4. Установка библиотек
echo "📥 Установка Python-зависимостей..."
./venv/bin/pip install fastapi uvicorn[standard] aiogram requests beautifulsoup4 pydantic

# 5. ГЕНЕРАЦИЯ ФАЙЛОВ

# --- Файл данных: Видеокарты ---
cat <<EOF > gpus.json
[
  { "id": "rtx_4090", "name": "NVIDIA RTX 4090", "hashrate": 140, "power": 450, "price": 2000, "image_query": "rtx 4090 product" },
  { "id": "rtx_3080", "name": "NVIDIA RTX 3080", "hashrate": 100, "power": 320, "price": 700, "image_query": "rtx 3080 graphics card" },
  { "id": "rx_6800", "name": "AMD Radeon RX 6800", "hashrate": 64, "power": 300, "price": 550, "image_query": "amd radeon rx 6800" },
  { "id": "gtx_1660s", "name": "GTX 1660 Super", "hashrate": 31, "power": 125, "price": 250, "image_query": "gtx 1660 super" }
]
EOF

# --- Файл данных: Монеты ---
cat <<EOF > coins.json
[
  { "symbol": "BTC", "name": "Bitcoin", "price_usd": 98000, "difficulty": 500000, "icon": "₿" },
  { "symbol": "TON", "name": "Toncoin", "price_usd": 7.5, "difficulty": 500, "icon": "💎" },
  { "symbol": "ETH", "name": "Ethereum", "price_usd": 3800, "difficulty": 25000, "icon": "Ξ" }
]
EOF

# --- Файл: Frontend (HTML) ---
cat <<EOF > static/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <title>Miner</title>
    <script src="https://telegram.org/js/telegram-web-app.js"></script>
    <style>
        :root { --bg: #181818; --card: #242424; --text: #fff; --accent: #3390ec; --green: #2ecc71; --red: #e74c3c; }
        body { background: var(--bg); color: var(--text); font-family: sans-serif; margin: 0; padding-bottom: 70px; }
        .header { padding: 15px; background: var(--card); position: sticky; top: 0; z-index: 10; display: flex; justify-content: space-between; align-items: center;}
        .balance { font-size: 20px; font-weight: bold; color: var(--green); }
        .container { padding: 15px; display: none; }
        .container.active { display: block; }
        .card { background: var(--card); border-radius: 10px; padding: 10px; margin-bottom: 10px; display: flex; gap: 10px; align-items: center; }
        .card img { width: 60px; height: 60px; border-radius: 5px; object-fit: cover; background: #000; }
        .btn { background: var(--accent); color: white; border: none; padding: 8px 15px; border-radius: 5px; cursor: pointer; width: 100%; margin-top: 5px;}
        .bar-bg { background: #333; height: 4px; border-radius: 2px; margin-top: 5px; width: 100%; }
        .bar-fill { height: 100%; background: var(--green); width: 100%; transition: 0.3s; }
        .nav { position: fixed; bottom: 0; width: 100%; background: var(--card); display: flex; padding: 10px 0; justify-content: space-around; border-top: 1px solid #333; }
        .nav-item { opacity: 0.6; font-size: 12px; text-align: center; }
        .nav-item.active { opacity: 1; color: var(--accent); font-weight: bold; }
        select { width: 100%; padding: 10px; background: var(--bg); color: white; border: 1px solid #444; border-radius: 5px; margin-bottom: 10px; }
    </style>
</head>
<body>
    <div class="header">
        <div>Майнер</div>
        <div class="balance">$<span id="bal">0</span></div>
    </div>

    <div id="tab-rig" class="container active">
        <div style="background: var(--card); padding: 15px; border-radius: 10px; margin-bottom: 20px;">
            <select id="coins"></select>
            <button class="btn" onclick="mine()" style="padding: 15px; font-size: 16px; background: linear-gradient(45deg, #2980b9, #2ecc71);">⛏ START MINING</button>
        </div>
        <div id="rig-list"></div>
    </div>

    <div id="tab-shop" class="container">
        <h3>Магазин</h3>
        <div id="shop-list"></div>
    </div>

    <div class="nav">
        <div class="nav-item active" onclick="nav('rig')">🏠 РИГ</div>
        <div class="nav-item" onclick="nav('shop')">🛒 МАГАЗИН</div>
    </div>

    <script>
        const tg = window.Telegram.WebApp; tg.expand();
        const uid = tg.initDataUnsafe?.user?.id || 111;
        let state = {};

        async function api(path, body={}) {
            body.user_id = uid;
            const res = await fetch('/api'+path, { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify(body)});
            return await res.json();
        }

        async function init() {
            const data = await api('/init');
            state = data;
            render();
        }

        function render() {
            document.getElementById('bal').innerText = Math.floor(state.user.balance);
            
            // Coins
            const cSelect = document.getElementById('coins');
            if(cSelect.options.length === 0) {
                state.coins.forEach(c => {
                    cSelect.innerHTML += \`<option value="\${c.symbol}">\${c.icon} \${c.name}</option>\`;
                });
            }

            // Rig
            const rigDiv = document.getElementById('rig-list');
            rigDiv.innerHTML = state.user.rig.length ? '' : '<div style="text-align:center;color:#666">Риг пуст</div>';
            state.user.rig.forEach(g => {
                const hp = 100 - g.wear;
                rigDiv.innerHTML += \`
                <div class="card">
                    <img src="\${g.image_url}">
                    <div style="flex:1">
                        <div>\${g.name}</div>
                        <div style="font-size:11px;opacity:0.7">\${g.hashrate} MH/s</div>
                        <div class="bar-bg"><div class="bar-fill" style="width:\${hp}%; background: \${hp<30?'#e74c3c':'#2ecc71'}"></div></div>
                    </div>
                    \${g.wear > 0 ? \`<button style="width:auto;padding:5px 10px;" class="btn" onclick="repair(\${g.uid})">🛠</button>\` : ''}
                </div>\`;
            });

            // Shop
            document.getElementById('shop-list').innerHTML = state.shop_new.map(g => \`
                <div class="card">
                    <img src="\${g.image_url}">
                    <div style="flex:1">
                        <div>\${g.name}</div>
                        <div style="color:var(--accent);font-weight:bold">$\${g.price}</div>
                    </div>
                    <button class="btn" style="width:auto" onclick="buy('\${g.id}', false)">Купить</button>
                </div>
            \`).join('') + state.shop_used.map(g => \`
                <div class="card" style="border:1px dashed #555">
                    <img src="\${g.image_url}">
                    <div style="flex:1">
                        <div>\${g.name} <span style="color:orange">[Б/У]</span></div>
                        <div style="font-size:11px">Износ: \${g.wear}%</div>
                        <div style="color:orange;font-weight:bold">$\${g.price}</div>
                    </div>
                    <button class="btn" style="width:auto" onclick="buy('\${g.id}', true)">Купить</button>
                </div>
            \`).join('');
        }

        async function mine() {
            tg.MainButton.showProgress();
            const coin = document.getElementById('coins').value;
            try {
                const res = await api('/mine', {coin_symbol: coin});
                state.user = { ...state.user, balance: res.balance, rig: res.rig };
                render();
                tg.showPopup({message: \`Намайнено: $\${res.profit_usd.toFixed(2)}\`});
            } catch(e) {}
            tg.MainButton.hideProgress();
        }

        async function buy(id, used) {
            try {
                const res = await api('/buy', {item_id: id, is_used: used});
                state.user = res.user;
                render();
                tg.showPopup({message: 'Куплено!'});
            } catch(e) { tg.showAlert('Не хватает денег'); }
        }

        async function repair(uid) {
            if(!confirm('Починить за деньги?')) return;
            try {
                const res = await api('/repair', {item_uid: uid});
                state.user = res.user;
                render();
            } catch(e) { tg.showAlert('Не хватает денег'); }
        }

        function nav(tab) {
            document.querySelectorAll('.container').forEach(c => c.classList.remove('active'));
            document.getElementById('tab-'+tab).classList.add('active');
            document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
            event.currentTarget.classList.add('active');
        }

        init();
    </script>
</body>
</html>
EOF

# --- Файл: Backend + Bot (main.py) ---
cat <<EOF > main.py
import json, random, os, requests, asyncio
from bs4 import BeautifulSoup
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from aiogram import Bot, Dispatcher, types
from aiogram.types import WebAppInfo
from aiogram.filters import Command
from contextlib import asynccontextmanager

# === CONFIG ===
TOKEN = "${BOT_TOKEN}"
DB_FILE = "users.json"
IMG_CACHE = "img_cache.json"
WEBAPP_URL_FILE = "webapp_url.txt"

# === DATABASE & UTILS ===
def load_db():
    if os.path.exists(DB_FILE):
        with open(DB_FILE) as f: return json.load(f)
    return {}

def save_db(data):
    with open(DB_FILE, 'w') as f: json.dump(data, f)

users = load_db()
with open('gpus.json') as f: GPUS = json.load(f)
with open('coins.json') as f: COINS = json.load(f)

# Image Parser
img_cache = {}
if os.path.exists(IMG_CACHE):
    with open(IMG_CACHE) as f: img_cache = json.load(f)

def get_img(query):
    if query in img_cache: return img_cache[query]
    try:
        html = requests.get(f"https://www.google.com/search?q={query}&tbm=isch").text
        soup = BeautifulSoup(html, 'html.parser')
        src = soup.find_all('img')[1].get('src') # 0 is logo usually
        img_cache[query] = src
        with open(IMG_CACHE, 'w') as f: json.dump(img_cache, f)
        return src
    except: return "https://via.placeholder.com/60"

for g in GPUS: g['image_url'] = get_img(g['image_query'])

# === BOT LOGIC ===
bot = Bot(token=TOKEN)
dp = Dispatcher()

def get_webapp_url():
    if os.path.exists(WEBAPP_URL_FILE):
        with open(WEBAPP_URL_FILE) as f: return f.read().strip()
    return "https://google.com" # Заглушка

@dp.message(Command("start"))
async def cmd_start(message: types.Message):
    url = get_webapp_url()
    kb = types.InlineKeyboardMarkup(inline_keyboard=[
        [types.InlineKeyboardButton(text="🎮 ИГРАТЬ", web_app=WebAppInfo(url=url))]
    ])
    await message.answer(f"Привет! Твоя крипто-ферма ждет.\nURL игры сейчас: {url}\n\nЕсли не работает, админ должен установить URL командой: /seturl <link>", reply_markup=kb)

@dp.message(Command("seturl"))
async def cmd_seturl(message: types.Message):
    # Команда для смены ссылки без перезагрузки сервера
    args = message.text.split()
    if len(args) < 2:
        await message.answer("Используй: /seturl https://твоя-ссылка-ngrok")
        return
    new_url = args[1]
    with open(WEBAPP_URL_FILE, "w") as f: f.write(new_url)
    await message.answer(f"✅ URL обновлен на: {new_url}")

# === API LOGIC ===
@asynccontextmanager
async def lifespan(app: FastAPI):
    # Запуск бота при старте сервера
    asyncio.create_task(dp.start_polling(bot))
    yield
    await bot.session.close()

app = FastAPI(lifespan=lifespan)

class IDReq(BaseModel): user_id: int
class BuyReq(BaseModel): user_id: int; item_id: str; is_used: bool
class MineReq(BaseModel): user_id: int; coin_symbol: str; item_uid: int = 0

def get_user(uid):
    suid = str(uid)
    if suid not in users:
        users[suid] = {"balance": 1000, "rig": [], "inventory": []}
        save_db(users)
    return users[suid]

@app.post("/api/init")
def init(r: IDReq):
    u = get_user(r.user_id)
    # Генерим б/у рынок
    used = []
    for g in GPUS:
        if random.random() > 0.5:
            wear = random.randint(20, 60)
            price = int(g['price'] * (1 - wear/120))
            used.append({**g, "price": price, "wear": wear, "is_used": True})
    return {"user": u, "shop_new": GPUS, "shop_used": used, "coins": COINS}

@app.post("/api/buy")
def buy(r: BuyReq):
    u = get_user(r.user_id)
    gpu = next((g for g in GPUS if g['id'] == r.item_id), None)
    if not gpu: raise HTTPException(404)
    
    price = gpu['price']
    wear = 0
    if r.is_used:
        wear = random.randint(20, 50)
        price = int(price * (1 - wear/120))
    
    if u['balance'] < price: raise HTTPException(400)
    u['balance'] -= price
    
    item = {**gpu, "uid": random.randint(10000,99999), "wear": wear}
    if len(u['rig']) < 4: u['rig'].append(item)
    else: u['inventory'].append(item)
    
    save_db(users)
    return {"user": u}

@app.post("/api/mine")
def mine(r: MineReq):
    u = get_user(r.user_id)
    coin = next((c for c in COINS if c['symbol'] == r.coin_symbol), None)
    total_hash = 0
    for card in u['rig']:
        if card['wear'] >= 100: continue
        eff = 1 - (card['wear'] / 200)
        total_hash += card['hashrate'] * eff
        card['wear'] = min(100, card['wear'] + random.uniform(0.5, 2.0))
    
    profit = (total_hash / coin['difficulty']) * 200
    profit_usd = profit * coin['price_usd']
    u['balance'] += profit_usd
    save_db(users)
    return {"profit_usd": profit_usd, "balance": u['balance'], "rig": u['rig']}

@app.post("/api/repair")
def repair(r: MineReq):
    u = get_user(r.user_id)
    card = next((c for c in u['rig'] if c['uid'] == r.item_uid), None)
    if not card: raise HTTPException(404)
    cost = card['wear'] * 2
    if u['balance'] < cost: raise HTTPException(400)
    u['balance'] -= cost
    card['wear'] = 0
    save_db(users)
    return {"user": u, "cost": cost}

app.mount("/", StaticFiles(directory="static", html=True), name="static")
EOF

# 6. Создание SYSTEMD сервиса
echo "⚙️ Настройка systemd сервиса..."
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Crypto Game Server & Bot
After=network.target

[Service]
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 7. Запуск
echo "🚀 Запуск и активация службы..."
systemctl daemon-reload
systemctl enable $SERVICE_NAME
systemctl restart $SERVICE_NAME

echo "==============================================="
echo "✅ УСТАНОВКА ЗАВЕРШЕНА!"
echo "Сервер работает на порту 8000."
echo "Бот запущен с токеном: $BOT_TOKEN"
echo ""
echo "ВАЖНО: ТАК КАК У ТЕБЯ NGROK/ТУННЕЛЬ:"
echo "1. Запусти ngrok: ngrok http 8000"
echo "2. Скопируй ссылку (https://....ngrok-free.app)"
echo "3. Зайди в своего бота @Cryptovalychik_bot"
echo "4. Напиши команду: /seturl https://твоя-ссылка"
echo "5. Жми /start и играй!"
echo "==============================================="
