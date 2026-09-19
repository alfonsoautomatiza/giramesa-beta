#!/usr/bin/env bash
# Ubuntu/Linux port of release-all.ps1 — dispatches release-test-builds.yml
# after exhaustive read-only preflight checks. Mirrors the PowerShell script 1:1.
set -euo pipefail

usage() {
    cat <<'EOF'
Uso: release-all.sh [opciones]

Opciones:
  --app-repository <dir>       Ruta local del repositorio privado
                               (predeterminado: ../DONDE_COMER junto a este script)
  --app-repository-slug <s>    Slug del repo privado (predeterminado: wertyMSD/donde-comer)
   --branch <nombre>            Rama a publicar (predeterminado: master)
  --beta-repository-slug <s>   Slug del repo público (predeterminado: wertyMSD/giramesa-beta)
  --release-notes-file <f>     Notas de la release (predeterminado: release-notes.txt junto al script)
  --api-base-url <url>         URL HTTPS pública de la API (opcional)
  --skip-android               No compilar Android
  --skip-web                   No compilar Web
  --skip-windows               No compilar Windows
  --skip-ios                   No compilar iOS
  --wait                       Esperar la ejecución del workflow y propagar su resultado
  --dry-run | --what-if        Mostrar el comando planificado sin ejecutar el dispatch
  -h, --help                   Mostrar esta ayuda
EOF
}

write_status() {
    printf '[Giramesa] %s\n' "$1"
}

die() {
    printf '[Giramesa] ERROR: %s\n' "$1" >&2
    exit 1
}

require_command() {
    local name="$1" path
    if ! path="$(command -v "$name")" || [ -z "$path" ]; then
        die "No se encontró '$name' en PATH. Instalalo por separado antes de continuar."
    fi
    printf '%s' "$path"
}

# Run a command, capture combined stdout+stderr, die on non-zero exit.
# Sets LAST_EXIT and LAST_TEXT.
run_cmd() {
    local fail_msg="$1"
    shift
    local out code
    set +e
    out="$("$@" 2>&1)"
    code=$?
    set -e
    LAST_EXIT=$code
    LAST_TEXT=$out
    if [ "$code" -ne 0 ]; then
        die "$fail_msg (código $code)."
    fi
}

# Same as run_cmd but never dies. Sets LAST_EXIT and LAST_TEXT.
run_tolerant() {
    local out code
    set +e
    out="$("$@" 2>&1)"
    code=$?
    set -e
    LAST_EXIT=$code
    LAST_TEXT=$out
}

run_git() {
    local repo="$1" fail_msg="$2"
    shift 2
    run_cmd "$fail_msg" git -C "$repo" "$@"
}

