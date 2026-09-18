# package-web-deploy.ps1 — 构建并打包 Web 静态站点，便于上传服务器
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File scripts\package-web-deploy.ps1
#
# 产出:
#   dist\china-study-free-web.zip  （解压后即为站点根目录，可直接给 nginx/cdn）

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $PSScriptRoot
$WebDir = Join-Path $RootDir "apps\web"
$PublicDir = Join-Path $WebDir "public"
$OutDir = Join-Path $WebDir "out"
$DistDir = Join-Path $RootDir "dist"
$ZipPath = Join-Path $DistDir "china-study-free-web.zip"

$HeavyDirs = @("audio", "story-images", "textbook-pages")
$SkipSuffix = ".__build_skip__"

function Move-HeavyAssets([string]$Action) {
  foreach ($name in $HeavyDirs) {
    $normal = Join-Path $PublicDir $name
    $skipped = Join-Path $PublicDir ($name + $SkipSuffix)
    if ($Action -eq "hide") {
      if ((Test-Path $normal) -and -not (Test-Path $skipped)) {
        Rename-Item $normal ($name + $SkipSuffix)
        Write-Host "  暂移出构建: $name"
      }
    } elseif ($Action -eq "restore") {
      if ((Test-Path $skipped) -and -not (Test-Path $normal)) {
        Rename-Item $skipped $name
        Write-Host "  已恢复: $name"
      }
    }
  }
}

function Copy-HeavyAssetsToOut {
  foreach ($name in $HeavyDirs) {
    $src = Join-Path $PublicDir $name
    if (-not (Test-Path $src)) {
      $alt = Join-Path $PublicDir ($name + $SkipSuffix)
      if (Test-Path $alt) { $src = $alt }
    }
    if (-not (Test-Path $src)) {
      Write-Host "  跳过缺失资源: $name" -ForegroundColor Yellow
      continue
    }
    $dest = Join-Path $OutDir $name
    Write-Host "  复制 $name → out/ ..."
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    # robocopy 对海量小文件更快
    & robocopy $src $dest /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
    if ($LASTEXITCODE -ge 8) {
      throw "robocopy 失败: $name (code $LASTEXITCODE)"
    }
  }
}

Write-Host "=== ChinaStudyFree Web 部署打包 ===" -ForegroundColor Cyan
Write-Host "Web: $WebDir"

$nodeVer = (node -v)
Write-Host "Node: $nodeVer"
if ($nodeVer -notmatch '^v(20|22|24)\.') {
  Write-Host "建议使用与 node_modules 一致的 Node 20+/24（当前已安装的 SWC 二进制需匹配）" -ForegroundColor Yellow
}

Push-Location $WebDir
try {
  Write-Host ""
  Write-Host "--- 1/4 生成 data ---" -ForegroundColor Cyan
  npm run build:data

  Write-Host ""
  Write-Host "--- 2/4 暂移大型静态资源后执行 next build ---" -ForegroundColor Cyan
  Move-HeavyAssets "hide"
  try {
    if (Test-Path $OutDir) { Remove-Item $OutDir -Recurse -Force }
    if (Test-Path (Join-Path $WebDir ".next")) { Remove-Item (Join-Path $WebDir ".next") -Recurse -Force }
    $env:NODE_OPTIONS = "--max-old-space-size=8192"
    npx next build
  } finally {
    Move-HeavyAssets "restore"
  }

  if (-not (Test-Path $OutDir)) {
    throw "构建未产出 out/ 目录"
  }

  Write-Host ""
  Write-Host "--- 3/4 把音频/配图/课本页拷入 out/ ---" -ForegroundColor Cyan
  Copy-HeavyAssetsToOut

  Write-Host ""
  Write-Host "--- 4/4 打 zip ---" -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
  if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

  # Compress-Archive 对超大目录很慢且易崩；优先 tar.gz，再退回 zip
  $TarPath = Join-Path $DistDir "china-study-free-web.tar.gz"
  if (Test-Path $TarPath) { Remove-Item $TarPath -Force }
  Write-Host "  打包 tar.gz（推荐上传）..."
  tar -czf $TarPath -C $OutDir .
  $tarSize = [math]::Round((Get-Item $TarPath).Length / 1MB, 1)
  Write-Host "  完成: $TarPath ($tarSize MB)" -ForegroundColor Green

  Write-Host ""
  Write-Host "=== 部署说明 ===" -ForegroundColor Green
  Write-Host "1. 上传 dist\china-study-free-web.tar.gz 到服务器"
  Write-Host "2. 解压到站点根目录，例如:"
  Write-Host "     mkdir -p /var/www/china-study && tar -xzf china-study-free-web.tar.gz -C /var/www/china-study"
  Write-Host "3. Nginx 示例:"
  Write-Host @'
     server {
       listen 80;
       server_name your.domain;
       root /var/www/china-study;
       index index.html;
       location / {
         try_files $uri $uri/ $uri/index.html =404;
       }
       # 音频/图片可长期缓存
       location ~* \.(opus|jpg|jpeg|png|svg|js|css|woff2)$ {
         expires 30d;
         add_header Cache-Control "public, immutable";
       }
     }
'@
} finally {
  Pop-Location
  # 确保异常时也恢复资源目录
  Move-HeavyAssets "restore"
}
