import json
import random
import os
import requests
from bs4 import BeautifulSoup
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

app = FastAPI()

# Разрешаем запросы из Телеграма
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- 1. НАСТРОЙКИ И ДАННЫЕ ---
USERS_FILE = "users_db.json"
IMAGE_CACHE_FILE = "image_cache.json"

# Загружаем конфиги
with open("gpus.json", "r", encoding="utf-8") as f:
    GPUS_DB = json.load(f)

with open("coins.json", "r", encoding="utf-8") as f:
    COINS_DB = json.load(f)

# Кэш картинок (чтобы Google нас не забанил за частые запросы)
if os.path.exists(IMAGE_CACHE_FILE):
    with open(IMAGE_CACHE_FILE, "r") as f:
        image_cache = json.load(f)
else:
    image_cache = {}

# --- 2. ПАРСЕР КАРТИНОК (GOOGLE) ---
def get_image_url(query):
    """Ищет картинку в гугле по запросу. Если уже искали — берет из кэша."""
    if query in image_cache:
        return image_cache[query]

    try:
        print(f"🔍 Ищу картинку для: {query}...")
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/100.0.4896.60 Safari/537.36"
        }
        params = {"q": query, "tbm": "isch", "hl": "en"}
        # Используем прокси или просто таймауты в реальном проекте
        html = requests.get("https://www.google.com/search", params=params, headers=headers, timeout=5).text
        soup = BeautifulSoup(html, 'html.parser')
        
        # Google часто меняет верстку, ищем все img и берем первый нормальный url
        images = soup.find_all('img')
        for img in images:
            src = img.get('src')
            if src and src.startswith('http') and 'encrypted' in src:
                image_cache[query] = src
                # Сохраняем кэш
                with open(IMAGE_CACHE_FILE, "w") as f:
                    json.dump(image_cache, f)
                return src
    except Exception as e:
        print(f"Ошибка парсинга: {e}")

    return "https://via.placeholder.com/150?text=GPU" # Заглушка

# Предзагрузка картинок при старте
for item in GPUS_DB:
    item['image_url'] = get_image_url(item['image_query'])

# --- 3. РАБОТА С БАЗОЙ ДАННЫХ ---
def load_users():
    if os.path.exists(USERS_FILE):
        with open(USERS_FILE, "r") as f:
            return json.load(f)
    return {}

def save_users(users_data):
    with open(USERS_FILE, "w") as f:
        json.dump(users_data, f, indent=2)

users_db = load_users()

def get_or_create_user(user_id):
    user_id = str(user_id)
    if user_id not in users_db:
        users_db[user_id] = {
            "balance": 1000.0,  # Стартовый капитал
            "rig": [],          # Установленные карты
            "inventory": [],    # Карты в запасе
            "mined_coins": {c['symbol']: 0.0 for c in COINS_DB}
        }
        save_users(users_db)
    return users_db[user_id]

# --- 4. API МОДЕЛИ ---
class InitRequest(BaseModel):
    user_id: int

class BuyRequest(BaseModel):
    user_id: int
    item_id: str
    is_used: bool

class ActionRequest(BaseModel):
    user_id: int
    item_uid: Optional[int] = None # Для ремонта
    coin_symbol: Optional[str] = None # Для майнинга

# --- 5. ЭНДПОИНТЫ (API) ---

@app.post("/api/init")
def init_game(req: InitRequest):
    user = get_or_create_user(req.user_id)
    
    # Генерируем Б/У рынок "на лету" каждый раз при входе
    used_market = []
    for gpu in GPUS_DB:
        if gpu.get('type') == 'psu': continue # БП редко продают б/у в игре
        
        # Шанс появления карты на б/у
        if random.random() > 0.3:
            wear_lvl = random.randint(15, 60) # Износ от 15 до 60%
            discount = wear_lvl * 0.8 # Скидка зависит от износа
            price = gpu['price'] * (1 - discount/100)
            
            used_market.append({
                **gpu,
                "price": int(price),
                "is_used": True,
                "wear": wear_lvl,
                "id": gpu['id']
            })

    return {
        "user": user,
        "shop_new": GPUS_DB,
        "shop_used": used_market,
        "coins": COINS_DB
    }