assert_repository_slug() {
    local value="$1" owner repo
    if [[ ! "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        die "Slug de repositorio no válido: $value"
    fi
    owner="${value%%/*}"
    repo="${value#*/}"
    if [ "$owner" = "." ] || [ "$owner" = ".." ] || [ "$repo" = "." ] || [ "$repo" = ".." ]; then
        die "Slug de repositorio no válido: $value"
    fi
}

get_flutter_metadata() {
    local pubspec="$1" count line version_token
    if [ ! -f "$pubspec" ]; then
        die "No existe el archivo Flutter requerido: $pubspec"
    fi
    if ! iconv -f UTF-8 -t UTF-8 "$pubspec" >/dev/null 2>&1; then
        die 'app/pubspec.yaml debe ser texto UTF-8 válido.'
    fi

    count="$(grep -c -- '^version:' "$pubspec" || true)"
    if [ "$count" -ne 1 ]; then
        die "app/pubspec.yaml debe contener exactamente una clave top-level 'version:'; se encontraron $count."
    fi

    line="$(grep -- '^version:' "$pubspec")"
    line="${line%$'\r'}"

    # NOTE: POSIX ERE has no \t escape; [[:blank:]] = space + tab.
    local line_re='^version:[[:blank:]]*([^[:blank:]+]+)\+([1-9][0-9]*)[[:blank:]]*$'
    if [[ ! "$line" =~ $line_re ]]; then
        die "La versión Flutter debe tener el formato SemVer estricto X.Y.Z[-prerelease]+N, con N entero positivo; por ejemplo 'version: 0.1.1+2'."
    fi
    version_token="${BASH_REMATCH[1]}"
    BUILD_NUMBER="${BASH_REMATCH[2]}"

    local semver_re='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*)?'
    if [[ ! "$version_token" =~ ^${semver_re}$ ]]; then
        die "La versión Flutter debe tener el formato SemVer estricto X.Y.Z[-prerelease]+N, con N entero positivo; por ejemplo 'version: 0.1.1+2'."
    fi

    if [ "$BUILD_NUMBER" -lt 1 ] || [ "$BUILD_NUMBER" -gt 2147483647 ]; then
        die 'El build number de app/pubspec.yaml excede el rango de entero positivo admitido por las plataformas.'
    fi
    FLUTTER_VERSION="$version_token"
}

assert_safe_release_notes() {
    local path="$1" size
    if [ ! -f "$path" ]; then
        die "No existe ReleaseNotesFile: $path"
    fi
    size="$(stat -c %s -- "$path")"
    if [ "$size" -lt 1 ] || [ "$size" -gt 40960 ]; then
        die 'Las notas deben contener entre 1 byte y 40 KiB para respetar el límite de workflow_dispatch.'
    fi
    if ! iconv -f UTF-8 -t UTF-8 "$path" >/dev/null 2>&1; then
        die 'Las notas deben ser texto UTF-8 válido.'
    fi
    if [ -z "$(tr -d '[:space:]' < "$path")" ]; then
        die 'Las notas están vacías o contienen bytes nulos.'
    fi
    # NOTE: bash cannot pass a NUL byte as an argument ($'\x00' yields an empty
    # string), so the NUL scan must use a PCRE escape instead.
    if LC_ALL=C grep -Pq -- '\x00' "$path"; then
        die 'Las notas están vacías o contienen bytes nulos.'
    fi
    if grep -Eq -- '-----BEGIN [A-Z ]*PRIVATE KEY-----' "$path"; then
        die 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
    fi
    if grep -Eq -- 'ghp_[A-Za-z0-9]{30,}' "$path"; then
        die 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
    fi
    if grep -Eq -- 'github_pat_[A-Za-z0-9_]{30,}' "$path"; then
        die 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
    fi
    if grep -Eq -- 'AKIA[0-9A-Z]{16}' "$path"; then
        die 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
    fi
    if grep -Eiq -- '(api[_-]?key|client[_-]?secret|password|access[_-]?token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"'[:space:]]{8,}["'"'"']' "$path"; then
        die 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
    fi
}

is_public_ipv4() {
    local ip="$1" a b c d
    IFS='.' read -r a b c d <<< "$ip"
    if [ "$a" -eq 0 ] || [ "$a" -eq 10 ] || [ "$a" -eq 127 ] || [ "$a" -ge 224 ]; then
        return 1
    fi
    if [ "$a" -eq 169 ] && [ "$b" -eq 254 ]; then
        return 1
    fi
    if [ "$a" -eq 172 ] && [ "$b" -ge 16 ] && [ "$b" -le 31 ]; then
        return 1
    fi
    if [ "$a" -eq 192 ] && [ "$b" -eq 168 ]; then
        return 1
    fi
    if [ "$a" -eq 100 ] && [ "$b" -ge 64 ] && [ "$b" -le 127 ]; then
        return 1
    fi
    return 0
}

is_public_ipv6() {
    local ip="${1,,}" mapped
    if [ "$ip" = "::1" ] || [ "$ip" = "::" ]; then
        return 1
    fi
    if [[ "$ip" == "::ffff:"*"."* ]]; then
        mapped="${ip#::ffff:}"
        if is_public_ipv4 "$mapped"; then return 0; else return 1; fi
    fi
    case "$ip" in
        fe8*|fe9*|fea*|feb*) return 1 ;; # link-local
        fec*|fed*|fee*|fef*) return 1 ;; # site-local
        fc*|fd*)             return 1 ;; # ULA fc00::/7
        ff*)                 return 1 ;; # multicast
    esac
    return 0
}

assert_public_https_url() {
    local value="$1" re authority host addrs a all_public=1
    re='^https://([^/?#@]+)(/[^?#]*)?$'
    if [[ ! "$value" =~ $re ]]; then
        die 'ApiBaseUrl debe ser una URL HTTPS pública sin credenciales, query ni fragmento.'
    fi
    authority="${BASH_REMATCH[1]}"
    host="$authority"
    if [[ "$host" == \[*\] ]]; then
        host="${host:1:-1}"
    elif [[ "$host" == *:* ]]; then
        host="${host%:*}"
    fi
    if [ -z "$host" ]; then
        die 'ApiBaseUrl debe ser una URL HTTPS pública sin credenciales, query ni fragmento.'
    fi
    if [ "$host" = "localhost" ] || [[ "$host" == *.localhost ]] || [[ "$host" == *.local ]] || [[ "$host" == *.internal ]]; then
        die 'ApiBaseUrl no puede apuntar a localhost ni a una red privada.'
    fi
    addrs="$(getent ahosts "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
    if [ -z "$addrs" ]; then
        die 'No se pudo resolver el host de ApiBaseUrl.'
    fi
    while IFS= read -r a; do
        [ -n "$a" ] || continue
        if [[ "$a" == *.* ]]; then
            is_public_ipv4 "$a" || all_public=0
        else
            is_public_ipv6 "$a" || all_public=0
        fi
    done <<< "$addrs"
    if [ "$all_public" -ne 1 ]; then
        die 'ApiBaseUrl resuelve a una dirección no pública y fue bloqueada.'
    fi
}

