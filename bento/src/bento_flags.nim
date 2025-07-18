# bento_flags.nim - Flag system and autocompletion for Bento Package Manager

import std/[os, strutils, strformat, terminal, osproc, tables, sequtils]

# Flag definitions - pacman/yay style
const
  SYNC_FLAGS = {
    "S": "install",      # -S package
    "Sy": "update",      # -Sy (sync database)
    "Su": "upgrade",     # -Su (upgrade system)
    "Syu": "full-update", # -Syu (update + upgrade)
    "Ss": "search",      # -Ss term
    "Si": "info",        # -Si package
    "Sc": "clean",       # -Sc (clean cache)
    "Scc": "deep-clean"  # -Scc (deep clean)
  }.toTable

const
  REMOVE_FLAGS = {
    "R": "remove",       # -R package
    "Rs": "remove-deps", # -Rs (remove with deps)
    "Rn": "autoremove",  # -Rn (remove orphans)
    "Rns": "purge"       # -Rns (complete removal)
  }.toTable

const
  QUERY_FLAGS = {
    "Q": "list",         # -Q (list installed)
    "Qi": "info",        # -Qi package (info)
    "Ql": "files",       # -Ql package (list files)
    "Qo": "owner",       # -Qo file (find owner)
    "Qm": "foreign",     # -Qm (foreign packages)
    "Qn": "native",      # -Qn (native packages)
    "Qt": "orphans",     # -Qt (orphan packages)
    "Qu": "updates"      # -Qu (check updates)
  }.toTable

const
  SECURITY_FLAGS = {
    "A": "audit",        # -A (security audit)
    "As": "security",    # -As package (security report)
    "Av": "verify",      # -Av package (verify)
    "Ac": "cve",         # -Ac CVE-ID (search CVE)
    "Ap": "pgp-setup",   # -Ap (setup PGP)
    "Am": "maintenance", # -Am package (maintenance status)
    "Ao": "obsolete",    # -Ao (obsolete packages)
    "Ah": "health"       # -Ah (system health)
  }.toTable

const
  PORT_FLAGS = {
    "P": "port-info",    # -P port (port info)
    "Ps": "port-search", # -Ps term (search ports)
    "Pi": "port-install", # -Pi path (install port)
    "Pb": "port-build",  # -Pb path (build port)
    "Pu": "port-update"  # -Pu (update ports tree)
  }.toTable

# Autocompletion data
const BASH_COMPLETION = """
# Bash completion for bento package manager
_bento_completion() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main flags
    local sync_flags="-S -Sy -Su -Syu -Ss -Si -Sc -Scc"
    local remove_flags="-R -Rs -Rn -Rns"
    local query_flags="-Q -Qi -Ql -Qo -Qm -Qn -Qt -Qu"
    local security_flags="-A -As -Av -Ac -Ap -Am -Ao -Ah"
    local port_flags="-P -Ps -Pi -Pb -Pu"
    local misc_flags="-h -V --help --version"

    # All flags combined
    local all_flags="$sync_flags $remove_flags $query_flags $security_flags $port_flags $misc_flags"

    case $prev in
        bento)
            COMPREPLY=($(compgen -W "$all_flags install remove search update upgrade info deps clean autoremove port-search port-info security audit help version" -- "$cur"))
            return 0
            ;;
        -S|-Si|-As|-Av|-Am|-Qi)
            # Package name completion
            local packages=$(pkg info -a | cut -d' ' -f1)
            COMPREPLY=($(compgen -W "$packages" -- "$cur"))
            return 0
            ;;
        -Ss|-Ps)
            # No completion for search terms
            return 0
            ;;
        -Pi|-Pb)
            # Port path completion
            COMPREPLY=($(compgen -d -- "$cur"))
            return 0
            ;;
        -Ac)
            # CVE completion (common CVE format)
            COMPREPLY=($(compgen -W "CVE-2024- CVE-2023-" -- "$cur"))
            return 0
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "$all_flags" -- "$cur"))
    fi
}

complete -F _bento_completion bento
"""

const ZSH_COMPLETION = """
#compdef bento

_bento() {
    local context state line
    typeset -A opt_args

    _arguments -C \
        '(- *)'{-h,--help}'[Show help information]' \
        '(- *)'{-V,--version}'[Show version information]' \
        '(-S --sync)'{-S,--sync}'[Synchronize packages]' \
        '(-R --remove)'{-R,--remove}'[Remove packages]' \
        '(-Q --query)'{-Q,--query}'[Query packages]' \
        '(-A --audit)'{-A,--audit}'[Security operations]' \
        '(-P --ports)'{-P,--ports}'[Ports operations]' \
        '*::bento command:_bento_commands'
}

_bento_commands() {
    local -a commands
    commands=(
        # Sync operations
        '-S:Install package'
        '-Sy:Update repositories'
        '-Su:Upgrade system'
        '-Syu:Update and upgrade'
        '-Ss:Search packages'
        '-Si:Package information'
        '-Sc:Clean cache'
        '-Scc:Deep clean cache'
        
        # Remove operations
        '-R:Remove package'
        '-Rs:Remove with dependencies'
        '-Rn:Remove orphans'
        '-Rns:Complete removal'
        
        # Query operations
        '-Q:List installed'
        '-Qi:Package info'
        '-Ql:List files'
        '-Qo:Find file owner'
        '-Qt:List orphans'
        '-Qu:Check updates'
        
        # Security operations
        '-A:Security audit'
        '-As:Security report'
        '-Av:Verify package'
        '-Ac:Search CVE'
        '-Ap:Setup PGP'
        '-Am:Maintenance status'
        '-Ao:Obsolete packages'
        '-Ah:Health check'
        
        # Ports operations
        '-P:Port info'
        '-Ps:Search ports'
        '-Pi:Install port'
        '-Pb:Build port'
        '-Pu:Update ports tree'
    )
    
    _describe 'bento commands' commands
}

_bento "$@"
"""

