#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# test_pipeline.sh — Compatible Windows (Git Bash), Linux, macOS
# Usage : bash test_pipeline.sh
# ─────────────────────────────────────────────────────────────────

# PAS de set -e ici — on gère nous-mêmes les erreurs
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
SKIP=0
VENV_DIR=".venv-test-pipeline"

# ─── Détection OS ──────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        Darwin*)               echo "mac"     ;;
        *)                     echo "linux"   ;;
    esac
}
OS=$(detect_os)

check() {
    local tool="$1"
    local expected="$2"
    local exit_code="$3"
    if [ "$exit_code" -ne 0 ] && [ "$expected" -eq 1 ]; then
        echo -e "${GREEN}[PASS]${NC} $tool — vulnérabilités détectées comme attendu"
        PASS=$((PASS + 1))
    elif [ "$exit_code" -eq 0 ] && [ "$expected" -eq 0 ]; then
        echo -e "${GREEN}[PASS]${NC} $tool — aucune erreur inattendue"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}[FAIL]${NC} $tool — résultat inattendu (exit=$exit_code, attendu=$expected)"
        FAIL=$((FAIL + 1))
    fi
}

skip() {
    echo -e "${BLUE}[SKIP]${NC} $1 — non disponible"
    SKIP=$((SKIP + 1))
}

# ─── Setup venv ────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  TEST DU PIPELINE — application principale"
echo "  OS détecté : $OS"
echo "══════════════════════════════════════════════════"
echo ""

echo "  → Création du virtual environment..."
python -m venv "$VENV_DIR"
if [ $? -ne 0 ]; then
    echo -e "${RED}ERREUR : impossible de créer le venv. Python est-il installé ?${NC}"
    echo "  Vérifie avec : python --version"
    exit 1
fi

echo "  → Activation du venv..."
if [ "$OS" = "windows" ]; then
    source "$VENV_DIR/Scripts/activate"
else
    source "$VENV_DIR/bin/activate"
fi
if [ $? -ne 0 ]; then
    echo -e "${RED}ERREUR : impossible d'activer le venv.${NC}"
    exit 1
fi

echo "  → Installation de pip..."
python -m pip install --upgrade pip 2>&1 | tail -1

echo "  → Installation de bandit..."
pip install bandit 2>&1 | tail -1

echo "  → Installation de safety..."
pip install typer==0.7.0 click==8.1.7 safety==2.3.5

echo "  → Installation de semgrep..."
pip install semgrep 2>&1 | tail -1

echo "  → Installation de checkov..."
pip install checkov 2>&1 | tail -1

echo ""
echo -e "${GREEN}  → Tous les outils installés.${NC}"
echo ""

# ─── 1. Gitleaks ───────────────────────────────────────
echo -e "${YELLOW}[1/7] Gitleaks — détection de secrets${NC}"
if command -v gitleaks &>/dev/null; then
    gitleaks detect --source . --verbose 2>&1; ec=$?
    check "Gitleaks" 0 "$ec"
else
    skip "Gitleaks (installer : https://github.com/gitleaks/gitleaks/releases)"
fi

# ─── 2. Bandit ─────────────────────────────────────────
echo ""
echo -e "${YELLOW}[2/7] Bandit — SAST Python${NC}"
bandit app/app.py -f screen 2>&1; ec=$?
check "Bandit" 0 "$ec"

# ─── 3. Safety CLI ─────────────────────────────────────
echo ""
echo -e "${YELLOW}[3/7] Safety CLI — CVE dépendances${NC}"
PYTHONUTF8=1 PYTHONIOENCODING=utf-8 safety check -r app/requirements.txt 2>&1; ec=$?
check "Safety CLI" 0 "$ec" || [ "$ec" -eq 64 ]

# ─── 4. Semgrep ────────────────────────────────────────
echo ""
echo -e "${YELLOW}[4/7] Semgrep — SAST multi-langage${NC}"
semgrep scan \
    --config "p/python" \
    --config "p/owasp-top-ten" \
    --config "p/secrets" \
    app/app.py 2>&1; ec=$?
check "Semgrep" 0 "$ec"

# ─── 5. Hadolint ───────────────────────────────────────
echo ""
echo -e "${YELLOW}[5/7] Hadolint — Dockerfile lint${NC}"
if command -v hadolint &>/dev/null; then
    hadolint app/Dockerfile 2>&1; ec=$?
    check "Hadolint" 0 "$ec"
elif command -v docker &>/dev/null; then
    docker run --rm -i hadolint/hadolint < app/Dockerfile 2>&1; ec=$?
    check "Hadolint (Docker)" 0 "$ec"
else
    skip "Hadolint (installer : https://github.com/hadolint/hadolint/releases)"
fi

# ─── 6. Checkov ────────────────────────────────────────
echo ""
echo -e "${YELLOW}[6/7] Checkov — scan IaC Kubernetes${NC}"
checkov -d .
check "Checkov" 0 "$ec"

# ─── 7. Trivy ──────────────────────────────────────────
echo ""
echo -e "${YELLOW}[7/7] Trivy — scan image container${NC}"
if command -v docker &>/dev/null; then
    echo "  Construction de l'image Docker..."
    docker build -f app/Dockerfile -t flask-app:test ./app 2>&1; ec=$?
    if [ "$ec" -eq 0 ]; then
        if command -v trivy &>/dev/null; then
            trivy image flask-app:test --severity HIGH,CRITICAL 2>&1; ec=$?
        else
            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                aquasecurity/trivy:latest image \
                --severity HIGH,CRITICAL flask-app:test 2>&1; ec=$?
        fi
        check "Trivy" 0 "$ec"
        docker rmi flask-app:test 2>/dev/null || true
    else
        skip "Trivy (Docker build a échoué)"
    fi
else
    skip "Trivy (Docker non disponible — installer Docker Desktop)"
fi

# ─── Résumé ────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo -e "  ${GREEN}${PASS} PASS${NC}  |  ${RED}${FAIL} FAIL${NC}  |  ${BLUE}${SKIP} SKIP${NC}"
echo "══════════════════════════════════════════════════"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
