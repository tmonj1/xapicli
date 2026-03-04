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
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND";' ERR

#
# constants
#

declare readonly LONG_OPTS="help,summary::,summary-csv"

# escape sequences for colored output on the console
RSET="\e[0m"  # reset
FRED="\e[31m" # foreground red
FGRN="\e[32m" # foreground green
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
  _msg "Usage: xapicli <method> <resource> [options]"
  _msg "Options:"
  _msg "  -q <query_param> <value>  Query parameter"
  _msg "  -p <post_param> <value>   Post parameter"
  _msg "  -d <json>                 Raw JSON body (overrides -p)"
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
  trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND";' ERR

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
  local -a query_params=()
  local -a post_params=()
  local raw_body=""
  local -a clean_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

  local args
  args=$(getopt -o "" -l "${LONG_OPTS}" -- ${clean_args[@]+"${clean_args[@]}"}) || return 1
  eval "set -- $args"

  local summary_csv=false
  local show_summary=false
  local method=""
  local resource=""
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
          shift
        else
          _err "Invalid argument: $1"
          _usage
          return 1
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
            + (.query_parameters // [] | [.[].name] | map("-q " + .))
            + (.post_parameters  // [] | [.[].name] | map("-p " + .))
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

  # HTTPリクエストの実行 (#1)
  local method_upper
  method_upper=$(printf '%s' "${method}" | tr '[:lower:]' '[:upper:]')
  if [[ "${method}" == "get" || "${method}" == "delete" ]]; then
    curl -s -X "${method_upper}" "${full_url}"
  else
    # -d で生JSONが指定された場合はそれを使用、なければ -p からJSONを組み立て
    local json_body
    if [[ -n "${raw_body}" ]]; then
      json_body="${raw_body}"
    else
      json_body="{}"
      if [[ ${#post_params[@]} -gt 0 ]]; then
        local i
        for ((i=0; i<${#post_params[@]}; i+=2)); do
          json_body=$(printf '%s' "${json_body}" | \
            jq --arg k "${post_params[$i]}" --arg v "${post_params[$((i+1))]}" '. + {($k): $v}')
        done
      fi
    fi
    curl -s -X "${method_upper}" "${full_url}" \
      -H "Content-Type: application/json" \
      -d "${json_body}"
  fi
}

# Call the main function with the provided arguments
# xapicli "$@"
