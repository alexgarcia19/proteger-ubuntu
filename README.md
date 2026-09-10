# Protección de una instalación nueva de Ubuntu

El archivo `proteger-ubuntu.sh` configura el servidor de forma interactiva en una sola ejecución. No instala Docker, no añade su repositorio y no descarga programas de instalación externos.

## Ejecución

Sube `proteger-ubuntu.sh` al servidor mediante tu cliente SFTP o SCP. En la sesión donde entras como root, ve a la carpeta donde lo guardaste y ejecuta:

```bash
bash proteger-ubuntu.sh
```

No necesitas editar el archivo ni instalar manualmente sus paquetes. Necesitas Internet para los repositorios de Ubuntu, una terminal interactiva y acceso a la consola del proveedor para una eventual recuperación. Mantén abierta la sesión inicial.

El script solicitará:

1. Un nombre para crear el administrador.
2. Los puertos adicionales que necesitas. Para una web convencional: `80/tcp 443/tcp`. Enter deja solamente las excepciones SSH y las reglas que ya existan. Abrir un puerto no instala el servicio correspondiente.
3. Opcionalmente, tu llave SSH **pública**. Puedes dejarla vacía y continuar usando contraseña. Nunca proporciones una llave privada.
4. Una contraseña para el nuevo administrador, que también necesitarás con `sudo`. Usa una contraseña larga y exclusiva.
5. Dos comprobaciones de acceso desde otra terminal, guiadas dentro de la misma ejecución.

En esas comprobaciones entra con el administrador al mismo servidor y puerto que utilizas ahora y ejecuta `sudo -k` seguido de `sudo id -u`. El resultado debe ser `0`. Si proporcionaste una llave, utiliza el comando indicado por el script, que impide recurrir a contraseña para esa prueba. Escribe `CONFIRMADO` en la sesión inicial solo después de comprobar el acceso y sudo.

La primera prueba verifica el administrador y el firewall. La segunda verifica el acceso después de desactivar SSH para root. Cada pregunta admite hasta diez minutos. No son instalaciones adicionales: son comprobaciones desde tu computadora que el servidor no puede realizar en tu nombre.

## Crear y utilizar una llave SSH pública (Windows, macOS y Linux)

Este paso es opcional. Si prefieres continuar con contraseña, deja vacío el campo de llave pública del script y presiona **Enter**.

La llave se crea en **la computadora desde la que te conectarás**, no dentro de la sesión del servidor. Se generan dos archivos: una llave privada que conservas en esa computadora y una pública que instalarás en el servidor. Mantén abierta la sesión inicial mientras realizas estos pasos en otra ventana.

### 1. Abrir una terminal local

- **Windows:** abre PowerShell o Windows Terminal con PowerShell. Necesitas el componente **Cliente OpenSSH**; si `ssh-keygen` no se reconoce, instálalo desde las características opcionales de Windows. No necesitas instalar el servidor OpenSSH en tu computadora.
- **macOS:** abre Terminal.
- **Linux:** abre una terminal. Si falta `ssh-keygen`, instala el cliente OpenSSH con el gestor de paquetes de tu distribución; en Ubuntu/Debian el paquete es `openssh-client`.

### 2. Generar el par de llaves

El comando es el mismo en los tres sistemas:

```text
ssh-keygen -t ed25519
```

Cuando pregunte dónde guardar la llave, presiona **Enter** para aceptar la ubicación predeterminada. Normalmente será `.ssh/id_ed25519` dentro de tu carpeta de usuario.

**Si indica que el archivo ya existe, responde `n` para no sobrescribirlo.** Puedes utilizar esa llave si te pertenece y conoces su frase de contraseña. Para crear una distinta, vuelve a ejecutar el comando y escribe otra ruta cuando la solicite. Conserva esa ruta: tendrás que usarla en los pasos siguientes.

Cuando solicite una frase de contraseña (*passphrase*), escribe una frase larga para proteger la llave privada y repítela. No se mostrarán caracteres mientras escribes. Esta frase protege la llave en tu computadora; es diferente de la contraseña del administrador del servidor.

