#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later

"""Check the configured Samsung endpoints without downloading firmware bodies."""

import json
from pathlib import Path
import re
import sys
import time
from urllib.parse import urlsplit

import requests
from samloader import fusclient, main, versionfetch


request = requests.Session.request


def bounded_request(session, method, url, **kwargs):
    kwargs.setdefault("timeout", (10, 15))
    endpoint = urlsplit(url)
    label = f"{method.upper()} {endpoint.netloc}{endpoint.path}"
    print(f"Request: {label}", flush=True)
    started = time.monotonic()
    try:
        response = request(session, method, url, **kwargs)
    except requests.RequestException as error:
        print(f"{type(error).__name__} after {time.monotonic() - started:.1f}s", flush=True)
        raise
    print(f"HTTP {response.status_code} after {time.monotonic() - started:.1f}s", flush=True)
    return response


requests.Session.request = bounded_request
# The downloader's debug files contain FUS authorization headers. Keep this
# diagnostic limited to endpoint statuses and public firmware metadata.
fusclient.log_response = lambda *args, **kwargs: None
main.log_response = lambda *args, **kwargs: None

configs = [
    ("source", Path("unica/configs/essi.sh"), "SOURCE_FIRMWARE"),
    *[(device, Path(f"target/{device}/config.sh"), "TARGET_FIRMWARE")
      for device in ("o1s", "t2s", "p3s", "r9s")],
]
failed = False
for device, path, variable in configs:
    print(f"\nChecking {device}", flush=True)
    match = re.search(rf'^{variable}="([^"\n]+)"', path.read_text(), re.MULTILINE)
    if match is None:
        print(f"Missing {variable} in {path}", flush=True)
        failed = True
        continue
    model, region, identifier = match.group(1).split("/")
    try:
        version = versionfetch.getlatestver(model, region)
        client = fusclient.FUSClient()
        remote_path, name, size = main.getbinaryfile(client, version, model, region, identifier)
        print(json.dumps({"device": device, "model": model, "region": region,
                          "version": version, "bundle": name, "bytes": size}), flush=True)
        main.initdownload(client, name)
        authorization = (f'FUS nonce="{client.encnonce}", signature="{client.auth}", '
                         'nc="", type="", realm="", newauth="1"')
        with requests.head(
            "http://cloud-neofussvr.samsungmobile.com/NF_DownloadBinaryForMass.do",
            params={"file": remote_path + name},
            headers={"Authorization": authorization, "User-Agent": "Kies2.0_FUS",
                     "X-FUS-Protocol-Ver": "2.0"},
            allow_redirects=True,
        ) as response:
            print(json.dumps({"download_endpoint_status": response.status_code,
                              "content_length": response.headers.get("Content-Length")}), flush=True)
            response.raise_for_status()
    except (Exception, SystemExit) as error:
        print(f"{device}: {type(error).__name__}: {error}", flush=True)
        failed = True

sys.exit(1 if failed else 0)
