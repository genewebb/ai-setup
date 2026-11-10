"""Builds the CrewChief install pack (CrewChief/packs/install): get the latest master build of the platform pipeline,
remove the old Profisee from an application server, install and configure the new one.

  reference-kv/install/   machines, environment, instances, databases, build, addons
  internal/               install-build-get (download, unzip, verify, publish to the application server, list MSIs)

Source: the old CrewChief install workloads (backups 20261013-111111 / -111833: corpvm31-26r4-perf-tests-setup,
corpvm31-26r3-upgrade-db, 26r2-basic-uninstall, platform/download-latest-platform-build); every machine, version, path
and credential there is replaced by reference data or the shared admin secret (Gene 11/07: Run-As = the CrewChief
Run-As every pack uses; build = pipeline 293, master only).

Usage: python gen_install.py <packRoot>      (e.g. C:\\devops\\repos\\speed-merchants\\CrewChief\\packs\\install)
"""
import json, os, sys

root = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
FAM = 'install'
ref_dir = os.path.join(root, 'reference-kv', FAM)
wl_root = os.path.join(root, 'workloads', FAM)


def dump(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, indent=2)


def ref(s, k):
    return "{{$ref:%s/%s:%s}}" % (FAM, s, k)


# ---------------------------------------------------------------- reference sets
REF_SETS = {
    'machines': {
        "description": "Install pack: the machines an install touches. Profisee is removed and installed on the application server; its database lives on the database server; CrewChief runs on the test server.",
        "includeInReplacements": True,
        "entries": {"ApplicationServerName": "SMVM1", "ApplicationServerNameFQDN": "smvm1.corp.profisee.com",
                    "DatabaseServerName": "smvmdb1", "TestServerName": "smvmtr1"},
        "keyDescriptions": {
            "ApplicationServerName": "Short name of the application server Profisee is removed from and installed on. Every remote step targets it with the shared admin credential (UserCredentials secrets) over CredSSP.",
            "ApplicationServerNameFQDN": "Fully qualified name of the application server; health and REST checks after the install use it.",
            "DatabaseServerName": "SQL Server that holds the Profisee database of this instance (dropped and recreated by a clean install; pack base backups are restored here and configured through install-configure-upgrade at the start of each pack run).",
            "TestServerName": "Machine running CrewChief and these workloads (short name). The build is downloaded here and then copied to the application server."}},
    'environment': {
        "description": "Install pack: what differs between Profisee releases and boxes. Edit before installing a new release.",
        "includeInReplacements": True,
        "entries": {"ProfiseeVersionCode": "26R3T", "ProfiseeVersionNumber": "26.3.0", "MainServiceName": "",
                    "ConfigurationManagerKind": "classic",
                    "ConfigurationManagerNewRefusal": "Configuration manager 'new' is not supported yet (26R4 deferred).",
                    "LicenseFile": "C:\\Deploy\\License\\Prof_2020_3Inst_3Nodes_AllFeatures_AllConnectors_Production_@.corp.profisee.com_ConnexOn_AIOn_McpOn.plic",
                    "WebSiteName": "Default Web Site", "MetadataProvider": "None"},
        "keyDescriptions": {
            "ProfiseeVersionCode": "TestAuto version code of the release being installed (as in the other packs' environment sets). Hand runs of a root read it here; a TestAutoManager round passes it per lane.",
            "ProfiseeVersionNumber": "Product version of the release being installed, e.g. 26.4.0: the install is checked against it and the Configuration program is found under it.",
            "MainServiceName": "Profisee Windows service on the application server, stopped before the uninstall. Blank on releases with no Windows service; the stop step then reports Skipped.",
            "ConfigurationManagerKind": "Which Profisee Configuration program the release has: classic (the Configuration.exe the install runs) or new. 'new' is refused by install-configure-new and install-configure-upgrade until the release that has it is supported.",
            "ConfigurationManagerNewRefusal": "The text install-configure-new and install-configure-upgrade fail with when ConfigurationManagerKind is new (kept here because it names a release).",
            "LicenseFile": "Full path ON THE APPLICATION SERVER of the Profisee license file Configuration applies.",
            "WebSiteName": "IIS web site the instance lives under.",
            "MetadataProvider": "Configuration switch metadataProvider (None on the test lab)."},
        "keyBlankAllowed": {"MainServiceName": True}},
    'instances': {
        "description": "Install pack: the Profisee instance created on the application server.",
        "includeInReplacements": True,
        "entries": {"ProfiseeInstanceName": "profisee", "AppPoolName": "profisee", "MaestroServicePort": "8003",
                    "AttachmentRepositoryLocation": "C:\\FileRepository"},
        "keyDescriptions": {
            "ProfiseeInstanceName": "IIS application path of the instance (https://<server>/<instance>); removed and recreated by the install. The other packs' instances sets must name the same value.",
            "AppPoolName": "Main application pool of the instance (Configuration switch maestroAppPoolName).",
            "MaestroServicePort": "Port of the Maestro service; it must be free before the install.",
            "AttachmentRepositoryLocation": "Folder on the application server for attachments (Configuration switch)."}},
    'databases': {
        "description": "Install pack: the Profisee database of the instance.",
        "includeInReplacements": True,
        "entries": {"ProfiseeDatabaseName": "Profisee"},
        "keyDescriptions": {
            "ProfiseeDatabaseName": "The Profisee database of the instance. A clean install DROPS it and Configuration creates it empty; an upgrade keeps it. Pack base backups are not listed here: each pack run restores its own base, named <stem>_<ProfiseeVersionCode>.bak (one per release, in that pack's databases set), and runs Configuration on it (install-configure-upgrade) before it tests."}},
    'build': {
        "description": "Install pack: where the build comes from (Gene 11/07: platform pipeline 293, master branch only) and where it is put.",
        "includeInReplacements": True,
        "entries": {"AdoOrganizationUrl": "https://profisee.visualstudio.com", "AdoProject": "Products",
                    "AdoPipelineDefinitionId": "293", "AdoBranch": "refs/heads/master",
                    "DownloadDirectory": "C:\\Deploy\\Downloads", "PublishDirectory": "C:\\Deploy\\ReleaseToWeb\\CurrentBuild",
                    "RetentionCount": "5", "ServerMsi": "ProfiseePlatform.msi",
                    "FastAppStudioMsi": "MasterDataMaestroDesktop_x64.msi", "PlatformToolsMsi": "ProfiseePlatformTools.msi"},
        "keyDescriptions": {
            "AdoOrganizationUrl": "Azure DevOps organization of the platform pipeline.",
            "AdoProject": "Azure DevOps project of the platform pipeline.",
            "AdoPipelineDefinitionId": "Definition id of the platform pipeline (293).",
            "AdoBranch": "Branch whose latest successful build is installed when an install test runs alone. A TestAutoManager round passes its own branch and build instead (parameters AdoBranch and AdoBuildId).",
            "DownloadDirectory": "Folder ON THE APPLICATION SERVER the build is downloaded, unzipped and verified in (BuildPublish to a remote server reads the marker in that server's own download folder).",
            "PublishDirectory": "Folder ON THE APPLICATION SERVER the verified build is copied to; the installs read the MSIs from there.",
            "RetentionCount": "How many older builds the publish step keeps beside the current one.",
            "ServerMsi": "Path of the Profisee Server MSI relative to PublishDirectory (product name 'Profisee Server'; ProfiseePlatform.msi in the 26R4 builds).",
            "FastAppStudioMsi": "Path of the FastApp Studio MSI relative to PublishDirectory (product name 'Profisee FastApp Studio'; the file is MasterDataMaestroDesktop_x64.msi in the 26R4 builds).",
            "PlatformToolsMsi": "Path of the Command Line Utilities MSI relative to PublishDirectory (product name 'Profisee Command Line Utilities'; ProfiseePlatformTools.msi in the 26R4 builds)."}},
    'addons': {
        "description": "Install pack: optional imports after configure (blank = skipped).",
        "includeInReplacements": True,
        "entries": {"ModelFile": "", "ArchiveFile": "", "UsersFile": ""},
        "keyDescriptions": {
            "ModelFile": "Full path on the application server of a .maestromodel to import after the install. Blank = skipped.",
            "ArchiveFile": "Full path on the application server of a data archive to deploy after the install. Blank = skipped.",
            "UsersFile": "Full path on the application server of a .users file (accounts and teams) to import. Blank = skipped."},
        "keyBlankAllowed": {"ModelFile": True, "ArchiveFile": True, "UsersFile": True}},
}
for name, obj in REF_SETS.items():
    dump(os.path.join(ref_dir, name + '.json'), obj)

