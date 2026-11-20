#!/bin/bash

# ============================================================
# ODOO 19 COMMUNITY - INSTALACIÓN AUTOMÁTICA (v2)
# Ubuntu Server 24.04 LTS + PostgreSQL + NGINX + SSL
# SIE7E Consultech - www.sieteconsultech.com
# ============================================================
# Uso (como root, en el servidor del cliente):
#   bash <(curl -fsSL https://raw.githubusercontent.com/DMansOS/odoo19-ce-installer/main/odoo19CE_install_v2.sh)
#
# El script pregunta los datos (dominio, correo, proyecto...), muestra un
# resumen y pide confirmación antes de instalar.
# NO usar "curl ... | bash": así las preguntas no pueden leer lo que escribes.
#
# Sin preguntas: pasa los datos como variables de entorno, por ejemplo
#   DOMAIN=cliente.com EMAIL=ventas@cliente.com ODOO_SI=1 bash odoo19CE_install_v2.sh
# Variables: DOMAIN, USE_WWW, EMAIL, ODOO_PROJECT, ODOO_USER, HTTP_PORT,
#            GEVENT_PORT, ADMIN_PASSWORD, ODOO_SI, ODOO_SOLO_PREGUNTAS.
# ODOO_SOLO_PREGUNTAS=1 muestra el resumen y sale sin instalar nada.
#
# Si el archivo viene de Windows: sed -i 's/\r$//' odoo19CE_install_v2.sh
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ============================================================
# === DATOS DE LA INSTALACIÓN ===
# Se piden al arrancar. Si la variable ya viene en el entorno, no se pregunta.
# ============================================================

ODOO_VERSION="19.0"

ODOO_PROJECT="${ODOO_PROJECT:-}"      # Carpeta /opt/<proyecto>. Propuesto: odoo_<cliente>
ODOO_USER="${ODOO_USER:-}"            # Usuario del sistema y servicio. Propuesto: odoo19
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"  # Contraseña maestra. Vacía = se genera una segura y se guarda en /root
DOMAIN="${DOMAIN:-}"                  # Debe apuntar a este servidor. Sin valor propuesto
USE_WWW="${USE_WWW:-}"                # true/false: si www.<dominio> también apunta al servidor. Propuesto: true
EMAIL="${EMAIL:-}"                    # Avisos de Let's Encrypt. Propuesto: admin@<dominio>
HTTP_PORT="${HTTP_PORT:-}"            # Puerto principal. Propuesto: 8069 (o el siguiente libre)
GEVENT_PORT="${GEVENT_PORT:-}"        # Puerto WebSocket. Propuesto: 8072 (o el siguiente libre)

# ============================================================
# === RENDIMIENTO (ajustar según CPU y RAM del servidor) ===
# ============================================================

WORKERS=2
LIMIT_MEMORY_SOFT=2147483648       # 2 GB
LIMIT_MEMORY_HARD=2684354560       # 2.5 GB
LIMIT_TIME_CPU=600
LIMIT_TIME_REAL=1200
MAX_CRON_THREADS=1

# ============================================================
# === FUNCIONES ===
# ============================================================

titulo() {
    echo
    echo "============================================================"
    echo "$1"
    echo "============================================================"
}

error() {
    echo -e "\e[1;31mERROR:\e[0m $1" >&2
    exit 1
}

estado() {
    # systemctl status devuelve error si el servicio no está activo;
    # se muestra igual y la verificación real se hace al final.
    systemctl --no-pager --full status "$1" || true
}