get_repo_field() {
    # $1 = gh binary, $2 = slug, $3 = json field
    run_cmd "No se pudo consultar $2" "$1" repo view "$2" --json "$3" --jq ".$3"
    printf '%s' "$LAST_TEXT"
}

assert_github_object_absent() {
    local description="$1"
    if [ "$LAST_EXIT" -eq 0 ]; then
        die "$description ya existe. Actualizá version: en DONDE_COMER/app/pubspec.yaml; nunca se reutiliza ni sobrescribe una versión."
    fi
    if ! grep -Eiq 'HTTP[[:space:]]+404|not found' <<< "$LAST_TEXT"; then
        die "No se pudo confirmar que $description no exista; se cancela ante un resultado remoto ambiguo."
    fi
}

bool_not() {
    if [ "$1" = true ]; then printf 'false'; else printf 'true'; fi
}

trim_trailing_slashes() {
    local p="$1"
    while [ "$p" != "/" ] && [[ "$p" == */ ]]; do
        p="${p%/}"
    done
    printf '%s' "$p"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

app_repository=""
app_repository_slug="wertyMSD/donde-comer"
branch="master"
beta_repository_slug="wertyMSD/giramesa-beta"
api_base_url=""
skip_android=false
skip_web=false
skip_windows=false
skip_ios=false
do_wait=false
dry_run=false
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_notes_file="$script_dir/release-notes.txt"

need_value() {
    if [ $# -lt 2 ]; then
        printf 'Falta el valor para %s\n' "$1" >&2
        usage >&2
        exit 1
    fi
}

while [ $# -gt 0 ]; do
    case "$1" in
        --app-repository)          need_value "$@"; app_repository="$2"; shift 2 ;;
        --app-repository=*)        app_repository="${1#*=}"; shift ;;
        --app-repository-slug)     need_value "$@"; app_repository_slug="$2"; shift 2 ;;
        --app-repository-slug=*)   app_repository_slug="${1#*=}"; shift ;;
        --branch)                  need_value "$@"; branch="$2"; shift 2 ;;
        --branch=*)                branch="${1#*=}"; shift ;;
        --beta-repository-slug)    need_value "$@"; beta_repository_slug="$2"; shift 2 ;;
        --beta-repository-slug=*)  beta_repository_slug="${1#*=}"; shift ;;
        --release-notes-file)      need_value "$@"; release_notes_file="$2"; shift 2 ;;
        --release-notes-file=*)    release_notes_file="${1#*=}"; shift ;;
        --api-base-url)            need_value "$@"; api_base_url="$2"; shift 2 ;;
        --api-base-url=*)          api_base_url="${1#*=}"; shift ;;
        --skip-android)            skip_android=true; shift ;;
        --skip-web)                skip_web=true; shift ;;
        --skip-windows)            skip_windows=true; shift ;;
        --skip-ios)                skip_ios=true; shift ;;
        --wait)                    do_wait=true; shift ;;
        --dry-run|--what-if)       dry_run=true; shift ;;
        -h|--help)                 usage; exit 0 ;;
        *)
            printf 'Parámetro desconocido: %s\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight validation (read-only)
# ---------------------------------------------------------------------------