# ---------------------------------------------------------------- step helpers (same shapes as the CRUD pack)
base = {"parameters": {}, "timeoutSeconds": 600, "continueOnError": False, "retryEnabled": False, "maxRetries": 0,
        "retryDelaySeconds": 5, "workingDirectory": None, "notes": ""}
ADMIN = {"credentialSecretName": None, "credentialUserId": "{{$config:UserCredentials:AdminUser}}",
         "credentialPassword": "{{$config:UserCredentials:AdminPassword}}", "remoteAuthentication": "CredSSP"}
LOCAL = {"targetComputer": None, "remoteAuthentication": None}


def ps(label, script, desc, timeout=600):
    return {"label": label, "inline": {**base, "executionPolicy": "Bypass", "preferWindowsPowerShell": False,
            "runAsAdministrator": False, "captureVerbose": False, "captureDebug": False, "treatStderrAsError": True,
            "scriptContent": script.replace('\r\n', '\n').replace('\n', '\r\n'), "type": "PowerShellStep",
            "timeoutSeconds": timeout, "description": desc}}


def step(label, type_, desc, timeout=600, **fields):
    return {"label": label, "inline": {**base, **fields, "type": type_, "timeoutSeconds": timeout, "description": desc}}


def workload(name, desc, tags, globals_, steps, notes="", inputs=None):
    w = {"name": name, "description": desc, "tags": tags, "globalParameters": globals_, "globalParametersNotes": notes,
         "credentialUserId": None, "credentialPassword": None, "credentialNotes": "", "steps": steps}
    if inputs:
        w["inputs"] = [{"name": n, "description": d} for n, d in inputs]
    return w


# Every parent of install-build-get passes the build to install: the reference-data branch and the latest build, unless
# the caller (a TestAutoManager round, through CrewChief --param) passes AdoBranch / AdoBuildId of its own.
BUILD_GLOBALS = {"AdoBranch": ref('build', 'AdoBranch'), "AdoBuildId": ""}
BUILD_INPUTS = [
    ("AdoBranch", "Branch of the platform pipeline to install from (refs/heads/...), passed by the test that runs this "
                  "one: install/build:AdoBranch, or the branch of a TestAutoManager round."),
    ("AdoBuildId", "Exact Azure DevOps build id to install, passed by the test that runs this one; blank = the latest "
                   "successful build of AdoBranch."),
]

# Version keys (decision D12): a root (a workload no workload runs) reads each from reference data in its own global of
# the same name, or takes it from the caller (a TestAutoManager lane passes it as --param); every workload below a
# root declares the ones it uses as inputs and gets the value from its parent.
VERSION_GLOBALS = {"MainServiceName": ref('environment', 'MainServiceName'),
                   "ProfiseeVersionNumber": ref('environment', 'ProfiseeVersionNumber'),
                   "ConfigurationManagerKind": ref('environment', 'ConfigurationManagerKind')}
IN_MAIN_SERVICE = ("MainServiceName", "Profisee Windows service on the application server, stopped before the uninstall; "
                   "blank = the release has no Windows service. Passed by the test that runs this one (install/environment:"
                   "MainServiceName, or the lane's service name).")
IN_VERSION_NUMBER = ("ProfiseeVersionNumber", "Product version of the release being installed (n.n.n): the Configuration "
                     "and utilities programs are found under it. Passed by the test that runs this one "
                     "(install/environment:ProfiseeVersionNumber, or the lane's version).")
IN_CONFIG_KIND = ("ConfigurationManagerKind", "classic or new: which Configuration program the release has. Passed by the test "
                  "that runs this one (install/environment:ConfigurationManagerKind, or the lane's value); new is refused.")


G = {
    "ApplicationServerName": ref('machines', 'ApplicationServerName'),
    "DatabaseServerName": ref('machines', 'DatabaseServerName'),
    "DownloadDirectory": ref('build', 'DownloadDirectory'),
    "PublishDirectory": ref('build', 'PublishDirectory'),
}


def g(*names, **extra):
    out = {n: G[n] for n in names}
    out.update(extra)
    return out


# ---------------------------------------------------------------- internal/install-build-get
LIST_MSI = r"""$ErrorActionPreference = 'Stop'
$server = '{{ApplicationServerName}}'
$publish = '{{PublishDirectory}}'
$download = '{{DownloadDirectory}}'
# Both folders are paths on the application server; read them through the admin share.
$unc = '\\' + $server + '\' + ($publish -replace '^([A-Za-z]):', '$1$')
$downloadUnc = '\\' + $server + '\' + ($download -replace '^([A-Za-z]):', '$1$')
if (-not (Test-Path $unc)) { throw "Published build folder $publish is missing on $server ($unc)." }
$msis = @(Get-ChildItem -Path $unc -Recurse -Filter *.msi | Sort-Object FullName)
if ($msis.Count -eq 0) { throw "No MSI under $publish on $server." }
Write-Output "Build folders in ${download}:"
Get-ChildItem -Path $downloadUnc -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending |
    Select-Object -First 3 | ForEach-Object { Write-Output ("  {0}  {1:yyyy-MM-dd HH:mm}" -f $_.Name, $_.LastWriteTime) }
Write-Output "MSIs published to $publish on ${server} (path relative to the publish folder, size MB):"
foreach ($m in $msis) {
    $rel = $m.FullName.Substring($unc.Length).TrimStart('\')
    Write-Output ("  {0}  {1:N0}" -f $rel, ($m.Length / 1MB))
}
"""

