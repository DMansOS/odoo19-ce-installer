#!/bin/bash
# Pruebas de las preguntas del instalador (no instalan nada).
# Uso: bash pruebas/preguntas.sh   (en Ubuntu 24.04, como root)

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/odoo19CE_install_v2.sh"
FALLOS=0
SALIDA=""
CODIGO=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [ -n "${LISTENER:-}" ] && kill "$LISTENER" 2>/dev/null' EXIT

# correr "<entrada: texto con \n>" "<comandos>"  -> carga solo las funciones
# del script con la entrada indicada; deja SALIDA (stdout+stderr) y CODIGO.
correr() {
    printf '%b' "$1" > "$TMP/entrada"
    SALIDA="$(ODOO_ENTRADA="$TMP/entrada" ODOO_SOLO_FUNCIONES=1 bash -c "source '$SCRIPT'; $2" 2>&1)"
    CODIGO=$?
}

# instalar "<entrada>" [VAR=valor ...] -> corre el script completo en modo
# ODOO_SOLO_PREGUNTAS (o con las variables que se le pasen).
instalar() {
    local entrada="$1"; shift
    printf '%b' "$entrada" > "$TMP/entrada"
    # apt-get falso al frente del PATH: si un error dejara pasar la
    # instalación, se detiene en el primer paso sin tocar el servidor.
    mkdir -p "$TMP/bin"
    printf '#!/bin/sh\necho "apt-get FALSO: la instalación no debía empezar"\nexit 1\n' > "$TMP/bin/apt-get"
    chmod +x "$TMP/bin/apt-get"
    SALIDA="$(env PATH="$TMP/bin:$PATH" ODOO_ENTRADA="$TMP/entrada" "$@" bash "$SCRIPT" 2>&1)"
    CODIGO=$?
}

ok() { echo "OK    $1"; }
falla() { echo "FALLA $1"; FALLOS=$((FALLOS + 1)); }
esperar_codigo() { # nombre codigo_esperado
    if [ "$CODIGO" -eq "$2" ]; then ok "$1"; else falla "$1 (código $CODIGO, se esperaba $2)"; fi
}
esperar_texto() { # nombre texto
    if [[ "$SALIDA" == *"$2"* ]]; then ok "$1"; else falla "$1 (falta «$2»)"; fi
}
esperar_sin_texto() { # nombre texto
    if [[ "$SALIDA" != *"$2"* ]]; then ok "$1"; else falla "$1 (sobra «$2»)"; fi
}

# --- Tarea 1: validadores y funciones -----------------------------------

correr "" 'limpia_dominio "https://www.Cliente.com/"'
[ "$SALIDA" = "cliente.com" ] && ok "limpia_dominio" || falla "limpia_dominio ($SALIDA)"

correr "" 'valida_dominio "cliente"'; esperar_codigo "dominio sin punto es inválido" 1
correr "" 'valida_dominio "cliente.com.pa"'; esperar_codigo "dominio con subdominio es válido" 0
correr "" 'valida_dominio "dominio.com"'; esperar_codigo "dominio.com (ejemplo) es inválido" 1
correr "" 'valida_correo "admin@dominio.com"'; esperar_codigo "correo de ejemplo es inválido" 1
correr "" 'valida_correo "ventas@cliente.com"'; esperar_codigo "correo válido" 0
correr "" 'valida_proyecto "odoo cliente"'; esperar_codigo "proyecto con espacio es inválido" 1
correr "" 'valida_proyecto "odoo_cliente1"'; esperar_codigo "proyecto válido" 0
correr "" 'valida_usuario "Odoo"'; esperar_codigo "usuario con mayúscula es inválido" 1
correr "" 'valida_usuario "odoo19_cliente"'; esperar_codigo "usuario válido" 0
correr "" 'valida_puerto 80'; esperar_codigo "puerto 80 es inválido (<1024)" 1
correr "" 'valida_puerto abc'; esperar_codigo "puerto no numérico es inválido" 1
correr "" 'valida_puerto 18999'; esperar_codigo "puerto libre es válido" 0

python3 -m http.server 18998 --bind 127.0.0.1 >/dev/null 2>&1 &
LISTENER=$!
sleep 1
correr "" 'valida_puerto 18998'; esperar_codigo "puerto ocupado es inválido" 1

correr '\ncliente.com\n' 'preguntar DOMAIN "Dominio" "" valida_dominio; echo "DOMAIN=$DOMAIN"'
esperar_texto "preguntar repite tras una línea vacía" "DOMAIN=cliente.com"

correr '' 'DOMAIN=ya.com; preguntar DOMAIN "Dominio" "" valida_dominio; echo "DOMAIN=$DOMAIN"'
esperar_texto "preguntar no lee si la variable ya viene" "DOMAIN=ya.com"

