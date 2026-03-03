# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`xapicli` is a bash-based CLI tool that converts OpenAPI 3.0 specs into an interactive command-line interface for making REST API calls, with bash tab-completion support.

## Development Environment Setup

**macOS:**
```bash
brew install gnu-getopt
export PATH="/usr/local/opt/gnu-getopt/bin:${PATH}"
```

**Required tools:** `bash`, `jq`, `getopt` (GNU version), `shfmt` (for formatting), `shellcheck` (for linting)

**Formatting:** Uses `shfmt` via the VSCode ShellFormat extension. Set `shellformat.path` in `.vscode/settings.json` to the `shfmt` binary path.

## Workflow: Adding an API

```bash
# 1. Install json-refs (resolves $ref references in OpenAPI specs)
npm install -g json-refs

# 2. Resolve all $refs in the OpenAPI spec
json-refs resolve examples/petstore-oas3.json > examples/petstore-oas3-resolved.json

# 3. Generate the internal API definition file
cat examples/petstore-oas3-resolved.json | jq -f install-api.jq > .xapicli/apis/petstore-oas3.json

# 4. Point xapicli at the config directory
export XAPICLI_CONF_DIR=${PWD}/.xapicli
```

## Architecture

The project has two main components:

### `xapicli.sh` (sourced, not executed)
The script is designed to be **sourced** (`source xapicli.sh`), not run directly. This is required for bash completion to register in the current shell.

- **`_xapicli_completion()`** — Bash completion handler registered via `complete -F`. Reads the API definition file and completes HTTP methods, resource paths, `-q` (query params), and `-p` (post params) based on context.
- **`xapicli()`** — Main CLI function. Parses args with GNU `getopt`, loads the API definition via `curl file://`, and executes the request. The curl execution is currently a stub (lines 288–295).

### `install-api.jq`
A jq filter that transforms a resolved OpenAPI 3.0 `paths` object into a flat JSON structure used at runtime:
```json
{
  "/pet": [
    {
      "method": "post",
      "query_parameters": [{"name": "status", "type": "string", "required": true}],
      "post_parameters": [{"name": "name", "type": "string", "required": true}]
    }
  ]
}
```
Only `application/json` request bodies are recognized. `$refs` must be pre-resolved before passing to this filter.

### Configuration (`.xapicli/xapicli.conf`)
```json
{
  "default": "petstore",
  "petstore": {
    "openapispec": "../examples/petstore-oas3.json",
    "apidef": "petstore-oas3.json",
    "url": "http://localhost/api/v3/"
  }
}
```
The `apidef` field points to the processed file under `.xapicli/apis/`. `XAPICLI_CONF_DIR` env var overrides the default `$HOME/.xapicli` location.

## CLI Usage

```bash
source xapicli.sh

xapicli <method> <resource> [options]
  -q <param> <value>   Query parameter (repeatable)
  -p <param> <value>   Post/body parameter (repeatable)
  --summary[=resource] Print available endpoints
  --summary-csv        Print endpoints in CSV format
  --help
```

## Known Limitations

- `$refs` in OpenAPI specs must be pre-resolved with `json-refs`
- Only `application/json` request bodies are supported
- `explode`, `enum`, and nested object parameters are not supported
- Actual HTTP request execution (curl call) is not yet implemented
