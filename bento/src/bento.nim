import std/[os, strutils, strformat, terminal, osproc, tables, sequtils, json, re, times, httpclient, base64, random, xmlparser, xmltree, asyncdispatch, threadpool, logging, streams]

# Import flag system
include "bento_flags.nim"

const
  BENTO_VERSION = "1.0.0"
  PKG_CMD = "pkg"
  PORTS_DIR = "/usr/ports"
  MAKE_CMD = "make"
  BENTO_CACHE_DIR = getHomeDir() / ".bento"
  SECURITY_LOG = BENTO_CACHE_DIR / "security.log"
  ERROR_LOG = BENTO_CACHE_DIR / "errors.log"
  CVE_DATABASE = BENTO_CACHE_DIR / "cve_cache.json"
  CVE_NVD_CACHE = BENTO_CACHE_DIR / "nvd_cache.json"
  PGP_KEYRING = BENTO_CACHE_DIR / "pgp_keys"
  
  # Enhanced CVE sources
  FREEBSD_VULN_URL = "https://www.freebsd.org/security/advisories.rdf"
  NVD_CVE_API = "https://services.nvd.nist.gov/rest/json/cves/2.0"
  MITRE_CVE_API = "https://cveawg.mitre.org/api/cve"
  
  # BSD variants detection
  BSD_VARIANTS = @["FreeBSD", "OpenBSD", "NetBSD", "DragonFly", "MidnightBSD", "GhostBSD", "TrueOS", "FuryBSD"]

type
  BentoError = object of CatchableError
  
  PackageInfo = object
    name: string
    version: string
    description: string
    installed: bool
    dependencies: seq[string]
    reverseDependencies: seq[string]
    sha256: string
    signature: string
    verified: bool
    maintainer: string
    isOrphaned: bool
    lastUpdate: string
    vulnerabilities: seq[CVEInfo]
  
  PortInfo = object
    name: string
    category: string
    path: string
    description: string
    maintainer: string
    depends: seq[string]
    isOrphaned: bool
  
  CVEInfo = object
    id: string
    severity: string
    description: string
    affectedVersions: seq[string]
    patchAvailable: bool
    publishDate: string
    cvssScore: float
    source: string  # FreeBSD, NVD, MITRE
  
  SecurityStatus = enum
    SecurityOK, SecurityWarning, SecurityError, SecurityUnknown, SecurityCritical
  
  ProgressBar = object
    width: int
    current: int
    total: int
    title: string
  
  MaintenanceStatus = enum
    ActiveMaintenance, DeprecatedMaintenance, OrphanedPackage, UnknownMaintenance
  
  BSDVariant = object
    name: string
    version: string
    compatible: bool
    pkgManager: string
    portsPath: string
  
  AsyncTask = object
    name: string
    started: bool
    completed: bool
    result: string
    error: string

# Enhanced logging system
var
  errorLogger: FileLogger
  securityLogger: FileLogger
  debugMode: bool = false

proc initLogging() =
  ensureCacheDir()
  
  # Initialize loggers
  errorLogger = newFileLogger(ERROR_LOG, fmtStr = "[$datetime] $levelname: ")
  securityLogger = newFileLogger(SECURITY_LOG, fmtStr = "[$datetime] SECURITY: ")
  
  # Set logging levels
  errorLogger.levelThreshold = lvlError
  securityLogger.levelThreshold = lvlInfo
  
  addHandler(errorLogger)
  
  if debugMode:
    addHandler(newConsoleLogger(fmtStr = "DEBUG: $message"))

proc logError(message: string, exception: ref Exception = nil) =
  let fullMessage = if exception != nil:
    fmt"{message}: {exception.msg}\nStacktrace: {exception.getStackTrace()}"
  else:
    message
  
  try:
    error(fullMessage)
    if errorLogger != nil:
      errorLogger.log(lvlError, fullMessage)
  except:
    # Fallback to stderr if logging fails
    stderr.writeLine(fmt"LOGGING ERROR: {fullMessage}")

proc logSecurity(message: string, level: SecurityStatus) =
  let logLevel = case level
    of SecurityCritical: lvlFatal
    of SecurityError: lvlError
    of SecurityWarning: lvlWarn
    else: lvlInfo
  
  try:
    if securityLogger != nil:
      securityLogger.log(logLevel, message)
  except:
    stderr.writeLine(fmt"SECURITY LOG ERROR: {message}")

