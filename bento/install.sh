#!/bin/sh
# install.sh - Bento Package Manager Automated Installer
# Secure and elegant package manager for FreeBSD

set -e

# Configuration
BENTO_VERSION="1.0.0"
BENTO_REPO="https://github.com/freebsd/bento"
INSTALL_PREFIX="/usr/local"
TEMP_DIR="/tmp/bento-install-$$"
REQUIRED_SPACE=50000  # KB

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Print functions
print_banner() {
    printf "${CYAN}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════╗
║                                                          ║
║     🍱 BENTO Package Manager Installer                   ║
║                                                          ║
║     Secure • Fast • Elegant • Easy to use               ║
║                                                          ║
║     Installing on FreeBSD and compatible systems        ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"
}

print_info() {
    printf "${BLUE}ℹ️  $1${NC}\n"
}

print_success() {
    printf "${GREEN}✅ $1${NC}\n"
}

print_warning() {
    printf "${YELLOW}⚠️  $1${NC}\n"
}

print_error() {
    printf "${RED}❌ $1${NC}\n"
}

print_step() {
    printf "${CYAN}📦 $1${NC}\n"
}

# Cleanup function
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
}

# Set trap for cleanup
trap cleanup EXIT INT TERM

# Error handler
error_exit() {
    print_error "$1"
    printf "${RED}Installation failed. Check the error above.${NC}\n"
    exit 1
}

# Check if running as root for system-wide installation
check_permissions() {
    if [ "$(id -u)" = "0" ]; then
        print_info "Running as root - system-wide installation"
        return 0
    else
        print_warning "Not running as root - user installation only"
        INSTALL_PREFIX="$HOME/.local"
        return 1
    fi
}

# Detect BSD variant and compatibility
detect_system() {
    print_step "Detecting system compatibility..."
    
    SYSTEM=$(uname -s)
    VERSION=$(uname -r)
    ARCH=$(uname -m)
    
    print_info "System: $SYSTEM $VERSION ($ARCH)"
    
    case "$SYSTEM" in
        FreeBSD)
            COMPAT_LEVEL="full"
            PKG_MGR="pkg"
            PORTS_DIR="/usr/ports"
            print_success "FreeBSD detected - full compatibility"
            ;;
        GhostBSD|TrueOS|FuryBSD|MidnightBSD)
            COMPAT_LEVEL="high"
            PKG_MGR="pkg"
            PORTS_DIR="/usr/ports"
            print_success "$SYSTEM detected - high compatibility"
            ;;
        OpenBSD)
            COMPAT_LEVEL="limited"
            PKG_MGR="pkg_add"
            PORTS_DIR="/usr/ports"
            print_warning "OpenBSD detected - limited compatibility"
            ;;
        NetBSD)
            COMPAT_LEVEL="limited"
            PKG_MGR="pkgin"
            PORTS_DIR="/usr/pkgsrc"
            print_warning "NetBSD detected - limited compatibility"
            ;;
        DragonFly)
            COMPAT_LEVEL="high"
            PKG_MGR="pkg"
            PORTS_DIR="/usr/dports"
            print_success "DragonFlyBSD detected - high compatibility"
            ;;
        Linux)
            if [ -f /etc/debian_version ]; then
                print_error "Debian/Ubuntu detected - use apt instead"
            elif [ -f /etc/redhat-release ]; then
                print_error "Red Hat/CentOS detected - use yum/dnf instead"
            elif [ -f /etc/arch-release ]; then
                print_error "Arch Linux detected - use pacman instead"
            else
                print_error "Linux detected - use your distribution's package manager"
            fi
            error_exit "Bento is designed for BSD systems only"
            ;;
        Darwin)
            print_error "macOS detected - use Homebrew or MacPorts instead"
            error_exit "Bento is designed for BSD systems only"
            ;;
        *)
            print_error "Unknown system: $SYSTEM"
            error_exit "Bento is designed for BSD systems only"
            ;;
    esac
}

