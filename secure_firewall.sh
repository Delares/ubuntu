#!/usr/bin/env bash
set -euo pipefail

echo "[*] Configuring UFW ports..."

# Открываем нужные порты
for p in 80 10000 10001 10002 11001 11002; do
    sudo ufw allow "${p}"/tcp
done

# Закрываем 22-й порт (если правило есть)
sudo ufw delete allow 22/tcp || true

# Включаем UFW (если ещё не включён)
sudo ufw --force enable

echo "[*] Patching /etc/ufw/before.rules..."

FILE="/etc/ufw/before.rules"
BACKUP="/etc/ufw/before.rules.$(date +%Y%m%d_%H%M%S).bak"

# Бэкап
sudo cp "$FILE" "$BACKUP"
echo "Backup saved to $BACKUP"

patch_block() {
    local label="$1"   # INPUT или FORWARD
    local chain="ufw-before-$(echo "$label" | tr 'A-Z' 'a-z')"  # ufw-before-input/forward

    # 1) В блоке между комментариями меняем ACCEPT->DROP
    sudo sed -i "/# ok icmp codes for ${label}/,/^#/ s/ACCEPT/DROP/g" "$FILE"

    # 2) Добавляем правило source-quench, если ещё нет
    local rule="-A ${chain} -p icmp --icmp-type source-quench -j DROP"
    if ! grep -qF "$rule" "$FILE"; then
        sudo sed -i "/# ok icmp codes for ${label}/a ${rule}" "$FILE"
    fi
}

patch_block "INPUT"
patch_block "FORWARD"

echo "[*] Reloading UFW..."
sudo ufw reload

echo "[*] Changing SSH port to 10002..."

SSHD_CFG="/etc/ssh/sshd_config"
sudo cp "$SSHD_CFG" "${SSHD_CFG}.$(date +%Y%m%d_%H%M%S).bak"

# Если есть закомментированная строка Port 22 — раскомментируем и поменяем
if grep -qE '^[#]*Port[[:space:]]+22' "$SSHD_CFG"; then
    sudo sed -i 's/^[#]*Port[[:space:]]\+22/Port 10002/' "$SSHD_CFG"
elif grep -qE '^Port[[:space:]]+' "$SSHD_CFG"; then
    # Если есть другая строка Port N — меняем на 10002
    sudo sed -i 's/^Port[[:space:]]\+[0-9]\+/Port 10002/' "$SSHD_CFG"
else
    # Если строки Port нет — добавляем
    echo "Port 10002" | sudo tee -a "$SSHD_CFG" >/dev/null
fi

# Разрешаем новый порт для SSH (на всякий случай ещё раз)
sudo ufw allow 10002/tcp

echo "[*] Restarting sshd..."
sudo systemctl restart sshd

echo "[*] Done. Test SSH with: ssh -p 10002 user@server"
