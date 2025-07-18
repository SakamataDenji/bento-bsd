# bento_utils.nim - Utility functions and configuration management

import std/[json, times, os, strutils, strformat]

type
  BentoConfig = object
    enableParallelOps: bool
    maxConcurrentDownloads: int
    cveUpdateInterval: int  # hours
    debugMode: bool
    logRetentionDays: int
    autoCleanCache: bool
    pgpVerificationRequired: bool
    allowUnsupportedBSD: bool
    customCVESources: seq[string]
    networkTimeout: int  # seconds
    
  PerformanceMetrics = object
    operationName: string
    startTime: DateTime
    endTime: DateTime
    duration: float
    success: bool
    resourceUsage: ResourceUsage
    
  ResourceUsage = object
    memoryUsed: int  # KB
    cpuPercent: float
    diskIO: int      # bytes

const
  DEFAULT_CONFIG = BentoConfig(
    enableParallelOps: true,
    maxConcurrentDownloads: 4,
    cveUpdateInterval: 24,
    debugMode: false,
    logRetentionDays: 30,
    autoCleanCache: true,
    pgpVerificationRequired: false,
    allowUnsupportedBSD: false,
    customCVESources: @[],
    networkTimeout: 30
  )

var
  currentConfig: BentoConfig = DEFAULT_CONFIG
  performanceMetrics: seq[PerformanceMetrics]

# Configuration management
proc loadConfig(): BentoConfig =
  let configFile = BENTO_CACHE_DIR / "config.json"
  
  if not fileExists(configFile):
    return DEFAULT_CONFIG
  
  try:
    let jsonStr = readFile(configFile)
    let jsonData = parseJson(jsonStr)
    
    result = BentoConfig(
      enableParallelOps: jsonData{"enableParallelOps"}.getBool(DEFAULT_CONFIG.enableParallelOps),
      maxConcurrentDownloads: jsonData{"maxConcurrentDownloads"}.getInt(DEFAULT_CONFIG.maxConcurrentDownloads),
      cveUpdateInterval: jsonData{"cveUpdateInterval"}.getInt(DEFAULT_CONFIG.cveUpdateInterval),
      debugMode: jsonData{"debugMode"}.getBool(DEFAULT_CONFIG.debugMode),
      logRetentionDays: jsonData{"logRetentionDays"}.getInt(DEFAULT_CONFIG.logRetentionDays),
      autoCleanCache: jsonData{"autoCleanCache"}.getBool(DEFAULT_CONFIG.autoCleanCache),
      pgpVerificationRequired: jsonData{"pgpVerificationRequired"}.getBool(DEFAULT_CONFIG.pgpVerificationRequired),
      allowUnsupportedBSD: jsonData{"allowUnsupportedBSD"}.getBool(DEFAULT_CONFIG.allowUnsupportedBSD),
      networkTimeout: jsonData{"networkTimeout"}.getInt(DEFAULT_CONFIG.networkTimeout)
    )
    
    # Load custom CVE sources
    if jsonData.hasKey("customCVESources"):
      for source in jsonData["customCVESources"]:
        result.customCVESources.add(source.getStr())
    
  except Exception as e:
    logError("Failed to load config, using defaults", e)
    return DEFAULT_CONFIG

proc saveConfig(config: BentoConfig) =
  let configFile = BENTO_CACHE_DIR / "config.json"
  
  try:
    ensureCacheDir()
    
    let jsonData = %* {
      "enableParallelOps": config.enableParallelOps,
      "maxConcurrentDownloads": config.maxConcurrentDownloads,
      "cveUpdateInterval": config.cveUpdateInterval,
      "debugMode": config.debugMode,
      "logRetentionDays": config.logRetentionDays,
      "autoCleanCache": config.autoCleanCache,
      "pgpVerificationRequired": config.pgpVerificationRequired,
      "allowUnsupportedBSD": config.allowUnsupportedBSD,
      "customCVESources": config.customCVESources,
      "networkTimeout": config.networkTimeout,
      "lastModified": now().format("yyyy-MM-dd'T'HH:mm:ss")
    }
    
    writeFile(configFile, jsonData.pretty())
    success("Configuration saved successfully")
    
  except Exception as e:
    logError("Failed to save configuration", e)

