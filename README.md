# odoo19-ce-installer

Instalador automático de Odoo 19 Community para Ubuntu Server 24.04 LTS con PostgreSQL, NGINX y HTTPS (Let's Encrypt). SIE7E Consultech.

- `odoo19CE_install_v2.sh`: versión vigente.
- `odoo19CE_install.sh`: versión anterior, solo de referencia.
- `pruebas/preguntas.sh`: pruebas de las preguntas (no instalan nada).

## Uso

En el servidor del cliente (Ubuntu 24.04, como root, con el dominio ya apuntando al servidor):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/DMansOS/odoo19-ce-installer/main/odoo19CE_install_v2.sh)
```

El script pregunta el dominio, si usa `www`, el correo, el nombre del proyecto, el usuario del sistema, los puertos y la contraseña maestra. Cada pregunta propone un valor entre corchetes: Enter lo acepta. Al final muestra un resumen y pide confirmación antes de instalar; mientras no respondas `s`, no se toca nada.

**No uses `curl … | bash`.** Con la tubería, el propio script ocupa la entrada y las preguntas no pueden esperar lo que escribes. Con `bash <(curl …)` sí funciona.

Si ya hay otro Odoo en el servidor, propone un usuario distinto (`odoo19_<cliente>`) y los siguientes puertos libres (8169 y 8172, y así de 100 en 100).

Si dejas la contraseña maestra vacía, se genera una y se guarda en `/root/<proyecto>_credenciales.txt` (permisos 600).

## Instalar sin preguntas

Cualquier dato puede ir como variable de entorno; en ese caso no se pregunta (se valida igual). Lo que falte y tenga valor propuesto se toma tal cual; el dominio no tiene propuesto y es obligatorio.

| Variable | Qué es | Propuesto |
|---|---|---|
| `DOMAIN` | Dominio del cliente | (obligatorio) |
| `USE_WWW` | `true`/`false`: si `www.<dominio>` también apunta | `true` |
| `EMAIL` | Correo para avisos de Let's Encrypt | `admin@<dominio>` |
| `ODOO_PROJECT` | Carpeta `/opt/<proyecto>` | `odoo_<cliente>` |
| `ODOO_USER` | Usuario del sistema y nombre del servicio | `odoo19` |
| `HTTP_PORT` / `GEVENT_PORT` | Puertos de Odoo y WebSocket | `8069` / `8072` |
| `ADMIN_PASSWORD` | Contraseña maestra | se genera |
| `ODOO_SI` | `1` = no pedir la confirmación final | — |
| `ODOO_SOLO_PREGUNTAS` | `1` = mostrar el resumen y salir sin instalar | — |

Ejemplo:

```bash
DOMAIN=cliente.com EMAIL=ventas@cliente.com ODOO_SI=1 \
  bash <(curl -fsSL https://raw.githubusercontent.com/DMansOS/odoo19-ce-installer/main/odoo19CE_install_v2.sh)
```

Sin terminal y sin `ODOO_SI=1` el script se detiene antes de instalar.

## Pruebas

```bash
bash pruebas/preguntas.sh
```

Necesita Ubuntu 24.04, `python3` y `ss`. No instala nada: usa un `apt-get` falso para que un error no pueda empezar la instalación.
