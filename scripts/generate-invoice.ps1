#Requires -Version 5.1
<#
.SYNOPSIS
    AIKit Pro — Invoice Generator
.DESCRIPTION
    Generates a clean HTML invoice for a subscriber and opens it in the browser.
    Print to PDF from there (Ctrl+P → Save as PDF).

.EXAMPLE
    .\generate-invoice.ps1 -Name "John Smith" -Email "john@example.com" -Plan annual
    .\generate-invoice.ps1 -Name "Jane Doe"   -Email "jane@example.com" -Plan monthly
#>

param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Email,
    [Parameter(Mandatory)][ValidateSet("monthly","annual")][string]$Plan
)

# ── Config ────────────────────────────────────────────────────────────────────
$SellerName    = "OriginForge"
$SellerEmail   = "hello@aikit.originforge.net"
$SellerAddress = ""   # optional: fill in your address
$VATNumber     = ""   # optional: fill in if applicable

$Prices = @{ monthly = "€19.00"; annual = "€159.00" }
$Descs  = @{ monthly = "AIKit Pro — Monthly Subscription"; annual = "AIKit Pro — Annual Subscription" }

$InvoiceDate   = Get-Date -Format "yyyy-MM-dd"
$InvoiceNumber = "AK-" + (Get-Date -Format "yyyyMMdd") + "-" + (Get-Random -Maximum 9999).ToString("D4")
$Amount        = $Prices[$Plan]
$Description   = $Descs[$Plan]

# ── HTML ─────────────────────────────────────────────────────────────────────
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Invoice $InvoiceNumber</title>
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: 'Segoe UI', system-ui, sans-serif; background: #f5f2ec; color: #1a1108; padding: 48px; }
  .page { max-width: 680px; margin: 0 auto; background: #fff; border-radius: 8px; padding: 56px; box-shadow: 0 4px 24px rgba(0,0,0,0.08); }
  .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 48px; }
  .logo { font-size: 22px; font-weight: 700; color: #1a1108; letter-spacing: -0.03em; }
  .logo span { color: #B5722A; }
  .invoice-meta { text-align: right; }
  .invoice-meta h1 { font-size: 13px; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: #B5722A; margin-bottom: 8px; }
  .invoice-meta p { font-size: 13px; color: #7a6a54; line-height: 1.7; }
  .invoice-meta strong { color: #1a1108; }
  .divider { border: none; border-top: 1px solid #e4ded5; margin: 32px 0; }
  .parties { display: grid; grid-template-columns: 1fr 1fr; gap: 32px; margin-bottom: 40px; }
  .party h2 { font-size: 10px; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; color: #a8947a; margin-bottom: 10px; }
  .party p { font-size: 14px; color: #3d2e18; line-height: 1.7; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 32px; }
  th { font-size: 10px; font-weight: 600; letter-spacing: 0.1em; text-transform: uppercase; color: #a8947a; text-align: left; padding: 8px 0; border-bottom: 1px solid #e4ded5; }
  th:last-child, td:last-child { text-align: right; }
  td { font-size: 14px; padding: 16px 0; border-bottom: 1px solid #f0ede8; color: #3d2e18; }
  .total-row td { font-weight: 700; font-size: 16px; color: #1a1108; border-bottom: none; padding-top: 20px; }
  .status { display: inline-block; background: #dcfce7; color: #166534; font-size: 11px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; padding: 4px 10px; border-radius: 100px; margin-top: 4px; }
  .footer { margin-top: 48px; font-size: 12px; color: #a8947a; text-align: center; line-height: 1.8; }
  @media print { body { background: none; padding: 0; } .page { box-shadow: none; border-radius: 0; } }
</style>
</head>
<body>
<div class="page">
  <div class="header">
    <div class="logo">AIKit<span> Pro</span></div>
    <div class="invoice-meta">
      <h1>Invoice</h1>
      <p><strong>$InvoiceNumber</strong></p>
      <p>Date: $InvoiceDate</p>
      <p><span class="status">Paid</span></p>
    </div>
  </div>

  <div class="parties">
    <div class="party">
      <h2>From</h2>
      <p><strong>$SellerName</strong><br>
      $SellerEmail
      $(if ($SellerAddress) { "<br>$SellerAddress" })
      $(if ($VATNumber) { "<br>VAT: $VATNumber" })
      </p>
    </div>
    <div class="party">
      <h2>Bill To</h2>
      <p><strong>$Name</strong><br>$Email</p>
    </div>
  </div>

  <hr class="divider">

  <table>
    <thead>
      <tr><th>Description</th><th>Amount</th></tr>
    </thead>
    <tbody>
      <tr><td>$Description</td><td>$Amount</td></tr>
      <tr class="total-row"><td>Total</td><td>$Amount</td></tr>
    </tbody>
  </table>

  <hr class="divider">

  <div class="footer">
    Payment received via SEPA Direct Debit &nbsp;·&nbsp; Thank you for subscribing to AIKit Pro<br>
    $SellerEmail &nbsp;·&nbsp; aikit.originforge.net
  </div>
</div>
</body>
</html>
"@

# ── Output ────────────────────────────────────────────────────────────────────
$OutDir  = Join-Path $PSScriptRoot "..\invoices"
New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutFile = Join-Path $OutDir "$InvoiceNumber.html"
$html | Set-Content -Path $OutFile -Encoding UTF8

Write-Host "✓ Invoice: $OutFile"
Write-Host "  → Open in browser and Ctrl+P → Save as PDF to send to $Email"
Start-Process $OutFile
