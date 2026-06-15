#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIRS=()
FAILURES=0

RUN_DIR=""
BIN_DIR=""
HOME_DIR=""
WORKSPACE_DIR=""
SUMMARY_FILE=""
OUTPUT_FILE=""
STDOUT_FILE=""
STDERR_FILE=""
GEM_LOG=""
EXIT_CODE=0

function cleanup() {
  if [ "${#TEST_DIRS[@]}" -gt 0 ]; then
    rm -rf "${TEST_DIRS[@]}"
  fi
}

trap cleanup EXIT

function prepare_run() {
  local test_name="${1}"

  RUN_DIR="$(mktemp -d)"
  TEST_DIRS+=("${RUN_DIR}")
  BIN_DIR="${RUN_DIR}/bin"
  HOME_DIR="${RUN_DIR}/home"
  WORKSPACE_DIR="${RUN_DIR}/workspace"
  SUMMARY_FILE="${RUN_DIR}/summary.md"
  OUTPUT_FILE="${RUN_DIR}/output"
  STDOUT_FILE="${RUN_DIR}/stdout"
  STDERR_FILE="${RUN_DIR}/stderr"
  GEM_LOG="${RUN_DIR}/gem.log"

  mkdir -p "${BIN_DIR}" "${HOME_DIR}" "${WORKSPACE_DIR}"

  cat > "${BIN_DIR}/git" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB

  cat > "${BIN_DIR}/gem" <<'STUB'
#!/usr/bin/env bash

echo "$*" >> "${GEM_LOG}"

case "${GEM_STUB_MODE}:${1}" in
  build_failure:build)
    echo "build failed" >&2
    exit 42
    ;;
  no_artifact:build)
    exit 0
    ;;
  push_failure_rubygems:push)
    if [[ "$*" != *"--host"* ]]; then
      echo "Access Denied" >&2
      exit 43
    fi
    exit 0
    ;;
  push_failure_github:push)
    if [[ "$*" == *"rubygems.pkg.github.com"* ]]; then
      echo "GitHub package denied" >&2
      exit 44
    fi
    exit 0
    ;;
  push_failure_gemcoop:push)
    if [[ "$*" == *"gem.coop"* ]]; then
      echo "Gem.coop denied" >&2
      exit 45
    fi
    exit 0
    ;;
  push_failure_forgejo:push)
    if [[ "$*" == *"forgejo.example.com"* ]]; then
      echo "Forgejo denied" >&2
      exit 46
    fi
    exit 0
    ;;
  push_failure_gitea:push)
    if [[ "$*" == *"gitea.example.com"* ]]; then
      echo "Gitea denied" >&2
      exit 47
    fi
    exit 0
    ;;
  *:build)
    output=""
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --output)
          output="$2"
          shift 2
          ;;
        --output=*)
          output="${1#--output=}"
          shift
          ;;
        *)
          shift
          ;;
      esac
    done
    if [[ -z "${output}" ]]; then
      echo "missing --output" >&2
      exit 99
    fi
    touch "${output}"
    exit 0
    ;;
  *:push)
    exit 0
    ;;
  *)
    echo "unexpected gem command: $*" >&2
    exit 99
    ;;
esac
STUB

  chmod +x "${BIN_DIR}/git" "${BIN_DIR}/gem"
  echo "Running ${test_name}"
}

function add_gemspec() {
  local name="${1}"

  cat > "${WORKSPACE_DIR}/${name}.gemspec" <<SPEC
Gem::Specification.new do |spec|
  spec.name = "${name}"
  spec.version = "0.1.0"
  spec.summary = "${name} test gem"
  spec.authors = ["Actionshub"]
  spec.files = []
end
SPEC
}