# Check system requirements
check_requirements() {
    print_step "Checking system requirements..."
    
    # Check available disk space
    AVAILABLE_SPACE=$(df /tmp | awk 'NR==2 {print $4}')
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        error_exit "Insufficient disk space. Need ${REQUIRED_SPACE}KB, have ${AVAILABLE_SPACE}KB"
    fi
    print_success "Sufficient disk space available"
    
    # Check for required tools
    MISSING_TOOLS=""
    
    # Check for fetch or curl
    if ! command -v fetch >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS fetch/curl"
    fi
    
    # Check for tar
    if ! command -v tar >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS tar"
    fi
    
    # Check for make
    if ! command -v make >/dev/null 2>&1; then
        MISSING_TOOLS="$MISSING_TOOLS make"
    fi
    
    if [ -n "$MISSING_TOOLS" ]; then
        error_exit "Missing required tools:$MISSING_TOOLS"
    fi
    
    print_success "All required tools available"
}

# Check and install dependencies
install_dependencies() {
    print_step "Checking dependencies..."
    
    # Check if Nim is installed
    if ! command -v nim >/dev/null 2>&1; then
        print_warning "Nim compiler not found"
        
        if [ "$PKG_MGR" = "pkg" ]; then
            print_info "Installing Nim using pkg..."
            if [ "$(id -u)" = "0" ]; then
                pkg install -y lang/nim || error_exit "Failed to install Nim"
            else
                print_error "Need root privileges to install Nim system-wide"
                printf "${YELLOW}Run as root or install Nim manually: pkg install lang/nim${NC}\n"
                exit 1
            fi
        else
            error_exit "Please install Nim compiler manually for your system"
        fi
    else
        NIM_VERSION=$(nim --version | head -n1)
        print_success "Nim compiler found: $NIM_VERSION"
    fi
    
    # Check optional dependencies
    if ! command -v gpg >/dev/null 2>&1; then
        print_warning "GPG not found - PGP verification will be limited"
        print_info "Install with: $PKG_MGR install gnupg"
    else
        print_success "GPG found - PGP verification available"
    fi
    
    if ! command -v git >/dev/null 2>&1; then
        print_warning "Git not found - some features may be limited"
    else
        print_success "Git found"
    fi
}

# Download source code
download_source() {
    print_step "Downloading Bento source code..."
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Try git first, then fall back to tarball
    if command -v git >/dev/null 2>&1; then
        print_info "Cloning repository..."
        if git clone --depth 1 "$BENTO_REPO.git" bento-src; then
            cd bento-src
            print_success "Source code downloaded via git"
            return 0
        else
            print_warning "Git clone failed, trying tarball..."
        fi
    fi
    
    # Download tarball
    TARBALL_URL="$BENTO_REPO/archive/refs/heads/main.tar.gz"
    print_info "Downloading tarball from $TARBALL_URL"
    
    if command -v fetch >/dev/null 2>&1; then
        fetch -o bento.tar.gz "$TARBALL_URL" || error_exit "Download failed"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o bento.tar.gz "$TARBALL_URL" || error_exit "Download failed"
    else
        error_exit "No download tool available"
    fi
    
    print_info "Extracting source code..."
    tar xzf bento.tar.gz || error_exit "Extraction failed"
    
    # Find the extracted directory
    EXTRACTED_DIR=$(find . -maxdepth 1 -type d -name "bento-*" | head -n1)
    if [ -z "$EXTRACTED_DIR" ]; then
        error_exit "Could not find extracted source directory"
    fi
    
    cd "$EXTRACTED_DIR"
    print_success "Source code downloaded and extracted"
}

# Build Bento
build_bento() {
    print_step "Building Bento..."
    
    # Check if Makefile exists
    if [ -f Makefile ]; then
        print_info "Using Makefile for build"
        make clean || true
        make check || print_warning "Some checks failed, continuing..."
        make build || error_exit "Build failed"
    else
        # Fallback to direct nim compilation
        print_info "Compiling directly with Nim"
        if [ ! -f bento.nim ]; then
            error_exit "Source file bento.nim not found"
        fi
        
        nim c -d:release --opt:speed --threads:on bento.nim || error_exit "Compilation failed"
    fi
    
    # Verify the binary was created
    if [ ! -f bento ]; then
        error_exit "Binary 'bento' was not created"
    fi
    
    # Test the binary
    if ./bento --version >/dev/null 2>&1; then
        print_success "Build completed successfully"
    else
        error_exit "Built binary is not functional"
    fi
}

