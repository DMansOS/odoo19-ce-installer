#!/bin/bash

# ============================================================
# ODOO 19 COMMUNITY - INSTALACIÓN AUTOMÁTICA
# Ubuntu Server 24.04 LTS
# SIE7E Consultech
# ============================================================

set -e

# ============================================================
# === CONFIGURACIÓN PERSONALIZABLE ===
# ============================================================

ODOO_VERSION="19.0"

ODOO_PROJECT="odoo_cliente***"     # Cambia esto >>> Afecta al nombre de la carpeta de instalación
ODOO_USER="odoo19"                 # Cambia esto >>> Nombre de usuario del sistema Odoo
ODOO_HOME="/opt/$ODOO_PROJECT"

ODOO_DB_USER="$ODOO_USER"

ADMIN_PASSWORD="admin123"          # Cambia esto >>> Contraseña Segura

DOMAIN="dominio.com"               # Cambia esto >>> Debe de estar apuntando al servidor
EMAIL="admin@dominio.com"          # Cambia esto >>> Correo para notificaciones y administración

ODOO_CONF="/etc/$ODOO_USER.conf"
ODOO_SERVICE="/etc/systemd/system/$ODOO_USER.service"

# ============================================================
# === CONFIGURACIÓN PUETOS POR DEFECTO ===
# ============================================================

XMLRPC_PORT=8069                   # Cambia esto >>> Puerto Servidor Odoo > Para multiples instancias
LONGPOLLING_PORT=8072              # Cambia esto >>> Puerto Chat en Vivo > Para multiples instancias

# ============================================================
# === CONFIGURACIÓN INTERNA ===
# ============================================================

WKHTMLTOX_VERSION="0.12.6.1-3"
WKHTMLTOX_FILE="wkhtmltox_${WKHTMLTOX_VERSION}.jammy_amd64.deb"
WKHTMLTOX_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/${WKHTMLTOX_FILE}"
WKHTMLTOX_DEB="/tmp/${WKHTMLTOX_FILE}"

ODOO_DIR="$ODOO_HOME/odoo"
ODOO_VENV="$ODOO_HOME/odoo-venv"
CUSTOM_ADDONS="$ODOO_HOME/odoo-custom-addons"

NGINX_CONF="/etc/nginx/sites-available/$ODOO_USER"
NGINX_LINK="/etc/nginx/sites-enabled/$ODOO_USER"

# ============================================================
# === VALIDACIONES INICIALES ===
# ============================================================

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Este script debe ejecutarse como root."
    echo "Ejemplo: sudo bash install-odoo19.sh"
    exit 1
fi

if [ "$ODOO_VERSION" != "19.0" ]; then
    echo "ERROR: Este script está preparado para Odoo 19.0."
    exit 1
fi

if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "dominio.com" ]; then
    echo "ERROR: Debes configurar DOMAIN antes de ejecutar el script."
    exit 1
fi

if [ -z "$EMAIL" ] || [ "$EMAIL" = "admin@dominio.com" ]; then
    echo "ERROR: Debes configurar EMAIL antes de ejecutar el script."
    exit 1
fi

echo
echo "============================================================"
echo "     INSTALACIÓN AUTOMÁTICA DE ODOO $ODOO_VERSION"
echo "============================================================"
echo
echo "Usuario Odoo      : $ODOO_USER"
echo "Proyecto          : $ODOO_PROJECT"
echo "Directorio        : $ODOO_HOME"
echo "Puerto Odoo       : $XMLRPC_PORT"
echo "Puerto WebSocket  : $LONGPOLLING_PORT"
echo "Dominio           : $DOMAIN"
echo "Correo            : $EMAIL"
echo
echo "IMPORTANTE:"
echo "El dominio debe apuntar previamente a este servidor."
echo

# ============================================================
# 1. ACTUALIZAR SISTEMA
# ============================================================

echo
echo "============================================================"
echo "1. ACTUALIZANDO SISTEMA"
echo "============================================================"

apt update
apt upgrade -y

# ============================================================
# 2. POSTGRESQL
# ============================================================

echo
echo "============================================================"
echo "2. INSTALANDO POSTGRESQL"
echo "============================================================"

