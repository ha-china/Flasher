#先在管理员下执行下面这句命令，否则会报错
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser


# 加载 Windows Forms 程序集
Add-Type -AssemblyName System.Windows.Forms

# 检查管理员权限
Function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# 如果不是管理员权限，重新以管理员权限运行脚本
if (-not (Test-Admin)) {
    [System.Windows.Forms.MessageBox]::Show("脚本需要以管理员权限运行。现在将以管理员权限重新启动。", "权限不足", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

# 弹出内存选择对话框
Function Select-MemorySize {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "选择内存大小 (MB)"
    $form.Width = 300
    $form.Height = 200
    $form.StartPosition = "CenterScreen"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "请输入虚拟机内存大小 (默认 2048 MB):"
    $label.AutoSize = $true
    $label.Top = 20
    $label.Left = 20
    $form.Controls.Add($label)

    $textBox = New-Object System.Windows.Forms.TextBox
    $textBox.Text = "2048"
    $textBox.Width = 100
    $textBox.Top = 50
    $textBox.Left = 20
    $form.Controls.Add($textBox)

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "确定"
    $okButton.Top = 90
    $okButton.Left = 20
    $okButton.Add_Click({ 
        $form.Tag = $textBox.Text
        $form.Close()
    })
    $form.Controls.Add($okButton)

    $form.ShowDialog() | Out-Null
    return $form.Tag
}

# 获取用户选择的内存大小
$vmMemoryInput = Select-MemorySize
if (-not [int]::TryParse($vmMemoryInput, [ref]$null) -or [int]$vmMemoryInput -le 2048) {
    Write-Host "无效的内存输入，使用默认值 2048 MB。" -ForegroundColor Yellow
    $vmMemory = 2048
} else {
    $vmMemory = [int]$vmMemoryInput
}

Write-Host "用户选择的内存大小为 $vmMemory MB。"

# Step 1: 检查并安装 Hyper-V 功能
Write-Host "检查并安装 Hyper-V 功能..."
$featureName = "Microsoft-Hyper-V-All"

# 检查 Hyper-V 是否已启用
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
if ($hyperVFeature.State -ne "Enabled") {
    Write-Host "Hyper-V 未启用，正在启用..."
    Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
    Write-Host "Hyper-V 已启用，请重启系统以生效。"
    exit
} else {
    Write-Host "Hyper-V 已启用。"
}

# Step 2: 下载 Home Assistant OS 镜像（使用多线程下载加速）
Write-Host "正在下载 Home Assistant OS 镜像... (多线程加速下载中，请耐心等待。。。)"

$urls = @(
    "https://github.com/home-assistant/operating-system/releases/download/14.1/haos_ova-14.1.vhdx.zip"
)

$downloadDir = "C:\HyperV\HomeAssistant"

# 创建下载目录（如果不存在的话）
if (!(Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
}

# 定义下载任务
$jobs = @()

# 启动多个下载任务
foreach ($url in $urls) {
    $outputPath = Join-Path $downloadDir (Split-Path $url -Leaf)

    $jobs += Start-Job -ScriptBlock {
        param ($url, $outputPath)
        
        try {
            Write-Host "正在下载: $url"
            Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
            Write-Host "下载完成: $outputPath"
        } catch {
            Write-Host "下载失败: $url"
        }
    } -ArgumentList $url, $outputPath
}

# 等待所有下载任务完成
$jobs | ForEach-Object {
    Wait-Job -Job $_
    Remove-Job -Job $_
}

Write-Host "所有文件下载完成。"

# Step 3: 解压缩镜像文件
Write-Host "正在解压缩 Home Assistant OS 镜像..."
$extractPath = "C:\HyperV\HomeAssistant"
Expand-Archive -Path "$downloadDir\haos_ova-14.1.vhdx.zip" -DestinationPath $extractPath -Force
$vhdxFile = Get-ChildItem -Path $extractPath -Filter "*.vhdx" | Select-Object -ExpandProperty FullName
Write-Host "镜像文件已解压到: $vhdxFile"

# Step 4: 检查并创建虚拟交换机
Write-Host "检查虚拟交换机..."
$vmSwitch = "HomeAssistantSwitch"

if (!(Get-VMSwitch -Name $vmSwitch -ErrorAction SilentlyContinue)) {
    Write-Host "未找到默认交换机，正在创建新虚拟交换机..."
    New-VMSwitch -Name $vmSwitch -SwitchType Internal | Out-Null
    Write-Host "已创建新虚拟交换机: $vmSwitch"
} else {
    Write-Host "默认交换机已存在: $vmSwitch"
}
Start-Process "virtmgmt.msc"
[System.Windows.Forms.MessageBox]::Show("需要将虚拟交换机 $vmSwitch 设置为外部，设置完毕之后再点确定。切记切记切记，否则电脑端无法访问，修改完之后不需要关门Hyper-V界面", "修改交换机", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
# Step 5: 创建 Hyper-V 虚拟机并导入镜像
Write-Host "创建 Hyper-V 虚拟机..."

$vmName = "HomeAssistant"
$memoryInBytes = $vmMemory * 1MB

# 创建虚拟机（不启动）
New-VM -Name $vmName -MemoryStartupBytes $memoryInBytes -SwitchName $vmSwitch -Generation 2 -Path "C:\HyperV\$vmName" | Out-Null
Set-VMProcessor -VMName $vmName -Count 4

# 检查虚拟机是否成功创建
$vmExists = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vmExists) {
    Write-Host "虚拟机 '$vmName' 创建成功。"

    # 获取 SCSI 控制器
    $scsiController = Get-VMScsiController -VMName $vmName

    # 检查 SCSI 控制器是否成功创建
    if ($scsiController -and $scsiController.ControllerNumber -ne $null) {
        # 连接硬盘到 SCSI 控制器
        
        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber $scsiController.ControllerNumber -ControllerLocation 0 -Path $vhdxFile | Out-Null

        # 设置启动顺序为硬盘
        Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMHardDiskDrive -VMName $vmName) | Out-Null

        Write-Host "虚拟机 '$vmName' 已成功创建并配置完成，尚未启动。"
    } else {
        Write-Host "SCSI 控制器创建失败，请检查错误。"

    }
} else {
    Write-Host "虚拟机 '$vmName' 创建失败，请检查错误。"

}

Write-Host "完成！可以通过 Hyper-V 管理器查看虚拟机状态。"


Start-VM -Name '$vmName'
Start-Process -FilePath "vmconnect.exe" -ArgumentList "localhost", "HomeAssistant"