# Performance monitoring
proc startMetric(operationName: string): PerformanceMetrics =
  result = PerformanceMetrics(
    operationName: operationName,
    startTime: now(),
    success: false
  )
  
  # Get initial resource usage
  try:
    result.resourceUsage = getCurrentResourceUsage()
  except:
    discard  # Non-critical

proc endMetric(metric: var PerformanceMetrics, success: bool = true) =
  metric.endTime = now()
  metric.duration = (metric.endTime - metric.startTime).inMilliseconds().float / 1000.0
  metric.success = success
  
  # Calculate resource usage difference
  try:
    let finalUsage = getCurrentResourceUsage()
    metric.resourceUsage.memoryUsed = finalUsage.memoryUsed - metric.resourceUsage.memoryUsed
  except:
    discard
  
  performanceMetrics.add(metric)
  
  if currentConfig.debugMode:
    info(fmt"⏱️ {metric.operationName}: {metric.duration:.2f}s ({'✅' if success else '❌'})")

proc getCurrentResourceUsage(): ResourceUsage =
  try:
    # Get memory usage from /proc/self/status (if available)
    when defined(linux) or defined(freebsd):
      let (memOutput, _) = runCommand("ps", "-o", "rss=", "-p", $getCurrentProcessId())
      result.memoryUsed = parseInt(memOutput.strip())
    
    # CPU percentage is harder to get instantly, so we'll skip for now
    result.cpuPercent = 0.0
    result.diskIO = 0
    
  except:
    result = ResourceUsage(memoryUsed: 0, cpuPercent: 0.0, diskIO: 0)

proc showPerformanceReport() =
  if performanceMetrics.len == 0:
    info("No performance metrics available")
    return
  
  let successCount = performanceMetrics.count(m => m.success)
  let totalTime = performanceMetrics.mapIt(it.duration).foldl(a + b, 0.0)
  let avgTime = totalTime / performanceMetrics.len.float
  
  createInfoBox("PERFORMANCE METRICS", @[
    fmt"Total operations: {performanceMetrics.len}",
    fmt"Successful: {successCount} ({(successCount * 100 / performanceMetrics.len).int}%)",
    fmt"Total time: {totalTime:.2f}s",
    fmt"Average time: {avgTime:.2f}s",
    "",
    "Slowest operations:"
  ], fgCyan)
  
  # Show top 5 slowest operations
  let sortedMetrics = performanceMetrics.sorted((a, b) => cmp(b.duration, a.duration))
  
  for i, metric in sortedMetrics[0..min(4, sortedMetrics.len-1)]:
    let status = if metric.success: "✅" else "❌"
    echo fmt"  {i+1}. {metric.operationName}: {metric.duration:.2f}s {status}"

# Cache management
proc cleanOldLogs() =
  try:
    let cutoffDate = now() - initDuration(days = currentConfig.logRetentionDays)
    
    for logFile in @[ERROR_LOG, SECURITY_LOG]:
      if fileExists(logFile):
        let fileTime = getLastModificationTime(logFile)
        if fileTime < cutoffDate:
          removeFile(logFile)
          info(fmt"Cleaned old log file: {extractFilename(logFile)}")
    
  except Exception as e:
    logError("Failed to clean old logs", e)

