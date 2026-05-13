#!/usr/bin/env python3

from __future__ import annotations

import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RELEASE_MANIFEST = REPO_ROOT / "catalog" / "releases" / "release-2.2-official.json"
ALLOWED_DEPLOY_MODELS = {"terraform", "helm", "kubernetes_manifest", "shell"}
ALLOWED_INPUT_SOURCES = {"user", "module", "auto", "project_secret"}
ALLOWED_RELEASE_STATES = {"active", "legacy", "deprecated"}
OFFICIAL_FAMILIES = {"bnk", "k8s"}


def fail(message: str) -> None:
    print(f"ERROR: {message}")
    sys.exit(1)


def load_json(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as fp:
            return json.load(fp)
    except FileNotFoundError:
        fail(f"File not found: {path}")
    except json.JSONDecodeError as exc:
        fail(f"Invalid JSON in {path}: {exc}")


def validate_generic_module_contract(module_path: str, module_json: dict) -> list[str]:
    errors: list[str] = []

    source = module_json.get("source")
    if not isinstance(source, dict):
        errors.append(f"{module_path}: missing required object: source")
    else:
        if not isinstance(source.get("kind"), str) or not source.get("kind"):
            errors.append(f"{module_path}: source.kind must be a non-empty string")
        if not isinstance(source.get("channel"), str) or not source.get("channel"):
            errors.append(f"{module_path}: source.channel must be a non-empty string")

    execution = module_json.get("execution")
    if not isinstance(execution, dict):
        errors.append(f"{module_path}: missing required object: execution")
    else:
        engine = execution.get("engine")
        if not isinstance(engine, str) or not engine:
            errors.append(f"{module_path}: execution.engine must be a non-empty string")

        deploy_models = execution.get("deploy_models")
        if not isinstance(deploy_models, list) or not deploy_models:
            errors.append(f"{module_path}: execution.deploy_models must be a non-empty array")
        else:
            invalid = [model for model in deploy_models if model not in ALLOWED_DEPLOY_MODELS]
            if invalid:
                errors.append(f"{module_path}: invalid deploy model(s): {', '.join(invalid)}")

    contract = module_json.get("contract")
    if not isinstance(contract, dict):
        errors.append(f"{module_path}: missing required object: contract")
    else:
        metadata_version = contract.get("metadata_version")
        if not isinstance(metadata_version, str) or not metadata_version:
            errors.append(f"{module_path}: contract.metadata_version must be a non-empty string")

    inputs = module_json.get("inputs", {})
    all_inputs = []
    if isinstance(inputs, dict):
        for key in ("required", "optional"):
            entries = inputs.get(key, [])
            if isinstance(entries, list):
                all_inputs.extend(entries)

    for idx, input_entry in enumerate(all_inputs):
        if not isinstance(input_entry, dict):
            errors.append(f"{module_path}: inputs[{idx}] must be an object")
            continue
        input_source = input_entry.get("source")
        if input_source not in ALLOWED_INPUT_SOURCES:
            errors.append(
                f"{module_path}: input '{input_entry.get('name', '<unnamed>')}' has invalid source '{input_source}'. "
                f"Allowed: {sorted(ALLOWED_INPUT_SOURCES)}"
            )

    return errors


def validate_release_manifest(manifest: dict) -> list[str]:
    errors: list[str] = []

    if manifest.get("schema_version") != "catalog-release/v1alpha2":
        errors.append("release manifest schema_version must be catalog-release/v1alpha2")

    release = manifest.get("release", {})
    if release.get("channel") != "release/2.2":
        errors.append("release.channel must be release/2.2")
    if release.get("source_kind") != "official":
        errors.append("release.source_kind must be official")
    if release.get("execution_engine") != "opentofu":
        errors.append("release.execution_engine must be opentofu")

    if manifest.get("contract", {}).get("metadata_version") != "module-metadata/v2alpha1":
        errors.append("contract.metadata_version must be module-metadata/v2alpha1")

    official_modules = manifest.get("official_modules")
    if not isinstance(official_modules, list) or not official_modules:
        errors.append("official_modules must be a non-empty array")

    return errors


def validate_release_module_entry(entry: dict, module_json: dict, manifest: dict) -> list[str]:
    errors: list[str] = []
    module_path = entry.get("path", "<unknown>")

    state = entry.get("state")
    if state not in ALLOWED_RELEASE_STATES:
        errors.append(f"{module_path}: state must be one of {sorted(ALLOWED_RELEASE_STATES)}")
        return errors

    if state in {"legacy", "deprecated"}:
        reason = entry.get("reason")
        if not isinstance(reason, str) or not reason.strip():
            errors.append(f"{module_path}: state={state} requires non-empty reason")
        return errors

    source = module_json.get("source", {})
    release = manifest.get("release", {})
    if source.get("kind") != release.get("source_kind"):
        errors.append(f"{module_path}: source.kind must match release.source_kind ({release.get('source_kind')})")
    if source.get("channel") != release.get("channel"):
        errors.append(f"{module_path}: source.channel must match release.channel ({release.get('channel')})")

    execution = module_json.get("execution", {})
    entry_engine = entry.get("execution", {}).get("engine")
    expected_engine = entry_engine if entry_engine else release.get("execution_engine")
    if execution.get("engine") != expected_engine:
        errors.append(
            f"{module_path}: execution.engine must match expected ({expected_engine})"
        )

    expected_deploy_models = entry.get("execution", {}).get("deploy_models")
    if not isinstance(expected_deploy_models, list) or not expected_deploy_models:
        errors.append(f"{module_path}: active module requires execution.deploy_models in release manifest")
        return errors

    deploy_models = execution.get("deploy_models")
    if deploy_models != expected_deploy_models:
        errors.append(
            f"{module_path}: execution.deploy_models mismatch; expected {expected_deploy_models}, got {deploy_models}"
        )

    contract = module_json.get("contract", {})
    expected_metadata_version = manifest.get("contract", {}).get("metadata_version")
    if contract.get("metadata_version") != expected_metadata_version:
        errors.append(
            f"{module_path}: contract.metadata_version must match release contract ({expected_metadata_version})"
        )

    return errors


def main() -> None:
    manifest = load_json(RELEASE_MANIFEST)
    errors = validate_release_manifest(manifest)

    entries = manifest.get("official_modules", [])
    seen_paths: set[str] = set()

    for entry in entries:
        module_path = entry.get("path")
        if not module_path:
            errors.append("official_modules entry missing path")
            continue
        if module_path in seen_paths:
            errors.append(f"duplicate official_modules path: {module_path}")
            continue
        seen_paths.add(module_path)

        metadata_path = REPO_ROOT / module_path / "module.json"
        module_json = load_json(metadata_path)

        state = entry.get("state")
        if state == "active":
            errors.extend(validate_generic_module_contract(module_path, module_json))

        errors.extend(validate_release_module_entry(entry, module_json, manifest))

    discovered_official_paths: set[str] = set()
    for family in OFFICIAL_FAMILIES:
        family_root = REPO_ROOT / family
        if not family_root.exists():
            continue
        for module_file in family_root.rglob("module.json"):
            discovered_official_paths.add(str(module_file.parent.relative_to(REPO_ROOT)))

    missing_from_manifest = sorted(discovered_official_paths - seen_paths)
    if missing_from_manifest:
        errors.append(
            "release manifest must explicitly classify every bnk/ and k8s/ module. Missing entries: "
            + ", ".join(missing_from_manifest)
        )

    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        sys.exit(1)

    print("OK: generic module contract validation passed for active official modules")
    print("OK: release baseline assertions passed (release/2.2 official catalog manifest)")


if __name__ == "__main__":
    main()
