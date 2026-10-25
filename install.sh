#!/bin/sh
# Instalador do Klipper hibrido (firmware oficial + comunidade) para Ender-3 V3 SE.
# Testado em Debian 13 x86_64; para Raspberry Pi OS Lite 64-bit (Zero 2W / Pi 4/5) os
# mesmos passos valem (nao usa qemu nem binarios pre-compilados).
#
# uso:
#   sudo ./install.sh                      # instala em /opt/klipper-v3se
#   sudo DIR=/opt/klipper-v3se SERIAL=/dev/serial/by-id/usb-XXXX ./install.sh
#   sudo ./install.sh --build-firmware     # tambem compila o MCU com HX71X
#
set -eu

DIR=${DIR:-/opt/klipper-v3se}
DATA=$DIR/printer_data
TAG=${TAG:-1.0.1}
FORK=https://github.com/jpcurti/ender3-v3-se-klipper-with-display.git
HERE=$(cd "$(dirname "$0")" && pwd)
SERIAL=${SERIAL:-}
BUILD_FW=0
[ "${1:-}" = "--build-firmware" ] && BUILD_FW=1

log() { printf '\n=== %s\n' "$*"; }

[ "$(id -u)" = 0 ] || { echo "rode como root"; exit 1; }

log "1/9 pacotes"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl unzip nginx python3-venv python3-dev build-essential \
    openssl 7zip libsodium23 ca-certificates >/dev/null

log "2/9 klipper ($TAG) + patches"
mkdir -p "$DIR"
[ -d "$DIR/klipper" ] || git clone -q "$FORK" "$DIR/klipper"
cd "$DIR/klipper"
git fetch -q --tags
git checkout -q "$TAG"
git config user.email "klipper@localhost" 2>/dev/null || true
git config user.name "klipper" 2>/dev/null || true
for p in "$HERE"/patches/*.patch; do
    [ -e "$p" ] || continue
    if git log --oneline | grep -q "$(basename "$p" .patch | cut -c1-40)"; then
        echo "  ja aplicado: $(basename "$p")"
    else
        git am -q "$p" || { echo "FALHA aplicando $p"; git am --abort; exit 1; }
        echo "  aplicado: $(basename "$p")"
    fi
done

log "3/9 venv do klipper"
[ -d "$DIR/klipper-env" ] || python3 -m venv "$DIR/klipper-env"
"$DIR/klipper-env/bin/pip" install -q --upgrade pip
"$DIR/klipper-env/bin/pip" install -q -r scripts/klippy-requirements.txt

log "4/9 moonraker"
[ -d "$DIR/moonraker" ] || git clone -q --depth 1 https://github.com/Arksine/moonraker.git "$DIR/moonraker"
[ -d "$DIR/moonraker-env" ] || python3 -m venv "$DIR/moonraker-env"
"$DIR/moonraker-env/bin/pip" install -q --upgrade pip
"$DIR/moonraker-env/bin/pip" install -q -r "$DIR/moonraker/scripts/moonraker-requirements.txt"

log "5/9 fluidd"
mkdir -p /var/www
if [ ! -f /var/www/fluidd/index.html ]; then
    curl -fsSL -o /tmp/fluidd.zip https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip
    python3 -c "import zipfile;zipfile.ZipFile('/tmp/fluidd.zip').extractall('/var/www/fluidd')"
fi

log "6/9 configs"
mkdir -p "$DATA/config" "$DATA/logs" "$DATA/gcodes" "$DATA/comms"
for f in "$HERE"/config/*.cfg "$HERE"/config/moonraker.conf; do
    [ -e "$f" ] || continue
    dest="$DATA/config/$(basename "$f")"
    [ -e "$dest" ] || cp "$f" "$dest"
done
# ajusta caminhos e serial
for f in "$DATA"/config/*.cfg "$DATA"/config/moonraker.conf; do
    [ -e "$f" ] || continue
    sed -i "s|/opt/klipper-v3se|$DIR|g" "$f"
done
if [ -n "$SERIAL" ]; then
    sed -i "s|^serial:.*|serial: $SERIAL|" "$DATA/config/printer.cfg"
fi

log "7/9 unidades systemd"
cat > /etc/systemd/system/klipper.service <<EOF
[Unit]
Description=Klipper (fork jpcurti + patches hibridos)
After=network.target
Before=moonraker.service

[Service]
Type=simple
ExecStart=$DIR/klipper-env/bin/python $DIR/klipper/klippy/klippy.py $DATA/config/printer.cfg -a $DATA/comms/klippy.sock -l $DATA/logs/klippy.log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/moonraker.service <<EOF
[Unit]
Description=Moonraker
After=network.target klipper.service
Wants=klipper.service

[Service]
Type=simple
ExecStart=$DIR/moonraker-env/bin/python $DIR/moonraker/moonraker/moonraker.py -d $DATA
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/nginx/sites-available/firmware oficial <<'EOF'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/fluidd;
    index index.html;
    client_max_body_size 1024m;
    location / { try_files $uri $uri/ /index.html; }
    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://127.0.0.1:7125$request_uri;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF
ln -sf /etc/nginx/sites-available/firmware oficial /etc/nginx/sites-enabled/firmware oficial
rm -f /etc/nginx/sites-enabled/default
nginx -t

log "8/9 servicos"
systemctl daemon-reload
systemctl enable --now klipper moonraker >/dev/null 2>&1 || true
systemctl restart nginx

log "9/9 firmware do MCU (opcional)"
if [ "$BUILD_FW" = 1 ]; then
    apt-get install -y -qq gcc-arm-none-eabi >/dev/null
    cd "$DIR/klipper"
    cp -f test/configs/displayv3se.config .config
    grep -q '^CONFIG_WANT_HX71X=y' .config || echo 'CONFIG_WANT_HX71X=y' >> .config
    make olddefconfig >/dev/null
    make -j"$(nproc)" >/dev/null
    cp out/klipper.bin "$DIR/e3v3se_klipper_hx71x.bin"
    echo "  firmware: $DIR/e3v3se_klipper_hx71x.bin  (copie para o SD e ligue a impressora)"
    arm-none-eabi-nm out/klipper.elf | grep -c hx71 >/dev/null && echo "  HX71X presente: OK"
fi

IP=$(hostname -I | awk '{print $1}')
cat <<EOF

============================================================
 Instalado.
   Web UI .... http://$IP/
   API ....... http://$IP:7125/
   Dados ..... $DATA

 Proximos passos (uma vez):
   1. ajuste o serial em $DATA/config/printer.cfg se necessario
   2. no Fluidd: PID_EXTRUDER TARGET=210 / PID_BED TARGET=70
   3. MESH_CALIBRATE          (refaz e salva o mesh)
   4. AUTO_Z                  (mede o contato pela celula e aplica o offset)
   5. imprima uma peca com PRINT_START

 O PRINT_START usa o mesh salvo (rapido). Para refazer mesh/offset use as macros
 MESH_CALIBRATE / AUTO_Z, ou PRINT_START ... MESH=1 AUTO_Z=1.
============================================================
EOF
