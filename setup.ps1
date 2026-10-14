# Brushfall: guided setup for Docker hosts (Windows PowerShell 5.1 and newer).
#
#   irm https://raw.githubusercontent.com/Twelve47Studios/brushfall_release/main/setup.ps1 -OutFile setup.ps1
#   powershell -ExecutionPolicy Bypass -File setup.ps1                 # sets up $HOME\brushfall
#   powershell -ExecutionPolicy Bypass -File setup.ps1 D:\brushfall    # or another folder
#   powershell -ExecutionPolicy Bypass -File setup.ps1 -Share          # also share it outside your home (Tailscale Funnel)
#
# It is safe to run again: your .env settings are never replaced.
# What it does: checks Docker, gets docker-compose.yml and .env, picks a free port,
# starts Brushfall, and shows the address and the one-time setup code for the Studio Desk.

param(
  [string]$Folder = (Join-Path $HOME 'brushfall'),
  [switch]$Share
)

$RawUrl = 'https://raw.githubusercontent.com/Twelve47Studios/brushfall_release/main'
$FirstPort = 8080
$SetupCodeCmd = 'brushfall setup-code'

$ErrorActionPreference = 'Stop'
# GitHub needs TLS 1.2, which older Windows PowerShell doesn't turn on by itself.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Say([string]$Text = '') { Write-Host $Text }
function Fail([string]$Text) {
  Write-Host ''
  Write-Host "Sorry, setup stopped: $Text" -ForegroundColor Red
  exit 1
}

# Runs docker with these arguments and returns its exit code, output and error text (without stopping on stderr).
function Invoke-Docker([string[]]$DockerArgs) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $lines = & docker @DockerArgs 2>&1
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previous
  $out = @($lines | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
  $err = @($lines | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) -join "`n"
  return [pscustomobject]@{ Code = $code; Out = $out; Err = $err }
}

# Runs docker with its output shown as it goes; returns the exit code.
function Invoke-DockerLive([string[]]$DockerArgs) {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & docker @DockerArgs | Out-Host
  $code = $LASTEXITCODE
  $ErrorActionPreference = $previous
  return $code
}

Say ''
Say "Hello! Let's set up your Brushfall world."
Say ''

# --- 1. Docker ---------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Fail "Docker isn't installed yet. Install Docker Desktop from https://docs.docker.com/get-docker/, start it, and run this again."
}
if ((Invoke-Docker @('info')).Code -ne 0) {
  Fail 'Docker is installed but not running. Start Docker Desktop and look for the whale icon in the taskbar; when it stops moving, run this again.'
}
if ((Invoke-Docker @('compose', 'version')).Code -ne 0) {
  Fail 'Docker is running, but "docker compose" is missing. Update Docker Desktop and run this again.'
}
Say 'Docker is installed and running. Good.'

# --- 2. The folder and its two files ----------------------------------------
New-Item -ItemType Directory -Force -Path $Folder | Out-Null
Set-Location $Folder
$Folder = (Get-Location).Path
Say "Your Brushfall folder: $Folder"

function Get-RawFile([string]$Published, [string]$File) {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri "$RawUrl/$Published" -OutFile $File
  } catch {
    Fail "I couldn't download $RawUrl/$Published. Check this computer is online and try again. ($($_.Exception.Message))"
  }
}

$ComposeFile = Join-Path $Folder 'docker-compose.yml'
$EnvFile = Join-Path $Folder '.env'

Get-RawFile 'docker-compose.yml' "$ComposeFile.new"
if (-not (Test-Path $ComposeFile)) {
  Move-Item "$ComposeFile.new" $ComposeFile
  Say 'Got docker-compose.yml (what to run).'
} elseif ((Get-FileHash $ComposeFile).Hash -eq (Get-FileHash "$ComposeFile.new").Hash) {
  Remove-Item "$ComposeFile.new"
  Say 'docker-compose.yml is already up to date.'
} else {
  Move-Item -Force $ComposeFile "$ComposeFile.old"
  Move-Item "$ComposeFile.new" $ComposeFile
  Say 'Note: there was a newer docker-compose.yml, so I put it in place. Your old one is saved as docker-compose.yml.old in case you had changed it.'
}

$NewEnv = $false
if (Test-Path $EnvFile) {
  Say 'Keeping your settings in .env (I never replace it).'
} else {
  Get-RawFile '.env.example' $EnvFile
  $NewEnv = $true
  Say 'Got .env (your settings).'
}

