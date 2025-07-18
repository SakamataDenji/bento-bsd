# Makefile for Bento Package Manager
# Secure and elegant package manager for FreeBSD

# Configuration
CC = nim c
NIMFLAGS = -d:release --opt:speed --threads:on --gc:orc
DEBUG_FLAGS = -d:debug --lineTrace:on --stackTrace:on
TARGET = bento
SOURCES = bento.nim
UTILS = bento_utils.nim bento_flags.nim

# Installation paths
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
MANDIR = $(PREFIX)/man/man1
SYSCONFDIR = $(PREFIX)/etc
SHAREDIR = $(PREFIX)/share/bento

# BSD Detection
UNAME := $(shell uname -s)
VERSION := $(shell uname -r)

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
BLUE = \033[0;34m
YELLOW = \033[1;33m
NC = \033[0m

.PHONY: all build debug test install uninstall clean distclean check help

# Default target
all: check build

# Build targets
build: check-deps $(TARGET)
	@printf "$(GREEN)✅ Build completed successfully$(NC)\n"

$(TARGET): $(SOURCES) $(UTILS)
	@printf "$(BLUE)📦 Compiling $(TARGET)...$(NC)\n"
	$(CC) $(NIMFLAGS) -o:$(TARGET) $(SOURCES)
	@printf "$(GREEN)✅ Compilation successful$(NC)\n"

debug: check-deps
	@printf "$(YELLOW)🔧 Building debug version...$(NC)\n"
	$(CC) $(DEBUG_FLAGS) -o:$(TARGET)-debug $(SOURCES)
	@printf "$(GREEN)✅ Debug build completed$(NC)\n"

# System checks
check: check-system check-deps
	@printf "$(GREEN)✅ All checks passed$(NC)\n"

check-system:
	@printf "$(BLUE)🔍 Checking system compatibility...$(NC)\n"
	@if [ "$(UNAME)" != "FreeBSD" ]; then \
		printf "$(YELLOW)⚠️  Warning: Not running on FreeBSD (detected: $(UNAME))$(NC)\n"; \
		printf "$(YELLOW)   Bento is optimized for FreeBSD but may work on other BSD variants$(NC)\n"; \
	else \
		printf "$(GREEN)✅ FreeBSD $(VERSION) detected$(NC)\n"; \
	fi

check-deps:
	@printf "$(BLUE)🔍 Checking dependencies...$(NC)\n"
	@command -v nim >/dev/null 2>&1 || { \
		printf "$(RED)❌ Nim compiler not found$(NC)\n"; \
		printf "$(BLUE)💡 Install with: pkg install lang/nim$(NC)\n"; \
		exit 1; \
	}
	@printf "$(GREEN)✅ Nim compiler found: $$(nim --version | head -n1)$(NC)\n"
	@command -v pkg >/dev/null 2>&1 || { \
		printf "$(RED)❌ pkg not found$(NC)\n"; \
		exit 1; \
	}
	@printf "$(GREEN)✅ pkg found$(NC)\n"
	@command -v gpg >/dev/null 2>&1 || { \
		printf "$(YELLOW)⚠️  gpg not found - PGP features will be limited$(NC)\n"; \
		printf "$(BLUE)💡 Install with: pkg install security/gnupg$(NC)\n"; \
	}

# Testing
test: build
	@printf "$(BLUE)🧪 Running tests...$(NC)\n"
	@./$(TARGET) --version >/dev/null 2>&1 || { \
		printf "$(RED)❌ Basic functionality test failed$(NC)\n"; \
		exit 1; \
	}
	@printf "$(GREEN)✅ Basic tests passed$(NC)\n"
	@if [ -f tests/run_tests.sh ]; then \
		printf "$(BLUE)🧪 Running extended tests...$(NC)\n"; \
		sh tests/run_tests.sh; \
	fi

# Installation
install: build install-bin install-man install-completions install-config
	@printf "$(GREEN)🎉 Bento installation completed!$(NC)\n"
	@printf "$(BLUE)💡 Run 'bento completion bash' to set up shell completion$(NC)\n"
	@printf "$(BLUE)💡 Run 'bento health' to verify installation$(NC)\n"

install-bin: $(TARGET)
	@printf "$(BLUE)📦 Installing binary...$(NC)\n"
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(TARGET) $(DESTDIR)$(BINDIR)/$(TARGET)
	@printf "$(GREEN)✅ Binary installed to $(BINDIR)/$(TARGET)$(NC)\n"

install-man:
	@printf "$(BLUE)📖 Installing manual...$(NC)\n"
	install -d $(DESTDIR)$(MANDIR)
	@if [ -f man/bento.1 ]; then \
		install -m 644 man/bento.1 $(DESTDIR)$(MANDIR)/bento.1; \
		gzip -f $(DESTDIR)$(MANDIR)/bento.1; \
		printf "$(GREEN)✅ Manual installed$(NC)\n"; \
	else \
		printf "$(YELLOW)⚠️  Manual page not found$(NC)\n"; \
	fi

install-completions:
	@printf "$(BLUE)⚡ Installing shell completions...$(NC)\n"
	install -d $(DESTDIR)$(SHAREDIR)/completions
	@if [ -d completions ]; then \
		cp -r completions/* $(DESTDIR)$(SHAREDIR)/completions/; \
		printf "$(GREEN)✅ Completions installed$(NC)\n"; \
	else \
		printf "$(YELLOW)⚠️  Completion files not found$(NC)\n"; \
	fi

install-config:
	@printf "$(BLUE)⚙️  Installing configuration...$(NC)\n"
	install -d $(DESTDIR)$(SYSCONFDIR)/bento
	@if [ -f config/bento.conf.sample ]; then \
		install -m 644 config/bento.conf.sample $(DESTDIR)$(SYSCONFDIR)/bento/; \
		printf "$(GREEN)✅ Sample configuration installed$(NC)\n"; \
	fi

# Uninstallation
uninstall:
	@printf "$(BLUE)🗑️  Uninstalling Bento...$(NC)\n"
	rm -f $(DESTDIR)$(BINDIR)/$(TARGET)
	rm -f $(DESTDIR)$(MANDIR)/bento.1.gz
	rm -rf $(DESTDIR)$(SHAREDIR)
	rm -rf $(DESTDIR)$(SYSCONFDIR)/bento
	@printf "$(GREEN)✅ Bento uninstalled$(NC)\n"
	@printf "$(YELLOW)💡 User data in ~/.bento/ was preserved$(NC)\n"

# Cleaning
clean:
	@printf "$(BLUE)🧹 Cleaning build artifacts...$(NC)\n"
	rm -f $(TARGET) $(TARGET)-debug
	rm -rf nimcache/
	@printf "$(GREEN)✅ Clean completed$(NC)\n"

distclean: clean
	@printf "$(BLUE)🧹 Performing deep clean...$(NC)\n"
	rm -rf ~/.bento/cache/
	rm -f ~/.bento/*.log
	@printf "$(GREEN)✅ Deep clean completed$(NC)\n"

# Development targets
format:
	@printf "$(BLUE)✨ Formatting code...$(NC)\n"
	@if command -v nimpretty >/dev/null 2>&1; then \
		nimpretty $(SOURCES) $(UTILS); \
		printf "$(GREEN)✅ Code formatted$(NC)\n"; \
	else \
		printf "$(YELLOW)⚠️  nimpretty not available$(NC)\n"; \
	fi

lint:
	@printf "$(BLUE)🔍 Running linter...$(NC)\n"
	@if command -v nimlint >/dev/null 2>&1; then \
		nimlint $(SOURCES); \
		printf "$(GREEN)✅ Linting completed$(NC)\n"; \
	else \
		printf "$(YELLOW)⚠️  nimlint not available$(NC)\n"; \
	fi

# Package creation
package: build
	@printf "$(BLUE)📦 Creating package...$(NC)\n"
	mkdir -p bento-$(VERSION)
	cp $(TARGET) bento-$(VERSION)/
	cp README.md bento-$(VERSION)/ 2>/dev/null || true
	cp LICENSE bento-$(VERSION)/ 2>/dev/null || true
	cp -r man bento-$(VERSION)/ 2>/dev/null || true
	cp -r completions bento-$(VERSION)/ 2>/dev/null || true
	tar czf bento-$(VERSION).tar.gz bento-$(VERSION)/
	rm -rf bento-$(VERSION)/
	@printf "$(GREEN)✅ Package created: bento-$(VERSION).tar.gz$(NC)\n"

# FreeBSD port creation
port: package
	@printf "$(BLUE)🚢 Creating FreeBSD port...$(NC)\n"
	mkdir -p ports/sysutils/bento
	@printf "$(BLUE)💡 Port skeleton created in ports/sysutils/bento$(NC)\n"
	@printf "$(BLUE)💡 Manual editing of Makefile and pkg-descr required$(NC)\n"

# Benchmarking
benchmark: build
	@printf "$(BLUE)⏱️  Running benchmarks...$(NC)\n"
	@if [ -f tests/benchmark.sh ]; then \
		sh tests/benchmark.sh; \
	else \
		printf "$(YELLOW)⚠️  Benchmark script not found$(NC)\n"; \
	fi

# Help
help:
	@printf "$(BLUE)🍱 Bento Package Manager Build System$(NC)\n"
	@printf "\n$(YELLOW)Available targets:$(NC)\n"
	@printf "  $(GREEN)build$(NC)         Build Bento (default)\n"
	@printf "  $(GREEN)debug$(NC)         Build debug version\n"
	@printf "  $(GREEN)test$(NC)          Run tests\n"
	@printf "  $(GREEN)install$(NC)       Install Bento system-wide\n"
	@printf "  $(GREEN)uninstall$(NC)     Remove Bento from system\n"
	@printf "  $(GREEN)clean$(NC)         Clean build artifacts\n"
	@printf "  $(GREEN)distclean$(NC)     Deep clean including user cache\n"
	@printf "  $(GREEN)check$(NC)         Check dependencies and system\n"
	@printf "  $(GREEN)format$(NC)        Format source code\n"
	@printf "  $(GREEN)lint$(NC)          Run code linter\n"
	@printf "  $(GREEN)package$(NC)       Create distribution package\n"
	@printf "  $(GREEN)port$(NC)          Create FreeBSD port skeleton\n"
	@printf "  $(GREEN)benchmark$(NC)     Run performance benchmarks\n"
	@printf "  $(GREEN)help$(NC)          Show this help\n"
	@printf "\n$(YELLOW)Variables:$(NC)\n"
	@printf "  $(GREEN)PREFIX$(NC)        Installation prefix (default: /usr/local)\n"
	@printf "  $(GREEN)DESTDIR$(NC)       Staging directory for package builds\n"
	@printf "  $(GREEN)NIMFLAGS$(NC)      Additional Nim compiler flags\n"
	@printf "\n$(YELLOW)Examples:$(NC)\n"
	@printf "  $(BLUE)make$(NC)                    # Build Bento\n"
	@printf "  $(BLUE)make install$(NC)           # Install system-wide\n"
	@printf "  $(BLUE)make PREFIX=/opt/bento$(NC) # Install to /opt/bento\n"
	@printf "  $(BLUE)make debug$(NC)             # Build debug version\n"
	@printf "  $(BLUE)make package$(NC)           # Create distribution package\n"

# Version information
version:
	@printf "$(BLUE)🍱 Bento Package Manager$(NC)\n"
	@printf "Version: 1.0.0\n"
	@printf "System: $(UNAME) $(VERSION)\n"
	@printf "Build date: $$(date)\n"