firma_sie7e() {
    local C='\e[1;36m' G='\e[1;32m' N='\e[0m'
    echo -e "$C"
    cat <<'EOF'
  ██████╗██╗███████╗███████╗███████╗
 ██╔════╝██║██╔════╝╚════██║██╔════╝
 ╚█████╗ ██║█████╗      ██╔╝█████╗  
  ╚═══██╗██║██╔══╝     ██╔╝ ██╔══╝  
 ██████╔╝██║███████╗  ██╔╝  ███████╗
 ╚═════╝ ╚═╝╚══════╝  ╚═╝   ╚══════╝

  █████╗  █████╗ ███╗  ██╗ ██████╗██╗   ██╗██╗     ████████╗███████╗ █████╗ ██╗  ██╗
 ██╔══██╗██╔══██╗████╗ ██║██╔════╝██║   ██║██║     ╚══██╔══╝██╔════╝██╔══██╗██║  ██║
 ██║  ╚═╝██║  ██║██╔██╗██║╚█████╗ ██║   ██║██║        ██║   █████╗  ██║  ╚═╝███████║
 ██║  ██╗██║  ██║██║╚████║ ╚═══██╗██║   ██║██║        ██║   ██╔══╝  ██║  ██╗██╔══██║
 ╚█████╔╝╚█████╔╝██║ ╚███║██████╔╝╚██████╔╝███████╗   ██║   ███████╗╚█████╔╝██║  ██║
  ╚════╝  ╚════╝ ╚═╝  ╚══╝╚═════╝  ╚═════╝  ╚══════╝   ╚═╝   ╚══════╝ ╚════╝ ╚═╝  ╚═╝
EOF
    echo -e "$N"
    printf "  %-14s %b\n" "Odoo:"        "${G}https://$DOMAIN${N}"
    printf "  %-14s %s\n" "Versión:"     "Odoo $ODOO_VERSION Community"
    printf "  %-14s %s\n" "Servicio:"    "systemctl status $ODOO_USER"
    printf "  %-14s %s\n" "Logs:"        "journalctl -u $ODOO_USER -f"
    printf "  %-14s %s\n" "Credenciales:" "$CREDENTIALS_FILE"
    printf "  %-14s %s\n" "Fecha:"       "$(date '+%Y-%m-%d %H:%M')"
    echo
    echo -e "  Instalado por ${C}SIE7E Consultech${N} · www.sieteconsultech.com"
    echo
}

# ============================================================
# === PREGUNTAS: funciones ===
# ============================================================

# Las respuestas se leen siempre de la terminal (/dev/tty), nunca de stdin:
# así funcionan también cuando el script llega por curl. ODOO_ENTRADA cambia
# el origen (solo para pruebas).
ENTRADA="${ODOO_ENTRADA:-/dev/tty}"
HAY_TERMINAL="no"

abrir_entrada() {
    # Se abre una sola vez como descriptor 3. Se prueba antes en un subshell
    # porque un exec fallido cerraría el script.
    if ( exec 3<"$ENTRADA" ) 2>/dev/null; then
        exec 3<"$ENTRADA"
        HAY_TERMINAL="si"
    fi
}

leer_linea() {
    # Uso: leer_linea variable [-s]
    # Devuelve 1 si no hay terminal o si se acabó la entrada (y ya no vuelve a leer).
    local -n _destino="$1"
    local opcion="${2:-}"
    [ "$HAY_TERMINAL" = "si" ] || return 1
    if ! IFS= read -r ${opcion:+"$opcion"} -u 3 _destino; then
        HAY_TERMINAL="no"
        return 1
    fi
}

limpia_dominio() {
    local d="${1,,}"
    d="${d// /}"
    d="${d#http://}"
    d="${d#https://}"
    d="${d%%/*}"
    d="${d#www.}"
    echo "$d"
}

nombre_corto() {
    # Primera parte del dominio, apta para nombres de proyecto y usuario.
    local d="${1%%.*}"
    echo "${d//-/_}"
}

# Los validadores devuelven 0 si el valor sirve; si no, 1 y el motivo por stderr.

valida_proyecto() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "Usa solo letras, números, guion y guion bajo (ej.: odoo_sdluxes)." >&2
        return 1
    fi
}

valida_usuario() {
    if [[ ! "$1" =~ ^[a-z_][a-z0-9_-]*$ ]] || [ "${#1}" -gt 32 ]; then
        echo "Usa minúsculas, números, guion y guion bajo (máximo 32), sin empezar por número." >&2
        return 1
    fi
}

valida_dominio() {
    local re='^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
    if [[ ! "$1" =~ $re ]] || [ "$1" = "dominio.com" ]; then
        echo "Escribe un dominio válido, por ejemplo: cliente.com" >&2
        return 1
    fi
}

valida_correo() {
    local re='^[^@ ]+@[^@ ]+\.[^@ ]+$'
    if [[ ! "$1" =~ $re ]] || [ "$1" = "admin@dominio.com" ]; then
        echo "Escribe un correo válido, por ejemplo: ventas@cliente.com" >&2
        return 1
    fi
}

puerto_ocupado() {
    ss -lnt 2>/dev/null | awk -v p="$1" 'NR > 1 { n = split($4, a, ":"); if (a[n] == p) f = 1 } END { exit !f }'
}

valida_puerto() {
    if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1024 ] || [ "$1" -gt 65535 ]; then
        echo "Debe ser un número entre 1024 y 65535." >&2
        return 1
    fi
    if puerto_ocupado "$1"; then
        echo "El puerto $1 ya está en uso en este servidor." >&2
        return 1
    fi
}