proc cleanCache() =
  var metric = startMetric("cache_cleanup")
  
  try:
    info("🧹 Cleaning cache directories...")
    
    let cacheSize = safeFileOperation(
      proc(): int64 = getDirSize(BENTO_CACHE_DIR),
      "Failed to get cache size",
      0i64
    )
    
    # Clean temporary files
    let tempDir = BENTO_CACHE_DIR / "temp"
    if dirExists(tempDir):
      removeDir(tempDir)
    
    # Clean old CVE cache if > 7 days old
    if fileExists(CVE_DATABASE):
      let cveAge = now() - getLastModificationTime(CVE_DATABASE)
      if cveAge.inDays() > 7:
        removeFile(CVE_DATABASE)
        info("Removed old CVE cache")
    
    # Clean logs if configured
    if currentConfig.autoCleanCache:
      cleanOldLogs()
    
    let newCacheSize = safeFileOperation(
      proc(): int64 = getDirSize(BENTO_CACHE_DIR),
      "Failed to get new cache size",
      0i64
    )
    
    let savedSpace = cacheSize - newCacheSize
    success(fmt"Cache cleaned. Freed {formatSize(savedSpace)}")
    
    endMetric(metric, true)
    
  except Exception as e:
    logError("Cache cleanup failed", e)
    endMetric(metric, false)

proc formatSize(bytes: int64): string =
  const units = ["B", "KB", "MB", "GB"]
  var size = bytes.float
  var unitIndex = 0
  
  while size >= 1024.0 and unitIndex < units.len - 1:
    size = size / 1024.0
    inc unitIndex
  
  return fmt"{size:.1f} {units[unitIndex]}"

proc getDirSize(path: string): int64 =
  var totalSize = 0i64
  
  for kind, file in walkDir(path, relative = false):
    case kind
    of pcFile:
      totalSize += getFileSize(file)
    of pcDir:
      totalSize += getDirSize(file)
    else:
      discard
  
  return totalSize

# Network operations with timeout and retry
proc downloadWithRetry(url: string, maxRetries: int = 3): string =
  var attempts = 0
  var lastError: string
  
  while attempts < maxRetries:
    var metric = startMetric(fmt"download_{extractFilename(url)}")
    
    try:
      let client = newHttpClient(timeout = currentConfig.networkTimeout * 1000)
      defer: client.close()
      
      let response = client.getContent(url)
      endMetric(metric, true)
      return response
      
    except Exception as e:
      lastError = e.msg
      logError(fmt"Download attempt {attempts + 1} failed for {url}", e)
      endMetric(metric, false)
      
      inc attempts
      if attempts < maxRetries:
        sleep(2000 * attempts)  # Exponential backoff
  
  raise newException(IOError, fmt"Failed to download {url} after {maxRetries} attempts. Last error: {lastError}")

# Configuration commands
proc showConfig() =
  createInfoBox("BENTO CONFIGURATION", @[
    fmt"Parallel operations: {if currentConfig.enableParallelOps: \"Enabled\" else: \"Disabled\"}",
    fmt"Max concurrent downloads: {currentConfig.maxConcurrentDownloads}",
    fmt"CVE update interval: {currentConfig.cveUpdateInterval} hours",
    fmt"Debug mode: {if currentConfig.debugMode: \"Enabled\" else: \"Disabled\"}",
    fmt"Log retention: {currentConfig.logRetentionDays} days",
    fmt"Auto clean cache: {if currentConfig.autoCleanCache: \"Enabled\" else: \"Disabled\"}",
    fmt"PGP verification required: {if currentConfig.pgpVerificationRequired: \"Yes\" else: \"No\"}",
    fmt"Allow unsupported BSD: {if currentConfig.allowUnsupportedBSD: \"Yes\" else: \"No\"}",
    fmt"Network timeout: {currentConfig.networkTimeout} seconds",
    fmt"Custom CVE sources: {currentConfig.customCVESources.len}",
    "",
    "Use 'bento config set <option> <value>' to modify"
  ], fgCyan)

