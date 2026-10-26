#!/usr/bin/env python3
"""Live Skymill HTTP/Watermill qualification on the Fatline shared Redis proxy.

Invoked by fatline-composition-runtime.sh after Redis and Nginx are ready.
The HTTP test client joins the private Podman network; no host port is published.
"""
import base64
import json
import os
import urllib.parse
import subprocess
import time
import urllib.error
import urllib.request

def run(*args):
    return subprocess.check_output(args, text=True).strip()

def check(cond, description):
    if not cond:
        raise RuntimeError("FAIL: " + description)

name = os.environ["SKYMILL_TEST_NAME"]
image = os.environ["SKYMILL_TEST_IMAGE"]
network = os.environ["SKYMILL_TEST_NETWORK"]
password = os.environ["SKYMILL_TEST_PASSWORD"]
stream = "fatline-qual:skymill:stream:github.webhooks"
scope = "fatline-qual"
# Provider HTTP has no authenticator; keep it on the internal Podman network.
args = ["podman", "run", "-d", "--name", name, "--network", network,
        "--network-alias", "skymill-provider",
        "--user", "65534:65534", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "-e", "REDIS_URL=redis://skymill:" + urllib.parse.quote(password, safe="") + "@redis-proxy:6379/0",
        "-e", "FATLINE_REDIS_URL=redis://skymill:" + urllib.parse.quote(password, safe="") + "@redis-proxy:6379/0",
        "-e", "REDIS_USERNAME=skymill",
        "-e", "REDIS_PASSWORD=" + password,
        "-e", "SKYMILL_SCOPED_PROVIDER=true",
        "-e", "FATLINE_SCOPE=" + scope,
        "-e", "SKYMILL_STREAM=" + stream,
        "-e", "SKYMILL_CONSUMER_GROUP=qualification",
        "-e", "SKYMILL_CONSUMER=qualification-worker",
        "-e", "SKYMILL_LISTEN_ADDR=0.0.0.0:8081",
        "-e", "SKYMILL_BLOCK_TIME=250ms",
        "-e", "SKYMILL_CLAIM_INTERVAL=1s",
        "-e", "SKYMILL_MAX_IDLE_TIME=2s",
        image]
client_image = os.environ.get("SKYMILL_TEST_CLIENT_IMAGE", "alpine:latest")
check(subprocess.run(["podman", "image", "exists", client_image]).returncode == 0,
      "missing HTTP test client image: " + client_image)

def http_request(path, payload=None, timeout=20):
    cmd = ["podman", "run", "--rm", "--network", network,
           "--entrypoint", "/bin/busybox", client_image,
           "wget", "-T", str(timeout), "-S", "-O", "-"]
    if payload is not None:
        cmd += ["--header", "Content-Type: application/json",
                "--post-data", json.dumps(payload, separators=(",", ":"))]
    cmd += ["http://skymill-provider:8081" + path]
    return subprocess.run(cmd, capture_output=True, text=True)

def start():
    run(*args)
    last_error = "no response"
    for _ in range(40):
        state = run("podman", "inspect", "--format", "{{.State.Status}} exit={{.State.ExitCode}}", name)
        if not state.startswith("running"):
            raise RuntimeError("FAIL: provider exited: " + state + "\n" + run("podman", "logs", name))
        result = http_request("/v1/messages", timeout=2)
        if "405 Method Not Allowed" in result.stderr:
            return
        last_error = (result.stderr or result.stdout)[-700:]
        time.sleep(.25)
    raise RuntimeError("FAIL: private-network HTTP readiness: " + last_error + "\n" + run("podman", "logs", name))

def post(url, path, payload, timeout=8):
    result = http_request(path, payload, timeout)
    if result.returncode:
        raise RuntimeError("FAIL: HTTP " + path + ": " + (result.stderr or result.stdout)[-1500:])
    return json.loads(result.stdout)

def stop():
    subprocess.run(["podman", "rm", "-f", name], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)

print("CHECK: actual Skymill PublishOnce and Watermill delivery through shared Redis", flush=True)
try:
    start()
    url = None
    payload = {"idempotency_key": "fatline-provider-qual-1",
               "message_id": "fatline-provider-qual-1",
               "payload_base64": base64.b64encode(b"provider-qualification").decode()}
    first = post(url, "/v1/messages", payload)
    again = post(url, "/v1/messages", payload)
    check(first.get("duplicate") is False, "first PublishOnce must create entry")
    check(again.get("duplicate") is True, "second PublishOnce must deduplicate")
    check(first.get("stream_entry_id") == again.get("stream_entry_id"),
          "deduplicated publication must preserve entry ID")
    print("PASS: PublishOnce deduplicates and returns stable stream entry ID", flush=True)
    delivered = post(url, "/v1/deliveries/receive", {"limit": 1}, timeout=15)
    items = delivered.get("deliveries", [])
    check(len(items) == 1 and items[0]["message"]["id"] == payload["message_id"],
          "Watermill consumer group must receive published message")
    print("PASS: Watermill consumer-group delivery", flush=True)
    # Simulate process loss before ACK; Redis PEL should retain pending entry.
    stop()
    time.sleep(3)
    start()
    url = None
    recovered = post(url, "/v1/deliveries/receive", {"limit": 1}, timeout=20)
    entries = recovered.get("deliveries", [])
    check(len(entries) == 1 and entries[0]["message"]["id"] == payload["message_id"],
          "pending delivery must be reclaimed after provider process restart")
    check(post(url, "/v1/deliveries/ack", {"token": entries[0]["token"]}).get("ok") is True,
          "ACK must succeed after reclaim")
    print("PASS: pending-message recovery and ACK after provider process restart", flush=True)
finally:
    stop()