# The last value of Key= in .env (empty when missing).
function Get-EnvValue([string]$Key) {
  $value = ''
  foreach ($line in [IO.File]::ReadAllLines($EnvFile)) {
    if ($line.StartsWith("$Key=")) { $value = $line.Substring($Key.Length + 1).Trim().Trim('"') }
  }
  return $value
}
# Change Key's line in .env in place, or add it. Writes UTF-8 without a BOM, with the file's own line endings.
function Set-EnvValue([string]$Key, [string]$Value) {
  $text = [IO.File]::ReadAllText($EnvFile)
  $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.AddRange([string[]]($text -split "\r?\n"))
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
  $done = $false
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].StartsWith("$Key=")) { $lines[$i] = "$Key=$Value"; $done = $true }
  }
  if (-not $done) { $lines.Add("$Key=$Value") }
  [IO.File]::WriteAllText($EnvFile, (($lines -join $newline) + $newline), $Utf8NoBom)
}

# --- 3. A free port -----------------------------------------------------------
# Something listens on this TCP port on this computer (Docker Desktop's published ports included).
function Test-PortBusy([int]$Port) {
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $connect = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
    if (-not $connect.AsyncWaitHandle.WaitOne(500)) { return $false }
    try { $client.EndConnect($connect); return $true } catch { return $false }
  } finally {
    $client.Close()
  }
}

$Port = Get-EnvValue 'BRUSHFALL_PORT'
if (-not $NewEnv -and $Port) {
  Say "Using port $Port from your .env."
} else {
  $Port = $FirstPort
  while (Test-PortBusy $Port) {
    $Port++
    if ($Port -gt $FirstPort + 50) { Fail "Ports $FirstPort to $($Port - 1) are all in use on this computer. Set BRUSHFALL_PORT in .env to a free one and run this again." }
  }
  Set-EnvValue 'BRUSHFALL_PORT' "$Port"
  if ($Port -eq $FirstPort) {
    Say "Brushfall will use port $Port."
  } else {
    Say "Port $FirstPort is already used by something else on this computer, so Brushfall will use port $Port."
  }
}

# --- 4. Start it --------------------------------------------------------------
function Wait-ForHealth {
  Write-Host -NoNewline 'Waiting for your world to wake up'
  for ($try = 0; $try -lt 60; $try++) {
    try {
      $reply = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/health" -TimeoutSec 3
      if ("$($reply.Content)" -match '"ok":true') { Say ' ready!'; return }
    } catch {
      # Not answering yet (or still starting: 503). Keep waiting.
    }
    Write-Host -NoNewline '.'
    Start-Sleep -Seconds 2
  }
  Say ''
  Say 'Here is what Brushfall said last:'
  Invoke-DockerLive @('compose', 'logs', '--tail', '30', 'brushfall') | Out-Null
  Fail "Brushfall didn't answer on http://localhost:$Port within 2 minutes. The lines above usually say why. Fix that (or ask for help at https://github.com/Twelve47Studios/brushfall_release/issues) and run this again."
}

Say ''
Say 'Starting Brushfall. The first time, Docker downloads it, which takes a minute or two...'
if ((Invoke-DockerLive @('compose', 'up', '-d')) -ne 0) { Fail "Docker couldn't start Brushfall (the message above says why)." }
Wait-ForHealth

# --- 5. The setup code --------------------------------------------------------
$codeRun = Invoke-Docker (@('compose', 'exec', '-T', 'brushfall') + $SetupCodeCmd.Split(' '))
$Code = ''
switch ($codeRun.Code) {
  0 {
    $Code = $codeRun.Out.Trim()
    if (-not $Code) { Fail "Brushfall gave an empty setup code. Run: docker compose exec brushfall $SetupCodeCmd" }
  }
  3 { $Code = '' }
  default { Fail "I couldn't get the setup code ($($codeRun.Err.Trim())). Try: docker compose exec brushfall $SetupCodeCmd" }
}

# This computer's address on the home network: the IPv4 address of the interface with the default route.
function Get-LanAddress {
  if (-not (Get-Command Get-NetRoute -ErrorAction SilentlyContinue)) { return '' }
  $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1
  if (-not $route) { return '' }
  $address = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $address) { return '' }
  return $address.IPAddress
}

$AdminUrl = "http://localhost:$Port/admin"
$Lan = Get-LanAddress

Say ''
Say '+--------------------------------------------------------------+'
Say '  Your Brushfall world is running!'
Say ''
Say "  Open:  $AdminUrl"
if ($Code) {
  Say "  Setup code:  $Code"
  Say '  (type it on that page, name your world and make your account)'
} else {
  Say '  This world is already set up: sign in with your admin account.'
}
Say ''
if ($Lan) {
  Say "  Family on your home Wi-Fi can join at http://${Lan}:$Port"
} else {
  Say "  Family on your home Wi-Fi can join with this computer's address;"
  Say "  the Studio Desk's Hosting tab shows it, with a QR code."
}
Say '  If your computer asks whether to allow incoming connections,'
Say "  choose Allow, or family can't join."
Say '+--------------------------------------------------------------+'