proc setConfigOption(option: string, value: string) =
  var newConfig = currentConfig
  var changed = false
  
  case option.toLowerAscii()
  of "parallel", "enableparallelops":
    newConfig.enableParallelOps = parseBool(value)
    changed = true
  of "downloads", "maxconcurrentdownloads":
    newConfig.maxConcurrentDownloads = parseInt(value)
    changed = true
  of "cveinterval", "cveupdateinterval":
    newConfig.cveUpdateInterval = parseInt(value)
    changed = true
  of "debug", "debugmode":
    newConfig.debugMode = parseBool(value)
    changed = true
  of "logretention", "logretentiondays":
    newConfig.logRetentionDays = parseInt(value)
    changed = true
  of "autoclean", "autocleancache":
    newConfig.autoCleanCache = parseBool(value)
    changed = true
  of "pgprequired", "pgpverificationrequired":
    newConfig.pgpVerificationRequired = parseBool(value)
    changed = true
  of "allowunsupported", "allowunsupportedbsd":
    newConfig.allowUnsupportedBSD = parseBool(value)
    changed = true
  of "timeout", "networktimeout":
    newConfig.networkTimeout = parseInt(value)
    changed = true
  else:
    error(fmt"Unknown configuration option: {option}")
    return
  
  if changed:
    currentConfig = newConfig
    saveConfig(currentConfig)
    success(fmt"Configuration updated: {option} = {value}")
  else:
    error("Failed to update configuration")

# System health monitoring
proc checkSystemHealth(): tuple[healthy: bool, issues: seq[string], warnings: seq[string]] =
  var issues: seq[string]
  var warnings: seq[string]
  
  try:
    # Check disk space
    let (dfOutput, dfCode, dfSuccess) = safeRunCommand("df", "-h", "/")
    if dfSuccess:
      for line in dfOutput.splitLines()[1..^1]:
        if line.strip() != "":
          let parts = line.split()
          if parts.len >= 5:
            let usage = parts[4].replace("%", "")
            if parseInt(usage) > 90:
              issues.add(fmt"Disk usage critical: {usage}%")
            elif parseInt(usage) > 80:
              warnings.add(fmt"Disk usage high: {usage}%")
    
    # Check memory usage
    let cacheSize = getDirSize(BENTO_CACHE_DIR)
    if cacheSize > 1024 * 1024 * 1024:  # 1GB
      warnings.add(fmt"Large cache size: {formatSize(cacheSize)}")
    
    # Check log file sizes
    for logFile in @[ERROR_LOG, SECURITY_LOG]:
      if fileExists(logFile):
        let logSize = getFileSize(logFile)
        if logSize > 10 * 1024 * 1024:  # 10MB
          warnings.add(fmt"Large log file: {extractFilename(logFile)} ({formatSize(logSize)})")
    
    # Check for stale CVE database
    if fileExists(CVE_DATABASE):
      let cveAge = now() - getLastModificationTime(CVE_DATABASE)
      if cveAge.inDays() > currentConfig.cveUpdateInterval / 24:
        warnings.add("CVE database needs update")
    else:
      issues.add("CVE database missing")
    
    # Check PGP configuration if required
    if currentConfig.pgpVerificationRequired and not dirExists(PGP_KEYRING):
      issues.add("PGP verification required but not configured")
    
  except Exception as e:
    logError("System health check failed", e)
    issues.add("Health check system error")
  
  return (issues.len == 0, issues, warnings)

proc performHealthCheck() =
  info("💊 Performing system health check...")
  
  let (healthy, issues, warnings) = checkSystemHealth()
  
  let statusColor = if healthy and warnings.len == 0: fgGreen
                   elif healthy: fgYellow
                   else: fgRed
  
  let healthStatus = if healthy and warnings.len == 0: "🟢 HEALTHY"
                    elif healthy: "🟡 MINOR ISSUES"
                    else: "🔴 CRITICAL ISSUES"
  
  var reportLines = @[
    fmt"Overall status: {healthStatus}",
    fmt"Critical issues: {issues.len}",
    fmt"Warnings: {warnings.len}",
    ""
  ]
  
  if issues.len > 0:
    reportLines.add("❌ CRITICAL ISSUES:")
    for issue in issues:
      reportLines.add(fmt"  • {issue}")
    reportLines.add("")
  
  if warnings.len > 0:
    reportLines.add("⚠️ WARNINGS:")
    for warning in warnings:
      reportLines.add(fmt"  • {warning}")
    reportLines.add("")
  
  if healthy and warnings.len == 0:
    reportLines.add("✅ All systems operating normally")
  else:
    reportLines.add("Recommendations:")
    if issues.len > 0:
      reportLines.add("  • Address critical issues immediately")
    if warnings.len > 0:
      reportLines.add("  • Review warnings when convenient")
    reportLines.add("  • Run 'bento clean' to free space")
    reportLines.add("  • Run 'bento audit' for security check")
  
  createInfoBox("SYSTEM HEALTH REPORT", reportLines, statusColor)