# Install Bento
install_bento() {
    print_step "Installing Bento..."
    
    # Create installation directories
    mkdir -p "$INSTALL_PREFIX/bin" || error_exit "Cannot create bin directory"
    mkdir -p "$INSTALL_PREFIX/man/man1" || error_exit "Cannot create man directory"
    mkdir -p "$INSTALL_PREFIX/share/bento" || error_exit "Cannot create share directory"
    
    # Install binary
    print_info "Installing binary to $INSTALL_PREFIX/bin/bento"
    cp bento "$INSTALL_PREFIX/bin/bento" || error_exit "Failed to install binary"
    chmod +x "$INSTALL_PREFIX/bin/bento" || error_exit "Failed to set binary permissions"
    
    # Install manual page if available
    if [ -f man/bento.1 ]; then
        print_info "Installing manual page"
        cp man/bento.1 "$INSTALL_PREFIX/man/man1/" || print_warning "Failed to install manual"
        if command -v gzip >/dev/null 2>&1; then
            gzip -f "$INSTALL_PREFIX/man/man1/bento.1" 2>/dev/null || true
        fi
    fi
    
    # Install completion files if available
    if [ -d completions ]; then
        print_info "Installing shell completions"
        cp -r completions "$INSTALL_PREFIX/share/bento/" || print_warning "Failed to install completions"
    fi
    
    # Install configuration files if available
    if [ -d config ]; then
        print_info "Installing configuration files"
        cp -r config "$INSTALL_PREFIX/share/bento/" || print_warning "Failed to install config files"
    fi
    
    print_success "Installation completed"
}

# Post-installation setup
post_install() {
    print_step "Running post-installation setup..."
    
    # Add to PATH if not already there
    BENTO_PATH="$INSTALL_PREFIX/bin"
    if ! echo "$PATH" | grep -q "$BENTO_PATH"; then
        print_info "Adding $BENTO_PATH to PATH"
        
        # Determine shell configuration file
        SHELL_CONFIG=""
        case "$SHELL" in
            */bash)
                if [ -f "$HOME/.bashrc" ]; then
                    SHELL_CONFIG="$HOME/.bashrc"
                elif [ -f "$HOME/.bash_profile" ]; then
                    SHELL_CONFIG="$HOME/.bash_profile"
                fi
                ;;
            */zsh)
                SHELL_CONFIG="$HOME/.zshrc"
                ;;
            */fish)
                SHELL_CONFIG="$HOME/.config/fish/config.fish"
                ;;
            */csh|*/tcsh)
                SHELL_CONFIG="$HOME/.cshrc"
                ;;
        esac
        
        if [ -n "$SHELL_CONFIG" ] && [ -w "$SHELL_CONFIG" ]; then
            if ! grep -q "bento" "$SHELL_CONFIG" 2>/dev/null; then
                echo "# Added by Bento installer" >> "$SHELL_CONFIG"
                echo "export PATH=\"$BENTO_PATH:\$PATH\"" >> "$SHELL_CONFIG"
                print_success "PATH updated in $SHELL_CONFIG"
            fi
        else
            print_warning "Could not automatically update PATH"
            print_info "Add this line to your shell configuration:"
            printf "${CYAN}export PATH=\"$BENTO_PATH:\$PATH\"${NC}\n"
        fi
    fi
    
    # Test installation
    export PATH="$BENTO_PATH:$PATH"
    if command -v bento >/dev/null 2>&1; then
        INSTALLED_VERSION=$(bento --version 2>/dev/null | head -n1 || echo "unknown")
        print_success "Bento is working: $INSTALLED_VERSION"
    else
        print_warning "Bento installation may have issues"
    fi
    
    # Initialize Bento
    print_info "Initializing Bento configuration..."
    if bento health >/dev/null 2>&1; then
        print_success "Bento initialized successfully"
    else
        print_warning "Bento initialization had issues (this is normal for first run)"
    fi
}

