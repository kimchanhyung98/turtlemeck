.PHONY: help check package run fresh-run

.DEFAULT_GOAL := help

APP := $(CURDIR)/.build/turtlemeck.app
APP_EXECUTABLE := $(APP)/Contents/MacOS/turtlemeck

help: ## 사용 가능한 명령어 목록 출력
	@awk 'BEGIN {FS = ":.*##"; printf "\n사용법:\n  make \033[36m<target>\033[0m\n\n명령어:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

check: ## 테스트 및 빌드 검사 실행
	@echo "[check] running Swift tests..."
	@Tests/run.sh
	@echo "[check] building Swift package..."
	@swift build --disable-sandbox
	@echo "[check] all checks passed"

package: ## Universal2 .app/ZIP/DMG 빌드 및 ad-hoc 서명
	@./package.sh

run: ## 기존 앱 번들 실행(없으면 패키징)
	@if [ ! -x "$(APP_EXECUTABLE)" ]; then \
		$(MAKE) package; \
	fi
	@open "$(APP)"

fresh-run: ## 기존 앱 종료 후 재패키징하고 새 인스턴스 실행
	@osascript -e 'tell application id "com.go.turtlemeck" to quit' >/dev/null 2>&1 || true
	@attempt=0; \
	while [ $$attempt -lt 20 ]; do \
		if ! pgrep -x turtlemeck >/dev/null 2>&1; then break; fi; \
		sleep 0.1; \
		attempt=$$((attempt + 1)); \
	done
	@pkill -x turtlemeck >/dev/null 2>&1 || true
	@$(MAKE) package
	@open -n "$(APP)"