const FISH_COMPLETION = """
# Fish completion for bento package manager

# Sync operations
complete -c bento -s S -d "Install package" -xa "(__fish_print_packages)"
complete -c bento -o Sy -d "Update repositories"
complete -c bento -o Su -d "Upgrade system"  
complete -c bento -o Syu -d "Update and upgrade system"
complete -c bento -o Ss -d "Search packages"
complete -c bento -o Si -d "Show package information" -xa "(__fish_print_packages)"
complete -c bento -o Sc -d "Clean package cache"
complete -c bento -o Scc -d "Deep clean package cache"

# Remove operations
complete -c bento -s R -d "Remove package" -xa "(__fish_print_packages)"
complete -c bento -o Rs -d "Remove package with dependencies" -xa "(__fish_print_packages)"
complete -c bento -o Rn -d "Remove orphaned packages"
complete -c bento -o Rns -d "Complete package removal" -xa "(__fish_print_packages)"

# Query operations
complete -c bento -s Q -d "List installed packages"
complete -c bento -o Qi -d "Show installed package info" -xa "(__fish_print_packages)"
complete -c bento -o Ql -d "List package files" -xa "(__fish_print_packages)"
complete -c bento -o Qo -d "Find package owning file"
complete -c bento -o Qt -d "List orphaned packages"
complete -c bento -o Qu -d "Check for package updates"

# Security operations
complete -c bento -s A -d "Run security audit"
complete -c bento -o As -d "Security report for package" -xa "(__fish_print_packages)"
complete -c bento -o Av -d "Verify package integrity" -xa "(__fish_print_packages)"
complete -c bento -o Ac -d "Search CVE database"
complete -c bento -o Ap -d "Setup PGP verification"
complete -c bento -o Am -d "Check maintenance status" -xa "(__fish_print_packages)"
complete -c bento -o Ao -d "Find obsolete packages"
complete -c bento -o Ah -d "System health check"

# Ports operations
complete -c bento -s P -d "Show port information"
complete -c bento -o Ps -d "Search ports tree"
complete -c bento -o Pi -d "Install from port"
complete -c bento -o Pb -d "Build port"
complete -c bento -o Pu -d "Update ports tree"

# General options
complete -c bento -s h -l help -d "Show help information"
complete -c bento -s V -l version -d "Show version information"

# Function to get installed packages
function __fish_print_packages
    pkg info -a | cut -d' ' -f1
end
"""

# Function to parse flags and convert to commands
proc parseFlags(args: seq[string]): tuple[command: string, params: seq[string]] =
  if args.len == 0:
    return ("help", @[])
  
  let flag = args[0]
  var params = if args.len > 1: args[1..^1] else: @[]
  
  # Check sync flags (most common)
  if SYNC_FLAGS.hasKey(flag):
    return (SYNC_FLAGS[flag], params)
  
  # Check remove flags
  if REMOVE_FLAGS.hasKey(flag):
    return (REMOVE_FLAGS[flag], params)
  
  # Check query flags
  if QUERY_FLAGS.hasKey(flag):
    return (QUERY_FLAGS[flag], params)
  
  # Check security flags
  if SECURITY_FLAGS.hasKey(flag):
    return (SECURITY_FLAGS[flag], params)
  
  # Check port flags
  if PORT_FLAGS.hasKey(flag):
    return (PORT_FLAGS[flag], params)
  
  # Handle special cases
  case flag
  of "-h", "--help":
    return ("help", @[])
  of "-V", "--version":
    return ("version", @[])
  else:
    # If not a flag, treat as regular command
    return (flag, params)

