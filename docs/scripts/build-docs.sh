#!/usr/bin/env bash
#
# build-docs.sh — Build the Agora Platform documentation site
#
# Usage:
#   ./docs/scripts/build-docs.sh              # Build static site
#   ./docs/scripts/build-docs.sh serve         # Serve locally with hot-reload
#   ./docs/scripts/build-docs.sh validate      # Validate links only (no build)
#   ./docs/scripts/build-docs.sh clean         # Remove build artifacts
#
# Prerequisites: Python 3, pip, mkdocs-material
# Output: site/ directory (static HTML site)
#
# Source: docs/scripts/build-docs.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$DOCS_DIR")"
MKDOCS_CONFIG="$PROJECT_ROOT/mkdocs.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Utility Functions
# =============================================================================

log_info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    local failed=0

    echo ""
    log_info "Checking prerequisites..."
    echo ""

    # Python 3
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1)
        log_ok "Python: $PYTHON_VERSION"
    else
        log_error "Python 3 is not installed. Install from https://www.python.org/downloads/"
        failed=1
    fi

    # pip
    if command -v pip3 &>/dev/null; then
        PIP_VERSION=$(pip3 --version 2>&1)
        log_ok "pip:   $PIP_VERSION"
    elif command -v pip &>/dev/null; then
        PIP_VERSION=$(pip --version 2>&1)
        log_ok "pip:   $PIP_VERSION"
    else
        log_error "pip is not installed."
        failed=1
    fi

    # mkdocs
    if command -v mkdocs &>/dev/null; then
        MKDOCS_VERSION=$(mkdocs --version 2>&1)
        log_ok "mkdocs: $MKDOCS_VERSION"
    else
        log_warn "mkdocs is not installed. Installing mkdocs-material..."
        pip3 install mkdocs-material --quiet 2>&1 || pip install mkdocs-material --quiet 2>&1
        if command -v mkdocs &>/dev/null; then
            MKDOCS_VERSION=$(mkdocs --version 2>&1)
            log_ok "mkdocs: $MKDOCS_VERSION (installed)"
        else
            log_error "Failed to install mkdocs. Try: pip3 install mkdocs-material"
            failed=1
        fi
    fi

    # mkdocs-material (check via pip show)
    if python3 -c "import material" 2>/dev/null; then
        MATERIAL_VERSION=$(python3 -c "from material import __version__; print(__version__)" 2>/dev/null || echo "installed")
        log_ok "mkdocs-material: $MATERIAL_VERSION"
    else
        log_warn "mkdocs-material not found. Installing..."
        pip3 install mkdocs-material --quiet 2>&1 || pip install mkdocs-material --quiet 2>&1
        if python3 -c "import material" 2>/dev/null; then
            log_ok "mkdocs-material installed successfully"
        else
            log_error "Failed to install mkdocs-material."
            failed=1
        fi
    fi

    # Check for optional dependencies
    local optional_plugins=(
        "mkdocs-minify-plugin:mkdocs_minify_plugin"
        "mkdocs-git-revision-date-localized-plugin:mkdocs_git_revision_date_localized_plugin"
        "mkdocs-git-committers-plugin:mkdocs_git_committers_plugin"
        "mkdocs-awesome-pages-plugin:mkdocs_awesome_pages_plugin"
        "mkdocs-glightbox:glightbox"
    )

    for plugin_spec in "${optional_plugins[@]}"; do
        local pip_name="${plugin_spec%%:*}"
        local module_name="${plugin_spec##*:}"
        if python3 -c "import $module_name" 2>/dev/null; then
            log_ok "$pip_name: installed"
        else
            log_warn "$pip_name: not installed (install with: pip3 install $pip_name)"
        fi
    done

    # Check mkdocs config exists
    if [ -f "$MKDOCS_CONFIG" ]; then
        log_ok "mkdocs.yml found at $MKDOCS_CONFIG"
    else
        log_error "mkdocs.yml not found at $MKDOCS_CONFIG"
        failed=1
    fi

    echo ""
    if [ "$failed" -eq 1 ]; then
        log_error "Prerequisite check FAILED. Fix errors above and retry."
        exit 1
    else
        log_ok "All prerequisites satisfied."
        echo ""
    fi
}

# =============================================================================
# Install Dependencies
# =============================================================================

install_dependencies() {
    log_info "Installing/updating documentation dependencies..."

    local packages=(
        "mkdocs-material"
        "mkdocs-minify-plugin"
        "mkdocs-git-revision-date-localized-plugin"
        "mkdocs-git-committers-plugin"
        "mkdocs-awesome-pages-plugin"
        "mkdocs-glightbox"
    )

    for pkg in "${packages[@]}"; do
        echo -n "  Installing $pkg... "
        pip3 install "$pkg" --quiet 2>&1 && echo "done" || echo "failed"
    done

    echo ""
    log_ok "Dependencies installed."
    echo ""
}

