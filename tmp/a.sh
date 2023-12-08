#!/bin/bash

# @name DX CLI
# @brief The command line interface for DX
# @description ...です。
# ...ます。

#
# IFSとオプションの設定
#

# 現在のIFSとオプションの設定の退避
OLD_IFS="$IFS"
OLD_SET=$(set +o)

# 本スクリプトでの設定
IFS=$'\t\n'
set -uo pipefail

# スクリプト終了時、確実に元に戻す
#trap 'IFS="$OLD_IFS"; eval "$OLD_SET"' EXIT
trap 'IFS="$OLD_IFS"; eval "$OLD_SET"; xxx=1 echo restored' RETURN
trap 's=$?; echo "$0: Error on line "$LINENO": $BASH_COMMAND";' ERR

#
# @section private関数
#

# @description _func1
# です。
# @arg $1 ファイル名です
# @arg $2 パス名です
_func1()
{
  echo a
}

bar()
{
  xxx=1
}

baz()
{
    xxx=2
}

# @description _func2です
# @noarg
_func2()
{
  echo a
}

_func3()
{
  echo a
}

# @description DX CLIコマンド
#
# @example
#   # GET accounts/api/users
#   $ dx get accounts users
#   # POST accounts/api/users
#   $ dx post accounts users -p id=tm1
#
# @option -q <name=value> クエリオプションを<名称>=<値>の形式で指定します。複数のオプションを指定したいときは `-q` を複数回指定します。
# @option -p <name=value> 属性を<名称>=<値>の形式で指定します。複数の属性を指定したいときは `-q` を複数回指定します。
#   --query-option | **-q** と同じです。
# @exitcode 成功したら0、そうでなければ非0を返します。
# @stdout レスポンスのContent-Typeがapplication/jsonのときは
#   レスポンスボディを出力します。それ以外のときは何も出力しません。
# @stderr ステータスコードを出力します。
dx()
{
  # dx man
  # dx man service
  # dx man resource
  # dx man [METHOD] [SERVICE_NAME] [RESOURCE_NAME]
  # SERVICE_NAME | RESOURCE_NAME | METHOD | QUERY_OPTIONS | PARAMETERS
  # GET /SERVICE_NAME/api?q1=[q1_value]&q2=[q2_value]
  # {
  #   "p1": "..."
  # }
  (
  echo a
  )
}

# 指定した文字列が配列にあれば0、そうでなければ1を返す
_is_in_array()
{
  # 第1引数が指定文字列、第2引数が配列
  local word="${1}"
  shift
  local arr=("$@")

  local e
  for e in "${arr[@]}"; do
    if [[ "${e}" == "${word}" ]]; then
      return 0
    fi
  done

  return 1
}

# 配列から指定した要素を削除する
#
# 文字列と配列を引数に取り、文字列が配列要素に存在すれば配列から削除します。
# (引数で指定した配列を直接更新します)。
#
# 引数:
#  $1: r   文字列
#  $2: r/w 配列
# 戻り値:
#  常に0
_remove_elements_from_array()
{
  local e="$1"
  # shellcheck disable=SC2178
  local -n arr="$2"

  local -i i
  local -i length
  length="${#arr[@]}"
  for ((i = length - 1; i >= 0; i--)); do
    if [[ "${arr[${i}]}" == "${e}" ]]; then
      unset "arr[${i}]"
    fi
  done
}

# クエリオプション/JSON属性の一覧からすでにユーザーが指定しオプション/属性を除去
#
# クエリオプションまたはリクエストボディのJSONに設定する属性の一覧から、ユーザーが
# すでにコマンドラインで指定しているオプション/属性を除去します。
#
# 引数:
#  $1: r   クエリオプションのとき"-q"、パラメータのとき"-p"を指定します
#  $2: r/w 全オプション/クエリの配列を指定します。
# グローバル変数
#   COMP_WORDS r  ユーザー指定済みのオプション/属性を取得するのにCOMPWORDSを参照します。
# 戻り値:
#  常に0
_remove_specified_params()
{
  local pq="$1"
  local -n options="$2"

  local -i i
  local word next
  local -i length="${#COMP_WORDS[@]}"
  for ((i = 4; i < length; i++)); do
    word="${COMP_WORDS[${i}]}"
    if [[ "${word}" == "${pq}" ]]; then
      i+=1
      next="${COMP_WORDS[${i}]}"
      if [[ -n "${next}" ]]; then
        _remove_elements_from_array "${next}" options
      fi
    fi
  done
}

