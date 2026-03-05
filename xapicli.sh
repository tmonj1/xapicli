#!/usr/bin/env bash

#
# Bash Strict Mode (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
#

# 現在のIFSとオプションの設定の退避
OLD_IFS="$IFS"
OLD_SET=$(set +o | grep -e nounset -e pipefail)

# 本スクリプトでの設定
IFS=$'\t\n'
set -uo pipefail
HISTFILE=""

# スクリプト終了時(source実行時)、IFSとオプション設定を元に戻す
trap 'IFS="$OLD_IFS"; eval "$OLD_SET"' RETURN

# エラーが発生したコマンド名、行番号、EXITコードを出力
trap 'rc=$?; cmd="${BASH_COMMAND}"; echo >&2 "$0: Error on line $LINENO: $cmd (exit $rc)"' ERR

#
# constants
#

declare readonly LONG_OPTS="help,summary::,summary-csv,version"
declare readonly LONG_OPTS_INIT="init:"
declare readonly _XAPICLI_VERSION="0.1.0"

# escape sequences for colored output on the console
RSET=$'\e[0m'  # reset
FRED=$'\e[31m' # foreground red
FGRN=$'\e[32m' # foreground green
#FYEL="\e[43m" # background yellow

#
# globals
#

#
# private functions
#

# @description output error message (in red)
# @param $* error message text
# @stderr error message
# @exitcode 0
_err() {
  echo -e "${FRED} $* ${RSET}" >&2
}

# @description output informational message (in green)
# @param $* informational message text
# @stderr informational message
# @exitcode 0
_info() {
  echo -e "${FGRN} $* ${RSET}" >&2
}

# @description output plain message (with no color)
# @param $* message text
# @stderr message
# @exitcode 0
_msg() {
  echo -e "$*" >&2
}

# @description print usage
# @param (none)
# @stderr usage message
# @exitcode 0
_usage()
{
  _msg "Usage: xapicli [options] <method> <resource> [params]"
  _msg "Options:"
  _msg "  -h, --help                Show this help message"
  _msg "  --version                 Show version"
  _msg "  --init <spec-file>        Initialize API from an OpenAPI spec file"
  _msg "  --summary[=<resource>]    Print available endpoints"
  _msg "  --summary-csv             Print endpoints in CSV format"
  _msg "Params:"
  _msg "  -H <header: value>        Custom HTTP header (repeatable)"
  _msg "  -q <name> <value>         Query parameter (repeatable)"
  _msg "  -p <name> <value>         Body parameter (repeatable)"
  _msg "  -d <json>                 Raw JSON body (overrides -p)"
}