# =============================================================================
# Validate Internal Links
# =============================================================================

validate_links() {
    echo ""
    log_info "Validating internal links..."
    echo ""

    local broken_count=0
    local checked_count=0

    # Change to project root so relative paths resolve correctly
    cd "$PROJECT_ROOT"

    # Find all markdown files in the docs directory
    while IFS= read -r -d '' md_file; do
        # Extract relative links from the markdown file
        # Links look like: [text](path) or [text](../path)
        while IFS= read -r link; do
            # Skip external URLs and anchors-only
            if echo "$link" | grep -qE '^(http|https|ftp)://'; then
                continue
            fi
            if echo "$link" | grep -qE '^#'; then
                continue
            fi

            checked_count=$((checked_count + 1))

            # Resolve relative link relative to the markdown file's directory
            md_dir=$(dirname "$md_file")
            target_path="$md_dir/$link"

            # Remove URL fragment (part after #) for file check
            target_path_no_frag=$(echo "$target_path" | sed 's/#.*//')

            # Handle empty target
            if [ -z "$target_path_no_frag" ]; then
                continue
            fi

            if [ ! -f "$target_path_no_frag" ]; then
                # Also check if the path contains dangling anchors
                log_error "Broken link: '$link' in $md_file"
                broken_count=$((broken_count + 1))
            fi
        done < <(grep -oP '(?<=\]\()([^)]+)' "$md_file" 2>/dev/null || true)
    done < <(find "$DOCS_DIR" -name "*.md" -print0 2>/dev/null)

    echo ""
    if [ "$broken_count" -eq 0 ]; then
        log_ok "Validated $checked_count links — all OK."
    else
        log_error "Found $broken_count broken links out of $checked_count checked."
        exit 1
    fi
    echo ""
}

# =============================================================================
# Build Documentation
# =============================================================================

build_docs() {
    echo ""
    log_info "Building documentation site..."
    echo ""

    cd "$PROJECT_ROOT"

    # Clean build artifacts first
    if [ -d "site" ]; then
        log_info "Removing previous build..."
        rm -rf site
    fi

    # Build
    log_info "Running: mkdocs build"
    mkdocs build --config-file "$MKDOCS_CONFIG" --clean --strict 2>&1

    echo ""
    if [ -d "site" ]; then
        local site_size
        site_size=$(du -sh site 2>/dev/null | cut -f1)
        local page_count
        page_count=$(find site -name "*.html" 2>/dev/null | wc -l | tr -d ' ')

        log_ok "Build complete!"
        log_ok "Output:  $PROJECT_ROOT/site/ ($site_size)"
        log_ok "Pages:   $page_count HTML pages"
        log_ok "Config:  mkdocs.yml"

        # Validate links after build
        validate_links
    else
        log_error "Build failed — site/ directory not created."
        exit 1
    fi
    echo ""
}

# =============================================================================
# Serve Documentation Locally
# =============================================================================

serve_docs() {
    echo ""
    log_info "Starting local documentation server..."
    log_info "Open http://127.0.0.1:8000 in your browser"
    log_info "Press Ctrl+C to stop"
    echo ""

    cd "$PROJECT_ROOT"

    mkdocs serve \
        --config-file "$MKDOCS_CONFIG" \
        --dev-addr "127.0.0.1:8000" \
        --watch "$DOCS_DIR" \
        --watch "mkdocs.yml" \
        --strict \
        --livereload
}

# =============================================================================
# Clean Build Artifacts
# =============================================================================

clean() {
    echo ""
    log_info "Cleaning build artifacts..."
    echo ""

    cd "$PROJECT_ROOT"

    if [ -d "site" ]; then
        rm -rf site
        log_ok "Removed site/ directory"
    else
        log_info "No site/ directory to clean"
    fi

    # Remove Python cache files
    find "$DOCS_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$DOCS_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true

    log_ok "Clean complete."
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    local command="${1:-build}"

    echo "=============================================="
    echo "  Agora Platform Documentation Builder"
    echo "=============================================="
    echo ""

    case "$command" in
        build)
            check_prerequisites
            build_docs
            ;;
        serve)
            check_prerequisites
            serve_docs
            ;;
        validate)
            validate_links
            ;;
        clean)
            clean
            ;;
        install)
            check_prerequisites
            install_dependencies
            ;;
        *)
            echo "Usage: $0 [build|serve|validate|clean|install]"
            echo ""
            echo "  build     Build static site (default)"
            echo "  serve     Serve locally with hot-reload"
            echo "  validate  Validate internal links only"
            echo "  clean     Remove build artifacts"
            echo "  install   Install/update dependencies"
            echo ""
            exit 1
            ;;
    esac
}

main "$@"
