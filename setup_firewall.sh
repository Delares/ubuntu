#!/usr/bin/env bash
set -euo pipefail

# 1. Закрываем порт 22 и открываем нужные порты
echo "[*] Configuring UFW ports..."

# Открываем новые порты
for p in 80 10000 10001 10002 11001 11002; do
    sudo ufw allow "${p}"/tcp
done

# Закрываем 22 (можно заменить на 'delete allow ssh', если правило так создавалось)
sudo ufw delete allow 22/tcp || true

# Включаем UFW (если ещё не включён)
sudo ufw enable

# 2. Редактируем /etc/ufw/before.rules
echo "[*] Patching /etc/ufw/before.rules..."

FILE="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.$(date +%Y%m%d_%H%M%S).bak"

# Резервная копия
sudo cp "$FILE" "$BACKUP"
echo "Backup saved to $BACKUP"

# Функция: заменить в блоке все ACCEPT на DROP и добавить строку с source-quench
patch_block() {
    local label="$1"   # 'INPUT' или 'FORWARD'

    # 1) В блоке между комментариями меняем ACCEPT -> DROP
    sudo sed -i "/# ok icmp codes for ${label}/,/^$/ s/ACCEPT/DROP/g" "$FILE"

    # 2) Добавляем строку с source-quench, если её ещё нет
    if ! grep -q "ufw-before-$(echo "$label" | tr 'A-Z' 'a-z') -p icmp --icmp-type source-quench -j DROP" "$FILE"; then
        # Вставляем сразу после заголовка блока
        sudo sed -i "/# ok icmp codes for ${label}/a -A ufw-before-$(echo "$label" | tr 'A-Z' 'a-z') -p icmp --icmp-type source-quench -j DROP" "$FILE"
    fi
}

patch_block "INPUT"
patch_block "FORWARD"

echo "[*] Reloading UFW..."
sudo ufw reload

echo "[*] Done."