apt-get install -y postgresql

systemctl enable --now postgresql

echo
echo "Versión de PostgreSQL:"
psql --version

echo
echo "Estado de PostgreSQL:"
systemctl --no-pager --full status postgresql

# ============================================================
# 3. PYTHON Y DEPENDENCIAS
# ============================================================

echo
echo "============================================================"
echo "3. INSTALANDO PYTHON Y DEPENDENCIAS"
echo "============================================================"

apt install -y \
    git \
    python3-dev \
    python3-venv \
    python3-pip \
    build-essential \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libsasl2-dev \
    libssl-dev \
    libffi-dev \
    libpq-dev \
    libjpeg-dev \
    liblcms2-dev \
    libblas-dev \
    libatlas-base-dev \
    default-libmysqlclient-dev

echo
echo "Versión de Python:"
python3 --version

# ============================================================
# 4. USUARIO DEL SISTEMA ODOO
# ============================================================

echo
echo "============================================================"
echo "4. CREANDO USUARIO DEL SISTEMA"
echo "============================================================"

if id "$ODOO_USER" >/dev/null 2>&1; then
    echo "El usuario $ODOO_USER ya existe."
else
    useradd \
        -m \
        -d "$ODOO_HOME" \
        -U \
        -r \
        -s /bin/bash \
        "$ODOO_USER"
fi

mkdir -p "$ODOO_HOME"

chown -R "$ODOO_USER:$ODOO_USER" "$ODOO_HOME"

# ============================================================
# 5. USUARIO DE POSTGRESQL
# ============================================================

echo
echo "============================================================"
echo "5. CONFIGURANDO USUARIO DE POSTGRESQL"
echo "============================================================"

if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_DB_USER'" | grep -q 1; then
    echo "El usuario PostgreSQL $ODOO_DB_USER ya existe."
else
    sudo -u postgres createuser -d -R -S "$ODOO_DB_USER"
fi

# ============================================================
# 6. WKHTMLTOPDF
# ============================================================

echo
echo "============================================================"
echo "6. INSTALANDO WKHTMLTOPDF"
echo "============================================================"

wget -P /tmp "$WKHTMLTOX_URL"

dpkg -i "$WKHTMLTOX_DEB" || apt-get install -f -y

echo
echo "Versión instalada:"
wkhtmltopdf --version

rm -f "$WKHTMLTOX_DEB"

# ============================================================
# 7. CLONAR ODOO 19
# ============================================================

echo
echo "============================================================"
echo "7. DESCARGANDO ODOO $ODOO_VERSION"
echo "============================================================"

if [ -d "$ODOO_DIR/.git" ]; then
    echo "El código de Odoo ya existe en $ODOO_DIR."
else
    sudo -u "$ODOO_USER" git clone \
        https://github.com/odoo/odoo \
        --depth 1 \
        --branch "$ODOO_VERSION" \
        --single-branch \
        "$ODOO_DIR"
fi

# ============================================================
# 7.1. COMPATIBILIDAD ACCOUNT EDI / FACTUR-X
# ============================================================

echo
echo "============================================================"
echo "7.1. VERIFICANDO COMPATIBILIDAD ACCOUNT EDI / FACTUR-X"
echo "============================================================"

CII_FILE="$ODOO_DIR/addons/account_edi_ubl_cii/models/account_edi_cii.py"

if [ -f "$CII_FILE" ]; then

    # Detectar si Odoo ya trae la corrección oficialmente
    if grep -q "'deferred_start_date' in move_line._fields" "$CII_FILE" &&
       grep -q "'deferred_end_date' in move_line._fields" "$CII_FILE"; then

        echo "[OK] Odoo ya contiene la corrección de deferred dates."

    # Detectar código original vulnerable
    elif grep -q "if move_line.deferred_start_date" "$CII_FILE" &&
         grep -q "if move_line.deferred_end_date" "$CII_FILE"; then

        echo "[INFO] Se detectó el código vulnerable."
        echo "[INFO] Aplicando corrección de compatibilidad..."

        cp "$CII_FILE" "$CII_FILE.bak"

        python3 - "$CII_FILE" <<'PY'
import sys

