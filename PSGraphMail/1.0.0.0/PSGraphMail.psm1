<#
    .NOTES
    --------------------------------------------------------------------------------
     Code generated by:  SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.241 (L)
     Generated on:       11/8/2024 2:09 PM
     Generated by:       npeltier
    --------------------------------------------------------------------------------
    .DESCRIPTION
        Script generated by PowerShell Studio 2024
#>


	<#	
		===========================================================================
		 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2024 v5.8.241
		 Created on:   	11/8/2024 11:46 AM
		 Created by:   	npeltier
		 Organization: 	
		 Filename:     	PSGraphMail.psm1
		-------------------------------------------------------------------------
		 Module Name: PSGraphMail
		===========================================================================
	#>
	
	function New-GraphMailAttachement {
	    param (
	        $FilePath,
	        $FileType
	    )
	    $FilePath = (Resolve-Path $FilePath).Path
	    $FileName = Split-Path $FilePath -Leaf
	    $FileMIMEType = Get-FileMimeType -Path $FilePath
	    if (!$FileMIMEType) {
	        $FileMIMEType = "text/plain"
	    }
	    $FileBytesToBase64 = [convert]::ToBase64String(([IO.File]::ReadAllBytes($FilePath)))
	    return @{
	        '@odata.type' = '#microsoft.graph.fileAttachment'
	        name          = $FileName
	        contentType   = $FileMIMEType
	        contentBytes  = $FileBytesToBase64
	    }
	}
	
	function New-GraphMailRecipient {
	    param (
	        $Address
	    )
	    return @{
	        EmailAddress = @{
	            Address = $Address
	        }
	    }
	}
	
	function New-GraphMailBody {
	    param (
	        $Content,
	        $ContentType
	    )
	    return @{
	        ContentType = $ContentType
	        Content     = $Content
	    }
	}
	
	function Send-GraphMailMessage {
	    param (
	        $Subject,
	        $Body,
	        $From,
	        [string[]]$To,
	        $Attachments,
	        [switch]$BodyAsHTML
	    )
	    if (!((Get-MgContext).Account)) {
	        Write-Host "Please use Connect-MgGraph before trying to send mail." -ForegroundColor Yellow
	        return
	    }
	    $Message = @{
	    }
	    $BodyContentType = switch ($BodyAsHTML) {
	        $true {
	            "HTML"
	        }
	        default {
	            "Text"
	        }
	    }
	    $Recipients = foreach ($Address in $To) {
	        New-GraphMailRecipient -Address $Address
	    }
	    $Attachments = foreach ($file in $Attachments) {
	        New-GraphMailAttachement -FilePath $File
	    }
	    $Body = New-GraphMailBody -Content $Body -ContentType $BodyContentType
		
	    $Message.Add("Subject", $Subject)
	    $Message.Add("Body", $Body)
	    $Message.Add("ToRecipients", @($Recipients))
	    if ($Attachments) {
	        $Message.Add("Attachments", @($Attachments))
	    }
	    $MailParams = @{
	        Message = $Message
	    }
	    if (!$From) {
	        $From = (Get-MgContext).Account
	    }
	    Send-MgUserMail -BodyParameter $MailParams -UserId $From
		
	    return $MailParams
	}
	
	function Get-FileMimeType {
	    param ($Path)
	    New-PSDrive -Name HKCR -PSProvider Registry -Root HKEY_CLASSES_ROOT | Out-Null
		(Get-ItemProperty "HKCR:$((get-item $Path).Extension)" -Name "Content type")."Content Type"
	}
	
	function Get-MGMailFolderFromPath {
	    param(
	        [string]$Path,
	        [switch]$ShowChildren
	    )
		
		# Split the path into segments
		if ($Path -notmatch "\\" -or $Path -notlike "*@*") {
			$Path = $Path -replace "^","$((get-mgcontext).Account)\"
		}
	    $Segments = $Path -split '\\'
	
	    # Extract the User ID and the folder path
	    $UserId = $Segments[0]
	    $FolderPath = $Segments | Select-Object -Skip 1
	    
	    # Start with the root folder (msgfolderroot)
	    $CurrentFolder = Get-MgUserMailFolder -UserId $UserId -MailFolderId "msgfolderroot"
		
		# Traverse the folder hierarchy
		if ($Path) {
			foreach ($FolderName in $FolderPath) {
				# Get child folders of the current folder
				$ChildFolders = Get-MgUserMailFolderChildFolder -UserId $UserId -MailFolderId $CurrentFolder.Id
				
				# Find the next folder in the path
				$NextFolder = $ChildFolders | Where-Object {
					$_.DisplayName -eq $FolderName
				}
				
				if ($NextFolder) {
					# Move to the next folder
					$CurrentFolder = $NextFolder
				}
				else {
					Write-Error "Folder '$FolderName' not found under '$($CurrentFolder.DisplayName)'."
					return
				}
			}
		}
		elseif ($Path -notmatch "\\") {
			Get-MgUserMailFolder -UserId $Path
		}
		
		# Add a member for the UserID so we can pipe this to the Get-MailFolderMessages function
	    $CurrentFolder | Add-Member -MemberType NoteProperty -Name UserID -Value $UserId
	
	    # Return the final folder or its children
	    if ($ShowChildren) {
	        return Get-MgUserMailFolderChildFolder -UserId $UserId -MailFolderId $CurrentFolder.Id
	    }
	    else {
	        return $CurrentFolder
	    }
	}
	
	function Get-MailFolderMessages {
	    param(
	        [Parameter(ValueFromPipelineByPropertyName)]
	        $Id,
	        [Parameter(ValueFromPipelineByPropertyName)]
	        $UserID,
	        [switch]$New,
	        [switch]$Silent,
	        [switch]$NoSetTime
	    )
	    try {
	        $LastCheckTime = Get-LastMailCheckTime -VariableName $Id
	    }
	    catch {
	        $LastCheckTime = $null
	    }
	    $Messages = Get-MgUserMailFolderMessage -MailFolderId $Id -UserId $userID | ConvertFrom-MGMailMessage | Sort-Object -Property receiveddatetime -Descending
	    if ($New -and $LastCheckTime) {
	        if (!$silent) {
	            Write-Host "New-Messages since $LastCheckTime" -ForegroundColor Green
	        }
	        Write-Output ($Messages | Where-Object { $_.ReceivedDateTime -gt (get-date $LastCheckTime) })
	    }
	    else {
	        Write-Output $Messages
	    }
	    if (!$NoSetTime) {
	        Set-LastMailCheckTime -VariableName $Id
	    }
	
	}
	
	function Convert-HTMLToPlainText {
	    param(
	        [Parameter(ValueFromPipeline)]
	        $HTML,
	        [switch]$Pretty
	    )
	
	    # Replace some tags with a space and normalize whitespace
	    $PlainText = $HTML `
	        -replace "(</?(td|tr|p.*?|strong)>|<br>)|&nbsp;", " " `
	        -replace "<[^>]+>", "" `
	        -replace "\s+,\s+", ", " `
	        -replace "\s+", " " `
	        -replace '&quot;', '"' `
	        -replace "&lt;", "<" `
	        -replace "&gt;", ">"
	
	    # More complext replacing of tables, spans, and font tags to match it's original intended format
	    if ($Pretty) {
	        $PlainText = $HTML `
	            -replace "<p.*?>|<tr.*?>|<br>", "`n"`
	            -replace "</td><td>", ": " `
	            -replace "<li>", "* " `
	            -replace "(</?(td|tr|p.*?|strong)>|<br>)" `
	            -replace '&quot;', '"' `
	            -replace "<[^>]+>" `
	            -replace '(?s).*Protection by INKY' `
	            -replace "\s+,\s+", ", " `
	            -replace "^\s+" `
	            -replace "&lt;", "<" `
	            -replace "&gt;", ">" `
	            -replace "(\r?\n){4,}", "`n" `
	            -replace "&nbsp;", ""
	    }
	
	    return $PlainText
	}
	
	function ConvertFrom-MGMailMessage {
	    param(
	        [Parameter(ValueFromPipeline)]
	        $Message,
	        [Switch]$AsJson
	    )
	    PROCESS {
	        $Attachment = $Message.Attachments
	        $Object = [pscustomObject]@{
	            subject          = $Message.Subject
	            from             = $Message.From.EmailAddress.Address
	            to               = $Message.ToRecipients[0].EmailAddress.Address
	            sentDateTime     = $Message.SentDateTime
	            ReceivedDateTime = $message.ReceivedDateTime.ToLocalTime()
	            body             = [pscustomObject]@{
	                html        = $Message.Body.Content
	                bodyPreview = $Message.BodyPreview
	                plainText   = ($Message.Body.Content | Convert-HTMLToPlainText -Pretty)
	            }
	            
	            attachments      = [pscustomObject]@{
	                contentType  = $Attachment.ContentType
	                name         = $Attachment.Name
	                contentBytes = $Attachment.contentBytes
	            }
	            messageId        = $Message.Id
	            parentFolderId   = $MEssage.ParentFdlderId
	        }
	        Set-PSObjectDefaultProperties $Object @("Subject", "receiveddatetime")
	        if ($AsJson) {
	            return $Object | convertto-Json -Depth 20
	        }
	        else {
	            return $object
	        }
	    }
	}
	
	function Set-PSObjectDefaultProperties {
	    param(
	        [PSObject]$Object,
	        [string[]]$DefaultProperties
	    )
	    
	    $name = $Object.PSObject.TypeNames[0]     
	    
	    $xml = "<?xml version='1.0' encoding='utf-8' ?><Types><Type>"
	    
	    $xml += "<Name>$($name)</Name>"
	    
	    $xml += "<Members><MemberSet><Name>PSStandardMembers</Name><Members>"
	    
	    $xml += "<PropertySet><Name>DefaultDisplayPropertySet</Name><ReferencedProperties>"
	    
	    foreach ( $default in $DefaultProperties ) {
	        $xml += "<Name>$($default)</Name>"
	    }
	    
	    $xml += "</ReferencedProperties></PropertySet></Members></MemberSet></Members>"
	    
	    $xml += "</Type></Types>"
	    
	    $file = "$($env:Temp)\$name.ps1xml"
	    
	    Out-File -FilePath $file -Encoding "UTF8" -InputObject $xml -Force
	    
	    $typeLoaded = $host.Runspace.RunspaceConfiguration.Types | where { $_.FileName -eq $file }
	    
	    if ( $typeLoaded -ne $null ) {
	        Write-Verbose "Type Loaded"
	        Update-TypeData
	    }
	    else {
	        Update-TypeData $file
	    }
	}
	
	function Set-LastMailCheckTime {
	    param(
	        $VariableName = 'MGMailLastCheckTime'
	    )
	    $VariableName = $VariableName -replace '[^a-zA-Z0-9\s]'
	    [System.Environment]::SetEnvironmentVariable($VariableName, ((get-date).ToString()), [System.EnvironmentVariableTarget]::Machine)
	}
	
	function Get-LastMailCheckTime {
	    param(
	        $VariableName = 'MGMailLastCheckTime'
	    )
	    $VariableName = $VariableName -replace '[^a-zA-Z0-9\s]'
	    [System.Environment]::GetEnvironmentVariable($VariableName, "Machine")
	}
	
	
	