# @description initialize API from an OpenAPI spec file
# @param $1 path to the OpenAPI spec file (JSON)
# @exitcode 0 on success, 1 on error
_xapicli_init() {
  local spec_file="${1:-}"

  if [[ -z "${spec_file}" ]]; then
    _err "--init requires a spec file argument"
    _msg "Usage: xapicli --init <openapi-spec.json>"
    return 1
  fi

  if [[ ! -f "${spec_file}" ]]; then
    _err "File not found: ${spec_file}"
    return 1
  fi

  if ! command -v json-refs > /dev/null 2>&1; then
    _err "json-refs is required. Install it with: npm install -g json-refs"
    return 1
  fi

  # Derive API name from filename (strip path and extension)
  local api_name
  api_name=$(basename "${spec_file}" | sed 's/\.[^.]*$//')

  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local apis_dir="${conf_dir}/apis"
  local conf_file="${conf_dir}/xapicli.conf"
  local output_file="${apis_dir}/${api_name}.json"

  mkdir -p "${apis_dir}"

  _info "Resolving \$ref references in ${spec_file} ..."
  local resolved_json
  resolved_json=$(json-refs resolve "${spec_file}") || {
    _err "Failed to resolve \$ref references in ${spec_file}"
    return 1
  }

  _info "Generating API definition ..."
  local tmp_filter
  tmp_filter=$(mktemp)
  cat > "${tmp_filter}" <<'INSTALL_API_JQ'
# extract elements under "paths"
.paths
# split each resource to a single line in "key=resource-name, value=api-desc" format
| to_entries
# convert each line into the {"resource-name": {api-desc}} format using `map`
| map({
    key,
    value: [
      .value
      # split each HTTP method to a single line in "key=HTTP-method, value=api-desc" format
      | to_entries[]
      # convert each line into the {"method":"HTTP-method",
      # {query_parameters, post_parameters, post_parameters_required}} format
      | {
          method: .key,
          query_parameters: (
            [
              .value.parameters[]?
              | select(.in == "query")
              | select(.schema.type != "object" and .schema.type != "array")
              | { name: .name, type: .schema.type, required: (.required // false), enum: (.schema.enum // []) }
            ] // []
          ),
          post_parameters: (
            [
              ((.value.requestBody.content["application/json"].schema.properties // {})
              | to_entries[])
              | if .value.type == "object" then
                  (.key as $parent | ((.value.properties // {}) | to_entries[]) |
                    {"name": ($parent + "." + .key)} + .value)
                else
                  {"name": .key} + .value
                end
            ]
            | map(select(.type != "object" and (.type != "array" or (.items.type? != "object" and .items.type? != "array"))))
          ),
          post_parameters_required: (
            .value.requestBody.content["application/json"].schema.required // {}
          )
        }
      | if .method == "post" or .method == "put" then
          .post_parameters_required as $required_params
          | .post_parameters
          |= map (
              . as $post_param
              |
              if $required_params | any (. == $post_param.name) then
                $post_param + {required: true}
              else
                $post_param
              end
            )
        else
          del(.post_parameters)
        end
      | del(.post_parameters_required)
    ]
  })
| from_entries
| del(.. | .xml?)
INSTALL_API_JQ

  echo "${resolved_json}" | jq -f "${tmp_filter}" > "${output_file}"
  local jq_rc=$?
  rm -f "${tmp_filter}"

  if [[ ${jq_rc} -ne 0 ]]; then
    _err "Failed to generate API definition"
    rm -f "${output_file}"
    return 1
  fi

  # Extract base URL from spec (servers[0].url), fallback to empty string
  local base_url
  base_url=$(echo "${resolved_json}" | jq -r '.servers[0].url // ""')
  [[ "${base_url}" == "null" ]] && base_url=""

  # Update xapicli.conf: add/update entry; set as default only if conf doesn't exist yet
  if [[ ! -f "${conf_file}" ]]; then
    jq -n \
      --arg name "${api_name}" \
      --arg spec "${spec_file}" \
      --arg apidef "${api_name}.json" \
      --arg url "${base_url}" \
      '{default: $name, ($name): {openapispec: $spec, apidef: $apidef, url: $url}}' \
      > "${conf_file}"
  else
    local tmp_conf
    tmp_conf=$(mktemp)
    jq \
      --arg name "${api_name}" \
      --arg spec "${spec_file}" \
      --arg apidef "${api_name}.json" \
      --arg url "${base_url}" \
      '.[$name] = {openapispec: $spec, apidef: $apidef, url: $url}' \
      "${conf_file}" > "${tmp_conf}" && mv "${tmp_conf}" "${conf_file}"
  fi

  _info "API definition saved to: ${output_file}"
  _info "Config updated: ${conf_file}"
  if [[ -n "${base_url}" ]]; then
    _info "Base URL set to: ${base_url}"
    _msg "  (Update 'url' in ${conf_file} if this is incorrect)"
  else
    _msg "Note: No base URL found in spec. Set 'url' in ${conf_file} manually."
  fi
  return 0
}

#
# command completion function
#

# cache for api definition in completion context
declare _XAPICLI_APIDEF_CACHE=""
declare _XAPICLI_APIDEF_FILE_CACHE=""

# Bash completion function for xapicli
_xapicli_completion() {

  # シェルオプションを安全な状態に設定し、xapicli()が設定したRETURNトラップをクリア (#18)
  # set -u や set -o pipefail が有効な場合でも補完関数が途中で終了しないようにする
  local _saved_opts
  _saved_opts=$(set +o | grep -E 'nounset|pipefail|errexit')
  set +euo pipefail
  trap 'eval "$_saved_opts"' RETURN

  # 初期化処理
  COMPREPLY=()
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  #
  # load apidef file (with caching)
  #

  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local conf_file="${conf_dir}/xapicli.conf"
  [[ -f "${conf_file}" ]] || return 0

  local api_name
  api_name=$(jq -r '.default' "${conf_file}")
  local apidef_file
  apidef_file="${conf_dir}/apis/$(jq -r --arg name "${api_name}" '.[$name].apidef' "${conf_file}")"
  [[ -f "${apidef_file}" ]] || return 0

  # ファイルが変わった場合のみ再読み込み (#10: キャッシュによるパフォーマンス改善)
  if [[ "${apidef_file}" != "${_XAPICLI_APIDEF_FILE_CACHE}" ]]; then
    _XAPICLI_APIDEF_CACHE=$(cat "${apidef_file}")
    _XAPICLI_APIDEF_FILE_CACHE="${apidef_file}"
  fi
  local apidef="${_XAPICLI_APIDEF_CACHE}"

  local http_methods="get post put delete"

  # -q/-p の値補完: 直前が param 名で2つ前が -q/-p なら enum 値を候補に (#15)
  if [[ COMP_CWORD -ge 4 ]]; then
    local _flag="${COMP_WORDS[COMP_CWORD-2]}"
    if [[ "${_flag}" == "-q" || "${_flag}" == "-p" ]]; then
      local _method="${COMP_WORDS[1]}"
      local _res="${COMP_WORDS[2]}"
      local _param="${prev}"
      local _key
      [[ "${_flag}" == "-q" ]] && _key="query_parameters" || _key="post_parameters"
      local _enums
      _enums=$(echo "${apidef}" | jq -r \
        --arg res "${_res}" --arg meth "${_method}" \
        --arg p "${_param}" --arg k "${_key}" \
        '.[$res][]? | select(.method == $meth) | .[$k][] | select(.name == $p) | .enum[]?')
      if [[ -n "${_enums}" ]]; then
        COMPREPLY=( $(compgen -W "${_enums}" -- "${cur}") )
        return 0
      fi
    fi
  fi

  case "${prev}" in
    xapicli)
      COMPREPLY=( $(compgen -W "${http_methods}" -- "${cur}") )
      return 0
      ;;
    get|post|put|delete)
      # 選択されたHTTPメソッドをサポートするリソースのみ補完候補に表示 (#12)
      COMPREPLY=( $(compgen -W "$(echo "${apidef}" | jq -r --arg m "${prev}" \
        'to_entries[] | select(any(.value[]; .method == $m)) | .key')" -- "${cur}") )
      return 0
      ;;
    -q)
      local method="${COMP_WORDS[1]}"
      local resource="${COMP_WORDS[2]}"
      local query_params
      # --arg を使ってインジェクション対策 (#5)
      query_params=$(echo "${apidef}" | \
        jq -r --arg res "${resource}" --arg meth "${method}" \
        '.[$res][]? | select(.method == $meth) | .query_parameters[].name')
      COMPREPLY=( $(compgen -W "${query_params}" -- "${cur}") )
      return 0
      ;;
    -p)
      local method="${COMP_WORDS[1]}"
      local resource="${COMP_WORDS[2]}"
      local post_params
      # --arg を使ってインジェクション対策 (#5)
      post_params=$(echo "${apidef}" | \
        jq -r --arg res "${resource}" --arg meth "${method}" \
        '.[$res][]? | select(.method == $meth) | .post_parameters[].name')
      COMPREPLY=( $(compgen -W "${post_params}" -- "${cur}") )
      return 0
      ;;
    /*)
      # resource path: show applicable options (#13)
      local _method="${COMP_WORDS[1]}"
      local _resource="${prev}"
      local _flags
      _flags=$(echo "${apidef}" | jq -r --arg res "${_resource}" --arg m "${_method}" '
        [(.[$res][]? | select(.method == $m)) as $ep |
          (if (($ep.query_parameters // []) | length) > 0 then "-q" else empty end),
          (if (($ep.post_parameters  // []) | length) > 0 then "-p" else empty end)
        ] | unique | .[]
      ')
      COMPREPLY=( $(compgen -W "${_flags} --summary --help -H -d" -- "${cur}") )
      return 0
      ;;
  esac
}

# Register the completion function for xapicli command
complete -F _xapicli_completion xapicli

#
# main function
#

# xapicli main function
xapicli() {
  #
  # Bash Strict Mode
  #

  # 現在のIFSとオプションの設定の退避
  OLD_IFS="$IFS"
  OLD_SET=$(set +o | grep -e nounset -e pipefail)

  # 本スクリプトでの設定
  IFS=$'\t\n'
  set -uo pipefail

  # スクリプト終了時(source実行時)、IFSとオプション設定を元に戻す
  trap 'IFS="$OLD_IFS"; eval "$OLD_SET"' RETURN

  # エラーが発生したコマンド名、行番号、EXITコードを出力
  trap 'rc=$?; cmd="${BASH_COMMAND}"; echo >&2 "$0: Error on line $LINENO: $cmd (exit $rc)"' ERR

  #
  # GNU getopt の確認
  #

  local getopt_test
  if getopt -T > /dev/null 2>&1; then
    getopt_test=0
  else
    getopt_test=$?
  fi
  if [[ ${getopt_test} -ne 4 ]]; then
    _err "GNU getopt が必要です。以下を実行してください:"
    _err "  brew install gnu-getopt"
    _err "  export PATH=\"/opt/homebrew/opt/gnu-getopt/bin:\$PATH\""
    return 1
  fi

  # -h/--help/--version/--init は config ロード前に処理 (#31, #38)
  local _i=1
  while [[ $_i -le $# ]]; do
    case "${!_i}" in
      -h|--help)
        _usage
        return 0
        ;;
      --version)
        echo "xapicli ${_XAPICLI_VERSION}"
        return 0
        ;;
      --init)
        _i=$((_i + 1))
        _xapicli_init "${!_i:-}"
        return $?
        ;;
    esac
    _i=$((_i + 1))
  done

  #
  # load config and apidef file
  #

  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local conf_file="${conf_dir}/xapicli.conf"

  # エラーハンドリング: コンフィグファイルの存在確認 (#7)
  if [[ ! -f "${conf_file}" ]]; then
    _err "config file not found: ${conf_file}"
    return 1
  fi

  local api_name
  api_name=$(jq -r '.default' "${conf_file}")
  local apidef_file
  apidef_file="${conf_dir}/apis/$(jq -r --arg name "${api_name}" '.[$name].apidef' "${conf_file}")"

  # エラーハンドリング: API定義ファイルの存在確認 (#7)
  if [[ ! -f "${apidef_file}" ]]; then
    _err "API definition file not found: ${apidef_file}"
    return 1
  fi

  local apidef
  apidef=$(cat "${apidef_file}")

  # コンフィグからURLを読み込む (#2)
  local url
  url=$(jq -r --arg name "${api_name}" '.[$name].url' "${conf_file}")

  #
  # argument parsing
  #

  # Pre-process: -q/-p はそれぞれ <name> <value> の2引数、-d は <json> の1引数を取る (#3, #4)
  # -H は <header: value> の1引数 (#39)
  local -a query_params=()
  local -a post_params=()
  local -a custom_headers=()
  local raw_body=""
  local -a clean_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        _usage
        return 0
        ;;
      --version)
        echo "xapicli ${_XAPICLI_VERSION}"
        return 0
        ;;
      -H)
        shift
        if [[ $# -lt 1 ]]; then
          _err "'-H' requires one argument: <header: value>"
          return 1
        fi
        custom_headers+=("$1")
        shift
        ;;
      -q)
        shift
        if [[ $# -lt 2 ]]; then
          _err "'-q' requires two arguments: <param> <value>"
          return 1
        fi
        query_params+=("$1" "$2")
        shift 2
        ;;
      -p)
        shift
        if [[ $# -lt 2 ]]; then
          _err "'-p' requires two arguments: <param> <value>"
          return 1
        fi
        post_params+=("$1" "$2")
        shift 2
        ;;
      -d)
        shift
        if [[ $# -lt 1 ]]; then
          _err "'-d' requires one argument: <json>"
          return 1
        fi
        raw_body="$1"
        shift
        ;;
      *)
        clean_args+=("$1")
        shift
        ;;
    esac
  done

  # XAPICLI_CUSTOM_HEADER 環境変数からカスタムヘッダーを追加 (改行区切り) (#39)
  if [[ -n "${XAPICLI_CUSTOM_HEADER:-}" ]]; then
    while IFS= read -r _hdr; do
      [[ -n "${_hdr}" ]] && custom_headers+=("${_hdr}")
    done <<< "${XAPICLI_CUSTOM_HEADER}"
  fi

  local args
  args=$(getopt -o "" -l "${LONG_OPTS}" -- ${clean_args[@]+"${clean_args[@]}"}) || return 1
  eval "set -- $args"

  local summary_csv=false
  local show_summary=false
  local method=""
  local resource=""
  local apidef_resource=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        # end of options
        shift
        ;;
      --help)
        # show help (xapicli --help)
        _usage
        return 0
        ;;
      --summary-csv)
        # output api summary in csv (xapicli --summary-csv)
        shift
        summary_csv=true
        ;;
      --summary)
        # output api summary
        # all methods for all resources : xapicli --summary
        # all methods for a resource    : xapicli --summary=<resource>
        # a method for a resource       : xapicli <method> <resource> --summary
        shift
        if [[ $# -gt 0 && "${1:0:1}" != "-" ]]; then
          resource="$1"
          shift
        fi
        show_summary=true
        ;;
      get|post|put|delete)
        # http method
        method="$1"
        shift
        ;;
      *)
        # resource (xapicli <method> <resource>)
        local matched
        # --arg を使ってインジェクション対策 (#5)
        matched=$(echo "${apidef}" | jq -r --arg r "$1" 'keys[] | select(. == $r)' | wc -l)
        matched="${matched//[[:blank:]]/}"
        if [[ "${matched}" == 1 ]]; then
          resource="$1"
          apidef_resource="$1"
          shift
        else
          # パステンプレートマッチング: /pet/99 → /pet/{petId} (#20)
          local template_key
          template_key=$(echo "${apidef}" | jq -r --arg path "$1" '
            [keys[] | . as $k |
            ($k | gsub("{[^}]+}"; "[^/]+")) as $pattern |
            if ($path | test("^" + $pattern + "$")) then $k else empty end
            ][0] // empty
          ')
          if [[ -n "${template_key}" ]]; then
            resource="$1"
            apidef_resource="${template_key}"
            shift
          else
            _err "Invalid argument: $1"
            _usage
            return 1
          fi
        fi
        ;;
    esac
  done

  # show summary
  if [[ "${show_summary}" == true ]]; then
    echo "${apidef}" \
      | jq -r --arg m "${method}" --arg r "${resource}" '
          to_entries[]
          | .key as $k
          | .value[]
          | [.method + " " + $k]
            + (.query_parameters // [] | [.[]] | map("-q " + .name + (if .required then "*" else "" end)))
            + (.post_parameters  // [] | [.[]] | map("-p " + .name + (if .type == "array" then "[]" else "" end) + (if .required then "*" else "" end)))
          | select(
              ($m == "" or (.[0] | split(" ")[0]) == $m) and
              ($r == "" or (.[0] | split(" ")[1]) == $r)
            )
          | . + [""]
          | .[]
          | if startswith("-") then "  " + . else . end
        '
    return 0
  fi

  # summary-csv
  if [[ "${summary_csv}" == true ]]; then
    echo "${apidef}" \
      | jq -r '
          to_entries[]
          | .key as $k
          | .value[]
          | [.method, $k]
            + (.query_parameters // [] | [.[].name] | map("-q " + .))
            + (.post_parameters  // [] | [.[].name] | map("-p " + .))
          | @csv
        '
    return 0
  fi

  # 必須引数の検証
  if [[ -z "${method}" ]]; then
    _err "HTTP method is required"
    _usage
    return 1
  fi
  if [[ -z "${resource}" ]]; then
    _err "Resource path is required"
    _usage
    return 1
  fi

  # URLの組み立て: ベースURLの末尾スラッシュを除去してリソースパスを結合 (#2)
  local full_url="${url%/}${resource}"

  # クエリパラメータを URL に付加
  if [[ ${#query_params[@]} -gt 0 ]]; then
    local query_string=""
    local i
    for ((i=0; i<${#query_params[@]}; i+=2)); do
      [[ -n "${query_string}" ]] && query_string+="&"
      query_string+="${query_params[$i]}=${query_params[$((i+1))]}"
    done
    full_url+="?${query_string}"
  fi

  # カスタムヘッダーを curl の引数配列に変換 (#39)
  local -a curl_header_args=()
  local _ch
  for _ch in ${custom_headers[@]+"${custom_headers[@]}"}; do
    curl_header_args+=("-H" "${_ch}")
  done

  # HTTPリクエストの実行 (#1)
  local method_upper
  method_upper=$(printf '%s' "${method}" | tr '[:lower:]' '[:upper:]')
  if [[ "${method}" == "get" || "${method}" == "delete" ]]; then
    curl -s -X "${method_upper}" \
      ${curl_header_args[@]+"${curl_header_args[@]}"} \
      "${full_url}"
  else
    # -d で生JSONが指定された場合はそれを使用、なければ -p からJSONを組み立て
    local json_body
    if [[ -n "${raw_body}" ]]; then
      json_body="${raw_body}"
    else
      json_body="{}"
      if [[ ${#post_params[@]} -gt 0 ]]; then
        # 配列型パラメータ名の一覧を取得 (#23)
        local array_params
        array_params=$(echo "${apidef}" | jq -r \
          --arg r "${apidef_resource}" --arg m "${method}" \
          '.[$r][]? | select(.method == $m) | .post_parameters[]? | select(.type == "array") | .name' \
          | tr '\n' ':')
        local i
        for ((i=0; i<${#post_params[@]}; i+=2)); do
          local _pk="${post_params[$i]}"
          local _pv="${post_params[$((i+1))]}"
          if [[ ":${array_params}:" == *":${_pk}:"* ]]; then
            # 配列型: 初回は[$v]、2回目以降は追記
            json_body=$(printf '%s' "${json_body}" | \
              jq --arg k "${_pk}" --arg v "${_pv}" '
                if has($k) then .[$k] += [$v] else . + {($k): [$v]} end
              ')
          elif [[ "${_pk}" == *"."* ]]; then
            # ドット記法: category.id → {"category": {"id": $v}} (#24)
            json_body=$(printf '%s' "${json_body}" | \
              jq --arg k "${_pk}" --arg v "${_pv}" 'setpath(($k | split(".")); $v)')
          else
            json_body=$(printf '%s' "${json_body}" | \
              jq --arg k "${_pk}" --arg v "${_pv}" '. + {($k): $v}')
          fi
        done
      fi
    fi
    curl -s -X "${method_upper}" "${full_url}" \
      -H "Content-Type: application/json" \
      ${curl_header_args[@]+"${curl_header_args[@]}"} \
      -d "${json_body}"
  fi
}

# Call the main function with the provided arguments
# xapicli "$@"