# BSD Detection and Compatibility
proc detectBSDVariant(): BSDVariant =
  var bsdInfo = BSDVariant()
  
  try:
    let (unameOutput, unameCode) = runCommand("uname", "-s")
    let (versionOutput, versionCode) = runCommand("uname", "-r")
    
    if unameCode == 0:
      bsdInfo.name = unameOutput.strip()
      
      if versionCode == 0:
        bsdInfo.version = versionOutput.strip()
      
      # Check compatibility
      bsdInfo.compatible = bsdInfo.name in BSD_VARIANTS
      
      # Determine package manager
      case bsdInfo.name
      of "FreeBSD", "GhostBSD", "TrueOS", "FuryBSD", "MidnightBSD":
        bsdInfo.pkgManager = "pkg"
        bsdInfo.portsPath = "/usr/ports"
      of "OpenBSD":
        bsdInfo.pkgManager = "pkg_add"
        bsdInfo.portsPath = "/usr/ports"
      of "NetBSD":
        bsdInfo.pkgManager = "pkgin"
        bsdInfo.portsPath = "/usr/pkgsrc"
      of "DragonFly":
        bsdInfo.pkgManager = "pkg"
        bsdInfo.portsPath = "/usr/dports"
      else:
        bsdInfo.compatible = false
        bsdInfo.pkgManager = "unknown"
    
  except Exception as e:
    logError("Failed to detect BSD variant", e)
    bsdInfo.compatible = false
  
  return bsdInfo

proc showBSDCompatibility() =
  let bsdInfo = detectBSDVariant()
  
  createInfoBox("BSD SYSTEM COMPATIBILITY", @[
    fmt"Detected System: {bsdInfo.name} {bsdInfo.version}",
    fmt"Compatibility: {if bsdInfo.compatible: \"✅ Supported\" else: \"❌ Not Supported\"}",
    fmt"Package Manager: {bsdInfo.pkgManager}",
    fmt"Ports Path: {bsdInfo.portsPath}",
    "",
    if bsdInfo.compatible: "All Bento features available" else: "Limited functionality - FreeBSD recommended"
  ], if bsdInfo.compatible: fgGreen else: fgRed)

# Parallelized operations using async
proc downloadCVEDatabaseAsync(): Future[bool] {.async.} =
  try:
    info("📥 Downloading CVE databases asynchronously...")
    
    # Create async HTTP client
    let client = newAsyncHttpClient()
    defer: client.close()
    
    # Download FreeBSD advisories
    let freebsdTask = client.getContent(FREEBSD_VULN_URL)
    
    # Download NVD data (recent CVEs)
    let currentYear = now().year
    let nvdUrl = fmt"{NVD_CVE_API}?startIndex=0&resultsPerPage=100&pubStartDate={currentYear}-01-01T00:00:00.000&pubEndDate={currentYear}-12-31T23:59:59.999"
    let nvdTask = client.getContent(nvdUrl)
    
    # Wait for both downloads
    let freebsdData = await freebsdTask
    let nvdData = await nvdTask
    
    # Save FreeBSD data
    writeFile(CVE_DATABASE, freebsdData)
    
    # Save NVD data
    writeFile(CVE_NVD_CACHE, nvdData)
    
    success("✅ CVE databases updated successfully")
    logSecurity("CVE databases updated", SecurityOK)
    return true
    
  except Exception as e:
    logError("Failed to download CVE databases", e)
    return false

proc verifyPackageIntegrityAsync(packageName: string): Future[bool] {.async.} =
  try:
    info(fmt"🔍 Verifying {packageName} integrity asynchronously...")
    
    # Start multiple verification tasks in parallel
    let signatureTask = spawn verifyPackageSignature(packageName)
    let checksumTask = spawn verifyPackageChecksum(packageName)
    let vulnTask = spawn checkPackageVulnerabilities(packageName)
    
    # Wait for all tasks
    let signatureOK = ^signatureTask
    let checksumOK = ^checksumTask
    let vulnerabilities = ^vulnTask
    
    let result = signatureOK and checksumOK and vulnerabilities.len == 0
    
    if result:
      security(fmt"✅ {packageName} passed all integrity checks", SecurityOK)
    else:
      security(fmt"⚠️ {packageName} failed some integrity checks", SecurityWarning)
    
    return result
    
  except Exception as e:
    logError(fmt"Failed to verify package integrity for {packageName}", e)
    return false

proc scanOrphanedPackagesAsync(): Future[seq[string]] {.async.} =
  try:
    info("🏚️ Scanning for orphaned packages asynchronously...")
    
    # Use spawn for CPU-intensive orphan scanning
    let orphanTask = spawn scanOrphanedPackages()
    let result = ^orphanTask
    
    logSecurity(fmt"Found {result.len} orphaned packages", 
               if result.len > 0: SecurityWarning else: SecurityOK)
    
    return result
    
  except Exception as e:
    logError("Failed to scan orphaned packages", e)
    return @[]

