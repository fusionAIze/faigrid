# Executor Contract

version: v1

## Purpose

The faigrid Workbench ships 25 plugin scripts under
`core/workbench/scripts/plugins/`, each of which manages a single external
tool (a CLI, an agent, a router, a proxy, a memory service, etc.). The
Executor Contract defines the **versioned, observable interface** each plugin
implements so that the future Python control plane can treat every plugin as a
replaceable executor: discover it, read its metadata, invoke its lifecycle
verbs, and observe its result — without knowing anything tool-specific.

A plugin **conforms to this contract at version `v1`** when it satisfies the
checklist in [Conformance](#conformance). The contract version is the single
source of truth; the control plane negotiates on it, not on plugin names.

## Plugin anatomy

A plugin is a standalone, `source`-able bash file. It MUST NOT be executed
directly; the Workbench (and the future control plane) sources it in an
isolated subshell and then invokes the functions it defines.

- Plugins are sourced **in isolation**. They cannot rely on `_lib.sh` being
  loaded unless `control.sh` explicitly sources it first (it does so for
  `tool_configure` and `tool_doctor`; other verbs run in a bare subshell).
- Section 1 of the file declares **metadata as POSIX `VAR=value` assignments**
  (the `TOOL_*` block). The control plane reads these with `grep`, never by
  sourcing — so secrets are never exposed and untrusted code is not executed
  for discovery.
- Section 2 defines the **lifecycle functions** (`tool_*`).

### Metadata (`TOOL_*`)

Each plugin MUST declare at minimum:

| Variable            | Required | Values                                         |
| ------------------- | -------- | ---------------------------------------------- |
| `TOOL_NAME`         | yes      | registry name, lowercase, `[a-z0-9_-]+`        |
| `TOOL_CATEGORY`     | yes      | `clis`, `routers`, `memory`, `agents`, `automation`, `wrappers`, `monitoring`, `proxy`, `comms` |
| `TOOL_DESC`         | yes      | short human-readable description               |
| `TOOL_TYPE`         | yes      | `npm`, `apt`, `dnf`, `pipx`, `git`, `binary`, `docker`, `systemd`, `tbd` |

Optional metadata:

| Variable            | Meaning                                              |
| ------------------- | ---------------------------------------------------- |
| `TOOL_MANAGED`      | `"auto"` hides the plugin from install/boost/update  |
| `TOOL_DEPS`         | space-separated `TOOL_NAME`s installed first         |
| `TOOL_UPDATE_TYPE`  | `npm` / `git` / `github` — selects update check      |
| `TOOL_UPDATE_PKG`   | npm package name when `TOOL_UPDATE_TYPE="npm"`        |
| `TOOL_UPDATE_REPO`  | `owner/repo` when `TOOL_UPDATE_TYPE="github"`         |

The reference template `core/workbench/scripts/plugins/_template.sh` documents
every field inline.

## Entrypoint convention

The interface uses the `tool_*` function convention — **not** `cmd_*`, not a
single `main`, not sourced helpers. The observed, canonical entrypoints in the
repository are:

| Verb (contract)        | Actual function in repo | Semantics                                             |
| ---------------------- | ----------------------- | ----------------------------------------------------- |
| `tool_install`        | `tool_install`          | install the tool (idempotent)                        |
| `configure`           | `tool_configure`        | interactive configuration (optional)                 |
| `doctor`              | `tool_doctor`           | health / validation probe (optional)                 |
| `update`              | `tool_update`           | update/uninstall-state upgrade to latest              |
| *(install-state)*     | `tool_status`           | report installed version / state (REQUIRED)          |
| *(remove)*            | `tool_uninstall`        | remove the tool                                      |

The mapping above is the contract's four canonical lifecycle verbs plus the
two supporting verbs that exist in the codebase. The contract names verbs by
their **actual in-repo function names**, so there is no invented naming.

Each function:
- returns `0` on success, non-zero on failure,
- has no positional-argument convention, but MUST NOT require arguments,
- prints human-readable progress to stdout using the `_lib.sh` helpers
  (`info`, `success`, `warn`, `error`) when they are available, and MUST NOT
  print secrets.

### `tool_status` — the required observable verb

`tool_status()` is the single REQUIRED function in every plugin. It MUST print
**exactly the string `Not installed`** when the tool is absent; the registry
uses that literal to determine install state. When present it prints a
human-readable install string, conventionally `Installed` with an optional
version suffix:

```
Not installed
Installed
Installed (v1.2.3)
Installed (Running v2.7.5)
```

## Structured JSON status output

For the control plane, human-readable `tool_status` output is insufficient.
Each plugin SHOULD additionally emit a single-line **structured JSON status**
object on stdout on completion of any lifecycle verb. `tool_status` is the
primary emitter; other verbs SHOULD emit it on their final line when they
terminate cleanly.

The JSON object has this schema (all fields required; `data` MAY be `{}`):

```json
{
  "status": "ok",
  "plugin": "opencode",
  "verb": "status",
  "message": "Installed (v1.2.3)",
  "version": "1.2.3",
  "data": {}
}
```

### Field definitions

| Field     | Type   | Required | Description                                              |
| --------- | ------ | -------- | -------------------------------------------------------- |
| `status`  | string | yes      | `"ok"` or `"error"`                                     |
| `plugin`  | string | yes      | equals the plugin's `TOOL_NAME`                         |
| `verb`    | string | yes      | the lifecycle verb: `install`, `configure`, `doctor`, `update`, `status`, `uninstall` |
| `message` | string | yes      | human-readable result, JSON-escaped                     |
| `version` | string | no       | installed/tool version when known, else `null`          |
| `data`    | object | yes      | verb-specific payload, `{}` when not applicable         |

A conformant plugin prints this object as its **final** stdout line when the
verb completes, so a consumer may parse the last line:

```json
{"status":"error","plugin":"caddy","verb":"install","message":"no edge node registered","version":null,"data":{}}
```

The object MUST be valid JSON on a single line (JSON-escape `"`, `\`, and
control characters, as `_lib.sh`'s `log_event` does). A plugin is not required
to serialize with `jq`; a `printf` of a pre-escaped template is acceptable.

> Migration note (v1): the repository's 25 plugins today return
> human-readable `tool_status` strings, not structured JSON. The JSON status
> emitter is a **target** for new/changed plugins. The control plane MUST
> tolerate the absence of the JSON line and fall back to the
> `Not installed` / string convention above. This tolerance is what makes v1
> backward-compatible with the existing fleet.

## Lifecycle verbs

Four canonical verbs map to in-repo functions. Each is described with whether
it is required and what the JSON `verb` value is.

| Contract verb   | Function         | Required | JSON `verb`  |
| --------------- | ---------------- | -------- | ------------ |
| `tool_install`  | `tool_install`   | yes      | `install`    |
| `configure`     | `tool_configure` | no       | `configure`  |
| `doctor`        | `tool_doctor`    | no       | `doctor`     |
| `update`        | `tool_update`    | no       | `update`     |

Supporting verbs present in every conformant plugin:

| Function         | Required | JSON `verb` |
| ---------------- | -------- | ----------- |
| `tool_status`    | yes      | `status`    |
| `tool_uninstall` | yes      | `uninstall` |

### Invocation pattern

`control.sh` invokes a plugin in an isolated subshell:

```bash
( source "$plugin_file" && tool_install ) || warn "Failed to install $name"
```

Metadata discovery never sources the file:

```bash
grep -E "^TOOL_NAME=" "$plugin_file" | head -n1 | cut -d'"' -f2
```

A conformant control plane MUST follow this same split: **grep for metadata,
source for execution** — never the reverse.

## Conformance

### Checklist

A plugin conforms to the Executor Contract v1 when ALL of the following hold:

- [ ] Declares `TOOL_NAME`, `TOOL_CATEGORY`, `TOOL_DESC`, `TOOL_TYPE` at the top.
- [ ] Defines `tool_install()` and `tool_status()`.
- [ ] `tool_status()` prints the exact literal `Not installed` when absent.
- [ ] Defines `tool_uninstall()`.
- [ ] Optionally defines `tool_configure()`, `tool_doctor()`, `tool_update()`.
- [ ] Is `source`-able in isolation (does not depend on `_lib.sh` being loaded
      for `tool_install`/`tool_status`/`tool_uninstall`; copies any helpers it
      needs inline, per `_template.sh`).
- [ ] Returns `0`/non-zero from each function as defined above.
- [ ] (Target) Emits the structured JSON status object as its final stdout line.
- [ ] Never prints secrets.

### Mechanical conformance check

Because metadata is read with `grep`, a cheap conform sweep is:

```bash
for p in $(find core/workbench/scripts/plugins -mindepth 2 -name '*.sh' ! -name '_template.sh'); do
  missing=""
  for v in TOOL_NAME TOOL_CATEGORY TOOL_DESC TOOL_TYPE; do
    grep -qE "^${v}=" "$p" || missing="$missing $v"
  done
  for f in tool_install tool_status tool_uninstall; do
    grep -qE "^${f}\(\)" "$p" || missing="$missing ${f}()"
  done
  [ -n "$missing" ] && echo "NONCONFORMANT  ${p}:${missing}" || echo "ok  ${p}"
done
```

`shellcheck` over the plugin directory (via the repo's `.shellcheckrc`) flags
undefined-function and quoting issues but does not validate contract
semantics; it supplements, not replaces, the checklist.

## Repo references

- Template: `core/workbench/scripts/plugins/_template.sh`
- Dispatcher / plugin helpers: `core/workbench/scripts/control.sh`
  (`get_plugins`, `get_plugin_meta`, `_check_update`, and the `tool_*` call sites)
- Shared logging/JSON escaping: `core/workbench/scripts/_lib.sh` (`log_event`, `_json_escape`)
- Event log schema: `docs/reference/event-schema.md`