function run_publish() {
  local test_name="${1}"
  local stub_mode="${2}"
  local github_token="${3}"
  local rubygems_token="${4}"
  local gemcoop_token="${5}"
  local owner="${6}"
  local repository_owner="${7}"
  local forgejo_token="${8}"
  local forgejo_url="${9}"
  local forgejo_owner="${10}"
  local gitea_token="${11}"
  local gitea_url="${12}"
  local gitea_owner="${13}"
  shift 13

  prepare_run "${test_name}"

  local gemspec
  for gemspec in "$@"; do
    case "${gemspec}" in
      INVALID:*)
        echo "this is not a gemspec" > "${WORKSPACE_DIR}/${gemspec#INVALID:}.gemspec"
        ;;
      *)
        add_gemspec "${gemspec}"
        ;;
    esac
  done
  touch "${WORKSPACE_DIR}/stale-9.9.9.gem"

  (
    cd "${WORKSPACE_DIR}" || exit 1
    HOME="${HOME_DIR}" \
      GITHUB_WORKSPACE="${WORKSPACE_DIR}" \
      GITHUB_REPOSITORY_OWNER="${repository_owner}" \
      GITHUB_STEP_SUMMARY="${SUMMARY_FILE}" \
      GITHUB_OUTPUT="${OUTPUT_FILE}" \
      PUBLISH_GEM_GITHUB_TOKEN="${github_token}" \
      PUBLISH_GEM_RUBYGEMS_TOKEN="${rubygems_token}" \
      PUBLISH_GEM_GEMCOOP_TOKEN="${gemcoop_token}" \
      PUBLISH_GEM_OWNER="${owner}" \
      PUBLISH_GEM_FORGEJO_TOKEN="${forgejo_token}" \
      PUBLISH_GEM_FORGEJO_URL="${forgejo_url}" \
      PUBLISH_GEM_FORGEJO_OWNER="${forgejo_owner}" \
      PUBLISH_GEM_GITEA_TOKEN="${gitea_token}" \
      PUBLISH_GEM_GITEA_URL="${gitea_url}" \
      PUBLISH_GEM_GITEA_OWNER="${gitea_owner}" \
      GEM_LOG="${GEM_LOG}" \
      GEM_STUB_MODE="${stub_mode}" \
      PATH="${BIN_DIR}:${PATH}" \
      "${ROOT_DIR}/script/publish" > "${STDOUT_FILE}" 2> "${STDERR_FILE}"
  )

  EXIT_CODE=$?
}

function fail() {
  local message="${1}"

  echo "FAIL: ${message}"
  echo "--- stdout ---"
  cat "${STDOUT_FILE}"
  echo "--- stderr ---"
  cat "${STDERR_FILE}"
  echo "--- gem log ---"
  if [ -f "${GEM_LOG}" ]; then
    cat "${GEM_LOG}"
  fi
  echo "--- summary ---"
  if [ -f "${SUMMARY_FILE}" ]; then
    cat "${SUMMARY_FILE}"
  fi
  FAILURES=$((FAILURES + 1))
}

function assert_exit_code() {
  local expected="${1}"
  local message="${2}"

  if [ "${EXIT_CODE}" -ne "${expected}" ]; then
    fail "${message}: expected exit ${expected}, got ${EXIT_CODE}"
  fi
}

function assert_file_contains() {
  local file="${1}"
  local expected="${2}"
  local message="${3}"

  if ! grep -Fq -- "${expected}" "${file}"; then
    fail "${message}: expected ${file} to contain '${expected}'"
  fi
}

function assert_file_not_contains() {
  local file="${1}"
  local unexpected="${2}"
  local message="${3}"

  if [ -f "${file}" ] && grep -Fq -- "${unexpected}" "${file}"; then
    fail "${message}: expected ${file} not to contain '${unexpected}'"
  fi
}

function assert_file_line() {
  local file="${1}"
  local expected="${2}"
  local message="${3}"

  if ! grep -Fxq -- "${expected}" "${file}"; then
    fail "${message}: expected ${file} to contain line '${expected}'"
  fi
}

function assert_gem_log_count() {
  local expected="${1}"
  local pattern="${2}"
  local message="${3}"
  local actual

  actual="$(grep -Fc -- "${pattern}" "${GEM_LOG}" 2> /dev/null || true)"
  if [ "${actual}" -ne "${expected}" ]; then
    fail "${message}: expected ${expected} matches for '${pattern}', got ${actual}"
  fi
}

run_publish "no tokens exits 2" success "" "" "" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 2 "no tokens"
assert_file_contains "${STDOUT_FILE}" "::error::No API keys found." "no-token error command"
assert_file_line "${OUTPUT_FILE}" "completed=false" "no-token completed output"