### 3. Mostrar o copiar solamente la llave pública

Estos comandos suponen que aceptaste el nombre predeterminado. Si elegiste otro, sustituye la ruta por la de tu archivo terminado en `.pub`.

**Windows — PowerShell:**

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

Para copiarla al portapapeles:

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub" | Set-Clipboard
```

**macOS — Terminal:**

```bash
cat ~/.ssh/id_ed25519.pub
```

Para copiarla al portapapeles:

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

**Linux — Terminal:**

```bash
cat ~/.ssh/id_ed25519.pub
```

Selecciona y copia toda la salida con la función de copiar de tu terminal. No necesitas instalar una herramienta adicional de portapapeles.

La llave pública es una sola línea que empieza por `ssh-ed25519`, seguida de una cadena larga y, normalmente, un comentario. Aunque la terminal la muestre repartida visualmente en varios renglones, cópiala completa sin introducir saltos de línea ni incluir el indicador de la terminal.

### 4. Pegar la llave en el script

Regresa a la sesión del servidor cuando aparezca:

```text
Pega tu llave SSH PÚBLICA en una línea (Enter = continuar con contraseña):
```

Pega la línea completa y presiona **Enter**. El script la validará e instalará para el nuevo administrador; no necesitas ejecutar `ssh-copy-id` ni editar `authorized_keys` manualmente.

**Comparte únicamente la llave pública, el archivo terminado en `.pub`. Nunca pegues, subas a GitHub ni envíes la llave privada `id_ed25519` o su frase de contraseña.**

### 5. Comprobar el acceso desde tu computadora

Espera a que el script te pida comprobar la conexión. En otra terminal local, utiliza el comando que muestra el script sustituyendo el usuario, la dirección y el puerto por los de tu servidor. Reemplaza `USER` por tu usuario administrador e `IP_DEL_SERVIDOR` por la dirección del servidor. Ejemplo con el puerto SSH habitual:

```text
ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -p 22 USER@IP_DEL_SERVIDOR
```

Este comando funciona en Windows con OpenSSH, macOS y Linux. Puede pedirte la frase de contraseña de la llave privada; eso es normal y no significa que esté utilizando la contraseña SSH del servidor. Si aparece un aviso de identidad del servidor, verifica su huella con la consola del servidor antes de aceptarlo.

Si guardaste la llave con otro nombre, añade `-i RUTA_DE_LA_LLAVE_PRIVADA` al comando SSH. Usa la ruta de tu computadora **sin `.pub`**; SSH lee ese archivo localmente y no lo copia al servidor.

Dentro de la conexión nueva ejecuta:

```bash
sudo -k
sudo id -u
```

Introduce la contraseña del administrador cuando `sudo` la solicite. Debe mostrar `0`. Solo entonces vuelve a la sesión inicial y escribe `CONFIRMADO`. Repite la comprobación con una conexión nueva cuando el script lo solicite por segunda vez. Si el acceso falla, no confirmes ni cierres la sesión inicial.

## Agregar una PC nueva al servidor

Para conectarte desde otra computadora, crea una llave SSH en ella y agrega **su llave pública** al usuario administrador del servidor. No necesitas volver a ejecutar el script ni reiniciar SSH.

En los comandos siguientes, **reemplaza `USER` por tu usuario administrador** e **`IP_DEL_SERVIDOR` por la dirección del servidor**. Se usa el puerto `22` como ejemplo; sustitúyelo si tu servidor utiliza otro puerto.

### 1. Crear una llave en la PC nueva

Abre PowerShell en Windows o una terminal en macOS/Linux y ejecuta:

```text
ssh-keygen -t ed25519
```

Acepta la ubicación predeterminada y establece una frase de contraseña. Si ya existe una llave, no la sobrescribas. Para más detalles, consulta la sección anterior sobre creación de llaves.

### 2. Copiar la llave pública de la PC nueva

**Windows — PowerShell:**

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

**macOS o Linux:**

```bash
cat ~/.ssh/id_ed25519.pub
```

Copia toda la línea que empieza con `ssh-ed25519`. Si guardaste la llave con otro nombre, utiliza la ruta correspondiente al archivo `.pub`. Lleva esa línea a la computadora que ya tiene acceso al servidor; la llave privada permanece en la PC nueva.

### 3. Autorizarla desde la computadora que ya tiene acceso

Desde la computadora autorizada, conéctate al servidor:

```text
ssh -p 22 USER@IP_DEL_SERVIDOR
```

Dentro de esa sesión, abre el archivo de llaves del usuario:

```bash
nano ~/.ssh/authorized_keys
```

Ejecuta este comando como **`USER`**, sin cambiar a root: `~` representa la carpeta personal de la cuenta con la que estás conectado. Si no tienes `nano`, utiliza otro editor de texto disponible.

Añade la llave pública de la PC nueva **en una línea nueva**, conservando todas las llaves existentes. Cada llave debe ocupar una sola línea. En nano, guarda con **Ctrl+O**, presiona **Enter** y sal con **Ctrl+X**.

Después ajusta los permisos:

```bash
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### 4. Comprobar el acceso desde la PC nueva

