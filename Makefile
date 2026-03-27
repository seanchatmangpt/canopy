.PHONY: setup dev app backend desktop build check test clean doctor help logs logs-backend logs-frontend debug profile status format format-check

# Colors
BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
CYAN  := \033[36m
YELLOW := \033[33m

.DEFAULT_GOAL := help

help: ## Show this help message
	@printf '$(BOLD)Canopy — available targets:$(RESET)\n\n'
	@printf '$(YELLOW)Setup:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) First-time: install all deps (backend + desktop)\n' 'setup'
	@printf '\n$(YELLOW)Development:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Launch full stack (backend :9089 + desktop :5200)\n' 'dev'
	@printf '  $(CYAN)%-20s$(RESET) Launch with native Tauri app instead of browser\n' 'app'
	@printf '  $(CYAN)%-20s$(RESET) Backend only (Phoenix server on :9089)\n' 'backend'
	@printf '  $(CYAN)%-20s$(RESET) Desktop only (Vite dev on :5200, mock mode)\n' 'desktop'
	@printf '\n$(YELLOW)Quality & Testing:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Check code (format, warnings, docs)\n' 'check'
	@printf '  $(CYAN)%-20s$(RESET) Run all tests (backend + frontend)\n' 'test'
	@printf '  $(CYAN)%-20s$(RESET) Format code with prettier + mix format\n' 'format'
	@printf '  $(CYAN)%-20s$(RESET) Check formatting without modifying\n' 'format-check'
	@printf '\n$(YELLOW)Logs & Debugging:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Follow all service logs\n' 'logs'
	@printf '  $(CYAN)%-20s$(RESET) Follow backend logs only\n' 'logs-backend'
	@printf '  $(CYAN)%-20s$(RESET) Follow frontend logs only\n' 'logs-frontend'
	@printf '  $(CYAN)%-20s$(RESET) Open bash shell in running backend container\n' 'debug'
	@printf '  $(CYAN)%-20s$(RESET) Show service status and health\n' 'status'
	@printf '  $(CYAN)%-20s$(RESET) Show CPU/memory usage of services\n' 'profile'
	@printf '\n$(YELLOW)Build:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Build production Tauri app bundle (.app/.appimage)\n' 'build'
	@printf '\n$(YELLOW)Cleanup:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Clean build artifacts (DESTROYS local data)\n' 'clean'
	@printf '\n$(YELLOW)Environment:$(RESET)\n'
	@printf '  $(CYAN)%-20s$(RESET) Check prerequisites and port availability\n' 'doctor'
	@printf '\n'

# ── Setup ────────────────────────────────────────────────────────────────────

setup: ## First-time setup: install all dependencies
	@printf '$(BOLD)Installing backend dependencies...$(RESET)\n'
	cd backend && mix deps.get
	@printf '\n$(BOLD)Installing desktop dependencies...$(RESET)\n'
	cd desktop && npm install
	@printf '\n$(GREEN)Ready. Run $(CYAN)make dev$(GREEN) to launch.$(RESET)\n'

# ── Development ──────────────────────────────────────────────────────────────

dev: ## Launch full stack (backend :9089 + desktop :5200)
	@./scripts/start.sh

app: ## Launch with native Tauri app instead of browser
	@./scripts/start.sh --tauri

backend: ## Backend only (Phoenix server on :9089)
	cd backend && mix phx.server

desktop: ## Desktop only (Vite dev on :5200, mock mode)
	cd desktop && npm run dev

# ── Build ────────────────────────────────────────────────────────────────────

build: ## Build production Tauri app bundle (.app on macOS, .appimage on Linux)
	cd desktop && npm run tauri:build

# ── Quality ──────────────────────────────────────────────────────────────────

check: ## Check code (format, warnings, docs)
	@printf '$(BOLD)Checking frontend...$(RESET)\n'
	cd desktop && npm run check
	@printf '\n$(BOLD)Checking backend...$(RESET)\n'
	cd backend && mix compile --warnings-as-errors --parallel --max-concurrency 8
	@printf '$(GREEN)✓ All checks passed$(RESET)\n'

test: ## Run all tests (backend + frontend)
	@printf '$(BOLD)Running backend tests...$(RESET)\n'
	cd backend && mix test
	@printf '\n$(BOLD)Running frontend tests...$(RESET)\n'
	cd desktop && npm run test
	@printf '$(GREEN)✓ All tests passed$(RESET)\n'

format: ## Format code with prettier + mix format
	@printf '$(BOLD)Formatting code...$(RESET)\n'
	cd desktop && npm run format
	cd backend && mix format
	@printf '$(GREEN)Code formatted$(RESET)\n'

format-check: ## Check formatting without modifying
	@printf '$(BOLD)Checking format...$(RESET)\n'
	cd desktop && npm run format -- --check
	cd backend && mix format --check-formatted
	@printf '$(GREEN)✓ Format check passed$(RESET)\n'

# ── Logs & Debugging ─────────────────────────────────────────────────────────

logs: ## Follow all service logs
	@./scripts/start.sh --logs

logs-backend: ## Follow backend logs only
	@cd backend && mix phx.server 2>&1 | grep -E "^\[|Listening on"

logs-frontend: ## Follow frontend logs only
	@cd desktop && npm run dev 2>&1 | grep -E "VITE|Local:"

debug: ## Open bash shell in running backend container
	cd backend && iex -S mix phx.server

profile: ## Show service memory usage
	@echo "Backend process info:"
	@ps aux | grep "mix phx.server" | grep -v grep | awk '{print "  PID: " $$2 " | MEM: " $$6 "KB | CPU: " $$3 "%"}'

status: ## Show service status and health
	@echo "Canopy Status:"
	@echo "  Backend (Phoenix :9089): $$(curl -s http://localhost:9089/health >/dev/null 2>&1 && echo 'UP' || echo 'DOWN')"
	@echo "  Desktop (Vite :5200): $$(curl -s http://localhost:5200 >/dev/null 2>&1 && echo 'UP' || echo 'DOWN')"

# ── Cleanup ──────────────────────────────────────────────────────────────────

clean: ## Clean build artifacts (DESTROYS local data)
	@printf '$(BOLD)Cleaning build artifacts...$(RESET)\n'
	cd desktop && rm -rf build .svelte-kit node_modules
	cd desktop/src-tauri && cargo clean
	cd backend && rm -rf _build deps
	@printf '$(GREEN)Cleaned$(RESET)\n'

# ── Environment ──────────────────────────────────────────────────────────────

doctor: ## Check prerequisites and port availability
	@printf '$(BOLD)Checking prerequisites...$(RESET)\n'
	@command -v node >/dev/null 2>&1 && printf "  $(GREEN)Node.js:$(RESET) $$(node --version)\n" || printf "  $(RED)Node.js: MISSING (brew install node)$(RESET)\n"
	@command -v npm >/dev/null 2>&1 && printf "  $(GREEN)npm:$(RESET) $$(npm --version)\n" || printf "  $(RED)npm: MISSING$(RESET)\n"
	@command -v rustc >/dev/null 2>&1 && printf "  $(GREEN)Rust:$(RESET) $$(rustc --version)\n" || printf "  $(RED)Rust: MISSING (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)$(RESET)\n"
	@command -v elixir >/dev/null 2>&1 && printf "  $(GREEN)Elixir:$(RESET) $$(elixir --version | head -1)\n" || printf "  $(RED)Elixir: MISSING (brew install elixir)$(RESET)\n"
	@command -v mix >/dev/null 2>&1 && printf "  $(GREEN)Mix:$(RESET) OK\n" || printf "  $(RED)Mix: MISSING$(RESET)\n"
	@command -v psql >/dev/null 2>&1 && printf "  $(GREEN)PostgreSQL:$(RESET) $$(psql --version)\n" || printf "  $(RED)PostgreSQL: MISSING (brew install postgresql@16)$(RESET)\n"
	@printf '\n$(BOLD)Checking ports...$(RESET)\n'
	@lsof -ti:9089 >/dev/null 2>&1 && printf "  $(GREEN)9089:$(RESET) IN USE (backend)\n" || printf "  9089: free\n"
	@lsof -ti:5200 >/dev/null 2>&1 && printf "  $(GREEN)5200:$(RESET) IN USE (desktop)\n" || printf "  5200: free\n"
	@lsof -ti:8089 >/dev/null 2>&1 && printf "  $(GREEN)8089:$(RESET) IN USE (OSA)\n" || printf "  8089: free\n"
	@printf '\n'
