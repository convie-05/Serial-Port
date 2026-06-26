$repoName = 'SerialAssistant-Custom'
$clientId = '178c6fc778ccc68e1d6a'

Write-Host '========================================' -ForegroundColor Cyan
Write-Host '  GitHub Push Script' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan
Write-Host ''

# Step 1: Get device code
Write-Host '[1/5] Getting GitHub device code...' -ForegroundColor Yellow
$wc = New-Object System.Net.WebClient
$wc.Headers.Add('Content-Type', 'application/x-www-form-urlencoded')
$body1 = [System.Text.Encoding]::UTF8.GetBytes("client_id=$clientId&scope=repo")
$resp1 = $wc.UploadData('https://github.com/login/device/code', 'POST', $body1)
$curlResp = [System.Text.Encoding]::UTF8.GetString($resp1)
Write-Host "  Response: $curlResp" -ForegroundColor Gray

$deviceCode = ''
$userCode = ''
$verificationUri = ''
$interval = 5

foreach ($line in $curlResp -split '&') {
    $parts = $line -split '=', 2
    if ($parts.Length -eq 2) {
        $key = $parts[0]
        $value = [uri]::UnescapeDataString($parts[1])
        switch ($key) {
            'device_code' { $deviceCode = $value }
            'user_code' { $userCode = $value }
            'verification_uri' { $verificationUri = $value }
            'interval' { $interval = [int]$value }
        }
    }
}

if (-not $deviceCode) {
    Write-Host 'Failed to get device code.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Please authorize in your browser:' -ForegroundColor Green
Write-Host ''
Write-Host "  Device Code: $userCode" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ''
Write-Host "  URL: $verificationUri" -ForegroundColor Cyan
Write-Host ''

Start-Process $verificationUri

# Step 2: Poll for token
Write-Host '[2/5] Waiting for authorization...' -ForegroundColor Yellow
$token = $null
$maxAttempts = 60
for ($i = 0; $i -lt $maxAttempts; $i++) {
    Start-Sleep -Seconds $interval
    $wc2 = New-Object System.Net.WebClient
    $wc2.Headers.Add('Accept', 'application/json')
    $wc2.Headers.Add('Content-Type', 'application/x-www-form-urlencoded')
    $body2 = [System.Text.Encoding]::UTF8.GetBytes("client_id=$clientId&device_code=$deviceCode&grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code")
    $resp2 = $wc2.UploadData('https://github.com/login/oauth/access_token', 'POST', $body2)
    $tokenResp = [System.Text.Encoding]::UTF8.GetString($resp2)

    if ($tokenResp -like '*access_token*') {
        $json = $tokenResp | ConvertFrom-Json
        if ($json.access_token) {
            $token = $json.access_token
            Write-Host '  Authorized!' -ForegroundColor Green
            break
        }
    }
    elseif ($tokenResp -like '*authorization_pending*') {
        Write-Host "  Waiting... ($i/$maxAttempts)" -ForegroundColor Gray
    }
    elseif ($tokenResp -like '*slow_down*') {
        $json = $tokenResp | ConvertFrom-Json
        $interval = $json.interval + 1
        Write-Host '  Slowing down...' -ForegroundColor Gray
    }
    else {
        Write-Host "  Error: $tokenResp" -ForegroundColor Red
    }
}

if (-not $token) {
    Write-Host 'Authorization timeout.' -ForegroundColor Red
    exit 1
}

# Step 3: Get username
Write-Host ''
Write-Host '[3/5] Getting user info...' -ForegroundColor Yellow
$wc3 = New-Object System.Net.WebClient
$wc3.Headers.Add('Authorization', "token $token")
$resp3 = $wc3.DownloadData('https://api.github.com/user')
$userJson = [System.Text.Encoding]::UTF8.GetString($resp3)
$user = $userJson | ConvertFrom-Json
$username = $user.login
Write-Host "  Username: $username" -ForegroundColor Green

# Step 4: Create repo
Write-Host ''
Write-Host "[4/5] Creating repo '$repoName'..." -ForegroundColor Yellow
$repoBody = @{ name = $repoName; description = 'Serial Assistant Custom'; private = $false; auto_init = $false } | ConvertTo-Json
$wc4 = New-Object System.Net.WebClient
$wc4.Headers.Add('Authorization', "token $token")
$wc4.Headers.Add('Content-Type', 'application/json')
$wc4.Encoding = [System.Text.Encoding]::UTF8
try {
    $resp4 = $wc4.UploadString('https://api.github.com/user/repos', 'POST', $repoBody)
    $repo = $resp4 | ConvertFrom-Json
    Write-Host '  Repo created!' -ForegroundColor Green
    Write-Host "  URL: $($repo.html_url)" -ForegroundColor Cyan
}
catch [System.Net.WebException] {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 422) {
        Write-Host '  Repo already exists, using existing.' -ForegroundColor Yellow
    }
    else {
        Write-Host "  Failed (HTTP $status)" -ForegroundColor Red
        exit 1
    }
}

# Step 5: Push
Write-Host ''
Write-Host '[5/5] Pushing code to GitHub...' -ForegroundColor Yellow
$repoUrl = "https://$token@github.com/$username/$repoName.git"
$projectPath = 'c:\Users\HP\Desktop\UI界面设置\SerialAssistant'

Push-Location $projectPath
git remote remove origin 2>$null
git remote add origin $repoUrl
git branch -M main 2>$null
git push -u origin main --force
Pop-Location

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host '  Done!' -ForegroundColor Green
Write-Host "  https://github.com/$username/$repoName" -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Green