_autogen()
{
  # 引数
  local char_length="${1:-8}"
  local num_length="${2:-3}"

  # 文字列部分
  local chars=( {a..z} )
  local char_part=""
  for (( i=0; i<$char_length; i++ )); do
      char_part+="${chars[$RANDOM % ${#chars[@]}]}"
  done

  # 数字部分
  local nums=( {0..9} )
  local num_part=""
  for (( i=0; i<$num_length; i++ )); do
      num_part+="${nums[$RANDOM % ${#nums[@]}]}"
  done

  echo "${char_part}${num_part}"
  #local data_type={$1:-id}
  #case "${data_type}" in
  #id)

}

_dx()
{
  local options=(
    "-p" "-q" "-s" "-k"
  )
  local long_options=(
    "--request-body-json"
    "--request-body-parameter"
  )
  local method=("get" "post" "put" "delete")
  local svc=("forms" "accounts")
  # local accounts_resource=("users" "systemroles" "userroles")
  # local accounts_users_q=("q1" "q2")
  # local accounts_systemroles=("q3" "q4")

  # shellcheck disable=SC2089
  local resources='
    {
      "accounts": {
        "systemroles": {
          "get": {},
          "post": {}
        },
        "users": {
          "get": {
            "q": {
              "q1": {
                "required": "true",
                "default": "a",
                "candidates": ["a", "b", "c"]
              },
              "q2": "yes no",
              "q3": "yes no"
            }
          },
          "post": {
            "q": {
              "q3": "",
              "q4": ""
            },
            "p": {
              "id": "",
              "loginId": "",
              "name": "",
              "password": ""
            }
          },
          "user": {
            "put": {},
            "delete": {}
          }
        }
      },
      "forms": {
        "formapps": {
          "get": {},
          "post": {}
        },
        "formappmembers": {
          "get": {},
          "post": {}
        }
      }
    }
  '

  local cur prev cword
  _get_comp_words_by_ref -n : cur prev cword

  local s m r
  local rscs
  local opts
  case "${prev}" in
    dx)
      # shellcheck disable=SC2207
      COMPREPLY=($(compgen -W "${method[*]}" -- "${cur}"))
      ;;
    get | post | put | delete)
      # shellcheck disable=SC2207
      COMPREPLY=($(compgen -W "${svc[*]}" -- "${cur}"))
      ;;
    *)
      # ここに来るのはパス以降のときだけ。でなければ打ち間違い。
      if [[ cword -lt 3 ]]; then
        return
      fi

      # メソッドを取得
      m="${COMP_WORDS[1]}"
      if ! _is_in_array "${m}" "${method[@]}"; then
        return
      fi

      # サービス名を取得
      s="${COMP_WORDS[2]}"
      if ! _is_in_array "${s}" "${svc[@]}"; then
        return
      fi

      # 3番目の引数ならリソース名を返す
      if ((cword == 3)); then
        rscs=$(echo "${resources}" | jq -r '.'"${s}"' | keys | join(" ")')
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "${rscs}" -- "${cur}"))
        return
      fi

      # リソース名を取得
      r="${COMP_WORDS[3]}"

      #
      # 4番目以降はオプション指定
      #

      # 入力なしまたは"-"までのときは全オプションを出力
      if [[ -z "${cur}" || "${cur}" == "-" ]]; then
        opts=("${options[@]}" "${long_options[@]}")
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "${opts[*]}" -- "${cur}"))
      fi

      # "-q" のときはクエリオプションを出力
      if [[ "${prev}" == "-q" ]]; then
        # 対象リソースの全クエリオプションを取得
        local query_options_full
        query_options_full=$(echo "${resources}" | jq -r '.'"${s}.${r}.${m}.q"' | keys | join(" ")')

        # 既に指定済みのクエリオプションは除外
        local query_options_filtered
        read -a query_options_filtered <<< "${query_options_full}"
        _remove_specified_params "-q" query_options_filtered

        # 候補に設定
        # shellcheck disable=SC2207
        COMPREPLY=($(compgen -W "${query_options_filtered[*]}" -- "${cur}"))
      fi

      # TODO: "-p" のときはリクエストボディパラメータを出力

      #echo "COMP_WORD=${COMP_WORD}"
      #for ((i = 0; i < cword; i++)); do
      #  echo "COMP_WORDS["${i}"]=${COMP_WORDS[i]}"
      #done
      ;;
  esac
}

complete -F _dx dx

