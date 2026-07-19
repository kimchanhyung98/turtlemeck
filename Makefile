.PHONY: help check package run fresh-run

.DEFAULT_GOAL := help

help: ## 사용 가능한 명령어 목록 출력
	@awk 'BEGIN {FS = ":.*##"; printf "\n사용법:\n  make \033[36m<target>\033[0m\n\n명령어:\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

check: ## 테스트 및 빌드 검사 실행
	@echo "[check] running manual Swift tests..."
	@scripts/run-tests.sh
	@echo "[check] building Swift package..."
	@swift build --disable-sandbox
	@echo "[check] all checks passed"

package: ## Universal2 .app/ZIP/DMG 빌드 및 ad-hoc 서명
	@scripts/package-app.sh

run: ## 기존 앱 번들 실행(없으면 패키징)
	@scripts/run-app.sh

fresh-run: ## 기존 앱 종료 후 재패키징하고 새 인스턴스 실행
	@scripts/fresh-run-app.sh
