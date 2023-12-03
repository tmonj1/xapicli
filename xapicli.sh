#!/usr/bin/env bash

#
# Bash Strict Mode (http://redsymbol.net/articles/unofficial-bash-strict-mode/)
#

# 現在のIFSとオプションの設定の退避
OLD_IFS="$IFS"
OLD_SET=$(set +o)

# 本スクリプトでの設定
IFS=$' \t\n'
set -uo pipefail

# スクリプト終了時(source実行時)、IFSとオプション設定を元に戻す
trap 'IFS="$OLD_IFS"; eval "$OLD_SET"' RETURN

# エラーが発生したコマンド名、行番号、EXITコードを出力
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND";' ERR

#
# globals
#

# Function to display command completion candidates
function _xapicli_completion() {

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
      COMPREPLY=( $(compgen -W "$(curl -s "file://${apidef_file}" | jq -r 'keys | map(ltrimstr("/")) | .[]')" -- ${cur}) )
      return 0
      ;;
    -q)
      local method="${COMP_WORDS[1]}"
      local resource="/${COMP_WORDS[2]}"
      local query_options
      query_options=$(curl -s "file://${apidef_file}" | \
      jq -r '.["'"${resource}"'"][] | select(.method == "'"${method}"'") | .query_parameters | map(.name) | .[] ')
      COMPREPLY=( $(compgen -W "${query_options}" -- ${cur}) )
      return 0
      ;;
    -p)
      # Add logic to provide completion candidates for post parameters
      # You can fetch the available post parameters from the OpenAPI specification
     local post_params
     post_params=$(echo ${oas_spec_json} \
      | jq -r '.paths."'$url'.'"$method"' | .parameters | .[] | select(.in == "body") | .name')
      COMPREPLY=( $(compgen -W "${query_options}" -- ${cur}) )
      return 0
      ;;
  esac
}

# Register the completion function for xapicli command
complete -F _xapicli_completion xapicli

# Main function to handle the command
function xapicli() {
  local method url query_params post_params spec_file

  method="$1"
  url="$2"
  shift 2

  #
  # load apidef file
  #

  # get .xapicli.conf
  local conf_dir="${XAPICLI_CONF_DIR:-$HOME/.xapicli}"
  local conf_file="${conf_dir}/xapicli.conf"
  local apidef_file
  apidef_file="${conf_dir}/apis/$(jq -r '. as $root | .default as $default_target | $root[$default_target].apidef ' ${conf_file})"

  while [[ $# -gt 0 ]]; do
    case "$1" in
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
#      -f)
#        oas_spec_json=$(curl -sL "$1")
#        shift 2
#        ;;
      *)
        echo "Invalid option: $1"
        return 1
        ;;
    esac
  done

  # Add logic to construct the curl command and execute it
  # You can use the provided method, url, query_params, and post_params variables

  echo "Calling API with method: $method"
  echo "URL: $url"
  echo "Query Parameters: ${query_params[@]}"
  echo "Post Parameters: ${post_params[@]}"
}

# Call the main function with the provided arguments
# xapicli "$@"