# Enhanced CVE parsing with multiple sources
proc parseEnhancedCVEData(packageName: string): seq[CVEInfo] =
  var cves: seq[CVEInfo]
  
  try:
    # Parse FreeBSD CVE data
    if fileExists(CVE_DATABASE):
      let freebsdContent = readFile(CVE_DATABASE)
      let freebsdCVEs = parseFreeBSDCVEs(freebsdContent, packageName)
      cves.add(freebsdCVEs)
    
    # Parse NVD CVE data
    if fileExists(CVE_NVD_CACHE):
      let nvdContent = readFile(CVE_NVD_CACHE)
      let nvdCVEs = parseNVDCVEs(nvdContent, packageName)
      cves.add(nvdCVEs)
    
  except Exception as e:
    logError(fmt"Failed to parse CVE data for {packageName}", e)
  
  return cves

proc parseFreeBSDCVEs(content: string, packageName: string): seq[CVEInfo] =
  var cves: seq[CVEInfo]
  
  try:
    let lines = content.splitLines()
    
    for line in lines:
      if line.toLowerAscii().contains(packageName.toLowerAscii()):
        var cve = CVEInfo()
        
        if line.contains("CVE-"):
          let cveMatch = line.find("CVE-")
          if cveMatch >= 0:
            cve.id = line[cveMatch..min(cveMatch+12, line.len-1)]
            cve.description = line
            cve.severity = extractSeverity(line)
            cve.source = "FreeBSD"
            cve.publishDate = now().format("yyyy-MM-dd")
            cves.add(cve)
    
  except Exception as e:
    logError("Failed to parse FreeBSD CVE data", e)
  
  return cves

proc parseNVDCVEs(content: string, packageName: string): seq[CVEInfo] =
  var cves: seq[CVEInfo]
  
  try:
    let jsonData = parseJson(content)
    
    if jsonData.hasKey("vulnerabilities"):
      for vuln in jsonData["vulnerabilities"]:
        if vuln.hasKey("cve"):
          let cveData = vuln["cve"]
          let description = cveData{"descriptions"}[0]{"value"}.getStr("")
          
          if description.toLowerAscii().contains(packageName.toLowerAscii()):
            var cve = CVEInfo()
            cve.id = cveData{"id"}.getStr("")
            cve.description = description
            cve.source = "NVD"
            
            # Extract CVSS score
            if cveData.hasKey("metrics") and cveData["metrics"].hasKey("cvssMetricV31"):
              let cvssData = cveData["metrics"]["cvssMetricV31"][0]
              cve.cvssScore = cvssData{"cvssData"}{"baseScore"}.getFloat(0.0)
              cve.severity = cvssToSeverity(cve.cvssScore)
            
            cve.publishDate = cveData{"published"}.getStr("")
            cves.add(cve)
    
  except Exception as e:
    logError("Failed to parse NVD CVE data", e)
  
  return cves

proc extractSeverity(line: string): string =
  let lowerLine = line.toLowerAscii()
  if "critical" in lowerLine: "Critical"
  elif "high" in lowerLine: "High"
  elif "medium" in lowerLine: "Medium"
  else: "Low"

proc cvssToSeverity(score: float): string =
  if score >= 9.0: "Critical"
  elif score >= 7.0: "High"
  elif score >= 4.0: "Medium"
  else: "Low"

# Enhanced error handling with proper logging
proc safeRunCommand(cmd: string, args: varargs[string]): tuple[output: string, exitCode: int, success: bool] =
  try:
    let (output, exitCode) = runCommand(cmd, args)
    return (output, exitCode, exitCode == 0)
  except Exception as e:
    logError(fmt"Command failed: {cmd} {args.join(\" \")}", e)
    return ("", -1, false)

proc safeFileOperation[T](operation: proc(): T, errorMsg: string, default: T): T =
  try:
    return operation()
  except Exception as e:
    logError(errorMsg, e)
    return default

# Parallel security audit
proc performParallelSecurityAudit(): Future[tuple[critical: int, warnings: int, errors: seq[string]]] {.async.} =
  try:
    info("🛡️ Starting parallel security audit...")
    
    # Start multiple tasks simultaneously
    let cveUpdateTask = downloadCVEDatabaseAsync()
    let orphanScanTask = scanOrphanedPackagesAsync()
    let pkgAuditTask = spawn performPkgAudit()
    let integrityTask = spawn checkSystemIntegrity()
    
    # Wait for all tasks
    let cveSuccess = await cveUpdateTask
    let orphans = await orphanScanTask
    let auditResult = ^pkgAuditTask
    let integrityResult = ^integrityTask
    
    var critical = 0
    var warnings = 0
    var errors: seq[string]
    
    # Analyze results
    if not cveSuccess:
      errors.add("Failed to update CVE database")
    
    if orphans.len > 5:
      warnings += 1
      errors.add(fmt"{orphans.len} orphaned packages found")
    
    if not auditResult.success:
      critical += auditResult.criticalCount
      warnings += auditResult.warningCount
    
    if not integrityResult:
      critical += 1
      errors.add("System integrity check failed")
    
    logSecurity(fmt"Parallel audit completed: {critical} critical, {warnings} warnings", 
               if critical > 0: SecurityCritical else: SecurityOK)
    
    return (critical, warnings, errors)
    
  except Exception as e:
    logError("Parallel security audit failed", e)
    return (1, 0, @["Audit system failure"])