file_path = sys.argv[1]

with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

old = """        billing_start_dates = [invoice.invoice_date] if invoice.invoice_date else []
        billing_start_dates += [move_line.deferred_start_date for move_line in invoice.invoice_line_ids if move_line.deferred_start_date]
        billing_end_dates = [invoice.invoice_date_due] if invoice.invoice_date_due else []
        billing_end_dates += [move_line.deferred_end_date for move_line in invoice.invoice_line_ids if move_line.deferred_end_date]"""

new = """        billing_start_dates = [invoice.invoice_date] if invoice.invoice_date else []
        billing_start_dates += [
            move_line.deferred_start_date
            for move_line in invoice.invoice_line_ids
            if 'deferred_start_date' in move_line._fields and move_line.deferred_start_date
        ]

        billing_end_dates = [invoice.invoice_date_due] if invoice.invoice_date_due else []
        billing_end_dates += [
            move_line.deferred_end_date
            for move_line in invoice.invoice_line_ids
            if 'deferred_end_date' in move_line._fields and move_line.deferred_end_date
        ]"""

if old not in content:
    print("[ERROR] No se encontró exactamente el código esperado.")
    sys.exit(1)

content = content.replace(old, new, 1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)

print("[OK] Corrección aplicada correctamente.")
PY

    else
        echo "[ADVERTENCIA] No se pudo determinar el estado de la corrección."
        echo "[ADVERTENCIA] No se modificó el código de Odoo."
    fi

else
    echo "[ADVERTENCIA] No existe account_edi_ubl_cii."
fi

# ============================================================
# 8. VIRTUAL ENVIRONMENT
# ============================================================

echo
echo "============================================================"
echo "8. CREANDO ENTORNO VIRTUAL DE PYTHON"
echo "============================================================"

if [ ! -d "$ODOO_VENV" ]; then
    sudo -u "$ODOO_USER" python3 -m venv "$ODOO_VENV"
fi

sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install --upgrade pip

sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install setuptools wheel

sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install \
    -r "$ODOO_DIR/requirements.txt"

# ============================================================
# 9. CUSTOM ADDONS
# ============================================================

echo
echo "============================================================"
echo "9. CREANDO DIRECTORIO DE CUSTOM ADDONS"
echo "============================================================"

mkdir -p "$CUSTOM_ADDONS"

chown -R "$ODOO_USER:$ODOO_USER" "$CUSTOM_ADDONS"

# ============================================================
# 10. CONFIGURACIÓN DE ODOO
# ============================================================

echo
echo "============================================================"
echo "10. CREANDO CONFIGURACIÓN DE ODOO"
echo "============================================================"

cat > "$ODOO_CONF" <<EOF
[options]

; Contraseña que permite la gestión de la base de datos
admin_passwd = $ADMIN_PASSWORD

db_host = False
db_port = False
db_user = $ODOO_DB_USER
db_password = False

; Rutas de los módulos oficiales y personalizados
addons_path = $ODOO_DIR/addons,$CUSTOM_ADDONS

; Puerto principal de Odoo
http_port = $XMLRPC_PORT

; Puerto utilizado por WebSocket (gevent)
gevent_port = $LONGPOLLING_PORT

; Habilita el modo proxy cuando Odoo está detrás de NGINX
proxy_mode = True

; Restringe Odoo para que solo escuche en la interfaz local.
; Se descomenta automáticamente después de configurar NGINX y SSL.
; http_interface = 127.0.0.1

; Número de workers para mejorar el rendimiento en producción
workers = 2

; Si usa más de una base de datos, descomente la siguiente línea
; y especifique el filtro correspondiente.
; dbfilter = [your_database]
EOF

# IMPORTANTE:
# Odoo debe poder leer este archivo.
# root puede modificarlo y el usuario Odoo puede leerlo.
chown root:"$ODOO_USER" "$ODOO_CONF"
chmod 640 "$ODOO_CONF"

# ============================================================
# 11. SERVICIO SYSTEMD
# ============================================================

echo
echo "============================================================"
echo "11. CREANDO SERVICIO SYSTEMD"
echo "============================================================"