En una terminal de la PC nueva, ejecuta:

```text
ssh -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -p 22 USER@IP_DEL_SERVIDOR
```

Si elegiste un nombre diferente para la llave, añade `-i RUTA_DE_LA_LLAVE_PRIVADA` con su ruta local, sin `.pub`. Puede solicitar la frase de contraseña de esa llave.

Una vez conectado, comprueba los permisos del administrador:

```bash
sudo -k
sudo id -u
```

Introduce la contraseña del usuario cuando se solicite; debe mostrar `0`. **Mantén abierta la conexión anterior hasta verificar que la PC nueva puede entrar.**

Cada computadora conserva su propia llave privada. Solo se añade al servidor la pública, terminada en `.pub`; no copies la llave privada de una computadora a otra.

## Compatibilidad

Está diseñado para Ubuntu Server 22.04 o posterior, con systemd y OpenSSH ya funcionando, en una instalación nueva. Actualiza `distro-info-data` y consulta su calendario para admitir únicamente versiones publicadas con soporte estándar vigente según la fecha del servidor. No utiliza una lista fija de nombres de versiones.

No promete compatibilidad universal. Se detiene ante versiones desconocidas, preliminares, fuera de soporte estándar, repositorios que fallen, componentes ausentes o configuraciones SSH personalizadas con `Match`. No acepta versiones antiguas solamente por contar con Ubuntu Pro/ESM. Las versiones futuras admitidas por sus metadatos siguen necesitando validación práctica de compatibilidad.

Antes de comprobar soporte puede actualizar índices de APT e instalar/actualizar `python3` y `distro-info-data`; todavía no modifica SSH ni el firewall. Si encuentra un problema después, informa del fallo y no declara la instalación completa.

## Qué configura