proc performPkgAudit(): tuple[success: bool, criticalCount: int, warningCount: int] =
  try:
    let (output, exitCode, success) = safeRunCommand(PKG_CMD, "audit", "-F")
    
    var criticalCount = 0
    var warningCount = 0
    
    if not success and output.strip() != "":
      for line in output.splitLines():
        if "critical" in line.toLowerAscii():
          criticalCount += 1
        else:
          warningCount += 1
    
    return (success or (criticalCount == 0), criticalCount, warningCount)
    
  except Exception as e:
    logError("pkg audit failed", e)
    return (false, 1, 0)

proc checkSystemIntegrity(): bool =
  try:
    let (output, exitCode, success) = safeRunCommand(PKG_CMD, "check", "-s", "-a")
    
    if not success:
      logError("System integrity check failed: " & output)
    
    return success
    
  except Exception as e:
    logError("System integrity check error", e)
    return false

# Enhanced main function with better error handling
proc main() =
  try:
    # Initialize logging
    initLogging()
    
    # Check BSD compatibility
    let bsdInfo = detectBSDVariant()
    if not bsdInfo.compatible:
      print_warning("Running on unsupported BSD variant - functionality may be limited")
      logSecurity(fmt"Unsupported BSD: {bsdInfo.name}", SecurityWarning)
    
    if not checkPkgAvailable():
      error("pkg is not available. Make sure you're on a compatible BSD system.")
      logError("pkg command not available")
      quit(1)
    
    let args = commandLineParams()
    
    if args.len == 0:
      showHelp()
      return
    
    # Parse flags or regular commands
    let (command, params) = processBentoFlags(args)
    
    case command
    of "install", "i":
      if params.len < 1:
        error("Specify a package to install")
        echo "Usage: bento install <package> or bento -S <package>"
        return
      for package in params:
        let success = waitFor verifyPackageIntegrityAsync(package)
        if success:
          installPackage(package)
        else:
          logError(fmt"Pre-installation verification failed for {package}")
    
    of "audit":
      let auditResult = waitFor performParallelSecurityAudit()
      
      if auditResult.critical > 0:
        error(fmt"🚨 CRITICAL: {auditResult.critical} critical security issues found")
      elif auditResult.warnings > 0:
        warning(fmt"⚠️ {auditResult.warnings} security warnings found")
      else:
        success("✅ Security audit completed - no critical issues")
      
      for err in auditResult.errors:
        echo fmt"  - {err}"
    
    of "bsd-info":
      showBSDCompatibility()
    
    of "logs":
      if params.len > 0 and params[0] == "errors":
        if fileExists(ERROR_LOG):
          echo readFile(ERROR_LOG)
        else:
          info("No error log found")
      elif params.len > 0 and params[0] == "security":
        if fileExists(SECURITY_LOG):
          echo readFile(SECURITY_LOG)
        else:
          info("No security log found")
      else:
        echo "Usage: bento logs [errors|security]"
    
    of "debug":
      debugMode = true
      initLogging()
      info("Debug mode enabled")
    
    # ... rest of the existing commands ...
    
    else:
      error(fmt"Unknown command: {command}")
      echo "Use 'bento help' or 'bento flags' for available commands"
      logError(fmt"Unknown command attempted: {command}")

  except Exception as e:
    logError("Critical error in main function", e)
    error(fmt"Critical error: {e.msg}")
    if debugMode:
      echo "Stack trace: ", e.getStackTrace()
    quit(1)

# Entry point with enhanced error handling
when isMainModule:
  try:
    main()
  except Exception as e:
    # Last resort error handling
    try:
      stderr.writeLine(fmt"FATAL ERROR: {e.msg}")
      if debugMode:
        stderr.writeLine(fmt"Stack trace: {e.getStackTrace()}")
    except:
      # If even stderr fails, try to write to a file
      try:
        let emergencyLog = "/tmp/bento_crash.log"
        writeFile(emergencyLog, fmt"FATAL CRASH: {e.msg}\n{e.getStackTrace()}")
      except:
        discard  # Nothing more we can do
    
    quit(1)