preguntar() {
    # Uso: preguntar VARIABLE "Texto" "valor_propuesto" validador [limpiador]
    # Si la variable ya tiene valor, solo se valida. Sin terminal se usa el
    # valor propuesto; si no hay propuesto o no es válido, error.
    local var="$1" texto="$2" defecto="$3" validador="$4" limpiador="${5:-}"
    local valor="${!1:-}" motivo
    if [ -n "$valor" ]; then
        if [ -n "$limpiador" ]; then valor="$("$limpiador" "$valor")"; fi
        motivo="$("$validador" "$valor" 2>&1)" || error "$var: $motivo"
        printf -v "$var" '%s' "$valor"
        return 0
    fi
    while true; do
        printf '%s%s: ' "$texto" "${defecto:+ [$defecto]}" >&2
        if leer_linea valor; then
            valor="${valor:-$defecto}"
        else
            echo >&2
            valor="$defecto"
            [ -n "$valor" ] || error "Falta $var y no hay terminal para preguntarlo. Pásalo así: $var=valor"
        fi
        if [ -n "$limpiador" ]; then valor="$("$limpiador" "$valor")"; fi
        if motivo="$("$validador" "$valor" 2>&1)"; then
            break
        fi
        [ "$HAY_TERMINAL" = "si" ] || error "$var: $motivo"
        echo "  $motivo" >&2
    done
    printf -v "$var" '%s' "$valor"
}

preguntar_si_no() {
    # Uso: preguntar_si_no VARIABLE "Texto" "s|n"  -> deja true o false
    local var="$1" texto="$2" defecto="$3" valor="${!1:-}" sufijo respuesta
    if [ -n "$valor" ]; then
        case "${valor,,}" in
            true|s|si|sí|y|yes) valor="true" ;;
            false|n|no) valor="false" ;;
            *) error "$var debe ser true o false." ;;
        esac
    else
        if [ "$defecto" = "s" ]; then sufijo="S/n"; else sufijo="s/N"; fi
        while true; do
            printf '%s (%s): ' "$texto" "$sufijo" >&2
            respuesta=""
            leer_linea respuesta || echo >&2
            respuesta="${respuesta:-$defecto}"
            case "${respuesta,,}" in
                s|si|sí|y|yes) valor="true"; break ;;
                n|no) valor="false"; break ;;
            esac
            echo "  Responde s o n." >&2
        done
    fi
    printf -v "$var" '%s' "$valor"
}

genera_clave() {
    ADMIN_PASSWORD="$(openssl rand -base64 36 | tr -d '/+=' | cut -c1-24)"
    PASSWORD_GENERADA="sí"
}

clave_debil() {
    [ "$1" = "admin123" ] || [ "$1" = "admin" ]
}

preguntar_clave() {
    # Deja ADMIN_PASSWORD y PASSWORD_GENERADA. Enter vacío o sin terminal = generar.
    local a b
    if [ -n "$ADMIN_PASSWORD" ]; then
        if clave_debil "$ADMIN_PASSWORD"; then
            error "ADMIN_PASSWORD es insegura. Déjala vacía para generar una automáticamente."
        fi
        PASSWORD_GENERADA="no"
        return 0
    fi
    while true; do
        a=""
        b=""
        printf 'Contraseña maestra (no se ve al escribir; Enter = generar una segura): ' >&2
        leer_linea a -s || true
        echo >&2
        if [ -z "$a" ]; then
            genera_clave
            return 0
        fi
        if clave_debil "$a"; then
            echo "  Esa contraseña es insegura. Prueba otra o deja vacío para generar una." >&2
            continue
        fi
        printf 'Repite la contraseña: ' >&2
        leer_linea b -s || true
        echo >&2
        if [ "$a" != "$b" ]; then
            echo "  No coinciden. Intenta de nuevo." >&2
            continue
        fi
        ADMIN_PASSWORD="$a"
        PASSWORD_GENERADA="no"
        return 0
    done
}

abrir_entrada

# Las pruebas cargan solo las funciones de arriba.
if [ "${ODOO_SOLO_FUNCIONES:-}" = "1" ]; then
    return 0
fi

# ============================================================
# === VALIDACIONES INICIALES ===
# ============================================================

if [ "$EUID" -ne 0 ]; then
    error "Este script debe ejecutarse como root. Ejemplo: sudo bash $(basename "$0")"
fi