run_publish "no gemspec fails clearly" success "" "ruby-token" "" "" "sous-chefs" "" "" "" "" "" ""
assert_exit_code 1 "no gemspec"
assert_file_contains "${STDOUT_FILE}" "::error::No gemspec files found" "no-gemspec error command"

run_publish "gem build failure propagates" build_failure "" "ruby-token" "" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 42 "build failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to build alpha.gemspec" "build failure error command"
assert_file_contains "${STDERR_FILE}" "build failed" "build stderr"

run_publish "invalid gemspec fails with workflow error" success "" "ruby-token" "" "" "sous-chefs" "" "" "" "" "" "" INVALID:bad
assert_exit_code 1 "invalid gemspec"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to load bad.gemspec" "invalid gemspec error command"

run_publish "missing built artifact fails" no_artifact "" "ruby-token" "" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 1 "missing built artifact"
assert_file_contains "${STDOUT_FILE}" "::error::Gem build did not create" "missing artifact error command"

run_publish "RubyGems push failure names registry" push_failure_rubygems "" "ruby-token" "" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 43 "rubygems push failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to push alpha-0.1.0.gem to RubyGems.org" "rubygems failure error command"

run_publish "GitHub Packages push failure names owner host" push_failure_github "github-token" "" "" "custom-owner" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 44 "github push failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to push alpha-0.1.0.gem to GitHub Packages at https://rubygems.pkg.github.com/custom-owner" "github failure error command"

run_publish "Gem.coop push failure names registry" push_failure_gemcoop "" "" "gemcoop-token" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 45 "gemcoop push failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to push alpha-0.1.0.gem to Gem.coop" "gemcoop failure error command"

run_publish "Forgejo push failure names registry and host" push_failure_forgejo "" "" "" "" "sous-chefs" "forgejo-token" "https://forgejo.example.com" "forgejo-owner" "" "" "" alpha
assert_exit_code 46 "forgejo push failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to push alpha-0.1.0.gem to Forgejo at https://forgejo.example.com/api/packages/forgejo-owner/rubygems" "forgejo failure error command"

run_publish "Gitea push failure names registry and host" push_failure_gitea "" "" "" "" "sous-chefs" "" "" "" "gitea-token" "https://gitea.example.com" "gitea-owner" alpha
assert_exit_code 47 "gitea push failure"
assert_file_contains "${STDOUT_FILE}" "::error::Failed to push alpha-0.1.0.gem to Gitea at https://gitea.example.com/api/packages/gitea-owner/rubygems" "gitea failure error command"

run_publish "Forgejo token requires URL" success "" "" "" "" "sous-chefs" "forgejo-token" "" "" "" "" "" alpha
assert_exit_code 2 "forgejo missing url"
assert_file_contains "${STDOUT_FILE}" "::error::Forgejo publishing requires forgejo_url." "forgejo missing url error command"

run_publish "Gitea token requires URL" success "" "" "" "" "sous-chefs" "" "" "" "gitea-token" "" "" alpha
assert_exit_code 2 "gitea missing url"
assert_file_contains "${STDOUT_FILE}" "::error::Gitea publishing requires gitea_url." "gitea missing url error command"

run_publish "successful multi-gemspec publish pushes current artifacts" success "github-token" "ruby-token" "gemcoop-token" "" "sous-chefs" "" "" "" "" "" "" alpha beta
assert_exit_code 0 "successful publish"
assert_gem_log_count 1 "build alpha.gemspec --output" "alpha built once"
assert_gem_log_count 1 "build beta.gemspec --output" "beta built once"
assert_gem_log_count 6 "push " "only current built gems pushed to configured registries"
assert_file_contains "${GEM_LOG}" "push " "push commands logged"
assert_file_contains "${GEM_LOG}" "alpha-0.1.0.gem" "alpha pushed"
assert_file_contains "${GEM_LOG}" "beta-0.1.0.gem" "beta pushed"
assert_file_not_contains "${GEM_LOG}" "stale-9.9.9.gem" "stale workspace gem not pushed"
assert_file_contains "${GEM_LOG}" "https://rubygems.pkg.github.com/sous-chefs" "default owner used"
assert_file_contains "${SUMMARY_FILE}" "RubyGems.org" "summary includes rubygems"
assert_file_not_contains "${SUMMARY_FILE}" "github-token" "summary excludes github token"
assert_file_not_contains "${SUMMARY_FILE}" "ruby-token" "summary excludes rubygems token"
assert_file_not_contains "${SUMMARY_FILE}" "gemcoop-token" "summary excludes gemcoop token"
assert_file_line "${OUTPUT_FILE}" "completed=true" "successful completed output"
assert_file_line "${OUTPUT_FILE}" "version=0.1.0" "successful version output"
assert_file_contains "${OUTPUT_FILE}" "releases=[{\"name\":\"alpha\",\"version\":\"0.1.0\",\"file\":\"alpha-0.1.0.gem\",\"registries\":[\"RubyGems.org\",\"GitHub Packages\",\"Gem.coop\"]},{\"name\":\"beta\",\"version\":\"0.1.0\",\"file\":\"beta-0.1.0.gem\",\"registries\":[\"RubyGems.org\",\"GitHub Packages\",\"Gem.coop\"]}]" "successful releases output"

