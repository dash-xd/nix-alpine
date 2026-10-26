#!/usr/bin/env python3
"""Live Skymill HTTP/Watermill qualification on the Fatline shared Redis proxy.

Invoked by fatline-composition-runtime.sh after Redis and Nginx are ready.
No host-published service: HTTP is reached via podman exec using a Python
client inside the provider's network namespace? Instead publish loopback on
the host only, never the public interface.
"""
import base64
import json
import os
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
port = os.environ.get("SKYMILL_TEST_PORT", "18081")
# Provider's HTTP executable has no built-in authenticator. Publish on
# 127.0.0.1 only and never expose its delivery/ACK API externally.
args = ["podman", "run", "-d", "--name", name, "--network", network,
        "--network-alias", "skymill-provider",
        "-p", "127.0.0.1:" + port + ":8081",
        "--user", "65534:65534", "--read-only", "--cap-drop", "ALL",
        "--security-opt", "no-new-privileges",
        "-e", "REDIS_URL=redis://redis-proxy:6379/0",
        "-e", "FATLINE_REDIS_URL=redis://redis-proxy:6379/0",
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
def start():
    run(*args)
    # The explicit loopback-only -p binding is authoritative; rootless
    # Podman may not expose this mapping via podman port.
    url = "http://127.0.0.1:" + port
    for _ in range(80):
        try:
            # A 405 indicates HTTP server is ready; no unauthenticated data API called.
            urllib.request.urlopen(urllib.request.Request(url + "/v1/messages", method="GET"), timeout=1)
        except urllib.error.HTTPError as e:
            if e.code == 405:
                return url
        except (OSError, TimeoutError):
            pass
        time.sleep(.25)
    raise RuntimeError("FAIL: provider HTTP readiness; logs:\n" + run("podman", "logs", name))

def post(url, path, payload, timeout=8):
    request = urllib.request.Request(url + path, json.dumps(payload).encode(),
              {"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)

def stop():
    subprocess.run(["podman", "rm", "-f", name], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, check=False)

print("CHECK: actual Skymill PublishOnce and Watermill delivery through shared Redis", flush=True)
try:
    url = start()
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
    url = start()
    recovered = post(url, "/v1/deliveries/receive", {"limit": 1}, timeout=20)
    entries = recovered.get("deliveries", [])
    check(len(entries) == 1 and entries[0]["message"]["id"] == payload["message_id"],
          "pending delivery must be reclaimed after provider process restart")
    check(post(url, "/v1/deliveries/ack", {"token": entries[0]["token"]}).get("ok") is True,
          "ACK must succeed after reclaim")
    print("PASS: pending-message recovery and ACK after provider process restart", flush=True)
finally:
    stop()