if ! grep -q 'VERSION_ID="24.04"' /etc/os-release; then
    error "Este script está preparado para Ubuntu Server 24.04 LTS."
fi

[ "$ODOO_VERSION" = "19.0" ] || error "Este script está preparado para Odoo 19.0."

# ============================================================
# === PREGUNTAS ===
# ============================================================

titulo "     DATOS DE LA INSTALACIÓN"
echo "Enter acepta el valor propuesto entre [corchetes]."
echo

preguntar DOMAIN "Dominio (debe apuntar a este servidor)" "" valida_dominio limpia_dominio
preguntar_si_no USE_WWW "¿www.$DOMAIN también apunta a este servidor?" "s"
preguntar EMAIL "Correo para avisos de Let's Encrypt" "admin@$DOMAIN" valida_correo

NOMBRE_CORTO="$(nombre_corto "$DOMAIN")"
preguntar ODOO_PROJECT "Nombre del proyecto (carpeta /opt/<proyecto>)" "odoo_$NOMBRE_CORTO" valida_proyecto

# Si ya hay un Odoo en este servidor, se propone una instancia aparte.
USUARIO_PROPUESTO="odoo19"
if id -u odoo19 >/dev/null 2>&1; then
    USUARIO_PROPUESTO="odoo19_$NOMBRE_CORTO"
fi
preguntar ODOO_USER "Usuario del sistema y servicio" "$USUARIO_PROPUESTO" valida_usuario

PUERTO_PROPUESTO=8069
while puerto_ocupado "$PUERTO_PROPUESTO" || puerto_ocupado "$((PUERTO_PROPUESTO + 3))"; do
    PUERTO_PROPUESTO=$((PUERTO_PROPUESTO + 100))
done
preguntar HTTP_PORT "Puerto de Odoo" "$PUERTO_PROPUESTO" valida_puerto
preguntar GEVENT_PORT "Puerto WebSocket (chat y notificaciones)" "$((PUERTO_PROPUESTO + 3))" valida_puerto
[ "$HTTP_PORT" != "$GEVENT_PORT" ] || error "Los puertos de Odoo y WebSocket deben ser distintos."

preguntar_clave

# ============================================================
# === CONFIGURACIÓN INTERNA ===
# ============================================================

ODOO_HOME="/opt/$ODOO_PROJECT"
ODOO_DIR="$ODOO_HOME/odoo"
ODOO_VENV="$ODOO_HOME/odoo-venv"
CUSTOM_ADDONS="$ODOO_HOME/odoo-custom-addons"
ODOO_DB_USER="$ODOO_USER"

ODOO_CONF="/etc/$ODOO_USER.conf"
ODOO_SERVICE="/etc/systemd/system/$ODOO_USER.service"

NGINX_CONF="/etc/nginx/sites-available/$ODOO_USER"
NGINX_LINK="/etc/nginx/sites-enabled/$ODOO_USER"

WKHTMLTOX_VERSION="0.12.6.1-3"
WKHTMLTOX_FILE="wkhtmltox_${WKHTMLTOX_VERSION}.jammy_amd64.deb"
WKHTMLTOX_URL="https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOX_VERSION}/${WKHTMLTOX_FILE}"
WKHTMLTOX_DEB="/tmp/${WKHTMLTOX_FILE}"

CREDENTIALS_FILE="/root/${ODOO_PROJECT}_credenciales.txt"
ACME_ROOT="/var/lib/letsencrypt"

if [ "$USE_WWW" = "true" ]; then
    SERVER_NAMES="$DOMAIN www.$DOMAIN"
    CERTBOT_DOMAINS=(-d "$DOMAIN" -d "www.$DOMAIN")
else
    SERVER_NAMES="$DOMAIN"
    CERTBOT_DOMAINS=(-d "$DOMAIN")
fi


# ============================================================
# === RESUMEN Y CONFIRMACIÓN ===
# ============================================================

titulo "     INSTALACIÓN AUTOMÁTICA DE ODOO $ODOO_VERSION COMMUNITY"
echo
echo "Usuario / servicio : $ODOO_USER"
echo "Proyecto           : $ODOO_PROJECT"
echo "Directorio         : $ODOO_HOME"
echo "Puerto Odoo        : $HTTP_PORT"
echo "Puerto WebSocket   : $GEVENT_PORT"
echo "Dominio(s)         : $SERVER_NAMES"
echo "Correo             : $EMAIL"
if [ "$PASSWORD_GENERADA" = "sí" ]; then
    echo "Contraseña maestra : se generará y se guardará en $CREDENTIALS_FILE"