correr '' 'DOMAIN=https://www.Ya.com/; preguntar DOMAIN "Dominio" "" valida_dominio limpia_dominio; echo "DOMAIN=$DOMAIN"'
esperar_texto "preguntar limpia el dominio del entorno" "DOMAIN=ya.com"

correr '' 'DOMAIN=malo; preguntar DOMAIN "Dominio" "" valida_dominio'
esperar_codigo "variable inválida detiene el script" 1

correr '' 'DOMAIN=""; preguntar DOMAIN "Dominio" "" valida_dominio'
esperar_codigo "sin terminal y sin dato: error" 1
esperar_texto "sin terminal y sin dato: mensaje" "ERROR"

correr '\n' 'EMAIL=""; preguntar EMAIL "Correo" "ventas@cliente.com" valida_correo; echo "EMAIL=$EMAIL"'
esperar_texto "Enter acepta el valor propuesto" "EMAIL=ventas@cliente.com"

correr 'n\n' 'USE_WWW=""; preguntar_si_no USE_WWW "¿www?" "s"; echo "USE_WWW=$USE_WWW"'
esperar_texto "preguntar_si_no responde n" "USE_WWW=false"
correr '\n' 'USE_WWW=""; preguntar_si_no USE_WWW "¿www?" "s"; echo "USE_WWW=$USE_WWW"'
esperar_texto "preguntar_si_no con Enter usa el propuesto" "USE_WWW=true"
correr '' 'USE_WWW=no; preguntar_si_no USE_WWW "¿www?" "s"; echo "USE_WWW=$USE_WWW"'
esperar_texto "preguntar_si_no acepta no del entorno" "USE_WWW=false"

correr '\n' 'ADMIN_PASSWORD=""; preguntar_clave; echo "G=$PASSWORD_GENERADA L=${#ADMIN_PASSWORD}"'
esperar_texto "contraseña vacía se genera (24 caracteres)" "G=sí L=24"

correr 'abc12345\notra1234\nabc12345\nabc12345\n' 'ADMIN_PASSWORD=""; preguntar_clave; echo "P=$ADMIN_PASSWORD G=$PASSWORD_GENERADA"'
esperar_texto "contraseña: la primera pareja no coincide, la segunda sí" "P=abc12345 G=no"

correr 'admin123\n\n' 'ADMIN_PASSWORD=""; preguntar_clave; echo "G=$PASSWORD_GENERADA"'
esperar_texto "contraseña débil se rechaza y se vuelve a preguntar" "G=sí"

correr '' 'ADMIN_PASSWORD=admin123; preguntar_clave'
esperar_codigo "contraseña débil por entorno detiene el script" 1

# --- Tarea 2: flujo completo en modo «solo preguntas» --------------------

instalar 'cliente-pa.com\n\n\n\n\n\n\n\n' ODOO_SOLO_PREGUNTAS=1
esperar_codigo "flujo completo termina bien" 0
esperar_texto "proyecto propuesto desde el dominio" "Proyecto           : odoo_cliente_pa"
esperar_texto "correo propuesto desde el dominio" "Correo             : admin@cliente-pa.com"
esperar_texto "www propuesto" "Dominio(s)         : cliente-pa.com www.cliente-pa.com"
esperar_texto "contraseña generada en el resumen" "se generará"
esperar_sin_texto "el resumen no muestra la contraseña" "Contraseña maestra : $"

instalar 'cliente.com\nn\n\n\n\n\n\n\n' ODOO_SOLO_PREGUNTAS=1
esperar_texto "sin www" "Dominio(s)         : cliente.com"
esperar_sin_texto "sin www: el resumen no lista www" "Dominio(s)         : cliente.com www"

instalar '' ODOO_SOLO_PREGUNTAS=1 DOMAIN=cliente.com EMAIL=a@cliente.com \
    ODOO_PROJECT=odoo_x ODOO_USER=odoo_x USE_WWW=false HTTP_PORT=19069 GEVENT_PORT=19072
esperar_codigo "todo por entorno: no lee nada" 0
esperar_texto "todo por entorno: resumen" "Puerto Odoo        : 19069"

instalar '' ODOO_SOLO_PREGUNTAS=1 DOMAIN=cliente.com HTTP_PORT=19069 GEVENT_PORT=19069
esperar_codigo "puertos iguales se rechazan" 1

instalar 'cliente.com\n\n\n\n\n\n\n\nn\n'
esperar_codigo "responder n cancela con código 0" 0
esperar_texto "cancelación avisa" "Instalación cancelada"
esperar_sin_texto "cancelar no corre apt" "1. ACTUALIZANDO SISTEMA"

instalar '' DOMAIN=cliente.com
esperar_codigo "sin terminal y sin ODOO_SI no instala" 1
esperar_sin_texto "sin ODOO_SI no corre apt" "1. ACTUALIZANDO SISTEMA"

echo
if [ "$FALLOS" -eq 0 ]; then echo "Todas las pruebas pasaron."; else echo "$FALLOS prueba(s) fallaron."; exit 1; fi