# --- 6. Open the browser --------------------------------------------------------
try { Start-Process $AdminUrl } catch { Say "(Open $AdminUrl in your browser.)" }

# --- 7. Sharing outside the home (optional) -------------------------------------
if (-not $Share -and [Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
  Say ''
  $answer = Read-Host 'Do you want family outside your home to join too, with Tailscale (free)? [y/N]'
  if ($answer -match '^(y|yes)$') { $Share = $true }
}
if (-not $Share) {
  Say ''
  Say 'All done. Have fun painting! (Run this again with -Share any time to let family outside your home join.)'
  exit 0
}

Say ''
Say 'Sharing with Tailscale Funnel gives your world a public https address, with no router changes.'
Say 'Before we start, in the Tailscale admin console (free account at https://tailscale.com):'
Say '  1. DNS page: turn on MagicDNS and HTTPS Certificates.'
Say '  2. Access controls: allow Funnel (https://tailscale.com/kb/1223/funnel).'
Say '  3. Settings > Keys (https://login.tailscale.com/admin/settings/keys): generate an auth key.'

if (Get-EnvValue 'TS_AUTHKEY') {
  Say 'Using the Tailscale auth key already saved in your .env.'
} else {
  $secret = Read-Host -AsSecureString 'Paste your Tailscale auth key (it stays hidden while you type) and press Enter'
  $key = (New-Object System.Net.NetworkCredential('', $secret)).Password.Trim()
  if (-not $key) { Fail 'No key was pasted. Run setup.ps1 -Share again when you have one.' }
  if (-not $key.StartsWith('tskey-')) { Fail "That doesn't look like a Tailscale auth key (they start with tskey-). Copy it again from https://login.tailscale.com/admin/settings/keys" }
  Set-EnvValue 'TS_AUTHKEY' $key
  $key = $null
}

New-Item -ItemType Directory -Force -Path (Join-Path $Folder 'deploy') | Out-Null
Get-RawFile 'deploy/tailscale-funnel.json' (Join-Path $Folder 'deploy\tailscale-funnel.json')
Set-EnvValue 'TS_SERVE_FILE' 'tailscale-funnel.json'
Set-EnvValue 'TRUST_PROXY' '1'
# Docker reads this from .env, so plain "docker compose up -d" (and updates) include Tailscale from now on.
Set-EnvValue 'COMPOSE_PROFILES' 'tailscale'

Say 'Starting Tailscale...'
if ((Invoke-DockerLive @('compose', '--profile', 'tailscale', 'up', '-d')) -ne 0) { Fail "Docker couldn't start Tailscale (the message above says why)." }

Write-Host -NoNewline 'Waiting for Tailscale to connect'
$Name = ''
for ($try = 0; $try -lt 30; $try++) {
  $status = Invoke-Docker @('compose', 'exec', '-T', 'tailscale', 'tailscale', 'status', '--json')
  if ($status.Code -eq 0 -and $status.Out) {
    $json = $null
    try { $json = $status.Out | ConvertFrom-Json } catch { $json = $null }
    if ($json -and $json.BackendState -eq 'Running' -and $json.Self.DNSName) { $Name = $json.Self.DNSName.TrimEnd('.'); break }
  }
  Write-Host -NoNewline '.'
  Start-Sleep -Seconds 2
}
Say ''
if (-not $Name) {
  Say 'Here is what Tailscale said last:'
  Invoke-DockerLive @('compose', 'logs', '--tail', '30', 'tailscale') | Out-Null
  Fail "Tailscale didn't connect within a minute. The auth key may be wrong, expired or already used: make a new one, delete the TS_AUTHKEY value in $EnvFile, and run setup.ps1 -Share again."
}

$Public = "https://$Name"
Set-EnvValue 'PUBLIC_URL' $Public
Say 'Restarting Brushfall with its public address...'
if ((Invoke-DockerLive @('compose', 'up', '-d')) -ne 0) { Fail "Docker couldn't restart Brushfall (the message above says why)." }
Wait-ForHealth

Say ''
Say '+--------------------------------------------------------------+'
Say '  Family anywhere can now join at:'
Say "  $Public"
Say ''
Say '  The very first visit can take a minute while Tailscale makes'
Say '  the https certificate. Keep sign-ups on approval or invite.'
Say '+--------------------------------------------------------------+'
