#!/usr/bin/env python3
"""Small stdin/stdout adapter between Quickshell and NetworkManager.

One JSON request is read from stdin and one JSON result is written to stdout.
Secrets are passed to nmcli through passwd-file on stdin so they never appear
in a command line.
"""

import json
import os
import subprocess
import sys


NMCLI = "/usr/bin/nmcli"


class WifiError(Exception):
    pass


def run_nmcli(args, *, secret_lines=None, timeout=45):
    env = os.environ.copy()
    env["LC_ALL"] = "C"
    try:
        result = subprocess.run(
            [NMCLI, *args],
            input="" if secret_lines is None else "\n".join(secret_lines) + "\n",
            text=True,
            capture_output=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        raise WifiError("NetworkManager did not respond before the timeout") from error

    if result.returncode != 0:
        message = (result.stderr or result.stdout).strip()
        raise WifiError(message or f"nmcli exited with status {result.returncode}")
    return result.stdout.strip()


def clean(value, name, *, required=False):
    value = str(value or "").strip()
    if "\n" in value or "\r" in value:
        raise WifiError(f"{name} cannot contain a line break")
    if required and not value:
        raise WifiError(f"{name} is required")
    return value


def find_or_create_profile(request, *, hidden):
    ssid = clean(request.get("ssid"), "Network name", required=True)
    requested_uuid = clean(request.get("uuid"), "Profile UUID")
    if requested_uuid:
        run_nmcli(["connection", "show", "uuid", requested_uuid])
        return requested_uuid, False

    profile_id = f"Quickshell · {ssid}"
    lookup = subprocess.run(
        [NMCLI, "-g", "UUID", "connection", "show", "id", profile_id],
        text=True,
        capture_output=True,
        env={**os.environ, "LC_ALL": "C"},
        check=False,
    )
    if lookup.returncode == 0 and lookup.stdout.strip():
        return lookup.stdout.splitlines()[0].strip(), False

    command = ["connection", "add", "type", "wifi", "con-name", profile_id, "ssid", ssid]
    interface = clean(request.get("interface"), "Interface")
    if interface:
        command.extend(["ifname", interface])
    run_nmcli(command)
    profile_uuid = run_nmcli(["-g", "UUID", "connection", "show", "id", profile_id]).splitlines()[0]
    run_nmcli([
        "connection", "modify", "uuid", profile_uuid,
        "wifi.hidden", "yes" if hidden else "no",
        "ipv4.method", "auto",
        "ipv6.method", "auto",
    ])
    return profile_uuid, True


def activate_personal(request, *, hidden):
    password = clean(request.get("password"), "Password", required=True)
    key_mgmt = clean(request.get("keyMgmt"), "Key management") or "wpa-psk"
    if key_mgmt not in {"wpa-psk", "sae"}:
        raise WifiError("Unsupported personal Wi-Fi security mode")
    profile_uuid, _ = find_or_create_profile(request, hidden=hidden)
    run_nmcli([
        "connection", "modify", "uuid", profile_uuid,
        "wifi-sec.key-mgmt", key_mgmt,
        "wifi-sec.psk-flags", "2",
    ])
    run_nmcli(
        ["--wait", "40", "connection", "up", "uuid", profile_uuid,
         "passwd-file", "/dev/stdin"],
        secret_lines=[f"802-11-wireless-security.psk:{password}"],
    )
    return profile_uuid


def activate_open(request, *, hidden):
    profile_uuid, _ = find_or_create_profile(request, hidden=hidden)
    try:
        run_nmcli(["connection", "modify", "uuid", profile_uuid, "remove", "wifi-sec"])
    except WifiError:
        # A newly-created open profile has no security setting to remove.
        pass
    run_nmcli(["--wait", "40", "connection", "up", "uuid", profile_uuid])
    return profile_uuid


def activate_enterprise(request, *, hidden):
    existing_uuid = clean(request.get("uuid"), "Profile UUID")
    identity = clean(request.get("identity"), "Username", required=not bool(existing_uuid))
    password = clean(request.get("password"), "Password", required=True)
    eap = clean(request.get("eap"), "EAP method") or "peap"
    phase2 = clean(request.get("phase2"), "Inner authentication") or "mschapv2"
    if eap not in {"peap", "ttls"}:
        raise WifiError("Only PEAP and TTLS are supported by this form")
    allowed_phase2 = {"peap": {"mschapv2", "gtc"}, "ttls": {"pap", "chap", "mschap", "mschapv2"}}
    if phase2 not in allowed_phase2[eap]:
        raise WifiError(f"{phase2} is not valid for {eap.upper()}")

    profile_uuid, _ = find_or_create_profile(request, hidden=hidden)
    command = [
        "connection", "modify", "uuid", profile_uuid,
        "802-1x.password-flags", "2",
    ]
    if not existing_uuid:
        command.extend([
            "wifi-sec.key-mgmt", "wpa-eap",
            "802-1x.eap", eap,
            "802-1x.identity", identity,
            "802-1x.phase2-auth", phase2,
        ])
    elif identity:
        command.extend(["802-1x.identity", identity])
    anonymous_identity = clean(request.get("anonymousIdentity"), "Anonymous identity")
    domain = clean(request.get("domain"), "Server domain")
    ca_cert = clean(request.get("caCert"), "CA certificate")
    if anonymous_identity:
        command.extend(["802-1x.anonymous-identity", anonymous_identity])
    if domain:
        command.extend(["802-1x.domain-suffix-match", domain])
    if ca_cert:
        command.extend(["802-1x.ca-cert", ca_cert])
    elif not existing_uuid:
        command.extend(["802-1x.system-ca-certs", "yes"])
    run_nmcli(command)
    run_nmcli(
        ["--wait", "40", "connection", "up", "uuid", profile_uuid,
         "passwd-file", "/dev/stdin"],
        secret_lines=[f"802-1x.password:{password}"],
    )
    return profile_uuid


def handle(request):
    action = request.get("action")
    hidden = bool(request.get("hidden"))
    if action == "connect-personal":
        return activate_personal(request, hidden=hidden)
    if action == "connect-open":
        return activate_open(request, hidden=hidden)
    if action == "connect-enterprise":
        return activate_enterprise(request, hidden=hidden)
    raise WifiError("Unsupported Wi-Fi operation")


def main():
    try:
        request = json.loads(sys.stdin.readline())
        profile_uuid = handle(request)
        response = {"ok": True, "uuid": profile_uuid}
    except (WifiError, json.JSONDecodeError, OSError) as error:
        response = {"ok": False, "error": str(error)}
    except Exception as error:  # Keep the QML side on a structured error path.
        response = {"ok": False, "error": f"Unexpected helper failure: {error}"}
    print(json.dumps(response, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