- Crea una cuenta normal y la añade al grupo `sudo`. En ejecuciones posteriores solo reutiliza el usuario registrado por el propio script; no eleva silenciosamente una cuenta preexistente ajena.
- Conserva los puertos SSH declarados y el puerto observado en la conexión actual. No cambia `Port`, `ListenAddress` ni `ssh.socket`.
- Valida SSH antes de recargarlo. Conserva el método inicial hasta confirmar el administrador. Al terminar bloquea el acceso SSH directo de root. Sin llave pública, permite contraseña para el administrador; con llave pública comprobada, desactiva contraseña e interacción por teclado en SSH. La contraseña local de root no se elimina.
- Limita intentos y conexiones SSH sin autenticar, rechaza contraseñas vacías, desactiva X11 y registra más detalles de autenticación. Conserva los algoritmos criptográficos del OpenSSH suministrado por Ubuntu.
- Activa UFW para IPv4 e IPv6, deniega entrada por defecto y permite salida. Añade excepciones SSH y los puertos elegidos. **Conserva las reglas UFW preexistentes**: volver a ejecutar con menos puertos no elimina excepciones anteriores. No administra firewalls externos del proveedor ni reglas ajenas a UFW.
- Configura explícitamente la protección SSH de Fail2ban usando el journal de systemd: seis fallos en diez minutos producen un bloqueo de una hora. No depende de que exista `/var/log/auth.log`. Las direcciones de administración no quedan permanentemente exentas; varios usuarios detrás de una misma IP pueden compartir un bloqueo.
- Actualiza paquetes y activa actualizaciones automáticas de seguridad de Ubuntu. Las fuentes ESM solo aportan actualizaciones cuando corresponda y estén disponibles; no contrata ni activa Ubuntu Pro. No hace una actualización de versión de la distribución.
- Activa los perfiles disponibles de AppArmor si el kernel lo admite. Si no está disponible, muestra un aviso. Instalar AppArmor no crea perfiles para todas las aplicaciones futuras.
- Aplica ajustes disponibles del kernel: SYN cookies, restricciones de redirecciones y rutas de origen, protección de enlaces y restricciones de información del kernel. No desactiva IPv6 ni cambia el reenvío IP o la configuración de red del proveedor.
- Guarda registros y respaldos privados bajo `/var/lib/proteger-ubuntu/ejecucion-FECHA-.../`.

No reinicia automáticamente. Si Ubuntu necesita reiniciar para activar un kernel actualizado u otros cambios, lo indica al final. Ese reinicio queda pendiente hasta que tú lo programes. Las actualizaciones de paquetes pueden recargar servicios durante la instalación.

## Recuperación

Antes de cada fase de conectividad guarda SSH, UFW y su archivo de Fail2ban. Programa una recuperación mediante un temporizador de systemd a quince minutos. Confirmar correctamente cancela esa recuperación. Si cancelas la pregunta o el proceso termina con un error, intenta restaurar inmediatamente; si se pierde el proceso, el temporizador sirve de respaldo mientras el servidor siga encendido y systemd funcione.

La primera recuperación vuelve al estado anterior a configurar la conectividad. La segunda vuelve al estado que ya habías comprobado antes de cerrar el acceso de root. Esto puede volver a permitir root o contraseñas: revisa el registro y completa la configuración posteriormente.

Si necesitas una recuperación manual desde la consola del proveedor, localiza la carpeta de la fase fallida (`inicial` o `cierre-root`) dentro del directorio de ejecución mostrado por el script y ejecuta su `recuperar.sh` con Bash como root. El archivo `recuperacion.log` muestra el resultado. Una fase ya confirmada no se revierte al ejecutar ese auxiliar; sus respaldos quedan disponibles para revisión manual.

El temporizador es transitorio: no sobrevive a un reinicio. No reinicies durante las pruebas. No puede corregir una caída del proveedor, un fallo de disco o un firewall externo.

La recuperación automática **solo abarca conectividad**. No desinstala actualizaciones, elimina usuarios ni revierte AppArmor o los ajustes adicionales. Estos últimos conservan respaldos en `configuracion-adicional.tar` y valores anteriores en `sysctl-anterior.conf`; no es una instantánea completa del servidor. Una ejecución fallida puede dejar protección parcial, y volver a ejecutar no equivale a deshacerla.

## Referencias técnicas

Referencias técnicas: [OpenSSH en Ubuntu](https://ubuntu.com/server/docs/how-to/security/openssh-server/), [opciones de sshd](https://manpages.ubuntu.com/manpages/noble/man5/sshd_config.5.html), [UFW en Ubuntu](https://ubuntu.com/server/docs/how-to/security/firewalls/), [actualizaciones automáticas](https://ubuntu.com/server/docs/how-to/software/automatic-updates/) y [configuración oficial de Fail2ban](https://github.com/fail2ban/fail2ban/blob/master/config/jail.conf).
