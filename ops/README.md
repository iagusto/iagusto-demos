# Limpieza automática de disco — host Elestio

Responde a la alerta de Elestio:

> `space usage 81.5% matches resource limit [space usage > 80.0%]`
> Host: `cesar-ia-gusto-u55406`

`cleanup-disk.sh` recupera espacio borrando recursos prescindibles
(imágenes Docker sin usar, build cache, logs antiguos, caché de apt).
**No toca volúmenes ni bases de datos**, así que los datos de n8n,
Supabase, Postgres, etc. están a salvo.

## Instalación en el host (por SSH, como root)

```bash
# 1. Copiar el script al host (desde tu máquina, o git clone/pull en el host)
sudo mkdir -p /opt/ops
sudo cp cleanup-disk.sh /opt/ops/cleanup-disk.sh
sudo chmod +x /opt/ops/cleanup-disk.sh

# 2. Probar a mano una vez (ver que recupera espacio sin romper nada)
sudo /opt/ops/cleanup-disk.sh
cat /var/log/cleanup-disk.log
```

## Programar cada 15 días (cron)

Cron no tiene un "cada 15 días" exacto, así que se usa el patrón estándar:
ejecutar los **días 1 y 16 de cada mes** a las **03:00** (≈ cada 15 días).

```bash
# Crea la entrada de cron del sistema
echo '0 3 1,16 * * root /opt/ops/cleanup-disk.sh' | sudo tee /etc/cron.d/cleanup-disk
sudo chmod 644 /etc/cron.d/cleanup-disk
sudo systemctl restart cron 2>/dev/null || sudo service cron restart
```

### Alternativa: intervalo real de 15 días (systemd timer)

Si prefieres exactamente 15 días entre ejecuciones (en vez de días fijos):

```bash
# /etc/systemd/system/cleanup-disk.service
sudo tee /etc/systemd/system/cleanup-disk.service >/dev/null <<'EOF'
[Unit]
Description=Limpieza segura de disco

[Service]
Type=oneshot
ExecStart=/opt/ops/cleanup-disk.sh
EOF

# /etc/systemd/system/cleanup-disk.timer
sudo tee /etc/systemd/system/cleanup-disk.timer >/dev/null <<'EOF'
[Unit]
Description=Ejecuta la limpieza cada 15 dias

[Timer]
OnBootSec=1d
OnUnitActiveSec=15d
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now cleanup-disk.timer
sudo systemctl list-timers cleanup-disk.timer
```

## Evitar que los logs vuelvan a llenar el disco

Causa habitual nº1. Limita el tamaño de los logs de Docker en
`/etc/docker/daemon.json`:

```json
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

```bash
sudo systemctl restart docker
```

## Variables de entorno (opcionales)

| Variable                | Por defecto              | Qué hace                                        |
|-------------------------|--------------------------|-------------------------------------------------|
| `RETENTION_DAYS`        | `7`                      | Días de logs de journald a conservar            |
| `MAX_CONTAINER_LOG_MB`  | `10`                     | Trunca logs de contenedor mayores a este tamaño |
| `LOG_FILE`              | `/var/log/cleanup-disk.log` | Dónde escribir el registro de la limpieza    |