@app.post("/api/buy")
def buy_item(req: BuyRequest):
    user = get_or_create_user(req.user_id)
    
    # Ищем товар (в новых или создаем имитацию б/у по ID, если бы мы хранили рынок)
    # Для упрощения: мы доверяем клиенту, что он выбрал из списка, но пересчитываем цену
    base_item = next((g for g in GPUS_DB if g['id'] == req.item_id), None)
    if not base_item:
        raise HTTPException(404, "Item not found")

    price = base_item['price']
    wear = 0
    
    # Если покупка Б/У, генерируем параметры заново (симуляция того, что купил с рынка)
    if req.is_used:
        # В реальности тут надо передавать ID конкретного лота, но сделаем проще
        wear = random.randint(20, 50) 
        price = price * (1 - (wear * 0.8)/100)

    if user['balance'] < price:
        raise HTTPException(400, "Недостаточно денег!")

    user['balance'] -= price
    
    new_item = {
        "uid": random.randint(100000, 999999), # Уникальный ID конкретной железки
        "model_id": base_item['id'],
        "name": base_item['name'],
        "hashrate": base_item.get('hashrate', 0),
        "power": base_item['power'],
        "wear": wear,
        "image_url": base_item['image_url'],
        "type": base_item.get('type', 'gpu')
    }

    # Логика слотов: если GPU и есть место (<4), ставим в риг. Иначе в инвентарь.
    # БП (psu) всегда в риг, заменяя старый, или просто хранится.
    if new_item['type'] == 'gpu':
        if len(user['rig']) < 4: # Допустим 4 слота
            user['rig'].append(new_item)
        else:
            user['inventory'].append(new_item)
    else:
        user['inventory'].append(new_item) # Блоки питания пока в инвентарь

    save_users(users_db)
    return {"status": "ok", "user": user}

@app.post("/api/mine")
def mine_process(req: ActionRequest):
    user = get_or_create_user(req.user_id)
    coin = next((c for c in COINS_DB if c['symbol'] == req.coin_symbol), None)
    
    if not coin: raise HTTPException(404, "Unknown coin")

    total_hashrate = 0
    log = []

    # Расчет майнинга
    for card in user['rig']:
        if card['wear'] >= 100:
            log.append(f"{card['name']} сломана и не майнит.")
            continue
        
        # Эффективность падает от износа
        efficiency = 1.0 - (card['wear'] / 200) # Даже при 100% износе, эффективность 50%, потом слом
        actual_hash = card['hashrate'] * efficiency
        total_hashrate += actual_hash

        # Добавляем износ (рандомно)
        damage = random.uniform(0.5, 2.0)
        card['wear'] = min(100, card['wear'] + damage)

    # Формула награды: (Хэшрейт / Сложность) * 10 (множитель скорости игры)
    reward = (total_hashrate / coin['difficulty']) * 100 
    
    # Конвертируем в USD для баланса (или можно копить монеты)
    profit_usd = reward * coin['price_usd']
    
    # Оплата электричества (сумма ватт * цену кВт) - упрощенно 10% от дохода
    elec_cost = profit_usd * 0.15 
    final_profit = max(0, profit_usd - elec_cost)

    user['balance'] += final_profit
    user['mined_coins'][coin['symbol']] += reward
    
    save_users(users_db)
    return {
        "profit_usd": final_profit,
        "reward_coin": reward,
        "rig": user['rig'],
        "balance": user['balance']
    }

@app.post("/api/repair")
def repair_item(req: ActionRequest):
    user = get_or_create_user(req.user_id)
    
    # Ищем карту везде
    target = None
    in_rig = True
    for c in user['rig']:
        if c['uid'] == req.item_uid: target = c
    if not target:
        in_rig = False
        for c in user['inventory']:
            if c['uid'] == req.item_uid: target = c
            
    if not target: raise HTTPException(404, "Card not found")

    # Цена ремонта: $1 за каждый 1% износа
    cost = target['wear'] * 2.0 
    
    if user['balance'] < cost:
        raise HTTPException(400, "Нет денег на ремонт")

    user['balance'] -= cost
    target['wear'] = 0
    
    save_users(users_db)
    return {"status": "repaired", "user": user, "cost": cost}

# Раздача статики (HTML файл будет тут)
app.mount("/", StaticFiles(directory="static", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