build_steps = [
    step("Download The Build", "AdoBuildDownloadStep",
         "What: Download the platform pipeline build named by AdoBuildId, or, when it is blank, the latest successful build "
         "of AdoBranch. Why: every install starts from the build under test. Success: the build's artifact is in the download "
         "folder, or it was already there (skip when current). If it fails: the environment variable AZURE_DEVOPS_PAT "
         "(machine scope, or the CrewChief service account) is missing, expired or lacks Build Read; Azure DevOps is "
         "unreachable; or the build id is not a successful build of this pipeline on AdoBranch (the message says which).",
         timeout=3600, organizationUrl=ref('build', 'AdoOrganizationUrl'), project=ref('build', 'AdoProject'),
         pipelineDefinitionId=ref('build', 'AdoPipelineDefinitionId'), branch="{{AdoBranch}}", buildId="{{AdoBuildId}}",
         patSecret="{{$env:AZURE_DEVOPS_PAT}}", downloadDirectory="{{DownloadDirectory}}", skipIfCurrent=True, targetComputer="{{ApplicationServerName}}", **ADMIN),
    step("Unzip The Build", "BuildUnzipStep",
         "What: Extract the downloaded artifact. Why: the installs need the MSIs, not the zip. Success: the extracted "
         "folder exists. If it fails: the download is incomplete or the disk of the application server is full.",
         timeout=1800, downloadDirectory="{{DownloadDirectory}}", deleteZipAfterUnzip=False, targetComputer="{{ApplicationServerName}}", **ADMIN),
    step("Verify The Build", "BuildVerifyStep",
         "What: Check the extracted build holds at least the three MSIs an install needs. Why: a broken artifact must stop "
         "here, before anything is uninstalled. Success: three or more MSIs found. If it fails: the pipeline produced an "
         "incomplete artifact; pick an earlier build.",
         downloadDirectory="{{DownloadDirectory}}", minimumMsiCount=3, targetComputer="{{ApplicationServerName}}", **ADMIN),
    step("Publish The Build To The Application Server", "BuildPublishStep",
         "What: Copy the verified build from the download folder to the publish folder, both on the application server, and "
         "prune older copies. Why: the installs then read the MSIs locally there (no second network hop). Success: the publish folder holds this build. "
         "If it fails: the admin credential (UserCredentials secrets) cannot write to the application server over CredSSP, "
         "or its disk is full.",
         timeout=3600, downloadDirectory="{{DownloadDirectory}}", targetDirectory="{{PublishDirectory}}",
         retentionCount=ref('build', 'RetentionCount'), targetComputer="{{ApplicationServerName}}", **ADMIN),
    ps("List The Published MSIs", LIST_MSI,
       "What: List the MSIs now in the publish folder on the application server, and the newest build folders on the test "
       "application server. Why: shows which build an install will use and the MSI paths the build reference keys name. Success: at "
       "least one MSI listed. If it fails: the publish step did not reach the application server; check the admin share "
       "(\\\\<server>\\c$) is reachable from the test server."),
]
dump(os.path.join(wl_root, 'internal', 'install-build-get.workload.json'), workload(
    "install-build-get",
    ("What: Get the build under test of the platform pipeline (AdoBuildId, or the latest successful build of AdoBranch): "
     "download, unzip and verify it on the application server, then copy it to the publish folder there and list its "
     "MSIs. Why: every install uses the build under test, and a broken artifact must stop before anything is removed. "
     "When: first part of every install test, which passes AdoBranch and AdoBuildId (install-preflight shows the newest "
     "build without installing). Needs: environment variable AZURE_DEVOPS_PAT on the test server for the CrewChief account (Build Read); the application server reaches Azure DevOps; the shared admin "
     "credential can write to the application server. Success: Every step Succeeded. If it fails: open the first failed "
     "step, whose If it fails text names what to check."),
    ["install", "internal", "build"], g("ApplicationServerName", "DownloadDirectory", "PublishDirectory"), build_steps,
    inputs=BUILD_INPUTS))

# ---------------------------------------------------------------- internal/install-remove (+ preview)
# UninstallStep matches an exact display name only (UninstallExecutor), and the installed version can differ from the one
# being installed, so one remote PowerShell step finds every installed Profisee Server / FastApp Studio / Command Line
# Utilities product and removes it by product code (ruling 11/07, P1 Task 2).
REMOVE_PRODUCTS = r"""$ErrorActionPreference = 'Stop'
$preview = '{{RemovePreview}}' -eq 'true'
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$order = @{ 'Server' = 1; 'FastApp Studio' = 2; 'Command Line Utilities' = 3 }
$found = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '^Profisee (Server|FastApp Studio|Command Line Utilities)\b' -and $_.PSChildName -match '^\{' } |
    Sort-Object @{ Expression = { $order[($_.DisplayName -replace '^Profisee (Server|FastApp Studio|Command Line Utilities).*$', '$1')] } })
if ($found.Count -eq 0) { Write-Output "${env:COMPUTERNAME}: no Profisee Server, FastApp Studio or Command Line Utilities installed."; return }
foreach ($p in $found) { Write-Output ("{0}: installed {1} (version {2}, {3})" -f $env:COMPUTERNAME, $p.DisplayName, $p.DisplayVersion, $p.PSChildName) }
if ($preview) { Write-Output 'Preview: nothing removed.'; return }
foreach ($p in $found) {
    $r = Start-Process -FilePath msiexec.exe -ArgumentList "/x $($p.PSChildName) /qn /norestart" -Wait -PassThru
    if ($r.ExitCode -notin 0, 1605, 3010) { throw "msiexec /x for '$($p.DisplayName)' ended with exit code $($r.ExitCode)." }
    Write-Output ("Removed {0} (msiexec exit {1})" -f $p.DisplayName, $r.ExitCode)
}
$left = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^Profisee (Server|FastApp Studio|Command Line Utilities)\b' })
if ($left.Count) { throw ("Still installed after removal: " + (($left | ForEach-Object DisplayName) -join ', ')) }
"""


def remote_ps(label, script, desc, timeout=600):
    s = ps(label, script, desc, timeout)
    s["inline"].update({"targetComputer": "{{ApplicationServerName}}", **ADMIN})
    return s


def iis_service(name, action, desc):
    return step(f"{action} {name}", "ServiceControlStep", desc, serviceName=name, action=action,
                targetComputer="{{ApplicationServerName}}", **ADMIN)


def profisee_service(action):
    s = step(f"{action} The Profisee Service", "ServiceControlStep",
             f"What: {action} the Profisee Windows service on the application server. Why: older releases run one; it "
             "holds files the uninstall must replace. Success: the service is " + ("stopped" if action == 'Stop' else "running") +
             ". If it fails: the service name in MainServiceName (install/environment:MainServiceName, or the lane's) is wrong. "
             "Skipped when: it is blank (newer releases have no Profisee Windows service).",
             serviceName="{{MainServiceName}}", action=action, targetComputer="{{ApplicationServerName}}", **ADMIN)
    s["inline"]["runWhen"] = "{{MainServiceName}}"
    return s


