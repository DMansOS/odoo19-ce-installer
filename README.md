# odoo19-ce-installer

Instalador automático de Odoo 19 Community para Ubuntu Server 24.04 LTS con PostgreSQL, NGINX y HTTPS (Let's Encrypt). SIE7E Consultech.

- `odoo19CE_install_v2.sh`: versión vigente (2026-11-20).
- `odoo19CE_install.sh`: versión anterior, solo de referencia.

## Uso
1. Editar la sección «CONFIGURACIÓN PERSONALIZABLE» (`ODOO_PROJECT`, `DOMAIN`, `EMAIL`).
2. Si el archivo viene de Windows: `sed -i 's/\r$//' odoo19CE_install_v2.sh`
3. `sudo bash odoo19CE_install_v2.sh`

Si `ADMIN_PASSWORD` queda vacía, el script genera una y la guarda en `/root/<proyecto>_credenciales.txt`.