else
    echo "Contraseña maestra : la que escribiste"
fi
echo
echo "IMPORTANTE: el dominio debe apuntar previamente a este servidor"
echo "y los puertos 80 y 443 deben estar abiertos en el firewall del proveedor."
echo

if [ "${ODOO_SOLO_PREGUNTAS:-}" = "1" ]; then
    echo "Modo ODOO_SOLO_PREGUNTAS: no se instaló nada."
    exit 0
fi

if [ "${ODOO_SI:-}" != "1" ]; then
    RESPUESTA=""
    printf '¿Instalar con estos datos? (s/N): ' >&2
    leer_linea RESPUESTA || error "No hay terminal para confirmar. Para instalar sin preguntas usa ODOO_SI=1."
    case "${RESPUESTA,,}" in
        s|si|sí) ;;
        *)
            echo "Instalación cancelada. No se tocó nada."
            exit 0
            ;;
    esac
fi

# ============================================================
# 1. ACTUALIZAR SISTEMA
# ============================================================

titulo "1. ACTUALIZANDO SISTEMA"

apt-get update
apt-get upgrade -y

# ============================================================
# 2. FIREWALL (UFW)
# ============================================================

titulo "2. CONFIGURANDO FIREWALL"

apt-get install -y ufw

# SSH primero, para no perder el acceso al activar UFW.
ufw allow OpenSSH
ufw allow 80,443/tcp
ufw --force enable
ufw status

# ============================================================
# 3. POSTGRESQL
# ============================================================

titulo "3. INSTALANDO POSTGRESQL"

apt-get install -y postgresql
systemctl enable --now postgresql

echo
echo "Versión de PostgreSQL:"
psql --version
estado postgresql

# ============================================================
# 4. PYTHON Y DEPENDENCIAS
# ============================================================

titulo "4. INSTALANDO PYTHON Y DEPENDENCIAS"

apt-get install -y \
    git curl wget openssl \
    python3-dev python3-venv python3-pip \
    build-essential pkg-config \
    libxml2-dev libxslt1-dev \
    libldap2-dev libsasl2-dev \
    libssl-dev libffi-dev libpq-dev \
    libjpeg-dev libjpeg8-dev zlib1g-dev \
    libfreetype-dev liblcms2-dev libblas-dev \
    libcairo2-dev

echo
echo "Versión de Python:"
python3 --version

# ============================================================
# 5. USUARIO DEL SISTEMA ODOO
# ============================================================

titulo "5. CREANDO USUARIO DEL SISTEMA"

if id "$ODOO_USER" >/dev/null 2>&1; then
    echo "El usuario $ODOO_USER ya existe."
else
    useradd -m -d "$ODOO_HOME" -U -r -s /bin/bash "$ODOO_USER"
fi

mkdir -p "$ODOO_HOME"
chown "$ODOO_USER:$ODOO_USER" "$ODOO_HOME"

# ============================================================
# 6. USUARIO DE POSTGRESQL
# ============================================================

titulo "6. CONFIGURANDO USUARIO DE POSTGRESQL"

# Puede crear bases (-d), pero no es superusuario (-S) ni crea roles (-R).
if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$ODOO_DB_USER'" | grep -q 1; then
    echo "El usuario PostgreSQL $ODOO_DB_USER ya existe."
else
    sudo -u postgres createuser -d -R -S "$ODOO_DB_USER"
fi

# ============================================================
# 7. WKHTMLTOPDF
# ============================================================

titulo "7. INSTALANDO WKHTMLTOPDF"

if dpkg -l wkhtmltox 2>/dev/null | grep -q '^ii'; then
    echo "wkhtmltox ya está instalado."
else
    wget -q -O "$WKHTMLTOX_DEB" "$WKHTMLTOX_URL"
    apt-get install -y "$WKHTMLTOX_DEB"
    rm -f "$WKHTMLTOX_DEB"
fi

echo
echo "Versión instalada:"
wkhtmltopdf --version

# ============================================================
# 8. DESCARGAR ODOO 19
# ============================================================

titulo "8. DESCARGANDO ODOO $ODOO_VERSION"

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
# 8.1. COMPATIBILIDAD ACCOUNT EDI / FACTUR-X
# ============================================================
# Si la corrección falla, solo avisa: no detiene la instalación.
# Ojo: este cambio en el código de Odoo se pierde con cada "git pull".