# Show completion message
show_completion() {
    printf "\n${GREEN}"
    cat << 'EOF'
🎉 Bento Package Manager Installation Complete! 🎉
EOF
    printf "${NC}\n"
    
    printf "${CYAN}Next Steps:${NC}\n"
    printf "1. Restart your shell or run: ${YELLOW}source ~/.bashrc${NC}\n"
    printf "2. Set up shell completion: ${YELLOW}bento completion bash${NC}\n"
    printf "3. Run a health check: ${YELLOW}bento health${NC}\n"
    printf "4. View the manual: ${YELLOW}man bento${NC}\n"
    printf "5. Start using Bento: ${YELLOW}bento -Syu${NC}\n"
    
    printf "\n${CYAN}Quick Examples:${NC}\n"
    printf "• Install Firefox: ${YELLOW}bento install firefox${NC} or ${YELLOW}bento -S firefox${NC}\n"
    printf "• Update system: ${YELLOW}bento update${NC} or ${YELLOW}bento -Syu${NC}\n"
    printf "• Security audit: ${YELLOW}bento audit${NC} or ${YELLOW}bento -A${NC}\n"
    printf "• Search packages: ${YELLOW}bento search editor${NC} or ${YELLOW}bento -Ss editor${NC}\n"
    
    printf "\n${CYAN}Documentation:${NC}\n"
    printf "• Help: ${YELLOW}bento help${NC}\n"
    printf "• Flag reference: ${YELLOW}bento flags${NC}\n"
    printf "• Manual: ${YELLOW}man bento${NC}\n"
    
    if [ "$COMPAT_LEVEL" != "full" ]; then
        printf "\n${YELLOW}⚠️  Note: ${NC}Running on $SYSTEM with $COMPAT_LEVEL compatibility.\n"
        printf "Some features may be limited. FreeBSD is recommended for full functionality.\n"
    fi
    
    printf "\n${GREEN}Thank you for using Bento! 🍱${NC}\n"
}

# Main installation flow
main() {
    print_banner
    
    # Parse command line arguments
    FORCE_INSTALL=false
    USER_INSTALL=false
    
    while [ $# -gt 0 ]; do
        case $1 in
            --force)
                FORCE_INSTALL=true
                shift
                ;;
            --user)
                USER_INSTALL=true
                INSTALL_PREFIX="$HOME/.local"
                shift
                ;;
            --prefix=*)
                INSTALL_PREFIX="${1#*=}"
                shift
                ;;
            --help)
                cat << EOF
Bento Package Manager Installer

Usage: $0 [options]

Options:
    --force         Force installation even with warnings
    --user          Install for current user only (~/.local)
    --prefix=PATH   Install to custom prefix (default: /usr/local)
    --help          Show this help

Examples:
    $0                          # System-wide installation
    $0 --user                   # User installation
    $0 --prefix=/opt/bento      # Custom prefix
    $0 --force --user           # Force user installation

EOF
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Check permissions
    if [ "$USER_INSTALL" = false ]; then
        check_permissions || USER_INSTALL=true
    fi
    
    # Run installation steps
    detect_system
    check_requirements
    
    if [ "$FORCE_INSTALL" = false ] && [ "$COMPAT_LEVEL" = "limited" ]; then
        printf "${YELLOW}⚠️  Limited compatibility detected. Continue? (y/N): ${NC}"
        read -r response
        case "$response" in
            [yY]|[yY][eE][sS])
                print_info "Continuing with installation..."
                ;;
            *)
                print_info "Installation cancelled"
                exit 0
                ;;
        esac
    fi
    
    install_dependencies
    download_source
    build_bento
    install_bento
    post_install
    show_completion
}

# Run main function
main "$@"