IIS_STOP = [
    iis_service("W3SVC", "Stop", "What: Stop the World Wide Web Publishing Service on the application server. Why: IIS holds the "
                "Profisee files open; W3SVC must stop before WAS, which it depends on. Success: stopped. If it fails: the admin "
                "credential cannot manage services there over CredSSP."),
    iis_service("WAS", "Stop", "What: Stop the Windows Process Activation Service on the application server. Why: with W3SVC "
                "stopped, this stops every application pool. Success: stopped. If it fails: as the step before."),
]


def remove_steps(preview):
    mode = "List" if preview else "Remove"
    steps = [] if preview else [profisee_service("Stop"), *IIS_STOP]
    steps.append(remote_ps(f"{mode} Installed Profisee Products", REMOVE_PRODUCTS,
        ("What: On the application server, list every installed Profisee Server, FastApp Studio and Command Line Utilities "
         + ("product; change nothing. " if preview else "product and remove each with msiexec /x (Server first, then FastApp Studio, then the utilities, the order the old install workloads used). ")
         + "Why: the installed version may differ from the one being installed, so products are found, not named. Success: "
         + ("the products are listed (or none). " if preview else "none of them is installed afterwards (exit 3010 = reboot "
            "pending, accepted). ")
         + "If it fails: the error names the product and msiexec exit code; 1618 = another install is running on the server."),
        timeout=1800))
    if not preview:
        steps.append(step("Remove The Instance Web Application", "WebSiteStep",
            "What: Delete the instance's IIS application and the application pools only it used. Why: Configuration creates "
            "them again; a leftover application with an old path breaks the new install. Success: deleted, or already absent. "
            "If it fails: the admin credential cannot manage IIS on the application server.",
            sitePaths=[ref('environment', 'WebSiteName') + "/" + ref('instances', 'ProfiseeInstanceName')], action="Delete",
            deleteAppPools=True, targetComputer="{{ApplicationServerName}}", **{**ADMIN, "remoteAuthentication": "Auto"}))
    return steps