titulo "8.1. VERIFICANDO COMPATIBILIDAD ACCOUNT EDI / FACTUR-X"

CII_FILE="$ODOO_DIR/addons/account_edi_ubl_cii/models/account_edi_cii.py"

if [ ! -f "$CII_FILE" ]; then
    echo "[ADVERTENCIA] No existe account_edi_ubl_cii."
elif grep -q "'deferred_start_date' in move_line._fields" "$CII_FILE" &&
     grep -q "'deferred_end_date' in move_line._fields" "$CII_FILE"; then
    echo "[OK] Odoo ya contiene la corrección de deferred dates."
elif grep -q "if move_line.deferred_start_date" "$CII_FILE" &&
     grep -q "if move_line.deferred_end_date" "$CII_FILE"; then
    echo "[INFO] Se detectó el código sin corrección. Aplicando..."
    cp "$CII_FILE" "$CII_FILE.bak"

    if ! python3 - "$CII_FILE" <<'PY'
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
    print("[ADVERTENCIA] No se encontró exactamente el código esperado.")
    sys.exit(1)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content.replace(old, new, 1))

print("[OK] Corrección aplicada correctamente.")
PY
    then
        echo "[ADVERTENCIA] No se aplicó la corrección; el código de Odoo quedó sin cambios."
    fi
    chown "$ODOO_USER:$ODOO_USER" "$CII_FILE"*
else
    echo "[ADVERTENCIA] No se pudo determinar el estado de la corrección. No se modificó nada."
fi

# ============================================================
# 9. ENTORNO VIRTUAL DE PYTHON
# ============================================================

titulo "9. CREANDO ENTORNO VIRTUAL DE PYTHON"

if [ ! -d "$ODOO_VENV" ]; then
    sudo -u "$ODOO_USER" python3 -m venv "$ODOO_VENV"
fi

sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install --upgrade pip
sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install setuptools wheel
sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install -r "$ODOO_DIR/requirements.txt"

# Necesario para imprimir códigos de barras en los PDF.
sudo -u "$ODOO_USER" "$ODOO_VENV/bin/pip" install rlPyCairo

# ============================================================
# 10. CUSTOM ADDONS
# ============================================================

titulo "10. CREANDO DIRECTORIO DE CUSTOM ADDONS"

mkdir -p "$CUSTOM_ADDONS"
chown -R "$ODOO_USER:$ODOO_USER" "$CUSTOM_ADDONS"

# ============================================================
# 11. CONFIGURACIÓN DE ODOO
# ============================================================

titulo "11. CREANDO CONFIGURACIÓN DE ODOO"

cat > "$ODOO_CONF" <<EOF
[options]

; Contraseña maestra (gestión de bases de datos)
admin_passwd = $ADMIN_PASSWORD

db_host = False
db_port = False
db_user = $ODOO_DB_USER
db_password = False

; Rutas de los módulos oficiales y personalizados
addons_path = $ODOO_DIR/addons,$CUSTOM_ADDONS

; Puerto principal de Odoo
http_port = $HTTP_PORT

; Puerto utilizado por WebSocket (gevent)
gevent_port = $GEVENT_PORT

; Odoo detrás de NGINX
proxy_mode = True

; Solo escucha en local: el acceso público entra por NGINX (80/443)
http_interface = 127.0.0.1

; Rendimiento (ajustar según CPU y RAM)
workers = $WORKERS
limit_memory_soft = $LIMIT_MEMORY_SOFT
limit_memory_hard = $LIMIT_MEMORY_HARD
limit_time_cpu = $LIMIT_TIME_CPU
limit_time_real = $LIMIT_TIME_REAL
max_cron_threads = $MAX_CRON_THREADS

; Si usa más de una base de datos, descomente y especifique el filtro.
; dbfilter = ^nombre_base$

; Producción: oculta el administrador de bases (/web/database/manager).
; Descomentar DESPUÉS de crear la base de datos.
; list_db = False
EOF

# root puede modificarlo y el usuario Odoo solo leerlo.
chown root:"$ODOO_USER" "$ODOO_CONF"
chmod 640 "$ODOO_CONF"

# ============================================================
# 12. SERVICIO SYSTEMD
# ============================================================

titulo "12. CREANDO SERVICIO SYSTEMD"

cat > "$ODOO_SERVICE" <<EOF
[Unit]
Description=Odoo $ODOO_VERSION ($ODOO_PROJECT)
Requires=postgresql.service
After=network.target postgresql.service

