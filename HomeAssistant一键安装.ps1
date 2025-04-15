#���ڹ���Ա��ִ����������������ᱨ��
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser


# ���� Windows Forms ����
Add-Type -AssemblyName System.Windows.Forms

# ������ԱȨ��
Function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# ������ǹ���ԱȨ�ޣ������Թ���ԱȨ�����нű�
if (-not (Test-Admin)) {
    [System.Windows.Forms.MessageBox]::Show("�ű���Ҫ�Թ���ԱȨ�����С����ڽ��Թ���ԱȨ������������", "Ȩ�޲���", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    Start-Process -FilePath "powershell.exe" -ArgumentList "-File `"$($MyInvocation.MyCommand.Path)`"" -Verb RunAs
    exit
}

# �����ڴ�ѡ��Ի���
Function Select-MemorySize {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "ѡ���ڴ��С (MB)"
    $form.Width = 300
    $form.Height = 200
    $form.StartPosition = "CenterScreen"

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "������������ڴ��С (Ĭ�� 2048 MB):"
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
    $okButton.Text = "ȷ��"
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

# ��ȡ�û�ѡ����ڴ��С
$vmMemoryInput = Select-MemorySize
if (-not [int]::TryParse($vmMemoryInput, [ref]$null) -or [int]$vmMemoryInput -le 2048) {
    Write-Host "��Ч���ڴ����룬ʹ��Ĭ��ֵ 2048 MB��" -ForegroundColor Yellow
    $vmMemory = 2048
} else {
    $vmMemory = [int]$vmMemoryInput
}

Write-Host "�û�ѡ����ڴ��СΪ $vmMemory MB��"

# Step 1: ��鲢��װ Hyper-V ����
Write-Host "��鲢��װ Hyper-V ����..."
$featureName = "Microsoft-Hyper-V-All"

# ��� Hyper-V �Ƿ�������
$hyperVFeature = Get-WindowsOptionalFeature -Online -FeatureName $featureName
if ($hyperVFeature.State -ne "Enabled") {
    Write-Host "Hyper-V δ���ã���������..."
    Enable-WindowsOptionalFeature -Online -FeatureName $featureName -All -NoRestart
    Write-Host "Hyper-V �����ã�������ϵͳ����Ч��"
    exit
} else {
    Write-Host "Hyper-V �����á�"
}

# Step 2: ���� Home Assistant OS ����ʹ�ö��߳����ؼ��٣�
Write-Host "�������� Home Assistant OS ����... (���̼߳��������У������ĵȴ�������)"

$urls = @(
    "https://github.com/home-assistant/operating-system/releases/download/14.1/haos_ova-14.1.vhdx.zip"
)

$downloadDir = "C:\HyperV\HomeAssistant"

# ��������Ŀ¼����������ڵĻ���
if (!(Test-Path -Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir | Out-Null
}

# ������������
$jobs = @()

# ���������������
foreach ($url in $urls) {
    $outputPath = Join-Path $downloadDir (Split-Path $url -Leaf)

    $jobs += Start-Job -ScriptBlock {
        param ($url, $outputPath)
        
        try {
            Write-Host "��������: $url"
            Invoke-WebRequest -Uri $url -OutFile $outputPath -UseBasicParsing
            Write-Host "�������: $outputPath"
        } catch {
            Write-Host "����ʧ��: $url"
        }
    } -ArgumentList $url, $outputPath
}

# �ȴ����������������
$jobs | ForEach-Object {
    Wait-Job -Job $_
    Remove-Job -Job $_
}

Write-Host "�����ļ�������ɡ�"

# Step 3: ��ѹ�������ļ�
Write-Host "���ڽ�ѹ�� Home Assistant OS ����..."
$extractPath = "C:\HyperV\HomeAssistant"
Expand-Archive -Path "$downloadDir\haos_ova-14.1.vhdx.zip" -DestinationPath $extractPath -Force
$vhdxFile = Get-ChildItem -Path $extractPath -Filter "*.vhdx" | Select-Object -ExpandProperty FullName
Write-Host "�����ļ��ѽ�ѹ��: $vhdxFile"

# Step 4: ��鲢�������⽻����
Write-Host "������⽻����..."
$vmSwitch = "HomeAssistantSwitch"

if (!(Get-VMSwitch -Name $vmSwitch -ErrorAction SilentlyContinue)) {
    Write-Host "δ�ҵ�Ĭ�Ͻ����������ڴ��������⽻����..."
    New-VMSwitch -Name $vmSwitch -SwitchType Internal | Out-Null
    Write-Host "�Ѵ��������⽻����: $vmSwitch"
} else {
    Write-Host "Ĭ�Ͻ������Ѵ���: $vmSwitch"
}
Start-Process "virtmgmt.msc"
[System.Windows.Forms.MessageBox]::Show("��Ҫ�����⽻���� $vmSwitch ����Ϊ�ⲿ���������֮���ٵ�ȷ�����м��м��мǣ�������Զ��޷����ʣ��޸���֮����Ҫ����Hyper-V����", "�޸Ľ�����", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
# Step 5: ���� Hyper-V ����������뾵��
Write-Host "���� Hyper-V �����..."

$vmName = "HomeAssistant"
$memoryInBytes = $vmMemory * 1MB

# �������������������
New-VM -Name $vmName -MemoryStartupBytes $memoryInBytes -SwitchName $vmSwitch -Generation 2 -Path "C:\HyperV\$vmName" | Out-Null
Set-VMProcessor -VMName $vmName -Count 4

# ���������Ƿ�ɹ�����
$vmExists = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if ($vmExists) {
    Write-Host "����� '$vmName' �����ɹ���"

    # ��ȡ SCSI ������
    $scsiController = Get-VMScsiController -VMName $vmName

    # ��� SCSI �������Ƿ�ɹ�����
    if ($scsiController -and $scsiController.ControllerNumber -ne $null) {
        # ����Ӳ�̵� SCSI ������
        
        Add-VMHardDiskDrive -VMName $vmName -ControllerType SCSI -ControllerNumber $scsiController.ControllerNumber -ControllerLocation 0 -Path $vhdxFile | Out-Null

        # ��������˳��ΪӲ��
        Set-VMFirmware -VMName $vmName -FirstBootDevice (Get-VMHardDiskDrive -VMName $vmName) | Out-Null

        Write-Host "����� '$vmName' �ѳɹ�������������ɣ���δ������"
    } else {
        Write-Host "SCSI ����������ʧ�ܣ��������"

    }
} else {
    Write-Host "����� '$vmName' ����ʧ�ܣ��������"

}

Write-Host "��ɣ�����ͨ�� Hyper-V �������鿴�����״̬��"


Start-VM -Name '$vmName'
Start-Process -FilePath "vmconnect.exe" -ArgumentList "localhost", "HomeAssistant"