for preview in (False, True):
    name = "install-remove-preview" if preview else "install-remove"
    dump(os.path.join(wl_root, 'internal', name + '.workload.json'), workload(
        name,
        (("What: List what install-remove would remove on the application server (installed Profisee products), changing "
          "nothing. Why: see the old version before a destructive run. When: before the first install on a box, or any time. ")
         if preview else
         ("What: Remove Profisee from the application server: stop the Profisee service (older releases) and IIS, uninstall "
          "every installed Profisee Server, FastApp Studio and Command Line Utilities, delete the instance's IIS application "
          "and its pools. IIS stays stopped for the install that follows. Why: a clean install starts from nothing. When: "
          "from install-clean / install-upgrade; alone only to tear a box down. ")) +
        ("Needs: the shared admin credential is an administrator of the application server (WinRM, CredSSP). Success: Every "
         "step Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
        ["install", "internal", "remove"] + (["preview"] if preview else []),
        g("ApplicationServerName", RemovePreview="true" if preview else "false"), remove_steps(preview),
        inputs=None if preview else [IN_MAIN_SERVICE]))

# ---------------------------------------------------------------- internal/install-programs
MSI_INSTALL = r"""$ErrorActionPreference = 'Stop'
# InstallStep reads the MSI on the CrewChief machine and copies it to the server; the build is already published on
# the server, so msiexec runs there against the local path.
$msi = '%MSI%'
if (-not (Test-Path -LiteralPath $msi)) { throw "MSI not found on ${env:COMPUTERNAME}: $msi (install/build:PublishDirectory + install/build:%KEY%)." }
$log = Join-Path $env:TEMP ('install-' + [IO.Path]::GetFileNameWithoutExtension($msi) + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$p = Start-Process -FilePath 'msiexec.exe' -ArgumentList @('/i', ('"' + $msi + '"'), '/qn', '/norestart', '/l*v', ('"' + $log + '"')) -Wait -PassThru
$code = $p.ExitCode
if ($code -eq 0 -or $code -eq 3010) {
    $name = (Get-Item -LiteralPath $msi).Name
    Write-Output "Installed $name on ${env:COMPUTERNAME} (msiexec exit $code). Log: $log"
    return
}
Write-Output "msiexec exit $code. Last lines of ${log}:"
if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log -Tail 400 | Where-Object { $_ -match 'error|failed|return value 3' } | Select-Object -Last 15 }
throw "msiexec /i $msi failed with exit $code on ${env:COMPUTERNAME} (1618 = another install is running)."
"""


def install_msi(label, key, what):
    script = MSI_INSTALL.replace('%MSI%', ref('build', 'PublishDirectory') + "\\" + ref('build', key)).replace('%KEY%', key)
    return remote_ps(label, script,
                     f"What: Install {what} from the published build, running msiexec /i /qn on the application server. Why: one "
                     "of the three products a Profisee test box needs. Success: msiexec ends with 0 or 3010. If it fails: the "
                     f"MSI path (install/build:PublishDirectory + install/build:{key}) is wrong for this build, or another install "
                     "is running on the server (1618); the step prints the error lines of the msiexec log.", timeout=1800)


PORT_FREE = r"""$ErrorActionPreference = 'Stop'
$port = [int]'""" + ref('instances', 'MaestroServicePort') + r"""'
$held = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)
if ($held.Count) {
    $names = $held | ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName } | Sort-Object -Unique
    throw "Port $port on ${env:COMPUTERNAME} is held by: $($names -join ', ')."
}
Write-Output "Port $port is free on ${env:COMPUTERNAME}."
"""


programs_steps = [
    # CheckPortStep checks only the CrewChief machine (it refuses a remote target), so the check runs on the server.
    remote_ps("Check The Maestro Port Is Free", PORT_FREE,
              "What: Check nothing listens on the Maestro service port of the application server, on that server. Why: "
              "Configuration fails late when an old service still holds it. Success: the port is free. If it fails: an old "
              "Profisee service is still running; run install-remove-preview to see what is installed."),
    install_msi("Install Profisee Platform", "ServerMsi", "the Profisee Platform (server)"),
    install_msi("Install FastApp Studio", "FastAppStudioMsi", "FastApp Studio"),
    install_msi("Install Platform Tools", "PlatformToolsMsi", "the Platform Tools (command line utilities)"),
    iis_service("WAS", "Start", "What: Start the Windows Process Activation Service. Why: IIS must run before Configuration "
                "creates the instance. Success: running. If it fails: the admin credential cannot manage services there."),
    iis_service("W3SVC", "Start", "What: Start the World Wide Web Publishing Service. Why: as the step before. Success: running. "
                "If it fails: as the step before."),
]
dump(os.path.join(wl_root, 'internal', 'install-programs.workload.json'), workload(
    "install-programs",
    ("What: Install the Profisee Platform, FastApp Studio and Platform Tools from the published build on the application "
     "server, then start IIS. Why: the second half of a clean install, before Configuration. When: from install-clean / "
     "install-upgrade, after install-remove. Needs: install-build-get published the build; install/build:ServerMsi, "
     "FastAppStudioMsi and PlatformToolsMsi name its MSIs. Success: Every step Succeeded. If it fails: open the first failed "
     "step, whose If it fails text names what to check."),
    ["install", "internal", "programs"], g("ApplicationServerName"), programs_steps))

# ---------------------------------------------------------------- internal/install-configure-new / -upgrade
CONFIG_EXE = ("C:\\Program Files\\Profisee\\Master Data Maestro Server\\" + "{{ProfiseeVersionNumber}}" +
              "\\Configuration\\Profisee.MasterDataMaestro.Services.Configuration.exe")
ADMIN_USER, ADMIN_PW = "{{$config:UserCredentials:AdminUser}}", "{{$config:UserCredentials:AdminPassword}}"


CONFIG_KIND_CHECK = """$ErrorActionPreference = 'Stop'
# The Configuration program of a release that has the 'new' manager is not driven yet: refuse before anything is touched.
if ('{{ConfigurationManagerKind}}' -eq 'new') { throw "%s" }
Write-Output 'Configuration manager kind: {{ConfigurationManagerKind}}'
""" % ref('environment', 'ConfigurationManagerNewRefusal')


def configure(drop_db):
    switches = {
        "licenseFile": ref('environment', 'LicenseFile'), "sqlServer": "{{DatabaseServerName}}",
        "maestroDatabase": "{{ProfiseeDatabaseName}}", "useWindowsAuthentication": "TRUE",
        "webSiteName": ref('environment', 'WebSiteName'), "maestroWebAppName": ref('instances', 'ProfiseeInstanceName'),
        "useHttps": "TRUE", "maestroAppPoolName": ref('instances', 'AppPoolName'),
        "maestroAppPoolUserName": ADMIN_USER, "maestroAppPoolUserPassword": ADMIN_PW, "adminAccount": ADMIN_USER,
        "metadataProvider": ref('environment', 'MetadataProvider'),
        "AttachmentRepositoryLocation": ref('instances', 'AttachmentRepositoryLocation'),
        "AttachmentRepositoryUserName": ADMIN_USER, "AttachmentRepositoryUserPassword": ADMIN_PW,
        "maestroServicePort": ref('instances', 'MaestroServicePort'),
        "maestroServiceUserName": ADMIN_USER, "maestroServiceUserPassword": ADMIN_PW,
        "dropMaestroDatabase": "TRUE" if drop_db else "FALSE", "UseSeparateDatabases": "FALSE",
        "authAdName": ADMIN_USER, "firstUserClientID": "{{$config:UserCredentials:ProfAdminClientId}}",
        "AttachmentRepositoryLogonType": "Interactive", "authAdEnabled": "TRUE"}
    return step("Configure The Profisee Instance", "ConfigureStep",
                ("What: Run Profisee Configuration on the application server: " +
                 ("create the instance on a NEW, empty Profisee database. " if drop_db else
                  "create the instance on the EXISTING Profisee database, upgrading it to this release. ") +
                 "Why: Configuration creates the IIS application, pools, services and database for this machine and version. "
                 "Success: Configuration ends without error (the executor reads its log, since it exits 0 on failure too). If "
                 "it fails: the step output quotes Configuration's log; the license file (install/environment:LicenseFile) "
                 "must exist on the application server, and the admin account must be sysadmin on the database server."),
                timeout=2400, configurationExePath=CONFIG_EXE, arguments=None, switches=switches,
                targetComputer="{{ApplicationServerName}}", **ADMIN, preflightSqlRepair=True, preflightVerifyIisSite=True,
                postflightDisableCheckPolicy=True, postflightEnforceIdentities=True)


DROP_DB = step("Drop The Profisee Database", "DatabaseOperationsStep",
               "What: Drop the Profisee database named in install/databases:ProfiseeDatabaseName on the database server. Why: a "
               "clean install starts from an empty database. Success: dropped, or it did not exist. If it fails: the CrewChief "
               "account is not sysadmin on the database server.",
               timeout=1800, serverName="{{DatabaseServerName}}", connectionSecretName="", authMode="Windows",
               credentialUserId="", credentialPassword="", databaseName="{{ProfiseeDatabaseName}}", operation="DropDatabase",
               snapshotName="", backupFileName=None, fileUncPath=None, overwrite=False, relocateFiles=False,
               waitIndefinitely=False, dryRun=False)
G["ProfiseeDatabaseName"] = ref('databases', 'ProfiseeDatabaseName')
with open(os.path.join(here, 'health.ps1'), encoding='utf-8', newline='') as f:
    HEALTH = f.read()
G["MainHealthUrl"] = ("https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName')
                      + "/rest/health")
G["ProfiseeInstanceName"] = ref('instances', 'ProfiseeInstanceName')
G["ProfiseeBaseUrl"] = ("https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName')
                        + "/rest")
G["ProfiseeApiKey"] = "{{$config:RestKeys:ProfiseeRestKey}}"
G["ApiKeyUserName"] = "{{$config:ConnectRuntime:ApiKeyUserName}}"

# ---------------------------------------------------------------- internal/install-api-key-set (Gene 11/09)
# Rule of every pack: a workload that runs Profisee Configuration (or restores the Profisee database) sets the standard API
# key itself afterwards and proves it through the gateway and the Data service (Test-Pack rule R-key). A Configuration run
# issues a new key, and the services read a key change only after IIS restarts. Same shape as crud-api-key-set and
# matching-api-key-set; the reference keys it reads are this pack's (machines, instances, databases) and the key comes from
# the RestKeys:ProfiseeRestKey secret.
def key_service(action, what):
    s = step(f"{action} The Profisee Service", "ServiceControlStep", f"What: {what} Why: it caches the user it signed in with and must "
             "read the new key. Success: the service is " + ("stopped" if action == 'Stop' else "running") + ". If it fails: the service "
             "name in MainServiceName (install/environment:MainServiceName, or the lane's) is wrong, or the admin credential cannot manage "
             "services there over CredSSP. Skipped when: MainServiceName is blank (newer releases have no Profisee Windows service).",
             serviceName="{{MainServiceName}}", action=action, targetComputer="{{ApplicationServerName}}", **ADMIN)
    s["inline"]["runWhen"] = "{{MainServiceName}}"
    return s


def key_http(label, path, what, why):
    return step(label, "HTTP", f"What: {what} Why: {why} Success: HTTP 200. If it fails: 401, 400 DATA00030 or 403 means the key did not "
                "take: check the API user in meta.tUser and that IIS restarted after the key change; then rerun this workload.",
                timeout=600, retryEnabled=True, maxRetries=4, retryDelaySeconds=30, url="{{ProfiseeBaseUrl}}" + path, method="GET",
                headers={"x-api-key": "{{ProfiseeApiKey}}", "accept": "application/json"}, body="", outputFile="",
                expectedStatusCodes=[200], followRedirects=True, verifySsl=True, maxTimeSeconds=300)


key_set_steps = [
    key_service("Stop", "Stop the Profisee Windows service before the key change."),
    *IIS_STOP,
    step("Set API Key", "SetApiKeyStep",
         "What: Write the standard API key for the machine's API user (ConnectRuntime:ApiKeyUserName) into meta.tUser. Why: TestAuto, "
         "the rule removal and every check call the gateway with that key; Profisee Configuration issues a new key and a restored "
         "backup may carry another one. Success: the user row is updated. If it fails: the user is missing from meta.tUser; add it "
         "in Profisee as a super administrator.",
         username="{{ApiKeyUserName}}", key="{{ProfiseeApiKey}}", serverName="{{DatabaseServerName}}",
         databaseName="{{ProfiseeDatabaseName}}", authMode="Windows", credentialUserId="", credentialPassword="",
         sqlDestinationConnectionSecretName="", stripHyphens=True),
    iis_service("WAS", "Start", "What: Start the Windows Process Activation Service on the application server. Why: IIS must run again "
                "so the application pools start and read the new key. Success: running. If it fails: the admin credential cannot manage "
                "services there over CredSSP."),
    iis_service("W3SVC", "Start", "What: Start the World Wide Web Publishing Service on the application server. Why: as the step before. "
                "Success: running. If it fails: as the step before."),
    key_service("Start", "Start the Profisee Windows service after IIS starts."),
    ps("Start Every Service", HEALTH,
       "What: Wait until every health check of the instance is Healthy. Why: services stay cold after a recycle; the key checks "
       "below must not meet a cold service. Success: all checks Healthy within 10 minutes. If it fails: open the health URL "
       "({{MainHealthUrl}}) and fix the service it names.", timeout=900),
    key_http("Verify API Key Through Gateway", "/v1/Entities", "Call the gateway with the standard key.",
             "proves the key took before anything else uses it."),
    key_http("Verify API Key Through Data Service", "/v1/Rules?PageSize=1",
             "Prove the Data service accepts the API key as a real user: GET v1/Rules?PageSize=1.",
             "the gateway check can pass while the Data and Connect services still reject the user (400 DATA00030, 403 CNX00080)."),
]
dump(os.path.join(wl_root, 'internal', 'install-api-key-set.workload.json'), workload(
    "install-api-key-set",
    ("What: Stop the Profisee service and IIS on the application server, write the standard API key (RestKeys:ProfiseeRestKey) for "
     "the API user (ConnectRuntime:ApiKeyUserName) into the Profisee database, start IIS and the service, wait for every service, "
     "and prove the key through the gateway and the Data service. Why: the pack standard (Test-Pack rule R-key): whatever runs "
     "Profisee Configuration sets the key itself afterwards, so no later step meets a 401. When: Never run directly; "
     "install-configure-new and install-configure-upgrade run it right after Configuration. Running it alone is safe when no test "
     "uses this Profisee instance. Needs: the instance is configured and the API user exists in the Profisee database; secrets "
     "RestKeys:ProfiseeRestKey and ConnectRuntime:ApiKeyUserName; no test running on this application server. Success: Every step "
     "Succeeded or Skipped. If it fails: open the first failed step, whose If it fails text names what to check."),
    ["install", "internal", "api-key"],
    g("ApplicationServerName", "DatabaseServerName", "ProfiseeInstanceName", "ProfiseeDatabaseName", "ProfiseeBaseUrl", "MainHealthUrl",
      "ProfiseeApiKey", "ApiKeyUserName"),
    key_set_steps, inputs=[IN_MAIN_SERVICE]))


def run_child(label, name, what, timeout=21600):
    return step(label, "RunWorkloadStep",
                (f"What: {what}. Why: Runs the child workload '{name}' so its tested steps are reused here, not repeated. "
                 "Success: The child workload ends with every step Succeeded or Skipped. "
                 f"If it fails: Open the run output of '{name}'; its first failed step says what to check."),
                timeout=timeout, workloadName=name)


def key_set_child():
    return run_child("Set And Verify API Key", "install-api-key-set",
                     "Set the standard API key, restart IIS so every service reads it, and prove it through the gateway and the Data service",
                     timeout=3600)


# Gene 11/08: every pack run restores its base and runs install-configure-upgrade on it. Configuration writes new service
# sign-in ids into the database AND the application server, so a base configured before another one is rejected
# (400 DATA00030). A full pack base (CRUD: 47 GB) configures far slower than an empty database.
for drop_db in (True, False):
    name = "install-configure-new" if drop_db else "install-configure-upgrade"
    conf = configure(drop_db)
    if not drop_db:
        conf["inline"]["timeoutSeconds"] = 7200
    dump(os.path.join(wl_root, 'internal', name + '.workload.json'), workload(
        name,
        (("What: Drop the Profisee database and run Profisee Configuration to create the instance on a new, empty one. "
          if drop_db else
          "What: Run Profisee Configuration to create the instance on the existing Profisee database, upgrading it. ") +
         "Why: the installed programs do nothing until Configuration creates the instance for this machine. When: from "
         "install-clean / install-upgrade, after install-programs" +
         ("." if drop_db else
          "; and at the start of every pack run, right after the pack restores its base backup (crud-run-start, "
          "matching-*-scenario1-load), so the base carries this application server's service sign-in ids.") +
         " Then it sets the standard API key and proves it (install-api-key-set), because Configuration issues a new key. Needs: the programs of this release "
         "installed; the license file on the application server; secrets UserCredentials:AdminUser, AdminPassword and "
         "ProfAdminClientId. Success: Every step Succeeded. If it fails: open the first failed step, whose If it fails text "
         "names what to check."),
        ["install", "internal", "configure", "new-db" if drop_db else "upgrade"],
        g("ApplicationServerName", "DatabaseServerName", "ProfiseeDatabaseName"),
        [ps("Configuration Manager Supported", CONFIG_KIND_CHECK,
            "What: Refuse the run when ConfigurationManagerKind is new. Why: only the classic Configuration program is driven by "
            "this pack; the check runs first so nothing is dropped or changed for a release that cannot be configured. Success: "
            "the kind is classic. If it fails: the lane or install/environment:ConfigurationManagerKind names the new "
            "manager; run a release that has the classic one.", timeout=60)] +
        ([DROP_DB] if drop_db else []) + [conf, key_set_child()],
        inputs=[IN_VERSION_NUMBER, IN_CONFIG_KIND, IN_MAIN_SERVICE]))

# ---------------------------------------------------------------- internal/install-verify
VERSION_CHECK = r"""$ErrorActionPreference = 'Stop'
$want = '{{ProfiseeVersionNumber}}'
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$p = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^Profisee Server\b' })
if ($p.Count -ne 1) { throw "$env:COMPUTERNAME has $($p.Count) Profisee Server products installed (expected exactly 1): $(($p | ForEach-Object DisplayName) -join ', ')" }
if (-not "$($p[0].DisplayVersion)".StartsWith($want)) { throw "$env:COMPUTERNAME has $($p[0].DisplayName) version $($p[0].DisplayVersion); expected $want." }
Write-Output "$env:COMPUTERNAME runs $($p[0].DisplayName) version $($p[0].DisplayVersion) (expected $want)."
"""
verify_steps = [
    ps("Wait For Every Service", HEALTH,
       "What: Wait until every health check of the new instance is Healthy. Why: proves Configuration produced a working "
       "instance (it can exit 0 on failure). Success: all checks Healthy within 10 minutes. If it fails: open the health URL "
       "({{MainHealthUrl}}) and the Configuration log on the application server.", timeout=900),
    remote_ps("Check The Installed Version", VERSION_CHECK,
              "What: Check exactly one Profisee Server is installed on the application server and its version starts with "
              "ProfiseeVersionNumber. Why: a run must never measure the old version by mistake. Success: "
              "the version line prints. If it fails: the build installed is not the release the lane (or "
              "install/environment:ProfiseeVersionNumber) names; fix the version or pick the right build."),
]
dump(os.path.join(wl_root, 'internal', 'install-verify.workload.json'), workload(
    "install-verify",
    ("What: Check the new instance answers (every health check Healthy) and the installed Profisee Server version is the one "
     "in ProfiseeVersionNumber (the lane's, or install/environment:ProfiseeVersionNumber). Why: the proof an install worked before any pack measures it. When: last "
     "part of every install; alone any time (then pass ProfiseeVersionNumber). Needs: the instance exists. Success: Every step Succeeded. If it fails: open the "
     "first failed step, whose If it fails text names what to check."),
    ["install", "internal", "verify"],
    g("ApplicationServerName", "MainHealthUrl"), verify_steps, inputs=[IN_VERSION_NUMBER]))


# ---------------------------------------------------------------- tests and preflight
TESTS = {
    "install-clean": ("a clean install on a NEW, empty Profisee database (the database named in install/databases is dropped)",
                      [("Get The Build", "install-build-get"), ("Remove Profisee", "install-remove"),
                       ("Install The Programs", "install-programs"), ("Configure On A New Database", "install-configure-new"),
                       ("Verify", "install-verify")]),
    "install-upgrade": ("an install that KEEPS the Profisee database and upgrades it",
                        [("Get The Build", "install-build-get"), ("Remove Profisee", "install-remove"),
                         ("Install The Programs", "install-programs"),
                         ("Configure On The Existing Database", "install-configure-upgrade"), ("Verify", "install-verify")]),
}
for name, (what, kids) in TESTS.items():
    dump(os.path.join(wl_root, 'tests', name + '.workload.json'), workload(
        name,
        (f"What: Removes Profisee from the application server and installs the build under test: {what}. The build is AdoBuildId, or the latest successful build of AdoBranch "
         "(a TestAutoManager round passes both; run alone: install/build:AdoBranch and its latest build). Why: every test "
         "round starts from a known install of the build under test. When: at the start of a round on that box, never while "
         "a test runs against it. Needs: install-preflight green. Success: every child Succeeded and install-verify printed the "
         "expected version. If it fails: it stops at the first failed child; open that run's output."),
        ["install", "tests"], {**BUILD_GLOBALS, **VERSION_GLOBALS}, [run_child(l, w, f"{l}: {w}") for l, w in kids]))

PREFLIGHT = r"""$ErrorActionPreference = 'Stop'
$problems = @()
# Secrets the install uses: checked for presence only, never printed.
foreach ($pair in @(@('AZURE_DEVOPS_PAT', '{{$env:AZURE_DEVOPS_PAT}}'), @('UserCredentials:AdminUser', '{{$config:UserCredentials:AdminUser}}'),
                    @('UserCredentials:ProfAdminClientId', '{{$config:UserCredentials:ProfAdminClientId}}'))) {
    if ([string]::IsNullOrWhiteSpace($pair[1])) { $problems += "secret $($pair[0]) is empty" } else { Write-Output "secret $($pair[0]): present" }
}
# The Azure DevOps token reaches the pipeline (latest successful master build).
$pat = '{{$env:AZURE_DEVOPS_PAT}}'
$hdr = @{ Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':' + $pat)) }
$api = '{{AdoOrganizationUrl}}/{{AdoProject}}/_apis/build/builds?definitions={{AdoPipelineDefinitionId}}&branchName={{AdoBranch}}&resultFilter=succeeded&statusFilter=completed&$top=1&api-version=7.0'
try {
    $b = (Invoke-RestMethod -Uri $api -Headers $hdr -TimeoutSec 60).value | Select-Object -First 1
    if ($b) { Write-Output "latest successful build of {{AdoBranch}}: $($b.buildNumber) (finished $($b.finishTime))" } else { $problems += 'no successful build of {{AdoBranch}} found' }
} catch { $problems += "Azure DevOps refused the token or is unreachable: $($_.Exception.Message -replace '[0-9a-f]{32}', '[redacted]')" }
# The application server: admin share, license file, free disk.
$app = '{{ApplicationServerName}}'
$lic = '\\' + $app + '\' + ('{{LicenseFile}}' -replace '^([A-Za-z]):', '$1$')
if (Test-Path $lic) { Write-Output "license file present on $app" } else { $problems += "license file {{LicenseFile}} missing on $app" }
try {
    $disk = Get-CimInstance -ComputerName $app -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    $gb = [math]::Round($disk.FreeSpace / 1GB, 1); Write-Output "free space on ${app} C: $gb GB"
    if ($gb -lt 10) { $problems += "only $gb GB free on $app C: (need 10)" }
} catch { $problems += "cannot read disk space of ${app}: $($_.Exception.Message)" }
# The database server answers.
try {
    $c = New-Object System.Data.SqlClient.SqlConnection 'Server={{DatabaseServerName}};Database=master;Integrated Security=True;TrustServerCertificate=True;Connect Timeout=15'
    $c.Open(); Write-Output "SQL Server {{DatabaseServerName}} answers"; $c.Close()
} catch { $problems += "SQL Server {{DatabaseServerName}} does not answer: $($_.Exception.Message)" }
if ($problems) { throw ("Install preflight found: " + ($problems -join '; ')) }
Write-Output 'Install preflight: every check passed.'
"""
LANE_VERSION = r"""$ErrorActionPreference = 'Stop'
$prefix = '{{InstalledVersionMustBe}}'
$keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
$p = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match '^Profisee Server\b' })
if ($p.Count -ne 1) { throw "$env:COMPUTERNAME has $($p.Count) Profisee Server products installed (expected exactly 1 for a lane that tests $prefix): $(($p | ForEach-Object DisplayName) -join ', ')" }
$v = "$($p[0].DisplayVersion)"
if (-not $v.StartsWith("$prefix.")) { throw "$env:COMPUTERNAME runs Profisee Server $v; this lane tests $prefix. Pick Install, or a lane of version $v." }
Write-Output "$env:COMPUTERNAME runs Profisee Server $v, as the lane ($prefix) expects."
"""
_lane_step = remote_ps("Installed Version Matches The Lane", LANE_VERSION,
                       "What: Check exactly one Profisee Server is installed on the application server and its DisplayVersion starts "
                       "with InstalledVersionMustBe followed by a dot. Why: a lane that keeps the installed Profisee (no install) must "
                       "not run against another version. Success: the version line prints. If it fails: the message names the "
                       "installed version; pick Install in the round, or a lane of that version. Skipped when: InstalledVersionMustBe "
                       "is blank (a hand run, or a lane that installs).")
_lane_step["inline"]["runWhen"] = "{{InstalledVersionMustBe}}"
pre_steps = [
    ps("Check Secrets, Build, License, Disk And SQL", PREFLIGHT,
       "What: Check the secrets an install needs are present (not printed), the Azure DevOps token finds the latest "
       "successful master build, the license file is on the application server, it has 10 GB free, and the SQL Server "
       "answers. Why: an install must not start removing Profisee when it cannot finish. Success: 'every check passed'. If it "
       "fails: the message lists each problem."),
    remote_ps("List What Is Installed Now", REMOVE_PRODUCTS,
              "What: List the Profisee products installed on the application server (preview, nothing removed). Why: shows "
              "what an install will remove and proves the admin credential works there over CredSSP. Success: the products "
              "(or none) are listed. If it fails: WinRM/CredSSP to the application server or the admin credential is wrong."),
    _lane_step,
]
dump(os.path.join(wl_root, 'start', 'install-preflight.workload.json'), workload(
    "install-preflight",
    ("What: Check everything an install needs, changing nothing: secrets present, the Azure DevOps token finds the latest "
     "master build, license file and disk space on the application server, SQL Server answers, and what is installed now. "
     "Why: an install removes the old version first, so it must not start when it cannot finish. When: before every install "
     "and after changing install reference data. A TestAutoManager lane that keeps the installed Profisee passes "
     "InstalledVersionMustBe (the lane's build prefix); blank = no version check. Needs: the install reference sets filled in. Success: Every step Succeeded. "
     "If it fails: the failing step lists each problem."),
    ["install", "start", "preflight"],
    g("ApplicationServerName", "DatabaseServerName", RemovePreview="true", InstalledVersionMustBe="", LicenseFile=ref('environment', 'LicenseFile'),
      AdoOrganizationUrl=ref('build', 'AdoOrganizationUrl'), AdoProject=ref('build', 'AdoProject'),
      AdoPipelineDefinitionId=ref('build', 'AdoPipelineDefinitionId'), AdoBranch=ref('build', 'AdoBranch')), pre_steps))


# ---------------------------------------------------------------- internal/install-addons (Platform Tools on the app server)
CLU_EXE = ("C:\\Program Files\\Profisee\\Master Data Maestro Utilities\\" + "{{ProfiseeVersionNumber}}" +
           "\\Profisee.MasterDataMaestro.Utilities.exe")


def clu(label, key, verb, what):
    script = ("$ErrorActionPreference = 'Stop'\n"
              "$exe = '" + CLU_EXE + "'\n"
              "$file = '{{AddonFile}}'\n"
              "if (-not (Test-Path $exe)) { throw \"Platform Tools not installed on ${env:COMPUTERNAME}: $exe\" }\n"
              "if (-not (Test-Path $file)) { throw \"File not found on ${env:COMPUTERNAME}: $file\" }\n"
              "$url = 'https://" + ref('machines', 'ApplicationServerNameFQDN') + "/" + ref('instances', 'ProfiseeInstanceName') + "'\n"
              f"& $exe \"/url:$url\" '{verb}' \"/File:$file\" '/clientid:{{{{$config:UserCredentials:ProfAdminClientId}}}}' | Write-Output\n"
              "$code = $LASTEXITCODE\n"
              "# Exit codes 0 and 1 are accepted, as the old install workloads did (successExitCodes 0,1).\n"
              "if ($code -notin 0, 1) { throw \"Utilities exited $code\" }\n"
              "Write-Output \"Utilities exited $code\"\n").replace('{{AddonFile}}', ref('addons', key))
    s = remote_ps(label, script,
                  f"What: Run the Profisee utilities on the application server to {what} from install/addons:{key}. Why: "
                  "some test rounds need the model, data or accounts on top of a clean install. Success: the utility exits 0 or "
                  "1. If it fails: the file path is wrong on the application server, or the Platform Tools of this release are "
                  f"not installed. Skipped when: install/addons:{key} is blank.", timeout=3600)
    s["inline"]["runWhen"] = ref('addons', key)
    return s


dump(os.path.join(wl_root, 'internal', 'install-addons.workload.json'), workload(
    "install-addons",
    ("What: Import a model, deploy a data archive and import accounts and teams with the Profisee utilities on the application "
     "server, each only when its install/addons key names a file. Why: rounds that start from a clean database but need a "
     "model. When: from install-clean-base-prep after install-verify; alone after an install. Needs: Platform Tools of this "
     "release installed; the files on the application server; secret UserCredentials:ProfAdminClientId. Success: every step "
     "Succeeded or Skipped. If it fails: open the failed step."),
    ["install", "internal", "addons"], g("ApplicationServerName"),
    [clu("Import The Model", "ModelFile", "/Import", "import the model"),
     clu("Deploy The Data Archive", "ArchiveFile", "/deploydata", "deploy the data archive"),
     clu("Import Accounts And Teams", "UsersFile", "/Import", "import the accounts and teams")],
    inputs=[IN_VERSION_NUMBER]))

name = "install-clean-base-prep"
# The name is kept (rounds and profiles use it); since 11/08 each pack run configures its own base (install-configure-upgrade).
kids = TESTS["install-clean"][1] + [("Add-Ons", "install-addons")]
dump(os.path.join(wl_root, 'tests', name + '.workload.json'), workload(
    name,
    ("What: install-clean (remove, install the build under test, new empty database), then the add-ons in install/addons "
     "(on that clean database). The pack base backups are NOT touched here: every pack run restores its base, runs "
     "Configuration on it (install-configure-upgrade) and backs up a run-start copy before it tests. Why: the default start of "
     "a test round: the build under test installed. When: at the start of a round on that box, never while a test runs "
     "against it; run each pack's setup after it. Needs: install-preflight green. Success: every child Succeeded or Skipped. If it fails: it stops at the first failed "
     "child; open that run's output."),
    ["install", "tests"], {**BUILD_GLOBALS, **VERSION_GLOBALS}, [run_child(l, w, f"{l}: {w}") for l, w in kids]))

print("install pack written")
