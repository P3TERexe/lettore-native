#!/bin/bash
set -e

# ==============================================================================
# Script di Pubblicazione Release v0.3.0 per Lettore Native
# Corregge la versione errata (v3.0.0 -> v0.3.0) su GitHub
# ==============================================================================

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo -e "${BLUE}=== Inizio Procedura di Allineamento Release v0.3.0 ===${NC}\n"

# 1. Verifica autenticazione GitHub CLI (gh)
echo -e "${BLUE}1. Verifica stato autenticazione GitHub CLI...${NC}"
if ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}⚠️ Il token di GitHub CLI non risulta autenticato o è scaduto.${NC}"
    echo -e "${YELLOW}Avvio della procedura interattiva di login: 'gh auth login'${NC}\n"
    gh auth login -h github.com
fi

# Configura git affinché utilizzi il token di gh per autenticare le operazioni di push
gh auth setup-git

echo -e "${GREEN}✓ GitHub CLI autenticato e configurato per git.${NC}\n"

# 2. Verifica / creazione del file zip di release v0.3.0
ZIP_FILE="LettoreNative-v0.3.0-macOS.zip"
if [ ! -f "$ZIP_FILE" ]; then
    echo -e "${BLUE}2. Archivio $ZIP_FILE non trovato. Compilo con build-app.sh...${NC}"
    ./build-app.sh
else
    echo -e "${GREEN}✓ Archivio $ZIP_FILE trovato ($(du -h "$ZIP_FILE" | cut -f1)).${NC}\n"
fi

# Rimuovi eventuale vecchio archivio v3.0.0 locale
if [ -f "LettoreNative-v3.0.0-macOS.zip" ]; then
    echo -e "${YELLOW}Rimuovo archivio deprecato LettoreNative-v3.0.0-macOS.zip...${NC}"
    rm -f "LettoreNative-v3.0.0-macOS.zip"
fi

# 3. Rimozione della vecchia release errata v3.0.0 da GitHub
echo -e "${BLUE}3. Rimozione release errata v3.0.0 da GitHub (se presente)...${NC}"
if gh release view v3.0.0 &>/dev/null; then
    gh release delete v3.0.0 --yes --cleanup-tag
    echo -e "${GREEN}✓ Release v3.0.0 rimossa da GitHub.${NC}\n"
else
    echo -e "${YELLOW}Nessuna release v3.0.0 trovata su GitHub.${NC}\n"
fi

# 4. Rimozione tag remoto v3.0.0 (se ancora presente nei refs remoti)
echo -e "${BLUE}4. Pulizia del tag remoto v3.0.0...${NC}"
git push origin :refs/tags/v3.0.0 2>/dev/null || true
echo -e "${GREEN}✓ Tag remoto v3.0.0 verificato/ripulito.${NC}\n"

# 5. Push del branch main e configurazione/push del tag locale v0.3.0
echo -e "${BLUE}5. Push delle modifiche del branch main su origin...${NC}"
git push origin main

echo -e "${BLUE}Allineamento tag locale v0.3.0 all'attuale commit di main...${NC}"
git tag -d v3.0.0 2>/dev/null || true
git tag -a v0.3.0 -m "Release v0.3.0: Native macOS Edition" -f

echo -e "${BLUE}Push del tag v0.3.0 su GitHub...${NC}"
git push origin v0.3.0 -f
echo -e "${GREEN}✓ Tag v0.3.0 pushato su origin.${NC}\n"

# 6. Creazione della nuova Release v0.3.0 su GitHub
echo -e "${BLUE}6. Pubblicazione della nuova Release v0.3.0 su GitHub...${NC}"
NOTES_FILE="scripts/release-notes-v0.3.0.md"

gh release create v0.3.0 "$ZIP_FILE" \
    --title "Lettore Native v0.3.0 (Native macOS Edition)" \
    --notes-file "$NOTES_FILE" \
    --latest

echo -e "\n${GREEN}================================================================${NC}"
echo -e "${GREEN}🎉 Allineamento completato con successo!${NC}"
echo -e "${GREEN}Release v0.3.0 attiva e disponibile come 'Latest':${NC}"
echo -e "🔗 https://github.com/P3TERexe/lettore-native/releases/tag/v0.3.0"
echo -e "${GREEN}================================================================${NC}"
