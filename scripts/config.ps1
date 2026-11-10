# =====================================================================
# Configuracion de despliegue del proyecto final (EC2 unico) - VERSION WINDOWS.
# Editar estos valores antes de ejecutar cualquier script .ps1.
# Todos pueden sobrescribirse como variable de entorno:
#   $env:EC2_HOST = "1.2.3.4"; .\scripts\deploy.ps1
#
# Requisitos Windows 10/11:
#   - Cliente OpenSSH (ssh/scp): viene habilitado en Win10 1809+ y Win11
#     (Configuracion > Aplicaciones > Caracteristicas opcionales > Cliente OpenSSH)
#   - tar y curl: incluidos en Windows 10 1803+
#   - AWS CLI v2 instalado y configurado (aws configure)
# =====================================================================

# IP publica o DNS publico de la instancia EC2. OBLIGATORIO.
$EC2_HOST = if ($env:EC2_HOST) { $env:EC2_HOST } else { "ec2-77-113-69-25.us-east-2.compute.amazonaws.com" }

# Usuario SSH segun la AMI: "ubuntu" (Ubuntu) | "ec2-user" (Amazon Linux)
$EC2_USER = if ($env:EC2_USER) { $env:EC2_USER } else { "ec2-user" }

# Llave privada SSH (vive en la raiz del proyecto; NO se sube al EC2)
$PROJECT_ROOT = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$KEY_PATH = if ($env:KEY_PATH) { $env:KEY_PATH } else { Join-Path $PROJECT_ROOT "mi-llave-privada.pem" }

# Directorio (relativo al home del usuario) donde vive el proyecto en el EC2
$REMOTE_DIR = if ($env:REMOTE_DIR) { $env:REMOTE_DIR } else { "proyectoFinal" }

# ---- Solo para security-group.ps1 ----
$AWS_REGION = if ($env:AWS_REGION) { $env:AWS_REGION } else { "us-east-2" }

# ID del Security Group de la instancia.
$SG_ID = if ($env:SG_ID) { $env:SG_ID } else { "sg-0dac330c25b8c2240" }

# ---- Infra comun ----
# Opciones base para ssh/scp (arrays: cada elemento es un argumento separado)
$script:SSH_BASE = @("-i", $KEY_PATH, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=accept-new")

# Ejecuta un script bash EN el EC2. $Script es el cuerpo del script (here-string).
# Internamente: lo guarda como UTF-8 sin BOM con finales de linea LF (bash no
# tolera CRLF), lo sube con scp y lo ejecuta con bash.
# Evita el problema clasico de PowerShell: pipear texto a ssh convierte los
# saltos de linea a CRLF y bash falla con $'\r': command not found.
function Invoke-Remote {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptBody,
        [string[]]$ScriptArgs = @()
    )
    $tmpLocal = Join-Path ([IO.Path]::GetTempPath()) "proyecto-final-remote.sh"
    $lfOnly = $ScriptBody -replace "`r`n", "`n"
    [IO.File]::WriteAllText($tmpLocal, $lfOnly, (New-Object Text.UTF8Encoding($false)))

    & scp @script:SSH_BASE -q $tmpLocal "${EC2_USER}@${EC2_HOST}:/tmp/proyecto-final-remote.sh"
    if ($LASTEXITCODE -ne 0) { throw "fallo scp del script remoto" }

    $quoted = ($ScriptArgs | ForEach-Object { "'$_'" }) -join " "
    & ssh @script:SSH_BASE "${EC2_USER}@${EC2_HOST}" "bash /tmp/proyecto-final-remote.sh $quoted"
    if ($LASTEXITCODE -ne 0) { throw "el script remoto fallo (exit code $LASTEXITCODE)" }
}

# Valida que la config sea usable (host definido y llave existente).
function Assert-Config {
    if (-not $EC2_HOST) { throw "defini EC2_HOST en scripts\config.ps1 (o con `$env:EC2_HOST)" }
    if (-not (Test-Path $KEY_PATH)) { throw "no existe la llave en $KEY_PATH" }
    # Nota permisos Windows: si ssh rechaza la llave ("UNPROTECTED PRIVATE KEY"),
    # restringir la ACL (PowerShell como administrador NO requerido):
    #   icacls "$KEY_PATH" /inheritance:r /grant "${env:USERNAME}:F"
}