cat > "$ODOO_SERVICE" <<EOF
[Unit]
Description=odoo19
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$ODOO_USER
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_VENV/bin/python3 $ODOO_DIR/odoo-bin -c $ODOO_CONF
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

systemctl enable --now "$ODOO_USER"

echo
echo "Estado del servicio Odoo:"
systemctl --no-pager --full status "$ODOO_USER"

# ============================================================
# 12. VERIFICACIÓN INICIAL DE ODOO
# ============================================================

echo
echo "============================================================"
echo "12. VERIFICANDO PUERTO DE ODOO"
echo "============================================================"

sleep 3

ss -lntp | grep ":$XMLRPC_PORT" || true

# ============================================================
# 13. INSTALAR NGINX
# ============================================================

echo
echo "============================================================"
echo "13. INSTALANDO NGINX"
echo "============================================================"

apt install -y nginx

systemctl enable nginx

echo
echo "Estado de NGINX:"
systemctl --no-pager --full status nginx

# ============================================================
# 14. INSTALAR CERTBOT
# ============================================================

echo
echo "============================================================"
echo "14. INSTALANDO CERTBOT"
echo "============================================================"

apt install -y certbot python3-certbot-nginx

# ============================================================
# 15. PREPARAR LET'S ENCRYPT
# ============================================================

echo
echo "============================================================"
echo "15. PREPARANDO LET'S ENCRYPT"
echo "============================================================"

mkdir -p /var/lib/letsencrypt

chgrp www-data /var/lib/letsencrypt
chmod g+s /var/lib/letsencrypt

mkdir -p /var/lib/letsencrypt/.well-known/acme-challenge

# ============================================================
# 16. CONFIGURACIÓN INICIAL NGINX
# ============================================================

echo
echo "============================================================"
echo "16. CONFIGURANDO NGINX PARA CERTBOT"
echo "============================================================"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
        default_type "text/plain";
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}
EOF

ln -sf "$NGINX_CONF" "$NGINX_LINK"

nginx -t

systemctl restart nginx

# ============================================================
# 17. PRUEBA ACME
# ============================================================

echo
echo "============================================================"
echo "17. PROBANDO ACME CHALLENGE"
echo "============================================================"

mkdir -p /var/lib/letsencrypt/.well-known/acme-challenge

echo "certbot-test" | tee \
    /var/lib/letsencrypt/.well-known/acme-challenge/test >/dev/null

echo
echo "Probando:"
echo "http://$DOMAIN/.well-known/acme-challenge/test"

curl -f "http://$DOMAIN/.well-known/acme-challenge/test"

echo
echo "Probando:"
echo "http://www.$DOMAIN/.well-known/acme-challenge/test"

curl -f "http://www.$DOMAIN/.well-known/acme-challenge/test"

rm -f /var/lib/letsencrypt/.well-known/acme-challenge/test

# ============================================================
# 18. CERTIFICADO SSL
# ============================================================

echo
echo "============================================================"
echo "18. GENERANDO CERTIFICADO SSL"
echo "============================================================"

certbot certonly \
    --non-interactive \
    --agree-tos \
    --no-eff-email \
    --email "$EMAIL" \
    --webroot \
    -w /var/lib/letsencrypt \
    -d "$DOMAIN" \
    -d "www.$DOMAIN"

echo
echo "Certificados disponibles:"
certbot certificates

# ============================================================
# 19. CONFIGURACIÓN FINAL NGINX
# ============================================================

echo
echo "============================================================"
echo "19. CONFIGURANDO NGINX + HTTPS + WEBSOCKET"
echo "============================================================"

cat > "$NGINX_CONF" <<EOF
upstream odooserver {
    server 127.0.0.1:$XMLRPC_PORT;
}

upstream odoochat {
    server 127.0.0.1:$LONGPOLLING_PORT;
}

# ============================================================
# HTTP -> HTTPS
# ============================================================

server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN www.$DOMAIN;

    location ^~ /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
        default_type "text/plain";
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}

# ============================================================
# HTTPS www -> DOMINIO PRINCIPAL
# ============================================================

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location ^~ /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
        default_type "text/plain";
        try_files \$uri =404;
    }

    return 301 https://$DOMAIN\$request_uri;
}