# Function to install shell completion
proc installCompletion(shell: string) =
  let homeDir = getHomeDir()
  
  case shell.toLowerAscii()
  of "bash":
    let bashCompletionDir = homeDir / ".bash_completion.d"
    let bashRc = homeDir / ".bashrc"
    
    if not dirExists(bashCompletionDir):
      createDir(bashCompletionDir)
    
    let completionFile = bashCompletionDir / "bento"
    writeFile(completionFile, BASH_COMPLETION)
    
    # Add source line to .bashrc if not present
    let bashrcContent = if fileExists(bashRc): readFile(bashRc) else: ""
    if not bashrcContent.contains("bento"):
      let sourceLine = fmt"source {completionFile}"
      appendFile(bashRc, "\n# Bento package manager completion\n" & sourceLine & "\n")
    
    echo "✅ Bash completion installed successfully"
    echo fmt"📝 Added to: {completionFile}"
    echo "🔄 Restart your shell or run: source ~/.bashrc"
  
  of "zsh":
    let zshCompletionDir = homeDir / ".zsh" / "completions"
    let zshRc = homeDir / ".zshrc"
    
    if not dirExists(zshCompletionDir):
      createDirRecursive(zshCompletionDir)
    
    let completionFile = zshCompletionDir / "_bento"
    writeFile(completionFile, ZSH_COMPLETION)
    
    # Add fpath and autoload to .zshrc if not present
    let zshrcContent = if fileExists(zshRc): readFile(zshRc) else: ""
    if not zshrcContent.contains("bento"):
      let setupLines = fmt"""
# Bento package manager completion
fpath=({zshCompletionDir} $fpath)
autoload -U compinit && compinit
"""
      appendFile(zshRc, setupLines)
    
    echo "✅ Zsh completion installed successfully"
    echo fmt"📝 Added to: {completionFile}"
    echo "🔄 Restart your shell or run: source ~/.zshrc"
  
  of "fish":
    let fishCompletionDir = homeDir / ".config" / "fish" / "completions"
    
    if not dirExists(fishCompletionDir):
      createDirRecursive(fishCompletionDir)
    
    let completionFile = fishCompletionDir / "bento.fish"
    writeFile(completionFile, FISH_COMPLETION)
    
    echo "✅ Fish completion installed successfully"
    echo fmt"📝 Added to: {completionFile}"
    echo "🔄 Restart your shell or run: fish"
  
  else:
    echo "❌ Unsupported shell: " & shell
    echo "📋 Supported shells: bash, zsh, fish"

# Function to show flag help
proc showFlagHelp() =
  echo """
🍱 BENTO PACKAGE MANAGER - FLAGS REFERENCE

SYNC OPERATIONS (Package Installation & Updates):
  -S <package>     📦 Install package
  -Sy              🔄 Update package repositories  
  -Su              ⬆️  Upgrade installed packages
  -Syu             🔄⬆️ Update repositories and upgrade system
  -Ss <term>       🔍 Search for packages
  -Si <package>    ℹ️  Show detailed package information
  -Sc              🧹 Clean package cache
  -Scc             🧹🧹 Deep clean cache and unused files

REMOVE OPERATIONS (Package Removal):
  -R <package>     ❌ Remove package
  -Rs <package>    ❌🔗 Remove package with unused dependencies
  -Rn              🗑️  Remove orphaned packages (autoremove)
  -Rns <package>   💀 Complete removal (purge)

QUERY OPERATIONS (System Information):
  -Q               📋 List all installed packages
  -Qi <package>    ℹ️  Show installed package information
  -Ql <package>    📁 List files owned by package
  -Qo <file>       🔍 Find which package owns a file
  -Qt              🏚️  List orphaned packages
  -Qu              📊 Check for available updates

SECURITY OPERATIONS (Security & Auditing):
  -A               🛡️  Run complete security audit
  -As <package>    🔒 Security report for specific package
  -Av <package>    ✅ Verify package integrity (SHA256 + PGP)
  -Ac <CVE-ID>     🚨 Search CVE database
  -Ap              🔐 Setup PGP verification system
  -Am <package>    👤 Check package maintenance status
  -Ao              📅 Find obsolete packages
  -Ah              💊 System health check

PORTS OPERATIONS (FreeBSD Ports Integration):
  -P <port>        🚢 Show port information
  -Ps <term>       🔍 Search FreeBSD ports tree
  -Pi <path>       ⚙️  Install package from port (compile)
  -Pb <path>       🔨 Build port without installing
  -Pu              🔄 Update ports tree

EXAMPLES:
  bento -S firefox         # Install Firefox
  bento -Syu              # Full system update
  bento -Ss editor        # Search for editors
  bento -Rs old-package   # Remove with dependencies
  bento -A                # Security audit
  bento -As firefox       # Security check Firefox
  bento -Ps vim           # Search vim in ports
  bento -Qi firefox       # Info about installed Firefox

GENERAL OPTIONS:
  -h, --help       ❓ Show this help
  -V, --version    📋 Show version information

SHELL COMPLETION SETUP:
  bento completion bash   # Install bash completion
  bento completion zsh    # Install zsh completion  
  bento completion fish   # Install fish completion
"""

# Export the parsing function for use in main bento.nim
proc processBentoFlags*(args: seq[string]): tuple[command: string, params: seq[string]] =
  return parseFlags(args)

when isMainModule:
  # Test the flag system
  let testArgs = @["-Syu"]
  let (cmd, params) = parseFlags(testArgs)
  echo fmt"Command: {cmd}, Params: {params}"
