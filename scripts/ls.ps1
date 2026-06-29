# DESCRIPTION: List directory contents (Get-ChildItem wrapper for CMD)

param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$PassThrough
)

Get-ChildItem @PassThrough