# Advanced diagnostic commands
proc runDiagnostics() =
  info("🔧 Running comprehensive diagnostics...")
  
  var diagnosticResults: seq[string]
  
  # Test 1: Package manager connectivity
  var metric1 = startMetric("pkg_connectivity_test")
  let (pkgOutput, pkgCode, pkgSuccess) = safeRunCommand(PKG_CMD, "version")
  endMetric(metric1, pkgSuccess)
  
  if pkgSuccess:
    diagnosticResults.add("✅ Package manager: Working")
  else:
    diagnosticResults.add("❌ Package manager: Failed")
  
  # Test 2: Network connectivity
  var metric2 = startMetric("network_connectivity_test")
  try:
    let testUrl = "https://pkg.freebsd.org"
    let client = newHttpClient(timeout = 5000)
    defer: client.close()
    discard client.getContent(testUrl)
    diagnosticResults.add("✅ Network connectivity: Working")
    endMetric(metric2, true)
  except:
    diagnosticResults.add("❌ Network connectivity: Failed")
    endMetric(metric2, false)
  
  # Test 3: CVE database status
  if fileExists(CVE_DATABASE):
    let cveAge = now() - getLastModificationTime(CVE_DATABASE)
    let ageStr = fmt"{cveAge.inDays()} days old"
    diagnosticResults.add(fmt"✅ CVE database: Available ({ageStr})")
  else:
    diagnosticResults.add("⚠️ CVE database: Missing")
  
  # Test 4: PGP configuration
  if dirExists(PGP_KEYRING):
    let (gpgOutput, gpgCode, gpgSuccess) = safeRunCommand("gpg", "--homedir", PGP_KEYRING, "--list-keys")
    if gpgSuccess and gpgOutput.strip() != "":
      diagnosticResults.add("✅ PGP configuration: Working")
    else:
      diagnosticResults.add("⚠️ PGP configuration: No keys found")
  else:
    diagnosticResults.add("⚠️ PGP configuration: Not configured")
  
  # Test 5: Cache directory permissions
  try:
    let testFile = BENTO_CACHE_DIR / "test_write"
    writeFile(testFile, "test")
    removeFile(testFile)
    diagnosticResults.add("✅ Cache directory: Writable")
  except:
    diagnosticResults.add("❌ Cache directory: Permission error")
  
  # Test 6: Performance metrics
  if performanceMetrics.len > 0:
    let avgTime = performanceMetrics.mapIt(it.duration).foldl(a + b, 0.0) / performanceMetrics.len.float
    diagnosticResults.add(fmt"📊 Average operation time: {avgTime:.2f}s")
  else:
    diagnosticResults.add("📊 Performance metrics: No data")
  
  createInfoBox("DIAGNOSTIC RESULTS", diagnosticResults, fgCyan)
  
  # Show performance report if available
  if performanceMetrics.len > 0:
    echo ""
    showPerformanceReport()

# Initialize utilities
proc initializeUtils() =
  currentConfig = loadConfig()
  
  # Apply configuration
  debugMode = currentConfig.debugMode
  
  # Clean cache if configured
  if currentConfig.autoCleanCache:
    cleanCache()

# Export functions for main module
proc getConfig*(): BentoConfig = currentConfig
proc setDebugMode*(enabled: bool) = 
  currentConfig.debugMode = enabled
  saveConfig(currentConfig)
