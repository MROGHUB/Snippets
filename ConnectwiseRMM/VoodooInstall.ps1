    Write-Host "Running Voodoo Install..." -ForegroundColor Green
    $Dir = "C:\Temp\"

    function CreateDirectory {
        if (-not (Test-Path -Path $Dir -PathType Container)) {
            New-Item -ItemType Directory -Path $Dir -Force -ErrorAction Stop
            Write-Host "Path Creation Completed"
        } else {
            Write-Host "Path already exists"
        }
    }

    function DownloadFile {
        $URI = Read-Host "Enter the URI of the file to download"
        $FileName = [regex]::Match($URI, "(?<=/)[^/]*(?=/MSI/setup)").Value.Replace("%20", " ")
        $FileName += ".msi"
        $FilePath = Join-Path -Path $Dir -ChildPath $FileName

        if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
            try {
                Invoke-WebRequest -Uri $URI -OutFile $FilePath -ErrorAction Stop
                Write-Host "[$FilePath] Created"
            } catch {
                Write-Host "Failed to download the file from the specified URI"
                return
            }
        } else {
            Write-Host "[$FilePath] already exists"
        }

        InstallFile -FilePath $FilePath
    }

    function InstallFile {
        param([string]$FilePath)

        if (Test-Path -Path $FilePath -PathType Leaf) {
            try {
                $msiPackageToInstall = $FilePath
                $tmpFile = [System.IO.Path]::GetTempFileName()
                Start-Process msiexec -ArgumentList "/i `"$msiPackageToInstall`" /qn /L*v `"$tmpFile`"" -NoNewWindow -Wait
                Write-Host "[$FilePath] installed successfully"
            } catch {
                Write-Host "Failed to install the file"
            }
        } else {
            Write-Host "File [$FilePath] does not exist"
        }
    }

    # Run CreateDirectory, then DownloadFile, then InstallFile functions
    CreateDirectory
    DownloadFile

    Start-Sleep -Seconds 2
    Write-Host "Install completed." -ForegroundColor Green