[Service]
Type=simple
SyslogIdentifier=$ODOO_USER
User=$ODOO_USER
Group=$ODOO_USER
ExecStart=$ODOO_VENV/bin/python3 $ODOO_DIR/odoo-bin -c $ODOO_CONF
Restart=on-failure
RestartSec=5
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$ODOO_USER"
systemctl restart "$ODOO_USER"

sleep 5
estado "$ODOO_USER"

# ============================================================
# 13. NGINX Y CERTBOT
# ============================================================

titulo "13. INSTALANDO NGINX Y CERTBOT"

apt-get install -y nginx certbot python3-certbot-nginx
systemctl enable --now nginx

# Quita la página de bienvenida de NGINX.
rm -f /etc/nginx/sites-enabled/default

mkdir -p "$ACME_ROOT/.well-known/acme-challenge"
chgrp www-data "$ACME_ROOT"
chmod g+s "$ACME_ROOT"

# ============================================================
# 14. NGINX INICIAL (SOLO HTTP, PARA CERTBOT)
# ============================================================

titulo "14. CONFIGURANDO NGINX PARA CERTBOT"

cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $SERVER_NAMES;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type "text/plain";
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}
EOF

ln -sf "$NGINX_CONF" "$NGINX_LINK"
nginx -t
systemctl reload nginx

# ============================================================
# 15. PRUEBA ACME
# ============================================================

titulo "15. PROBANDO ACME CHALLENGE"

echo "certbot-test" > "$ACME_ROOT/.well-known/acme-challenge/test"

for HOST in $SERVER_NAMES; do
    echo "Probando: http://$HOST/.well-known/acme-challenge/test"
    if ! curl -fsS "http://$HOST/.well-known/acme-challenge/test"; then
        rm -f "$ACME_ROOT/.well-known/acme-challenge/test"
        error "$HOST no responde. Revisa el DNS y que el puerto 80 esté abierto en el proveedor."
    fi
done

rm -f "$ACME_ROOT/.well-known/acme-challenge/test"

# ============================================================
# 16. CERTIFICADO SSL
# ============================================================

titulo "16. GENERANDO CERTIFICADO SSL"

# --deploy-hook: recarga NGINX en cada renovación. Sin él, el sitio
# seguiría mostrando el certificado vencido a los 90 días.
certbot certonly \
    --non-interactive \
    --agree-tos \
    --no-eff-email \
    --email "$EMAIL" \
    --webroot \
    -w "$ACME_ROOT" \
    "${CERTBOT_DOMAINS[@]}" \
    --deploy-hook "systemctl reload nginx"

echo
echo "Certificados disponibles:"
certbot certificates

# ============================================================
# 17. NGINX FINAL (HTTPS + WEBSOCKET)
# ============================================================

titulo "17. CONFIGURANDO NGINX + HTTPS + WEBSOCKET"

# Nombres de upstream y logs por instancia, para poder tener varias
# instalaciones de Odoo en el mismo servidor.
UP_SERVER="${ODOO_USER}_server"
UP_CHAT="${ODOO_USER}_chat"

if [ "$USE_WWW" = "true" ]; then
    WWW_BLOCK="
# HTTPS www -> dominio principal
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name www.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    return 301 https://$DOMAIN\$request_uri;
}"
else
    WWW_BLOCK=""
fi

# El map de WebSocket va en un archivo aparte y común a todas las
# instancias: repetido en cada sitio, NGINX daría error de duplicado.
if ! grep -rqs 'connection_upgrade' /etc/nginx/conf.d/ /etc/nginx/nginx.conf; then
    cat > /etc/nginx/conf.d/websocket_upgrade.conf <<'EOF'
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
fi

cat > "$NGINX_CONF" <<EOF
upstream $UP_SERVER {
    server 127.0.0.1:$HTTP_PORT;
}

upstream $UP_CHAT {
    server 127.0.0.1:$GEVENT_PORT;
}

# HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;

    server_name $SERVER_NAMES;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type "text/plain";
    }

    location / {
        return 301 https://$DOMAIN\$request_uri;
    }
}
$WWW_BLOCK

