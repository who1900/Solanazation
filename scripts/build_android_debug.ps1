param(
    [string]$GodotPath = $env:SOLANAZATION_GODOT,
    [string]$JavaHome = $env:SOLANAZATION_JAVA_HOME,
    [string]$AndroidSdk = $env:SOLANAZATION_ANDROID_SDK
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $GodotPath) {
    $GodotPath = "C:\temp\DEEP\tools\godot\Godot_v4.4.1-stable_win64_console.exe"
}
if (-not $JavaHome) {
    $JavaHome = "C:\Program Files\Eclipse Adoptium\jdk-17.0.16.8-hotspot"
}
if (-not $AndroidSdk) {
    $AndroidSdk = Join-Path $env:USERPROFILE "AppData\Local\Android\Sdk"
}

$isolatedRoot = Join-Path $projectRoot ".local-tooling"
$appData = Join-Path $isolatedRoot "appdata"
$templateDir = Join-Path $appData "Godot\export_templates\4.4.1.stable"
$debugTemplate = Join-Path $templateDir "android_debug.apk"
$releaseTemplate = Join-Path $templateDir "android_release.apk"
$templateVersion = Join-Path $templateDir "version.txt"
$apk = Join-Path $projectRoot "build\android\solanazation-debug.apk"
$java = Join-Path $JavaHome "bin\java.exe"
$keytool = Join-Path $JavaHome "bin\keytool.exe"
$platformJar = Join-Path $AndroidSdk "platforms\android-34\android.jar"
$buildTools = Join-Path $AndroidSdk "build-tools\34.0.0"
$aapt = Join-Path $buildTools "aapt.exe"
$apksigner = Join-Path $buildTools "apksigner.bat"
$zipalign = Join-Path $buildTools "zipalign.exe"
$apkanalyzer = Join-Path $AndroidSdk "cmdline-tools\latest\bin\apkanalyzer.bat"
$debugKeystore = Join-Path $appData "Godot\keystores\debug.keystore"
$debugUser = "androiddebugkey"
$debugPassword = "android"
$expectedDebugSubject = "CN=Godot, OU=Godot Engine, O=Stichting Godot, C=NL"

$expectedGodotVersion = "4.4.1.stable.official.49a5bc7b6"
$expectedDebugTemplateHash = "BB65BDE5419C25451BEC1B1131CEA984E7ECAF90AEEA7677C20D68E3B5109542"
$expectedReleaseTemplateHash = "F5E24726198704E02736DB22526E7B0D9AA69755ACCE799A6E5FA2BA62265D75"
$templateArchiveUrl = "https://godot-releases.nbg1.your-objectstorage.com/4.4.1-stable/Godot_v4.4.1-stable_export_templates.tpz"
$templateArchiveBytes = 1206040900
$templateArchiveHash = "7A8D14ADE489FD4D22F178193021FE8A876A9E51068ED4DDE26DAC3AE4C59A88"

foreach ($name in @(
    "GODOT_ANDROID_KEYSTORE_DEBUG_PATH",
    "GODOT_ANDROID_KEYSTORE_DEBUG_USER",
    "GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD",
    "GODOT_ANDROID_KEYSTORE_RELEASE_PATH",
    "GODOT_ANDROID_KEYSTORE_RELEASE_USER",
    "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD"
)) {
    Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
}

$required = @($GodotPath, $java, $keytool, $platformJar, $aapt, $apksigner, $zipalign, $apkanalyzer)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Android debug build prerequisite: $path"
    }
}

$templateProblem = $null
foreach ($path in @($debugTemplate, $releaseTemplate, $templateVersion)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $templateProblem = "missing $path"
        break
    }
}
if (-not $templateProblem -and (Get-Content -LiteralPath $templateVersion -Raw).Trim() -ne "4.4.1.stable") {
    $templateProblem = "version.txt is not 4.4.1.stable"
}
if (-not $templateProblem -and (Get-FileHash -LiteralPath $debugTemplate -Algorithm SHA256).Hash -ne $expectedDebugTemplateHash) {
    $templateProblem = "android_debug.apk SHA-256 mismatch"
}
if (-not $templateProblem -and (Get-FileHash -LiteralPath $releaseTemplate -Algorithm SHA256).Hash -ne $expectedReleaseTemplateHash) {
    $templateProblem = "android_release.apk SHA-256 mismatch"
}
if ($templateProblem) {
    throw @"
Godot 4.4.1 export templates are not provisioned correctly: $templateProblem
Download manually from the official URL (the script never auto-downloads):
$templateArchiveUrl
Expected archive bytes: $templateArchiveBytes
Expected archive SHA-256: $templateArchiveHash
Extract templates/android_debug.apk, templates/android_release.apk, and templates/version.txt into:
$templateDir
Then rerun this command.
"@
}

$godotVersion = ((& $GodotPath --version 2>&1) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $godotVersion -ne $expectedGodotVersion) {
    throw "Godot must report exactly $expectedGodotVersion; found '$godotVersion'."
}
$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$javaVersion = (& $java -version 2>&1) -join "`n"
$javaExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
if ($javaExitCode -ne 0 -or $javaVersion -notmatch 'version "17(?:\.|\")') {
    throw "Java major version 17 is required; java -version reported:`n$javaVersion"
}
$buildToolsProperties = Get-Content -LiteralPath (Join-Path $buildTools "source.properties") -Raw
if ($buildToolsProperties -notmatch '(?m)^Pkg\.Revision\s*=\s*34\.0\.0\s*$') {
    throw "Android build-tools must report exactly 34.0.0."
}
$platformProperties = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $platformJar) "source.properties") -Raw
if ($platformProperties -notmatch '(?m)^AndroidVersion\.ApiLevel\s*=\s*34\s*$') {
    throw "Android platform must report API level 34."
}

