 xapicli - A Command Line Interface for every Restful API

## dev environment

* This repo uses the `ShellFormat` VSCode extension, which needs `shfmt` to be installed on your PC. So, install `shfmt` and set `shellformat.path` in `.vscode/settings.json` to the path of it. 

## how to use


```
# install json-refs
npm install -g json-refs
json-refs resolve examples/petstore-oas3.json > examples/petstore-oas3-resolved.json 

# create API def file from OAS
cat examples/petstore-oas3-resolved.json | jq -f install-api.jq > .xapicli/apis/petstore-oas3.json

# set xapicli configuration directory ($HOME by default)
export XAPICLI_CONF_DIR=${PWD}/.xapicli

```

If you are on a Mac, do below

```
# install GNU getopt
brew install gnu-getopt

# add `getopt` path to your PATH
export PATH="/usr/local/opt/gnu-getopt/bin:${PATH}"
```

### Supported OpenAPI format

`xapicli` only uses part of request definition. It ignores the rest of part, for example, response and security. It also recognizes part of specification even in the request definition. For example, It only recognizes `application/json` part of requests, igores other types of content like `application/xml`.

* list of unsupported tags (imperfect)
* `$refs` is unsupported. If your OpenAPI spec file contains `$refs` in it, first resolve them using [`json-refs`](https://www.npmjs.com/package/json-refs).
* `explode`


## Todo's

* HTTPメソッドに合致したリソースだけ候補に追加する
* `-`を
* short/longオプションをコマンド補完に追加
* `-p`と`-q`の必須に`*`をつける
* 実行系
* enum対応
* object対応
* `summary` に description を追加
* 全体的にリファクタリング
* Unit Test
* ShellDoc