# ============================================================
# HTTPS PRINCIPAL
# ============================================================

server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    proxy_set_header X-Forwarded-Host \$host;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Real-IP \$remote_addr;

    access_log /var/log/nginx/odoo.access.log;
    error_log /var/log/nginx/odoo.error.log;

    client_max_body_size 200m;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    # ========================================================
    # Let's Encrypt
    # ========================================================

    location ^~ /.well-known/acme-challenge/ {
        root /var/lib/letsencrypt;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # ========================================================
    # WebSocket
    # ========================================================

    location /websocket {
        proxy_pass http://odoochat;

        proxy_http_version 1.1;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
    }

    # ========================================================
    # Odoo
    # ========================================================

    location / {
        proxy_pass http://odooserver;

        proxy_redirect off;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # ========================================================
    # Archivos estáticos
    # ========================================================

    location ~* /web/static/ {
        proxy_cache_valid 200 90m;
        proxy_buffering on;
        expires 864000;

        proxy_pass http://odooserver;
    }

    # ========================================================
    # Gzip
    # ========================================================

    gzip on;

    gzip_types
        text/css
        text/plain
        text/xml
        application/xml
        application/json
        application/javascript;
}
EOF

nginx -t

systemctl reload nginx

# ============================================================
# 20. CERTBOT TIMER
# ============================================================

echo
echo "============================================================"
echo "20. VERIFICANDO RENOVACIÓN AUTOMÁTICA"
echo "============================================================"

systemctl enable --now certbot.timer

echo
echo "Estado de certbot.timer:"
systemctl --no-pager --full status certbot.timer

echo
echo "Prueba de renovación:"
certbot renew --dry-run

# ============================================================
# 21. RESTRINGIR ODOO A LOCALHOST
# ============================================================

echo
echo "============================================================"
echo "21. RESTRINGIENDO ODOO A 127.0.0.1"
echo "============================================================"

sed -i \
    's/^; http_interface = 127\.0\.0\.1$/http_interface = 127.0.0.1/' \
    "$ODOO_CONF"

# ============================================================
# 22. REINICIAR ODOO
# ============================================================

echo
echo "============================================================"
echo "22. REINICIANDO ODOO"
echo "============================================================"

systemctl restart "$ODOO_USER"

sleep 3

echo
echo "Estado final de Odoo:"
systemctl --no-pager --full status "$ODOO_USER"

# ============================================================
# 23. VERIFICACIÓN FINAL
# ============================================================

echo
echo "============================================================"
echo "VERIFICACIÓN FINAL"
echo "============================================================"

ERRORS=0

# ------------------------------------------------------------
# ODOO
# ------------------------------------------------------------

if systemctl is-active --quiet "$ODOO_USER"; then
    echo "[OK] Odoo está activo"
else
    echo "[ERROR] Odoo no está activo"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# NGINX
# ------------------------------------------------------------

if systemctl is-active --quiet nginx; then
    echo "[OK] NGINX está activo"
else
    echo "[ERROR] NGINX no está activo"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# CERTBOT
# ------------------------------------------------------------

if systemctl is-active --quiet certbot.timer; then
    echo "[OK] Certbot está activo"
else
    echo "[ERROR] Certbot no está activo"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# CONFIGURACIÓN NGINX
# ------------------------------------------------------------

if nginx -t >/dev/null 2>&1; then
    echo "[OK] Configuración de NGINX correcta"
else
    echo "[ERROR] Configuración de NGINX incorrecta"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# PUERTO ODOO
# ------------------------------------------------------------

if ss -lnt | grep -q "127.0.0.1:$XMLRPC_PORT"; then
    echo "[OK] Odoo escucha en 127.0.0.1:$XMLRPC_PORT"
else
    echo "[ERROR] Odoo no está escuchando en 127.0.0.1:$XMLRPC_PORT"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# PUERTO WEBSOCKET
# ------------------------------------------------------------

if ss -lnt | grep -q "127.0.0.1:$LONGPOLLING_PORT"; then
    echo "[OK] WebSocket escucha en 127.0.0.1:$LONGPOLLING_PORT"
else
    echo "[ERROR] WebSocket no está escuchando en 127.0.0.1:$LONGPOLLING_PORT"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# HTTP
# ------------------------------------------------------------

if ss -lnt | grep -qE '0\.0\.0\.0:80|\*:80|:::80'; then
    echo "[OK] HTTP está escuchando en el puerto 80"
else
    echo "[ERROR] HTTP no está escuchando en el puerto 80"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# HTTPS
# ------------------------------------------------------------

if ss -lnt | grep -qE '0\.0\.0\.0:443|\*:443|:::443'; then
    echo "[OK] HTTPS está escuchando en el puerto 443"
else
    echo "[ERROR] HTTPS no está escuchando en el puerto 443"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# CONFIGURACIÓN ODOO
# ------------------------------------------------------------

if grep -q "^http_interface = 127.0.0.1$" "$ODOO_CONF"; then
    echo "[OK] Odoo está restringido a 127.0.0.1"
else
    echo "[ERROR] Odoo NO está restringido a 127.0.0.1"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# CERTIFICADO SSL
# ------------------------------------------------------------

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] &&
   [ -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    echo "[OK] Certificado SSL encontrado"
else
    echo "[ERROR] Certificado SSL no encontrado"
    ERRORS=$((ERRORS + 1))
fi

# ------------------------------------------------------------
# RESULTADO FINAL
# ------------------------------------------------------------

echo

if [ "$ERRORS" -eq 0 ]; then

    echo "============================================================"
    echo "INSTALACIÓN COMPLETADA CORRECTAMENTE"
    echo "============================================================"
    echo
    echo "[OK] Odoo está activo"
    echo "[OK] NGINX está activo"
    echo "[OK] Certbot está activo"
    echo "[OK] SSL configurado"
    echo "[OK] Odoo protegido en localhost"
    echo "[OK] WebSocket configurado"
    echo "[OK] Puertos verificados"
    echo
    echo -e "\e[1;36mOdoo:\e[0m \e[1;32mhttps://$DOMAIN\e[0m"
    echo

else

    echo "============================================================"
    echo "INSTALACIÓN FINALIZADA CON $ERRORS ERROR(ES)"
    echo "============================================================"
    echo
    echo "Revisa los mensajes marcados con [ERROR]."
    echo

    exit 1

fi

# ============================================================
# === FIN ===
# ============================================================

echo -e "Instalación de Odoo v19 finalizada en \e[1;32mhttps://$DOMAIN\e[0m por SIE7E Consultech"
echo -
echo
echo ░██████╗██╗███████╗███████╗███████╗
echo ██╔════╝██║██╔════╝╚════██║██╔════╝
echo ╚█████╗░██║█████╗░░░░░░██╔╝█████╗░░
echo ░╚═══██╗██║██╔══╝░░░░░██╔╝░██╔══╝░░
echo ██████╔╝██║███████╗░░██╔╝░░███████╗
echo ╚═════╝░╚═╝╚══════╝░░╚═╝░░░╚══════╝
echo 
echo ░█████╗░░█████╗░███╗░░██╗░██████╗██╗░░░██╗██╗░░░░░████████╗███████╗░█████╗░██╗░░██╗
echo ██╔══██╗██╔══██╗████╗░██║██╔════╝██║░░░██║██║░░░░░╚══██╔══╝██╔════╝██╔══██╗██║░░██║
echo ██║░░╚═╝██║░░██║██╔██╗██║╚█████╗░██║░░░██║██║░░░░░░░░██║░░░█████╗░░██║░░╚═╝███████║
echo ██║░░██╗██║░░██║██║╚████║░╚═══██╗██║░░░██║██║░░░░░░░░██║░░░██╔══╝░░██║░░██╗██╔══██║
echo ╚█████╔╝╚█████╔╝██║░╚███║██████╔╝╚██████╔╝███████╗░░░██║░░░███████╗╚█████╔╝██║░░██║
echo ░╚════╝░░╚════╝░╚═╝░░╚══╝╚═════╝░░╚═════╝░░░╚══════╝░░░╚═╝░░░╚══════╝░╚════╝░╚═╝░░╚═╝
echo -
echo WWW.SIETECONSULTECH.COM
echo -