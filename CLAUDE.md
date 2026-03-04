# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`xapicli` is a bash-based CLI tool that converts OpenAPI 3.0 specs into an interactive command-line interface for making REST API calls, with bash tab-completion support.

## Development Environment Setup

**macOS (Apple Silicon):**
```bash
brew install gnu-getopt
export PATH="/opt/homebrew/opt/gnu-getopt/bin:${PATH}"
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

- **`_xapicli_completion()`** — Bash completion handler registered via `complete -F`. Completes:
  - HTTP methods after `xapicli`
  - Resource paths filtered by the selected method
  - Options (`-q`, `-p`, `-d`, `--summary`, `--help`) after a resource path, based on what the endpoint supports
  - Query/post parameter names after `-q`/`-p`
  - Enum values after a parameter name (when the parameter has an `enum` constraint)
- **`xapicli()`** — Main CLI function. Parses args with GNU `getopt`, loads the API definition, and executes HTTP requests via `curl`. Supports GET, POST, PUT, DELETE. POST/PUT bodies are assembled from `-p` flags or passed raw via `-d`. Path parameters (e.g., `/pet/99`) are matched to templates (e.g., `/pet/{petId}`) via jq regex.

### `install-api.jq`
A jq filter that transforms a resolved OpenAPI 3.0 `paths` object into a flat JSON structure used at runtime:
```json
{
  "/pet": [
    {
      "method": "post",
      "query_parameters": [{"name": "status", "type": "string", "required": false, "enum": ["available", "pending", "sold"]}],
      "post_parameters": [
        {"name": "name", "type": "string", "required": true},
        {"name": "photoUrls", "type": "array", "items": {"type": "string"}, "required": true},
        {"name": "category.id", "type": "integer"},
        {"name": "category.name", "type": "string"}
      ]
    }
  ]
}
```
Key transformation rules:
- Only `application/json` request bodies are recognized
- `$refs` must be pre-resolved before passing to this filter
- `query_parameters`: includes `enum` field for tab completion
- `post_parameters`: object-type properties are flattened one level into dot-notation entries (e.g., `category` → `category.id`, `category.name`); array-type properties with scalar items are included with `type: "array"`
- Required parameters are marked with `required: true`

### Configuration (`.xapicli/xapicli.conf`)
```json
{
  "default": "petstore",
  "petstore": {
    "openapispec": "../examples/petstore-oas3.json",
    "apidef": "petstore-oas3.json",
    "url": "http://localhost:8080/api/v3/"
  }
}
```
The `apidef` field points to the processed file under `.xapicli/apis/`. `XAPICLI_CONF_DIR` env var overrides the default `$HOME/.xapicli` location.

## CLI Usage

```bash
source xapicli.sh

xapicli <method> <resource> [options]
  -q <name> <value>      Query parameter (repeatable)
  -p <name> <value>      Body parameter (repeatable); builds a JSON object
                           Repeat the same name for array params: -p tags a -p tags b → {"tags":["a","b"]}
                           Use dot notation for object params: -p category.id 1 → {"category":{"id":"1"}}
  -d <json>              Raw JSON body (overrides -p)
  --summary[=resource]   Print available endpoints; required params marked *, array params marked []
  --summary-csv          Print endpoints in CSV format
  --help
```

## Known Limitations

- `$refs` in OpenAPI specs must be pre-resolved with `json-refs`
- Only `application/json` request bodies are supported
- Array parameters are supported only when items are scalar types; arrays of objects are not supported
- Object parameters are supported one level deep via dot notation; deeper nesting is not supported
- `explode` is not supported
- Authentication headers must be added manually (not supported natively)
