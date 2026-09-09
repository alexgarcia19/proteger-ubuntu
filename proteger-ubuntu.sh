#!/usr/bin/env bash
# Configuración independiente para un VPS Ubuntu nuevo. No instala Docker.
# Ejecutar desde un archivo: sudo bash proteger-ubuntu.sh
set -Eeuo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export LC_ALL=C
umask 077

die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
say() { printf '\n%s\n' "$*"; }
ask() { read -r -p "$1" "$2" </dev/tty || die 'Entrada cancelada.'; }
valid_port() { [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && (( 10#$1 <= 65535 )); }
valid_user() { [[ "$1" =~ ^[a-z][a-z0-9_-]{0,30}$ && "$1" != root ]]; }

main() {
[[ ${1:-} != --help ]] || {
  printf 'Uso: sudo bash proteger-ubuntu.sh\nUbuntu Server nuevo, systemd, terminal interactiva. Sin Docker.\n'
  return 0
}
[[ $# == 0 ]] || die 'Argumento desconocido. Usa --help.'
[[ $EUID == 0 ]] || die 'Ejecuta como root: sudo bash proteger-ubuntu.sh'
[[ -f /etc/os-release ]] || die 'No se detectó el sistema operativo.'
# shellcheck disable=SC1091
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || die 'Este script solo admite Ubuntu.'
[[ ${VERSION_ID:-} =~ ^[0-9]+\.[0-9]+$ ]] || die 'Versión Ubuntu desconocida.'
(( ${VERSION_ID%%.*} >= 22 )) || die 'Requiere Ubuntu 22.04 o posterior con soporte estándar vigente.'
[[ -d /run/systemd/system ]] || die 'Requiere systemd como sistema de inicio.'
[[ -r /dev/tty && -w /dev/tty ]] || die 'Necesita una terminal interactiva.'
for cmd in apt-get systemctl systemd-run flock sshd ssh-keygen ss tar; do
  command -v "$cmd" >/dev/null || die "Falta el requisito: $cmd"
done
exec 9>/run/lock/proteger-ubuntu.lock
flock -n 9 || die 'Ya hay otra ejecución en curso.'
sshd -t || die 'La configuración SSH inicial ya contiene errores.'
# Configuraciones personalizadas requieren revisión, no una reescritura a ciegas.
if [[ -f /etc/default/ssh ]] && grep -Eq '^SSHD_OPTS=.*[^"[:space:]=]' /etc/default/ssh; then
  # Permitimos exclusivamente el valor vacío habitual.
  grep -Eq "^SSHD_OPTS=(\"\"|'')?[[:space:]]*$" /etc/default/ssh || die 'SSHD_OPTS personalizado: revisa el servicio SSH antes de usar este script.'
fi

STATE=/var/lib/proteger-ubuntu
install -d -m 700 "$STATE"
RUN=$(mktemp -d "$STATE/ejecucion-$(date +%Y%m%d-%H%M%S)-XXXXXX")
LOG="$RUN/instalacion.log"
touch "$LOG"
exec > >(tee -a "$LOG") 2>&1
ACTIVE=''
trap 'finish $?' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP
say "Ubuntu $VERSION_ID. Registro y respaldos: $RUN"
say 'Mantén abierta esta sesión. Tendrás que probar otra conexión SSH durante la ejecución.'
say 'Usa una instalación nueva y conserva acceso a la consola del proveedor.'
if command -v cloud-init >/dev/null; then
  timeout 300 cloud-init status --wait || die 'cloud-init no terminó correctamente; espera o revisa su estado.'
fi

# Solo metadatos y requisitos antes de comprobar soporte. APT verifica firmas.
apt-get -o DPkg::Lock::Timeout=300 -o APT::Update::Error-Mode=any update
apt_run install distro-info-data python3
python3 - "$VERSION_ID" <<'PY'
import csv, datetime, sys
version = sys.argv[1]
today = datetime.date.today()
with open('/usr/share/distro-info/ubuntu.csv') as f:
    rows = [r for r in csv.DictReader(f) if r['version'].split()[0] == version]
if len(rows) != 1:
    sys.exit('Versión no reconocida por distro-info-data. No se aplicará protección.')
r = rows[0]
try:
    released = datetime.date.fromisoformat(r['release'])
    end = datetime.date.fromisoformat(r['eol'])
except (KeyError, ValueError):
    sys.exit('No se puede verificar el período de soporte de esta versión.')
if not released <= today < end:
    sys.exit('Versión preliminar o fuera del soporte estándar. Instala una Ubuntu con soporte.')
print(f"Soporte estándar verificado hasta {end}. Fecha del servidor: {today}.")
PY

# Una política Match podría permitir root desde otras direcciones aunque
# sshd -T -C confirme la política para la conexión actual. No se acepta aquí.
python3 - <<'PY'
import glob, pathlib, shlex, sys
seen = set()
def inspect(path):
    path = pathlib.Path(path).resolve()
    if path in seen:
        return
    seen.add(path)
    for number, line in enumerate(path.read_text().splitlines(), 1):
        words = shlex.split(line, comments=True)
        if not words:
            continue
        if words[0].lower() == 'match':
            sys.exit(f'Configuración SSH personalizada: {path}:{number} contiene Match. Requiere revisión específica.')
        if words[0].lower() == 'include':
            for pattern in words[1:]:
                if not pattern.startswith('/'):
                    pattern = '/etc/ssh/' + pattern
                for child in sorted(glob.glob(pattern)):
                    inspect(child)
inspect('/etc/ssh/sshd_config')
PY

ask 'Usuario administrador que deseas crear: ' ADMIN
valid_user "$ADMIN" || die 'Nombre inválido: letras minúsculas, números, _ y -; empieza por letra.'
if id "$ADMIN" >/dev/null 2>&1; then
  [[ -f "$STATE/administrador" && $(cat "$STATE/administrador") == "$ADMIN" ]] || die 'Ese usuario ya existe y no fue creado por este script; elige otro.'
fi
ask 'Puertos adicionales (ejemplo: 80/tcp 443/tcp 443/udp; Enter = solo SSH): ' EXTRA
read -r -a RULES <<< "$EXTRA"
for rule in "${RULES[@]}"; do
  [[ "$rule" =~ ^([1-9][0-9]{0,4})/(tcp|udp)$ ]] || die "Puerto inválido: $rule"
  valid_port "${BASH_REMATCH[1]}" || die "Puerto inválido: $rule"
done
ask 'Pega tu llave SSH PÚBLICA en una línea (Enter = continuar con contraseña): ' PUBLIC_KEY
if [[ -n "$PUBLIC_KEY" ]]; then
  [[ "$PUBLIC_KEY" =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com|sk-ecdsa-sha2-nistp256@openssh.com)[[:space:]] ]] || die 'Formato de llave pública no admitido. No pegues una llave privada.'
  printf '%s\n' "$PUBLIC_KEY" > "$RUN/clave-publica"
  ssh-keygen -l -f "$RUN/clave-publica" || die 'La llave pública no es válida.'
fi

say 'Instalando herramientas y actualizaciones (puede tardar varios minutos)...'
apt_run install sudo ufw fail2ban python3-systemd unattended-upgrades apparmor apparmor-utils
apt_run upgrade
if ! id "$ADMIN" >/dev/null 2>&1; then
  adduser --disabled-password --gecos '' "$ADMIN"
  printf '%s\n' "$ADMIN" > "$STATE/administrador"
fi
[[ $(id -u "$ADMIN") -ge 1000 ]] || die 'El administrador no es una cuenta normal.'
ADMIN_HOME=$(getent passwd "$ADMIN" | cut -d: -f6)
[[ "$ADMIN_HOME" == "/home/$ADMIN" && ! -L "$ADMIN_HOME" ]] || die 'Directorio personal inesperado.'
if [[ $(passwd -S "$ADMIN" | awk '{print $2}') != P ]]; then
  say 'Establece una contraseña larga y exclusiva para el administrador (también se usará con sudo).'
  passwd "$ADMIN" </dev/tty
fi
usermod -aG sudo "$ADMIN"
visudo -c
# Ya se ejecuta como root; la redirección es intencionalmente del proceso principal.
# shellcheck disable=SC2024
sudo -l -U "$ADMIN" > "$RUN/permisos-sudo.txt"
if [[ -n "$PUBLIC_KEY" ]]; then
  [[ ! -L "$ADMIN_HOME/.ssh" && ! -L "$ADMIN_HOME/.ssh/authorized_keys" ]] || die 'Se encontró un enlace simbólico en .ssh.'
  install -d -m 700 -o "$ADMIN" -g "$(id -gn "$ADMIN")" "$ADMIN_HOME/.ssh"
  touch "$ADMIN_HOME/.ssh/authorized_keys"
  grep -qxF "$PUBLIC_KEY" "$ADMIN_HOME/.ssh/authorized_keys" || printf '%s\n' "$PUBLIC_KEY" >> "$ADMIN_HOME/.ssh/authorized_keys"
  chown "$ADMIN:$(id -gn "$ADMIN")" "$ADMIN_HOME/.ssh/authorized_keys"
  chmod 600 "$ADMIN_HOME/.ssh/authorized_keys"
fi

# Conserva todos los puertos configurados y el puerto real de esta conexión,
# incluso con activación por ssh.socket. Nunca cambia Port ni ListenAddress.
sshd -T > "$RUN/ssh-inicial.txt"
mapfile -t PORTS < <(awk '$1=="port" {print $2}' "$RUN/ssh-inicial.txt")
CLIENT_IP=127.0.0.1
SERVER_IP=127.0.0.1
CONNECT_PORT=${PORTS[0]:-22}
if [[ -n ${SSH_CONNECTION:-} ]]; then
  read -r CLIENT_IP _ SERVER_IP CONNECT_PORT <<< "$SSH_CONNECTION"
  PORTS+=("$CONNECT_PORT")
fi
mapfile -t PORTS < <(printf '%s\n' "${PORTS[@]}" | sort -nu)
for port in "${PORTS[@]}"; do valid_port "$port" || die 'Puerto SSH inesperado.'; done
printf 'Puertos SSH que se conservarán: %s\n' "${PORTS[*]}"
ROOT_MODE=$(awk '$1=="permitrootlogin" {print $2}' "$RUN/ssh-inicial.txt")
PASS_MODE=$(awk '$1=="passwordauthentication" {print $2}' "$RUN/ssh-inicial.txt")
[[ "$PASS_MODE" == yes || -n "$PUBLIC_KEY" ]] || die 'SSH ya exige llave; proporciona una llave pública y vuelve a ejecutar.'

say 'Configurando actualizaciones automáticas y protección adicional...'
tar -C / -cpf "$RUN/configuracion-adicional.tar" etc/apt/apt.conf.d etc/sysctl.d
cat > /etc/apt/apt.conf.d/99-proteger-ubuntu <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
#clear Unattended-Upgrade::Allowed-Origins;
#clear Unattended-Upgrade::Origins-Pattern;
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
APT
apt-config dump > "$RUN/apt-efectivo.txt"
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
unattended-upgrade --dry-run --debug > "$RUN/actualizaciones-prueba.log" 2>&1
SYSCTL_FILE=/etc/sysctl.d/99-proteger-ubuntu.conf
: > "$SYSCTL_FILE"
: > "$RUN/sysctl-anterior.conf"
while read -r key value; do
  if old=$(sysctl -n "$key" 2>/dev/null); then
    printf '%s = %s\n' "$key" "$old" >> "$RUN/sysctl-anterior.conf"
    printf '%s = %s\n' "$key" "$value" >> "$SYSCTL_FILE"
  else
    printf 'Ajuste no disponible; omitido: %s\n' "$key"
  fi
done <<'SYSCTL'
net.ipv4.tcp_syncookies 1
net.ipv4.conf.all.accept_redirects 0
net.ipv4.conf.default.accept_redirects 0
net.ipv4.conf.all.send_redirects 0
net.ipv4.conf.default.send_redirects 0
net.ipv4.conf.all.accept_source_route 0
net.ipv4.conf.default.accept_source_route 0
net.ipv6.conf.all.accept_redirects 0
net.ipv6.conf.default.accept_redirects 0
net.ipv6.conf.all.accept_source_route 0
net.ipv6.conf.default.accept_source_route 0
kernel.dmesg_restrict 1
kernel.kptr_restrict 2
fs.protected_hardlinks 1
fs.protected_symlinks 1
SYSCTL
sysctl -p "$SYSCTL_FILE"
if aa-enabled; then
  systemctl enable --now apparmor
  aa-status > "$RUN/apparmor.txt"
else
  say 'AVISO: AppArmor está instalado, pero el kernel no lo tiene activo. Se registra como pendiente.'
fi

say 'Aplicando SSH, firewall y Fail2ban con recuperación automática en 15 minutos...'
begin_transaction inicial
write_ssh "$ROOT_MODE" "$PASS_MODE"
ufw default deny incoming
ufw default allow outgoing
# IPv6 se filtra también; no se desactiva la conectividad IPv6 del servidor.
sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
for port in "${PORTS[@]}"; do ufw allow "$port/tcp" comment 'SSH conservar acceso'; done
for rule in "${RULES[@]}"; do ufw allow "$rule"; done
ufw logging low
ufw --force enable
F2B_PORTS=$(IFS=,; printf '%s' "${PORTS[*]}")
cat > /etc/fail2ban/jail.d/99-proteger-ubuntu.local <<F2B
[sshd]
enabled = true
backend = systemd
port = $F2B_PORTS
banaction = ufw
findtime = 10m
maxretry = 6
bantime = 1h
ignoreip = 127.0.0.1/8 ::1
F2B
fail2ban-client -t
systemctl enable --now fail2ban
systemctl restart fail2ban
timeout 30 bash -c 'until fail2ban-client ping; do sleep 1; done'
fail2ban-client status sshd
ufw status verbose
say "SIN CERRAR ESTA SESIÓN: abre otra terminal y entra como $ADMIN al mismo servidor y puerto que usas ahora ($CONNECT_PORT)."
if [[ -n "$PUBLIC_KEY" ]]; then
  say "Prueba tu llave: ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -p $CONNECT_PORT $ADMIN@DIRECCION_DEL_SERVIDOR"
else
  say "Comando: ssh -p $CONNECT_PORT $ADMIN@DIRECCION_DEL_SERVIDOR"
fi
say 'En la conexión nueva ejecuta: sudo -k; sudo id -u  (debe mostrar 0).'
confirm_access || die 'Acceso sin confirmar: se restaurará la configuración de conectividad anterior.'
commit_transaction

say 'El acceso del administrador está confirmado. Se desactivará el login SSH de root.'
if [[ -n "$PUBLIC_KEY" ]]; then
  PASS_MODE=no
  say 'Como confirmaste el acceso por llave, también se desactivarán las contraseñas SSH.'
else
  say 'El administrador seguirá entrando con contraseña; Fail2ban protegerá los intentos de acceso.'
fi
begin_transaction cierre-root
write_ssh no "$PASS_MODE"
say 'Abre una conexión NUEVA con el administrador y vuelve a comprobar sudo id -u.'
confirm_access || die 'No se confirmó el cambio final; se recuperará el modo de acceso anterior.'
commit_transaction
sshd -T > "$RUN/ssh-final.txt"
ufw status verbose > "$RUN/firewall-final.txt"
fail2ban-client status sshd > "$RUN/fail2ban-final.txt"
say "Configuración completada. Administrador: $ADMIN. SSH root: desactivado. Contraseña SSH: $PASS_MODE."
say "Registro y respaldos: $RUN"
say 'No se instaló Docker. No se reiniciará automáticamente.'
[[ ! -f /var/run/reboot-required ]] || say 'PENDIENTE: Ubuntu indica que necesita reiniciar para completar actualizaciones. Programa el reinicio cuando puedas.'
}

apt_run() {
  DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=l apt-get \
    -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold -y "$@"
}

finish() {
  local rc=$1
  trap - EXIT
  if [[ -n ${ACTIVE:-} ]]; then
    printf '\nRestaurando SSH, UFW y Fail2ban a su estado anterior...\n'
    bash "$ACTIVE/recuperar.sh" || printf 'Fallo de recuperación: usa la consola del proveedor y revisa %s\n' "$ACTIVE"
    systemctl stop "$UNIT.timer" >/dev/null 2>&1 || true
  fi
  if (( rc != 0 )); then
    printf '\nProceso incompleto. Las actualizaciones, el usuario y los ajustes adicionales pueden haber quedado aplicados.\nRegistro: %s\n' "${LOG:-no disponible}"
  fi
  exit "$rc"
}

begin_transaction() {
  ACTIVE="$RUN/$1"
  mkdir -m 700 "$ACTIVE"
  local path
  : > "$ACTIVE/presentes"
  : > "$ACTIVE/ausentes"
  for path in etc/ssh/sshd_config etc/ssh/proteger-ubuntu.conf etc/ufw etc/default/ufw etc/fail2ban/jail.d/99-proteger-ubuntu.local; do
    if [[ -e /$path ]]; then printf '%s\n' "$path" >> "$ACTIVE/presentes"
    else printf '%s\n' "$path" >> "$ACTIVE/ausentes"; fi
  done
  tar -C / -cpf "$ACTIVE/config.tar" -T "$ACTIVE/presentes"
  ufw status | head -n 1 > "$ACTIVE/ufw-estado"
  systemctl is-active fail2ban > "$ACTIVE/f2b-activo" || true
  systemctl is-enabled fail2ban > "$ACTIVE/f2b-habilitado" || true
  cat > "$ACTIVE/recuperar.sh" <<'RECOVER'
#!/usr/bin/env bash
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
exec 8>"$HERE/lock"
flock 8
[[ ! -e "$HERE/confirmado" && ! -e "$HERE/restaurado" ]] || exit 0
touch "$HERE/restaurando"
exec >>"$HERE/recuperacion.log" 2>&1
rc=0
systemctl stop fail2ban || true
while IFS= read -r path; do rm -f -- "/$path" || rc=1; done < "$HERE/ausentes"
tar -C / -xpf "$HERE/config.tar" || rc=1
if grep -qx 'Status: active' "$HERE/ufw-estado"; then ufw --force enable || rc=1
else ufw --force disable || rc=1; fi
if sshd -t; then systemctl reload ssh || rc=1; else rc=1; fi
if grep -qx enabled "$HERE/f2b-habilitado"; then systemctl enable fail2ban || rc=1
else systemctl disable fail2ban || rc=1; fi
if grep -qx active "$HERE/f2b-activo"; then systemctl start fail2ban || rc=1; fi
(( rc != 0 )) || touch "$HERE/restaurado"
exit "$rc"
RECOVER
  chmod 700 "$ACTIVE/recuperar.sh"
  UNIT="proteger-ubuntu-$(date +%s)-$$-$1"
  systemd-run --unit="$UNIT" --on-active=15m --timer-property=AccuracySec=1s /bin/bash "$ACTIVE/recuperar.sh"
  systemctl is-active --quiet "$UNIT.timer" || die 'No se pudo armar la recuperación automática.'
}

commit_transaction() {
  (
    flock -x 8
    [[ ! -e "$ACTIVE/restaurando" ]] || exit 1
    touch "$ACTIVE/confirmado"
  ) 8>"$ACTIVE/lock" || die 'El plazo venció y ya se inició la recuperación.'
  systemctl stop "$UNIT.timer"
  ACTIVE=''
}

confirm_access() {
  local answer
  printf '\nTienes 10 minutos. Escribe CONFIRMADO solo después de comprobar el nuevo acceso y sudo: '
  read -r -t 600 answer </dev/tty && [[ "$answer" == CONFIRMADO ]]
}

write_ssh() {
  local root_mode=$1 password_mode=$2 user effective
  cat > /etc/ssh/proteger-ubuntu.conf <<SSH
# Administrado por proteger-ubuntu.sh
PermitRootLogin $root_mode
PasswordAuthentication $password_mode
PubkeyAuthentication yes
KbdInteractiveAuthentication no
PermitEmptyPasswords no
UsePAM yes
MaxAuthTries 6
LoginGraceTime 30
MaxStartups 10:30:60
X11Forwarding no
PermitUserEnvironment no
LogLevel VERBOSE
SSH
  # Include explícito en primera posición: evita precedencia accidental de cloud-init.
  python3 - <<'PY'
from pathlib import Path
p = Path('/etc/ssh/sshd_config')
line = 'Include /etc/ssh/proteger-ubuntu.conf'
lines = [s for s in p.read_text().splitlines() if s.strip() != line]
p.write_text(line + '\n' + '\n'.join(lines) + '\n')
PY
  chmod 600 /etc/ssh/proteger-ubuntu.conf
  sshd -t
  for user in root "$ADMIN"; do
    effective=$(sshd -T -C "user=$user,addr=$CLIENT_IP,host=$CLIENT_IP,laddr=$SERVER_IP,lport=$CONNECT_PORT")
    grep -qx "permitrootlogin $root_mode" <<< "$effective" || die 'Una regla Match altera PermitRootLogin.'
    grep -qx "passwordauthentication $password_mode" <<< "$effective" || die 'Una regla Match altera PasswordAuthentication.'
    grep -qx 'pubkeyauthentication yes' <<< "$effective" || die 'Una regla Match desactiva las llaves.'
    grep -qx 'kbdinteractiveauthentication no' <<< "$effective" || die 'Una regla Match altera la autenticación interactiva.'
  done
  systemctl reload ssh
  systemctl is-active --quiet ssh
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