# HTTPS principal
server {
    listen 443 ssl;
    listen [::]:443 ssl;

    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    access_log /var/log/nginx/$ODOO_USER.access.log;
    error_log /var/log/nginx/$ODOO_USER.error.log;

    client_max_body_size 200m;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    # IMPORTANTE: si un location define algún proxy_set_header, NO hereda
    # los del bloque server. Por eso los encabezados se repiten en cada uno.

    # Let's Encrypt
    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type "text/plain";
        try_files \$uri =404;
    }

    # WebSocket (chat y notificaciones en vivo)
    location /websocket {
        proxy_pass http://$UP_CHAT;
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;

        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    # Odoo
    location / {
        proxy_pass http://$UP_SERVER;
        proxy_redirect off;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Archivos estáticos
    location ~* /web/static/ {
        proxy_pass http://$UP_SERVER;
        proxy_buffering on;
        expires 864000;

        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    # Gzip
    gzip on;
    gzip_types text/css text/plain text/xml application/xml application/json application/javascript;
}
EOF

nginx -t
systemctl reload nginx

# ============================================================
# 18. RENOVACIÓN AUTOMÁTICA DEL SSL
# ============================================================

titulo "18. VERIFICANDO RENOVACIÓN AUTOMÁTICA"

systemctl enable --now certbot.timer
estado certbot.timer

echo
echo "Prueba de renovación:"
certbot renew --dry-run

# ============================================================
# 19. GUARDAR CREDENCIALES
# ============================================================

titulo "19. GUARDANDO DATOS DE LA INSTALACIÓN"

umask 077
cat > "$CREDENTIALS_FILE" <<EOF
Odoo $ODOO_VERSION Community - $ODOO_PROJECT
Instalado: $(date '+%Y-%m-%d %H:%M')
URL: https://$DOMAIN
Contraseña maestra (admin_passwd): $ADMIN_PASSWORD
Archivo de configuración: $ODOO_CONF
EOF
chmod 600 "$CREDENTIALS_FILE"
echo "Datos guardados en $CREDENTIALS_FILE (solo root puede leerlo)."

# ============================================================
# 20. VERIFICACIÓN FINAL
# ============================================================

titulo "VERIFICACIÓN FINAL"

ERRORS=0

check() {
    # check "<descripción>" <comando...>
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        echo -e "\e[1;32m[OK]\e[0m $desc"
    else
        echo -e "\e[1;31m[ERROR]\e[0m $desc"
        ERRORS=$((ERRORS + 1))
    fi
}

sleep 3

check "Odoo está activo"                      systemctl is-active --quiet "$ODOO_USER"
check "PostgreSQL está activo"                systemctl is-active --quiet postgresql
check "NGINX está activo"                     systemctl is-active --quiet nginx
check "Renovación SSL (certbot.timer) activa" systemctl is-active --quiet certbot.timer
check "Configuración de NGINX correcta"       nginx -t
check "Odoo escucha en 127.0.0.1:$HTTP_PORT"  bash -c "ss -lnt | grep -q '127.0.0.1:$HTTP_PORT '"
check "WebSocket escucha en 127.0.0.1:$GEVENT_PORT" bash -c "ss -lnt | grep -q '127.0.0.1:$GEVENT_PORT '"
check "HTTP escucha en el puerto 80"          bash -c "ss -lnt | grep -qE ':80 '"
check "HTTPS escucha en el puerto 443"        bash -c "ss -lnt | grep -qE ':443 '"
check "Certificado SSL encontrado"            test -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
check "Odoo responde por HTTPS"               curl -fsS -o /dev/null --max-time 30 "https://$DOMAIN/web/login"

echo

if [ "$ERRORS" -ne 0 ]; then
    titulo "INSTALACIÓN FINALIZADA CON $ERRORS ERROR(ES)"
    echo
    echo "Revisa los mensajes marcados con [ERROR]:"
    echo "  journalctl -u $ODOO_USER -n 100"
    echo "  tail -n 50 /var/log/nginx/$ODOO_USER.error.log"
    echo
    exit 1
fi

titulo "INSTALACIÓN COMPLETADA CORRECTAMENTE"
echo
if [ "$PASSWORD_GENERADA" = "sí" ]; then
    echo -e "\e[1;33mContraseña maestra generada:\e[0m $ADMIN_PASSWORD"
    echo "(también guardada en $CREDENTIALS_FILE)"
    echo
fi
echo "SIGUIENTES PASOS:"
echo "  1. Entrar a https://$DOMAIN y crear la base de datos con la contraseña maestra."
echo "  2. En $ODOO_CONF descomentar 'list_db = False' y reiniciar: systemctl restart $ODOO_USER"
echo "  3. En Odoo (modo desarrollador) > Ajustes > Técnico > Parámetros del sistema:"
echo "     verificar web.base.url = https://$DOMAIN y crear web.base.url.freeze = True"

# ============================================================
# === FIN ===
# ============================================================

firma_sie7e
