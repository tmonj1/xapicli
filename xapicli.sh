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
}

#
# command completion function
#

# Bash completion function for xapicli
_xapicli_completion() {

  OLD_IFS="$IFS"
  #IFS=$'\t\n '
  trap 'IFS="$OLD_IFS"' RETURN

  # 初期化処理
  COMPREPLY=()
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  #
  # load apidef file
  #

  # get .xapicli.conf
  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local conf_file="${conf_dir}/xapicli.conf"
  local apidef_file
  apidef_file="${conf_dir}/apis/$(jq -r '. as $root | .default as $default_target | $root[$default_target].apidef ' ${conf_file})"

  local http_methods="get post put delete"

  case "${prev}" in
    xapicli)
      #COMPREPLY=( $(compgen -W "${http_methods}" -- ${cur}) )
      readarray -t COMPREPLY < <(compgen -W "${http_methods}" -- ${cur})
      return 0
      ;;
    get|post|put|delete)
      COMPREPLY=( $(compgen -W "$(curl -s "file://${apidef_file}" | jq -r 'keys | .[]')" -- ${cur}) )
      return 0
      ;;
    -q)
      local method="${COMP_WORDS[1]}"
      local resource="${COMP_WORDS[2]}"
      local query_params
      query_params=$(curl -s "file://${apidef_file}" | \
      jq -r '.["'"${resource}"'"][] | select(.method == "'"${method}"'") | .query_parameters | map(.name) | .[] ')
      COMPREPLY=( $(compgen -W "${query_params}" -- ${cur}) )
      return 0
      ;;
    -p)
      local method="${COMP_WORDS[1]}"
      local resource="${COMP_WORDS[2]}"
      local post_params
      post_params=$(curl -s "file://${apidef_file}" | \
      jq -r '.["'"${resource}"'"][] | select(.method == "'"${method}"'") | .post_parameters | map(.name) | .[] ')
      COMPREPLY=( $(compgen -W "${post_params}" -- ${cur}) )
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
  # load apidef file
  #

  # get .xapicli.conf
  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local conf_file="${conf_dir}/xapicli.conf"
  local apidef_file
  apidef_file="${conf_dir}/apis/$(jq -r '. as $root | .default as $default_target | $root[$default_target].apidef ' ${conf_file})"
  local apidef
  apidef=$(curl -s "file://${apidef_file}")

  #
  # argument parsing
  #
  local readonly LONG_OPTS="help,summary::,summary-csv"
  local readonly SHORT_OPTS="q:p:"
  args=$(getopt -o "${SHORT_OPTS}" -l "${LONG_OPTS}" -- "$@") || return 1
  eval "set -- $args"

  local summary_csv=false
  local show_summary=false
  local url=""
  local method=""
  local resource=""
  local query_params=""
  local post_params=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift;
        ;;
      --help)
        _usage
        return 0
        ;;
      --summary-csv)
        summary_csv=true
        shift
        ;;
      --summary)
        # xapicli --summary
        # xapicli --summary=<resource>
        # xapicli <method> <resource> --summary
        shift
        if [[ "${1:0:1}" != "-" ]]; then
          resource="$1"
          shift
        fi
        show_summary=true
        ;;
      get|post|put|delete)
        method="$1"
        shift
        ;;
      -q)
        shift
        query_params+=("$1")
        shift
        ;;
      -p)
        shift
        post_params+=("$1")
        shift
        ;;
      *)
        local matched
        matched=$(echo "${apidef}" | jq -r 'keys[] | select(. == "'"$1"'")' | wc -l)
        matched="${matched//[[:blank:]]/}"
        if [[ "${matched}" == 1 ]]; then
          resource="$1"
          shift
        else
          echo "Invalid argument: $1"
          _usage
          return 1
        fi
        ;;
    esac
  done

  # show summary
  if [[ "${show_summary}" == true ]]; then
    echo "${apidef}" \
      | jq -r '
          to_entries[]
          | .key as $k
          | .value[]
          | [.method + " " +  $k] + ([.query_parameters[].name]?
          | map("-q " + .)) + ([.post_parameters[].name]?
          | map("-p " + .))
          | select(
              .[0]
              | startswith("'"${method}"'") and endswith("'"${resource}"'")
            )
          | . + [""]
          | .[]
          | if startswith("-") then "  -" + . else . end
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
          | [.method, $k] + ([.query_parameters[].name]?
          | map("-q " + .)) + ([.post_parameters[].name]?
          | map("-p " + .))
          | @csv
        '
    return 0
  fi
  # Add logic to construct the curl command and execute it
  # You can use the provided method, url, query_params, and post_params variables

  echo "Calling API with method: $method"
  echo "URL: $url"
  echo "Query Parameters: ${query_params[@]}"
  echo "Post Parameters: ${post_params[@]}"
}

# Call the main function with the provided arguments
# xapicli "$@"