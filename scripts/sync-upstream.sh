#!/bin/bash

# sync-upstream.sh: Hole Updates aus dem Original-Repo (CachyOS/cachy-update), merge sie in deinen Fork,
# baue neu, installiere und pushe nach origin.
#
# Nutzung (im Repo-Ordner oder von ueberall):
#   scripts/sync-upstream.sh               # fetch + merge + build + install + push
#   scripts/sync-upstream.sh --no-install  # ohne Build / Installation
#   scripts/sync-upstream.sh --no-push     # ohne Push nach origin
#   scripts/sync-upstream.sh --check       # nur anzeigen, ob es Neuerungen gibt

set -u

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/CachyOS/cachy-update.git}"
PREFIX="${PREFIX:-/usr}"

do_install="true"
do_push="true"
check_only=""

for arg in "${@}"; do
	case "${arg}" in
		--no-install) do_install="" ;;
		--no-push) do_push="" ;;
		--check) check_only="true" ;;
		-h|--help)
			sed -n '3,11p' "${0}" | sed 's/^# \{0,1\}//'
			exit 0
		;;
		*)
			echo "Unbekannte Option: ${arg}" >&2
			exit 1
		;;
	esac
done

msg() { echo -e "\e[1;34m==>\e[0m\e[1m ${1}\e[0m"; }
err() { echo -e "\e[1;31m==> FEHLER:\e[0m ${1}" >&2; }

# In den Repo-Root wechseln
cd "$(dirname "$(readlink -f "${0}")")" || exit 1
repo_root=$(git rev-parse --show-toplevel 2> /dev/null) || { err "Kein Git-Repository gefunden"; exit 1; }
cd "${repo_root}" || exit 1

# Upstream-Remote anlegen, falls noch nicht vorhanden
if ! git remote get-url upstream > /dev/null 2>&1; then
	msg "Lege Remote 'upstream' an (${UPSTREAM_URL})"
	git remote add upstream "${UPSTREAM_URL}" || exit 1
fi

# Saubere Arbeitskopie erforderlich
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	err "Es gibt uncommittete Aenderungen. Bitte erst committen oder 'git stash' ausfuehren."
	git status --short --untracked-files=no
	exit 1
fi

msg "Hole Aenderungen von upstream..."
git fetch upstream || { err "git fetch fehlgeschlagen"; exit 1; }
git remote set-head upstream -a > /dev/null 2>&1

upstream_branch=$(git symbolic-ref --short refs/remotes/upstream/HEAD 2> /dev/null | sed 's#^upstream/##')
upstream_branch="${upstream_branch:-main}"
current_branch=$(git rev-parse --abbrev-ref HEAD)

new_commits=$(git rev-list --count "HEAD..upstream/${upstream_branch}")

if [ "${new_commits}" -eq 0 ]; then
	msg "Dein Fork ist bereits auf dem neuesten Stand (keine neuen Commits in upstream/${upstream_branch})."
	exit 0
fi

msg "${new_commits} neue Commit(s) in upstream/${upstream_branch}:"
git log --oneline --no-decorate "HEAD..upstream/${upstream_branch}" | head -20
[ "${new_commits}" -gt 20 ] && echo "  ... und $((new_commits - 20)) weitere"

[ -n "${check_only}" ] && exit 0

msg "Merge upstream/${upstream_branch} in ${current_branch}..."
if ! git merge --no-edit "upstream/${upstream_branch}"; then
	echo
	err "Merge-Konflikt! Betroffene Dateien:"
	git diff --name-only --diff-filter=U
	echo
	echo "Loesen: Dateien bearbeiten (Marker <<<<<<< / >>>>>>> entfernen), dann:"
	echo "  git add <dateien> && git commit"
	echo "  und dieses Skript erneut starten (oder manuell bauen / pushen)."
	echo "Abbrechen und Zustand zuruecksetzen: git merge --abort"
	exit 1
fi

# Syntaxcheck der Shell-Skripte nach dem Merge
syntax_ok="true"
for f in src/arch-update.sh src/lib/*.sh; do
	if ! bash -n "${f}"; then
		err "Syntaxfehler in ${f}"
		syntax_ok=""
	fi
done
if [ -z "${syntax_ok}" ]; then
	err "Bitte Fehler beheben, bevor installiert / gepusht wird."
	exit 1
fi

# Pruefen, dass der Auto-Modus noch vorhanden ist (falls upstream Dateien stark umgebaut hat)
if ! grep -q 'auto_mode' src/lib/common.sh; then
	err "Der Auto-Modus (auto_mode) fehlt nach dem Merge in src/lib/common.sh - bitte pruefen."
	exit 1
fi

if [ -n "${do_install}" ]; then
	msg "Baue und installiere (PREFIX=${PREFIX})..."
    make build WITH_TRAY=false || { err "make build fehlgeschlagen"; exit 1; }
	sudo make install PREFIX="${PREFIX} WITH_TRAY=false || { err "make install fehlgeschlagen"; exit 1; }
fi

if [ -n "${do_push}" ]; then
	msg "Pushe nach origin/${current_branch}..."
	git push origin "${current_branch}" || { err "git push fehlgeschlagen"; exit 1; }
fi

msg "Fertig. Teste mit: cachy-update --auto"