run_publish "Forgejo and Gitea publish use documented package hosts" success "" "" "" "fallback-owner" "sous-chefs" "forgejo-token" "https://forgejo.example.com/" "" "gitea-token" "https://gitea.example.com" "gitea-owner" alpha
assert_exit_code 0 "forgejo and gitea publish"
assert_file_contains "${HOME_DIR}/.gem/credentials" "https://forgejo.example.com/api/packages/fallback-owner/rubygems: Bearer forgejo-token" "forgejo credentials"
assert_file_contains "${HOME_DIR}/.gem/credentials" "https://gitea.example.com/api/packages/gitea-owner/rubygems: Bearer gitea-token" "gitea credentials"
assert_file_contains "${GEM_LOG}" "push --host https://forgejo.example.com/api/packages/fallback-owner/rubygems" "forgejo push host"
assert_file_contains "${GEM_LOG}" "push --host https://gitea.example.com/api/packages/gitea-owner/rubygems" "gitea push host"
assert_file_contains "${STDOUT_FILE}" "::add-mask::forgejo-token" "forgejo token masked"
assert_file_contains "${STDOUT_FILE}" "::add-mask::gitea-token" "gitea token masked"
assert_file_contains "${SUMMARY_FILE}" "Forgejo" "summary includes forgejo"
assert_file_contains "${SUMMARY_FILE}" "Gitea" "summary includes gitea"
assert_file_not_contains "${SUMMARY_FILE}" "forgejo-token" "summary excludes forgejo token"
assert_file_not_contains "${SUMMARY_FILE}" "gitea-token" "summary excludes gitea token"

run_publish "token aliases github_token" success "alias-token" "" "" "" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 0 "token alias publish"
assert_file_contains "${HOME_DIR}/.gem/credentials" ":github: Bearer alias-token" "alias token credentials"
assert_file_contains "${STDOUT_FILE}" "::add-mask::alias-token" "alias token masked"

run_publish "explicit owner overrides repository owner" success "github-token" "" "" "explicit-owner" "sous-chefs" "" "" "" "" "" "" alpha
assert_exit_code 0 "explicit owner publish"
assert_file_contains "${GEM_LOG}" "https://rubygems.pkg.github.com/explicit-owner" "explicit owner used"

run_publish "tokens are masked before publishing" success "github-token" "ruby-token" "gemcoop-token" "" "sous-chefs" "forgejo-token" "https://forgejo.example.com" "" "gitea-token" "https://gitea.example.com" "" alpha
assert_exit_code 0 "mask publish"
assert_file_contains "${STDOUT_FILE}" "::add-mask::github-token" "github token masked"
assert_file_contains "${STDOUT_FILE}" "::add-mask::ruby-token" "rubygems token masked"
assert_file_contains "${STDOUT_FILE}" "::add-mask::gemcoop-token" "gemcoop token masked"
assert_file_contains "${STDOUT_FILE}" "::add-mask::forgejo-token" "forgejo token masked"
assert_file_contains "${STDOUT_FILE}" "::add-mask::gitea-token" "gitea token masked"

if [ "${FAILURES}" -gt 0 ]; then
  echo "${FAILURES} test failure(s)"
  exit 1
fi

echo "All publish tests passed"
