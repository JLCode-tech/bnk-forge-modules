#!/usr/bin/env python3
"""Validate every bnkforge.pack.json against forge's contract.

Vendored from bnk-forge-v2/backend/services/module_metadata.py
(ModuleMetadataValidator.validate_pack_manifest) — keep in sync. If you change
rules here, update the forge validator (or vice-versa) and bump
SCHEMA_FINGERPRINT below.

Scope note: forge's catalog sync only validates bnkforge.pack.json. module.json
files are read for description/dependencies but never validated against a
schema, so this CI gate intentionally mirrors that boundary. The release
manifest's stricter module.json contract is covered separately by
scripts/validate_module_metadata.py.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
PACK_MANIFEST_FILENAME = "bnkforge.pack.json"

SCHEMA_FINGERPRINT = "v1.2026-04-29"

VALID_INPUT_SOURCES = ["user", "module", "auto"]

VALID_PACK_ENGINES = ["opentofu", "kubernetes", "ansible", "script"]
VALID_TEMPLATE_ENGINES = ["simple", "jinja2"]
VALID_PACK_CATEGORIES = ["infra", "k8s", "bnk", "app", "other"]
VALID_RUNNER_PROFILES_BY_ENGINE = {
    "opentofu": ["opentofu-default"],
    "kubernetes": ["kubernetes-default"],
    "ansible": ["ansible-default"],
    "script": ["script-restricted"],
}
REQUIRED_PACK_LIFECYCLE_FIELDS = [
    "supports_init",
    "supports_plan",
    "supports_apply",
    "supports_destroy",
    "supports_refresh",
    "supports_drift",
]

DISALLOWED_SECRET_KEYS = [
    "value", "secret", "secret_value", "token", "password", "private_key", "key_material",
]

MAX_OUTPUT_VALUE_DEPTH = 6


def _is_non_empty_string(value: object) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_pack_manifest(manifest: dict, source: str) -> list[str]:
    errors: list[str] = []

    for field in ("schema_version", "module", "deployment_pack", "inputs", "outputs"):
        if field not in manifest:
            errors.append(f"{source}: missing required top-level field '{field}'")

    if errors:
        return errors

    if manifest.get("schema_version") != 1:
        errors.append(
            f"{source}: invalid schema_version {manifest.get('schema_version')!r}; must be 1"
        )

    errors.extend(_validate_pack_module_section(manifest.get("module"), source))
    errors.extend(_validate_pack_deployment_pack(manifest.get("deployment_pack"), source))
    errors.extend(_validate_pack_dependencies(manifest.get("dependencies"), source))
    errors.extend(_validate_pack_inputs(manifest.get("inputs"), source))
    errors.extend(_validate_pack_outputs(manifest.get("outputs"), source))
    errors.extend(_validate_secret_safety(manifest, source))

    return errors


def _validate_pack_module_section(module: object, source: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(module, dict):
        return [f"{source}: 'module' must be an object"]

    for field in ("name", "path", "version", "category", "description"):
        if not _is_non_empty_string(module.get(field)):
            errors.append(f"{source}: missing or invalid required field 'module.{field}'")

    category = module.get("category")
    if category not in VALID_PACK_CATEGORIES:
        errors.append(
            f"{source}: invalid module.category {category!r}; "
            f"must be one of: {', '.join(VALID_PACK_CATEGORIES)}"
        )

    return errors


def _validate_pack_deployment_pack(deployment_pack: object, source: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(deployment_pack, dict):
        return [f"{source}: 'deployment_pack' must be an object"]

    engine = deployment_pack.get("engine")
    if engine not in VALID_PACK_ENGINES:
        errors.append(
            f"{source}: invalid deployment_pack.engine {engine!r}; "
            f"must be one of: {', '.join(VALID_PACK_ENGINES)}"
        )

    template_engine = deployment_pack.get("template_engine")
    if template_engine is not None:
        if engine != "kubernetes":
            errors.append(
                f"{source}: deployment_pack.template_engine is only valid when engine is 'kubernetes'"
            )
        elif template_engine not in VALID_TEMPLATE_ENGINES:
            errors.append(
                f"{source}: invalid deployment_pack.template_engine {template_engine!r}; "
                f"must be one of: {', '.join(VALID_TEMPLATE_ENGINES)}"
            )

    runner_profile = deployment_pack.get("runner_profile")
    allowed = VALID_RUNNER_PROFILES_BY_ENGINE.get(engine or "", [])
    if runner_profile not in allowed:
        errors.append(
            f"{source}: invalid deployment_pack.runner_profile {runner_profile!r} for engine {engine!r}; "
            f"allowed: {', '.join(allowed) if allowed else '(none)'}"
        )

    if not _is_non_empty_string(deployment_pack.get("working_directory")):
        errors.append(f"{source}: missing or invalid required field 'deployment_pack.working_directory'")

    lifecycle = deployment_pack.get("lifecycle")
    if not isinstance(lifecycle, dict):
        errors.append(f"{source}: 'deployment_pack.lifecycle' must be an object")
    else:
        for field in REQUIRED_PACK_LIFECYCLE_FIELDS:
            if field not in lifecycle:
                errors.append(f"{source}: missing required field 'deployment_pack.lifecycle.{field}'")
            elif not isinstance(lifecycle[field], bool):
                errors.append(f"{source}: 'deployment_pack.lifecycle.{field}' must be a boolean")
        if lifecycle.get("supports_apply") is not True:
            errors.append(f"{source}: 'deployment_pack.lifecycle.supports_apply' must be true")

    entrypoints = deployment_pack.get("entrypoints")
    if not isinstance(entrypoints, dict):
        errors.append(f"{source}: 'deployment_pack.entrypoints' must be an object")
    else:
        errors.extend(_validate_engine_entrypoints(engine, entrypoints, source))

    return errors


def _validate_engine_entrypoints(engine: object, entrypoints: dict, source: str) -> list[str]:
    if engine == "opentofu":
        if not _is_non_empty_string(entrypoints.get("module_root")):
            return [f"{source}: missing or invalid required field 'deployment_pack.entrypoints.module_root'"]
        return []

    if engine == "kubernetes":
        candidates = ("manifest_path", "chart_path", "chart_ref")
        if not any(_is_non_empty_string(entrypoints.get(field)) for field in candidates):
            return [
                f"{source}: deployment_pack.entrypoints requires at least one of "
                "'manifest_path', 'chart_path', or 'chart_ref' for kubernetes"
            ]
        return []

    if engine == "ansible":
        if not _is_non_empty_string(entrypoints.get("playbook")):
            return [f"{source}: missing or invalid required field 'deployment_pack.entrypoints.playbook'"]
        return []

    if engine == "script":
        errors = []
        if not _is_non_empty_string(entrypoints.get("apply_script")):
            errors.append(f"{source}: missing or invalid required field 'deployment_pack.entrypoints.apply_script'")
        if not _is_non_empty_string(entrypoints.get("outputs_file")):
            errors.append(f"{source}: missing or invalid required field 'deployment_pack.entrypoints.outputs_file'")
        return errors

    return []


def _validate_pack_dependencies(dependencies: object, source: str) -> list[str]:
    errors: list[str] = []
    if dependencies is None:
        return errors
    if not isinstance(dependencies, dict):
        return [f"{source}: 'dependencies' must be an object"]

    required = dependencies.get("required", [])
    optional = dependencies.get("optional", [])

    if not isinstance(required, list):
        errors.append(f"{source}: 'dependencies.required' must be a list")
    else:
        for dep in required:
            if not isinstance(dep, dict):
                errors.append(f"{source}: each required dependency must be an object")
                continue
            if not _is_non_empty_string(dep.get("module")):
                errors.append(f"{source}: required dependency missing 'module' field")
            if not _is_non_empty_string(dep.get("reason")):
                errors.append(f"{source}: required dependency missing 'reason' field")

    if not isinstance(optional, list):
        errors.append(f"{source}: 'dependencies.optional' must be a list")
    else:
        for dep in optional:
            if not isinstance(dep, dict):
                errors.append(f"{source}: each optional dependency must be an object")
                continue
            if not _is_non_empty_string(dep.get("module")):
                errors.append(f"{source}: optional dependency missing 'module' field")

    return errors


def _validate_pack_inputs(inputs: object, source: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(inputs, dict):
        return [f"{source}: 'inputs' must be an object"]

    for group in ("required", "optional"):
        entries = inputs.get(group, [])
        if not isinstance(entries, list):
            errors.append(f"{source}: 'inputs.{group}' must be a list")
            continue
        for inp in entries:
            if not isinstance(inp, dict):
                errors.append(f"{source}: each {group} input must be an object")
                continue
            errors.extend(_validate_input_entry(inp, group, source))

    return errors


def _validate_input_entry(inp: dict, group: str, source: str) -> list[str]:
    errors: list[str] = []
    for field in ("name", "type", "description", "source"):
        if field not in inp:
            errors.append(f"{source}: {group} input missing '{field}' field")
    src = inp.get("source")
    if src is not None and src not in VALID_INPUT_SOURCES:
        errors.append(
            f"{source}: invalid input source {src!r}; must be one of: {', '.join(VALID_INPUT_SOURCES)}"
        )
    if src == "module":
        if "from_module" not in inp:
            errors.append(f"{source}: input with source='module' must have 'from_module' field")
        if "from_output" not in inp:
            errors.append(f"{source}: input with source='module' must have 'from_output' field")
    return errors


def _validate_pack_outputs(outputs: object, source: str) -> list[str]:
    errors: list[str] = []
    if not isinstance(outputs, dict):
        return [f"{source}: 'outputs' must be an object"]

    key_outputs = outputs.get("key_outputs", [])
    if not isinstance(key_outputs, list):
        return [f"{source}: 'outputs.key_outputs' must be a list"]

    for out in key_outputs:
        if not isinstance(out, dict):
            errors.append(f"{source}: each output in outputs.key_outputs must be an object")
            continue
        for field in ("name", "type", "description"):
            if not _is_non_empty_string(out.get(field)):
                errors.append(f"{source}: output missing '{field}' field")
        if "value" in out:
            errors.extend(
                _validate_output_value(
                    out["value"],
                    path=f"outputs.key_outputs[{out.get('name', '?')}].value",
                    source=source,
                )
            )

    return errors


def _validate_output_value(value: object, *, path: str, source: str, depth: int = 0) -> list[str]:
    if depth > MAX_OUTPUT_VALUE_DEPTH:
        return [f"{source}: {path} nesting is too deep (max depth {MAX_OUTPUT_VALUE_DEPTH})"]
    if value is None or isinstance(value, (str, int, float, bool)):
        return []
    if isinstance(value, list):
        errors: list[str] = []
        for idx, item in enumerate(value):
            errors.extend(_validate_output_value(item, path=f"{path}[{idx}]", source=source, depth=depth + 1))
        return errors
    if isinstance(value, dict):
        errors = []
        for key, item in value.items():
            if not isinstance(key, str):
                errors.append(f"{source}: {path} object keys must be strings")
            errors.extend(_validate_output_value(item, path=f"{path}.{key}", source=source, depth=depth + 1))
        return errors
    return [f"{source}: {path} must be JSON-compatible (string/number/boolean/null/object/array)"]


def _validate_secret_safety(manifest: dict, source: str) -> list[str]:
    errors: list[str] = []

    inputs = manifest.get("inputs", {})
    input_groups = []
    if isinstance(inputs, dict):
        input_groups.extend(inputs.get("required", []) or [])
        input_groups.extend(inputs.get("optional", []) or [])

    for inp in input_groups:
        if not isinstance(inp, dict):
            continue
        if inp.get("sensitive") is True and _is_non_empty_string(inp.get("default")):
            errors.append(
                f"{source}: sensitive input {inp.get('name', '<unknown>')!r} must not include an inline default value"
            )

    credentials = manifest.get("credentials")
    if credentials is None:
        return errors
    if not isinstance(credentials, dict):
        return errors + [f"{source}: 'credentials' must be an object"]

    for group_name in ("required", "optional"):
        entries = credentials.get(group_name, [])
        if not isinstance(entries, list):
            errors.append(f"{source}: 'credentials.{group_name}' must be a list")
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                errors.append(f"{source}: each credentials entry in '{group_name}' must be an object")
                continue
            for required_field in ("name", "type", "description"):
                if not _is_non_empty_string(entry.get(required_field)):
                    errors.append(
                        f"{source}: credential entry in '{group_name}' missing '{required_field}'"
                    )
            for key in DISALLOWED_SECRET_KEYS:
                if key in entry and _is_non_empty_string(entry.get(key)):
                    errors.append(
                        f"{source}: credentials.{group_name} entry must not contain raw secret field {key!r}"
                    )

    return errors


def _load_json(path: Path) -> tuple[dict | None, str | None]:
    try:
        with path.open("r", encoding="utf-8") as fp:
            return json.load(fp), None
    except FileNotFoundError:
        return None, f"file not found: {path}"
    except json.JSONDecodeError as exc:
        return None, f"invalid JSON in {path}: {exc}"


def main() -> int:
    pack_files = sorted(p for p in REPO_ROOT.rglob(PACK_MANIFEST_FILENAME) if ".git" not in p.parts)

    all_errors: list[str] = []

    for path in pack_files:
        rel = path.relative_to(REPO_ROOT)
        manifest, load_err = _load_json(path)
        if load_err:
            all_errors.append(f"{rel}: {load_err}")
            continue
        all_errors.extend(validate_pack_manifest(manifest, str(rel)))

    if all_errors:
        for err in all_errors:
            print(f"ERROR: {err}")
        print(f"\nFAILED: {len(all_errors)} error(s) across {len(pack_files)} pack manifest(s)")
        return 1

    print(
        f"OK: {len(pack_files)} pack manifest(s) pass forge-aligned schema "
        f"(fingerprint {SCHEMA_FINGERPRINT})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