$env:APPDATA = $appData
$env:LOCALAPPDATA = Join-Path $isolatedRoot "localappdata"
$env:TEMP = Join-Path $isolatedRoot "temp"
$env:JAVA_HOME = $JavaHome
$env:ANDROID_HOME = $AndroidSdk
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH = $debugKeystore
$env:GODOT_ANDROID_KEYSTORE_DEBUG_USER = $debugUser
$env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD = $debugPassword
New-Item -ItemType Directory -Force -Path $env:TEMP, (Split-Path -Parent $debugKeystore), (Split-Path -Parent $apk) | Out-Null

if (-not (Test-Path -LiteralPath $debugKeystore -PathType Leaf)) {
    & $keytool -genkeypair -keystore $debugKeystore -storepass $debugPassword -keypass $debugPassword `
        -alias $debugUser -keyalg RSA -keysize 2048 -validity 10000 -storetype PKCS12 `
        -dname $expectedDebugSubject | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to create the isolated disposable debug keystore." }
}

$certFile = Join-Path $env:TEMP "solanazation-debug-cert.cer"
Remove-Item -LiteralPath $certFile -Force -ErrorAction SilentlyContinue
& $keytool -exportcert -keystore $debugKeystore -storepass $debugPassword -alias $debugUser -file $certFile | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $certFile -PathType Leaf)) {
    throw "The isolated debug keystore does not contain the expected '$debugUser' private-key entry."
}
$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($certFile)
try {
    if ($certificate.Subject -ne $expectedDebugSubject) {
        throw "Unexpected isolated debug certificate subject: $($certificate.Subject)"
    }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $keystoreCertHash = ([BitConverter]::ToString($sha256.ComputeHash($certificate.RawData))).Replace("-", "").ToLowerInvariant()
    } finally {
        $sha256.Dispose()
    }
} finally {
    Remove-Item -LiteralPath $certFile -Force -ErrorAction SilentlyContinue
}

Remove-Item -LiteralPath $apk -Force -ErrorAction SilentlyContinue
& $GodotPath --headless --editor --path $projectRoot --quit
if ($LASTEXITCODE -ne 0) { throw "Godot import failed with exit code $LASTEXITCODE" }
& $GodotPath --headless --path $projectRoot --export-debug "Android Debug" $apk
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $apk -PathType Leaf)) {
    throw "Godot Android export failed with exit code $LASTEXITCODE"
}

$badging = (& $aapt dump badging $apk) -join "`n"
$expectedBadging = @(
    "name='com.solanazation.game.debug'",
    "versionCode='1'",
    "versionName='0.1.0-debug'",
    "sdkVersion:'21'",
    "targetSdkVersion:'34'",
    "application-label:'Solanazation'",
    "uses-feature: name='android.hardware.screen.portrait'",
    "native-code: 'arm64-v8a'"
)
foreach ($expected in $expectedBadging) {
    if (-not $badging.Contains($expected)) {
        throw "APK badging verification failed; missing: $expected"
    }
}

$permissions = (& $aapt dump permissions $apk) -join "`n"
if ($permissions -match "uses-permission") {
    throw "Unexpected discretionary Android permission in debug APK:`n$permissions"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($apk)
try {
    $nativeLibraries = @($zip.Entries | Where-Object { $_.FullName.StartsWith("lib/") })
    if ($nativeLibraries.Count -eq 0 -or
            @($nativeLibraries | Where-Object { -not $_.FullName.StartsWith("lib/arm64-v8a/") }).Count -ne 0) {
        throw "APK must contain only arm64-v8a native libraries."
    }
} finally {
    $zip.Dispose()
}

$signerOutput = (& $apksigner verify --verbose --print-certs $apk 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "apksigner verification failed:`n$signerOutput" }
foreach ($scheme in @("v1 scheme (JAR signing): true", "v2 scheme (APK Signature Scheme v2): true", "v3 scheme (APK Signature Scheme v3): true")) {
    if (-not $signerOutput.Contains($scheme)) { throw "APK signature verification missing: $scheme" }
}
$signerMatch = [regex]::Match($signerOutput, 'Signer #1 certificate SHA-256 digest:\s*([0-9a-fA-F]+)')
if (-not $signerMatch.Success) { throw "Could not read the APK signer SHA-256 fingerprint." }
$apkCertHash = $signerMatch.Groups[1].Value.ToLowerInvariant()
if ($apkCertHash -ne $keystoreCertHash) {
    throw "APK signer does not match the isolated disposable debug keystore."
}

$item = Get-Item -LiteralPath $apk
$hash = Get-FileHash -LiteralPath $apk -Algorithm SHA256
Write-Output "Toolchain=Godot $godotVersion / Java 17 / Android SDK and build-tools 34"
Write-Output "TemplatesSHA256=debug:$expectedDebugTemplateHash release:$expectedReleaseTemplateHash"
Write-Output "DebugCertSHA256=$apkCertHash"
Write-Output "APK=$($item.FullName)"
Write-Output "Bytes=$($item.Length)"
Write-Output "SHA256=$($hash.Hash)"
Write-Output "Package=com.solanazation.game.debug"
Write-Output "Version=1 / 0.1.0-debug"
Write-Output "ABI=arm64-v8a"
Write-Output "SDK=min21 target34"
Write-Output "Permissions=none"