assert_repository_slug "$app_repository_slug"
assert_repository_slug "$beta_repository_slug"
if [[ ! "$branch" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$branch" == *..* ]] || [[ "$branch" == /* ]] || [[ "$branch" == */ ]]; then
    die 'Branch contiene caracteres o segmentos no válidos.'
fi
if [ "$skip_android" = true ] && [ "$skip_web" = true ] && [ "$skip_windows" = true ] && [ "$skip_ios" = true ]; then
    die 'No se puede omitir las cuatro plataformas.'
fi
if [ -n "$api_base_url" ]; then
    assert_public_https_url "$api_base_url"
fi

if [ -z "${app_repository// /}" ]; then
    app_repository="$(dirname -- "$script_dir")/DONDE_COMER"
fi
if [ ! -d "$app_repository" ]; then
    die "No existe el repositorio privado local: $app_repository"
fi
app_repository="$(realpath -- "$app_repository")"
git_bin="$(require_command git)"
gh_bin="$(require_command gh)"

run_git "$app_repository" 'AppRepository no es un worktree Git válido' rev-parse --show-toplevel
repository_root="$(trim_trailing_slashes "$LAST_TEXT")"
if [ "$repository_root" != "$(trim_trailing_slashes "$app_repository")" ]; then
    die "AppRepository debe apuntar a la raíz del worktree privado: $repository_root"
fi

run_git "$app_repository" 'No se pudo comprobar el estado del worktree privado' status --porcelain --untracked-files=normal
if [ -n "$LAST_TEXT" ]; then
    die 'El worktree privado debe estar completamente limpio, incluidos archivos no rastreados. El script no hará commit, stash, pull ni push.'
fi
run_git "$app_repository" 'El worktree privado está en detached HEAD' symbolic-ref --quiet --short HEAD
current_branch="$LAST_TEXT"
if [ "$current_branch" != "$branch" ]; then
    die "El worktree privado está en la rama '$current_branch', pero se requiere '$branch'."
fi
run_git "$app_repository" 'No se pudo resolver HEAD' rev-parse HEAD
head_sha="$LAST_TEXT"
run_git "$app_repository" "No existe la referencia local origin/$branch; actualizala manualmente antes de publicar" rev-parse "refs/remotes/origin/$branch"
origin_sha="$LAST_TEXT"
if [ "$head_sha" != "$origin_sha" ]; then
    die "HEAD ($head_sha) no coincide con origin/$branch ($origin_sha). Sincronizá el worktree manualmente; el script no hará pull, merge ni push."
fi

get_flutter_metadata "$app_repository/app/pubspec.yaml"
release_version="$FLUTTER_VERSION"
build_number="$BUILD_NUMBER"
tag="v$release_version"

if [ ! -f "$release_notes_file" ]; then
    die "No existe ReleaseNotesFile: $release_notes_file"
fi
if grep -Fq -- 'TODO: rellenar las notas de esta release' "$release_notes_file"; then
    die "ReleaseNotesFile ($release_notes_file) todavía tiene el texto TODO por defecto. Rellená las notas de la release antes de continuar."
fi
assert_safe_release_notes "$release_notes_file"
notes_base64="$(base64 -w 0 -- "$release_notes_file")"

run_cmd "GitHub CLI no está autenticado. Ejecutá 'gh auth login' por separado; este script no autentica ni recibe tokens" \
    "$gh_bin" auth status --hostname github.com

app_repo_name="$(get_repo_field "$gh_bin" "$app_repository_slug" nameWithOwner)"
app_repo_visibility="$(get_repo_field "$gh_bin" "$app_repository_slug" visibility)"
app_repo_url="$(get_repo_field "$gh_bin" "$app_repository_slug" url)"
beta_repo_name="$(get_repo_field "$gh_bin" "$beta_repository_slug" nameWithOwner)"
beta_repo_visibility="$(get_repo_field "$gh_bin" "$beta_repository_slug" visibility)"
beta_repo_url="$(get_repo_field "$gh_bin" "$beta_repository_slug" url)"

if [ "${app_repo_name,,}" != "${app_repository_slug,,}" ] || [ "${app_repo_visibility,,}" != "private" ]; then
    die "$app_repository_slug debe existir y ser PRIVATE. El script no cambiará su visibilidad."
fi
if [ "${beta_repo_name,,}" != "${beta_repository_slug,,}" ] || [ "${beta_repo_visibility,,}" != "public" ]; then
    die "$beta_repository_slug debe existir y ser PUBLIC. El script no cambiará su visibilidad."
fi

encoded_branch="${branch//\//%2F}"
run_cmd "La rama remota $branch no existe o no es accesible" \
    "$gh_bin" api --method GET "repos/$app_repository_slug/branches/$encoded_branch" --jq .commit.sha
remote_branch_sha="$LAST_TEXT"
if [ "$remote_branch_sha" != "$head_sha" ]; then
    die "El HEAD local no coincide con GitHub $app_repository_slug@$branch. Ejecutá fetch y sincronizá manualmente antes de publicar."
fi
run_cmd "release-test-builds.yml no existe en $app_repository_slug@$branch" \
    "$gh_bin" api --method GET "repos/$app_repository_slug/contents/.github/workflows/release-test-builds.yml" -f "ref=$branch"
run_cmd 'El workflow existe como archivo pero GitHub Actions no lo reconoce en la rama predeterminada' \
    "$gh_bin" workflow view release-test-builds.yml --repo "$app_repository_slug"

run_tolerant "$gh_bin" release view "$tag" --repo "$beta_repository_slug" --json url
assert_github_object_absent "La Release $tag en $beta_repository_slug"
run_tolerant "$gh_bin" api --method GET "repos/$beta_repository_slug/git/ref/tags/$tag"
assert_github_object_absent "El tag $tag en $beta_repository_slug"

declare -A before_ids=()
run_cmd 'No se pudo obtener la lista inicial de ejecuciones' \
    "$gh_bin" run list --repo "$app_repository_slug" --workflow release-test-builds.yml --event workflow_dispatch --limit 100 --json databaseId --jq '.[].databaseId'
while IFS= read -r run_id; do
    [ -n "$run_id" ] && before_ids["$run_id"]=1
done <<< "$LAST_TEXT"

run_android="$(bool_not "$skip_android")"
run_web="$(bool_not "$skip_web")"
run_windows="$(bool_not "$skip_windows")"
run_ios="$(bool_not "$skip_ios")"

write_status "App privada local: $app_repository"
write_status "App remota: $app_repo_url@$branch ($head_sha)"
write_status "Destino público: $beta_repo_url"
write_status "Flutter pubspec: versión $release_version, build $build_number, tag $tag"

if [ "$dry_run" = true ]; then
    planned_notes="<base64 de notas: ${#notes_base64} caracteres>"
    write_status "WhatIf comando planificado: gh workflow run release-test-builds.yml --repo '$app_repository_slug' --ref '$branch' -f expected_commit_sha='$head_sha' -f beta_repository='$beta_repository_slug' -f release_notes_base64='$planned_notes' -f api_base_url='$api_base_url' -f run_android='$run_android' -f run_web='$run_web' -f run_windows='$run_windows' -f run_ios='$run_ios'"
    write_status 'WhatIf completado: todas las comprobaciones fueron de solo lectura y no se ejecutó workflow_dispatch.'
    exit 0
fi

# ---------------------------------------------------------------------------
# Dispatch and (optional) follow-up
# ---------------------------------------------------------------------------

run_cmd 'No se pudo iniciar release-test-builds.yml' \
    "$gh_bin" workflow run release-test-builds.yml \
    --repo "$app_repository_slug" \
    --ref "$branch" \
    -f "expected_commit_sha=$head_sha" \
    -f "beta_repository=$beta_repository_slug" \
    -f "release_notes_base64=$notes_base64" \
    -f "api_base_url=$api_base_url" \
    -f "run_android=$run_android" \
    -f "run_web=$run_web" \
    -f "run_windows=$run_windows" \
    -f "run_ios=$run_ios"

write_status 'Workflow solicitado; buscando la ejecución creada.'
created_run_id=""
created_run_url=""
created_run_status=""
for attempt in $(seq 1 12); do
    [ -n "$created_run_id" ] && break
    sleep 5
    run_cmd 'No se pudo localizar la ejecución creada' \
        "$gh_bin" run list --repo "$app_repository_slug" --workflow release-test-builds.yml --event workflow_dispatch --branch "$branch" --limit 20 \
        --json databaseId,url,status,conclusion,headSha \
        --jq '.[] | [.databaseId, .url, .status, .conclusion, .headSha] | @tsv'
    while IFS=$'\t' read -r run_id run_url run_status _run_conclusion run_head; do
        [ -n "$run_id" ] || continue
        if [ -z "${before_ids[$run_id]:-}" ] && [ "$run_head" = "$head_sha" ]; then
            created_run_id="$run_id"
            created_run_url="$run_url"
            created_run_status="$run_status"
            break
        fi
    done <<< "$LAST_TEXT"
done
if [ -z "$created_run_id" ]; then
    die "El dispatch fue aceptado, pero no se encontró su run. Revisá https://github.com/$app_repository_slug/actions/workflows/release-test-builds.yml"
fi

write_status "Run: $created_run_url"
write_status "Estado: $created_run_status"

if [ "$do_wait" = true ]; then
    run_tolerant "$gh_bin" run watch "$created_run_id" --repo "$app_repository_slug" --exit-status
    watch_exit="$LAST_EXIT"
    run_cmd 'No se pudo consultar el estado final' \
        "$gh_bin" run view "$created_run_id" --repo "$app_repository_slug" --json url,status,conclusion \
        --jq '[.url, .status, .conclusion] | @tsv'
    IFS=$'\t' read -r final_url final_status final_conclusion <<< "$LAST_TEXT"
    write_status "Estado final: $final_status / $final_conclusion"
    write_status "Run: $final_url"
    if [ "$watch_exit" -ne 0 ]; then
        exit "$watch_exit"
    fi
fi
