# DESCRIPTION: Display the current date and time in UTC

Write-Host (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') UTC
