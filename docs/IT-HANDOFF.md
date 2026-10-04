# IT handoff: local decision-model server (AMDHALO-CT3)

*Prepared 2026-10-04 for the IT team taking over this machine and connecting it to TrueFoundry.*

## What this machine does

This mini-PC runs **Rune**, an AI "decision model", as a small web service on the local network.
An application sends it some text (for example an email) plus a list of questions, such as "which
team should handle this?" or "is it urgent?". Rune returns an answer to each question with a
confidence score.

- It doesn't generate free text, and it never calls out to the internet while serving. The model
  and all its files are on this machine.
- On our 74-email benchmark it was as accurate as the paid cloud service we use today (TypeSafe
  Jev), at no per-request cost.

Your job, in short:
1. Keep the service running.
2. Make it reachable from TrueFoundry, protected by an API key.
3. Register it in TrueFoundry's AI Gateway.

The document covers two scenarios:

- **[Scenario A](#scenario-a-use-the-machine-as-is)**: the machine works as delivered. Verify
  it, harden it, connect it. *(About 1 hour.)*
- **[Scenario B](#scenario-b-rebuild-from-scratch)**: the disk was wiped or the install is
  broken. Rebuild, then continue with Scenario A. *(About 1.5–2 hours, mostly downloads.)*

## At a glance

| item | value |
| --- | --- |
| hostname | `AMDHALO-CT3` (workgroup `SCG`, not domain-joined) |
| network | Wi-Fi, `192.168.1.201` (DHCP). **Recommend wired Ethernet with a reserved IP.** |
| hardware | AMD Ryzen AI MAX+ 395, Radeon 8060S iGPU, 128 GB RAM, 1.7 TB free on C: |
| GPU memory | 96 GB of the RAM is reserved for the GPU (AMD Adrenalin, "Variable Graphics Memory"). Windows sees ~32 GB. |
| OS / driver | Windows 11 Enterprise 10.0.26200; AMD graphics driver **32.0.31041.1004** (known good) |
| power | "High performance" plan, sleep and hibernate **never** |
| Windows account | `AMDHALO-CT3\kghosh` (everything was installed per-user for this account; see [Accounts](#a6-move-off-the-kghosh-account)) |
| install folder | `C:\Users\kghosh\projects\local-decision-model` |
| source code | https://github.com/skiingfalcon/local-decision-model-halo (public, branch `main`) |
| **service** | **Rune 26B-A4B v3** (Q8_0) on llama.cpp `llama-server` b11382 (Vulkan), **port 8001** |
| service runner | Windows Scheduled Task **`RuneServe`**: starts at logon of `kghosh`, restarts the server if it stops |
| endpoints | `GET /health` (no auth) · `POST /v1/systemone` (the API) · `GET /props` (model and build info) · `GET /metrics` (Prometheus, for [Datadog](#a7-monitoring-with-datadog-optional), optional) |
| logs | `C:\Users\kghosh\projects\local-decision-model\state\logs\rune.log` |
| optional extra | **Laya**, a smaller, faster but less accurate model on port 8000 (task `LayaServe`). Not needed for TrueFoundry; see [Optional: Laya](#optional-laya). |

```mermaid
flowchart LR
    tfy["TrueFoundry AI Gateway<br/>(Custom Endpoint)"] -- "POST /v1/systemone<br/>Authorization: Bearer key" --> fw["Windows Firewall<br/>TCP 8001"]
    fw --> rune["llama-server :8001<br/>Rune Q8_0"]
    task["Scheduled task RuneServe<br/>(restarts on exit)"] --> rune
    rune --> gpu[("Radeon 8060S")]
    rune -.-> disk[("state\hf<br/>model file, 25 GB")]
```

### What has and hasn't been tested

| | status |
| --- | --- |
| Rune answers correctly on this machine (74-email benchmark, smoke test) | ✅ tested |
| The scheduled task restarts the server after it is killed (back in ~28 s) | ✅ tested |
| API key: `/v1/systemone` returns **401** without or with a wrong key, **200** with the right one; `/health` stays open | ✅ tested (on localhost) |
| `/metrics` (Prometheus) is served with `RUNE_METRICS=1` and also requires the key | ✅ tested (on localhost) |
| Access from another machine on the network / firewall rule | ⚠️ not yet tested |
| Running while nobody is logged on, or under an account other than `kghosh` | ⚠️ not yet tested (see [A2](#a2-make-it-always-on), [A6](#a6-move-off-the-kghosh-account)) |
| TrueFoundry connection | ⚠️ not yet tested; steps below follow TrueFoundry's documentation |
| Datadog configs in `monitoring\datadog\` | ⚠️ not yet tested; written from Datadog's documentation and checked against this machine's counters and endpoints |

---

## Scenario A: use the machine as-is

### A1. Check that it's running

Log in as `kghosh`, or as a local admin using an elevated PowerShell. Then run:

```powershell
cd C:\Users\kghosh\projects\local-decision-model
Get-ScheduledTask RuneServe | Select-Object TaskName, State        # expect: Running
Invoke-RestMethod http://127.0.0.1:8001/health                     # expect: status ok
.\scripts\smoke.ps1                                                # expect: department = billing ...
```

The smoke test sends one sample request ("we were billed twice... refund or we cancel") and
prints Rune's answers. Expect `department = billing` and a round trip of about 0.5 s.

If any of this fails, see [Troubleshooting](#troubleshooting).

### A2. Make it always-on

The `RuneServe` task starts **when `kghosh` logs on**, so after a reboot nothing serves until
someone logs in. The power plan already keeps the box awake. Pick one of these:

- **Option 1: auto-logon (simplest, matches what was tested).** Configure Windows to log
  `kghosh` on at boot, for example with Sysinternals **Autologon**, which stores the password
  encrypted. Then lock the screen with a policy if needed. The task starts exactly as tested.
- **Option 2: start at boot with nobody logged on.** Re-register the task for an account and
  start it at boot. Run this from an elevated PowerShell in the install folder; it prompts for
  that account's password, which Task Scheduler stores:

  ```powershell
  .\scripts\install-task.ps1 -RunAs AMDHALO-CT3\<account> -AtStartup
  ```

  The account can be `kghosh`, or better, an IT service account after [A6](#a6-move-off-the-kghosh-account).

  ⚠️ **Untested.** The server then runs in a non-interactive session, and GPU (Vulkan) access
  from there hasn't been verified on this machine. Reboot without logging in, then check
  `Invoke-RestMethod http://<host>:8001/health` and run a real request from another machine. If
  requests fail, check `rune.log` and fall back to Option 1. Auto-logon works with any account.

Also plan for **Windows Update reboots** (for example, a maintenance window). The service comes
back on its own after the reboot, given Option 1 or 2.

### A3. Open it to the network, with an API key

By default the server only listens on `127.0.0.1` with no key. To serve TrueFoundry:

1. **Pick an API key.** Use a long random string, kept in your secret store:

   ```powershell
   -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 48 | ForEach-Object { [char]$_ })
   ```

2. **Edit `C:\Users\kghosh\projects\local-decision-model\.env`:**

   ```ini
   RUNE_HOST=0.0.0.0
   RUNE_API_KEY=<the key from step 1>
   ```

   With a key set, every request except `/health` needs the header
   `Authorization: Bearer <key>`.

3. **Allow the port through Windows Firewall.** Limit it to the addresses TrueFoundry connects
   from (or your gateway/VPN subnet):

   ```powershell
   New-NetFirewallRule -DisplayName "Rune decision model (TCP 8001)" -Direction Inbound `
     -Protocol TCP -LocalPort 8001 -Action Allow -Profile Domain,Private `
     -RemoteAddress <TrueFoundry egress IPs or subnet>
   ```

   The network currently shows as `Private`. If yours is `Public`, add that profile, or better,
   fix the network category.

4. **Restart the service** to pick up `.env`:

   ```powershell
   .\scripts\stop.ps1
   Start-ScheduledTask RuneServe
   ```

5. **Test from another machine:**

   ```bash
   curl http://<AMDHALO-CT3 IP>:8001/health
   curl -X POST http://<AMDHALO-CT3 IP>:8001/v1/systemone \
     -H "Authorization: Bearer <key>" -H "Content-Type: application/json" \
     -d '{"state":{"body":"We were billed twice for March. Refund the duplicate or we cancel."},
          "questions":{"dept":{"type":"choice","instructions":"Which team should handle this?",
                       "criteria":{"billing":"invoices, payments, refunds","technical":"bugs, outages","other":"everything else"}}}}'
   ```

   Expect `"choice":"billing"`. Without the header you should get **401**.

The traffic is plain HTTP. If it crosses an untrusted network, put it behind your VPN, or a TLS
reverse proxy such as IIS ARR, Caddy or nginx on the box.

### A4. Connect it to TrueFoundry

**Use TrueFoundry's "Custom Endpoints".** Don't use "Self Hosted Models": that feature expects
OpenAI-style chat APIs, while this server speaks TypeSafe Jev's decision API (`/v1/systemone`).
Custom Endpoints proxy any HTTP API unchanged and inject the upstream credentials for you
([TrueFoundry docs](https://www.truefoundry.com/docs/ai-gateway/custom-endpoints)).

1. **Network path.** TrueFoundry's gateway must be able to reach `http://<host>:8001`. If you
   use TrueFoundry's hosted (SaaS) gateway, that means a VPN, tunnel or other private
   connectivity from the gateway to this machine. If your gateway is deployed inside our network,
   the firewall rule from A3 is enough. **This is your call. Nothing on the machine assumes
   either.**
2. **Register a Custom Endpoint in the AI Gateway:**

   | field | value |
   | --- | --- |
   | Base URL | `http://<AMDHALO-CT3 IP or DNS name>:8001` (no trailing slash) |
   | Header auth | name `Authorization`, value `Bearer <key from A3>` |
   | Endpoint / account names | for example account `local-decision-models`, endpoint `rune` |

3. **Clients then call the gateway, not the box.** Following TrueFoundry's URL pattern, they
   authenticate with their own TrueFoundry key and never see the box's key:

   ```
   POST {GATEWAY_BASE_URL}/proxy-api/local-decision-models/rune/v1/systemone
   Authorization: Bearer <TrueFoundry API key>
   ```

4. **Health check / monitoring.** `GET {...}/rune/health`, or `http://<host>:8001/health`
   directly, returns `{"status":"ok"}` when the model is loaded and ready.

### A5. Day-to-day operation

| task | command (PowerShell, in the install folder) |
| --- | --- |
| status | `Get-ScheduledTask RuneServe` and `Invoke-RestMethod http://127.0.0.1:8001/health` |
| stop | `.\scripts\stop.ps1` (stops the task and frees the port) |
| start | `Start-ScheduledTask RuneServe` (the model loads in ~20 s) |
| logs | `Get-Content state\logs\rune.log -Tail 50 -Wait` |
| sample request | `.\scripts\smoke.ps1` (sends the key automatically once it's in `.env`) |
| remove the service | `.\scripts\install-task.ps1 -Remove` |

What to expect:
- **Capacity:** about **2 s per request** with 8 questions on a ~2,000-token email, so about 0.5
  requests/s. Requests are processed one at a time; more parallel slots didn't help on this GPU.
  Plan rate limits in TrueFoundry accordingly.
- **Resources:** about 27 GB of GPU memory and about 1 GB of RAM, steady.

Please **don't**:
- Switch `RUNE_GGUF` to the BF16 file. It crashes the GPU driver ("device lost"), and only a
  reboot recovers it.
- Lower the 96 GB GPU-memory setting below ~40 GB.
- Update the AMD graphics driver without re-running the smoke test afterwards. Vulkan behaviour
  is driver-dependent; 32.0.31041.1004 is the known-good version.

### A6. Move off the kghosh account

**Do you need `kghosh`'s login today?**
- **Clients (TrueFoundry, apps): no.** They only make HTTP calls to port 8001.
- **IT admins looking at files: no.** Local Administrators (for example `sadmin` and the `la-*`
  accounts) have full control of `C:\Users\kghosh\projects\local-decision-model`. Accept the
  Explorer permission prompt, or use an elevated PowerShell. Admins can also start and stop the
  tasks in Task Scheduler.
- **Starting the service: yes, as delivered.** `RuneServe` runs as `kghosh` and starts at
  `kghosh`'s logon.

**Rune is easy to move.** At runtime it needs only PowerShell, `vendor\llama.cpp\` (the
llama-server program), the 25 GB model file and `.env`. Python and `uv` are only used by the
setup and download scripts. To move it to a neutral folder and an IT-owned account:

1. **Create an IT service account**, for example a local user `svc-decision`. It needs no admin
   rights.
2. **Stop and unregister the old task.** From an elevated PowerShell in the old folder:

   ```powershell
   cd C:\Users\kghosh\projects\local-decision-model
   .\scripts\stop.ps1; .\scripts\install-task.ps1 -Remove
   ```

3. **Copy the runtime pieces** to `C:\local-decision-model`. This skips the Python
   environments, which embed absolute paths and aren't needed by Rune:

   ```powershell
   $src = 'C:\Users\kghosh\projects\local-decision-model'; $dst = 'C:\local-decision-model'
   robocopy $src $dst /E /XD "$src\.venv" "$src\.venv-rocm" "$src\state\hf" __pycache__
   $snap = 'state\hf\hub\models--owao--surogate-rune-26b-a4b-systemone\snapshots\f6cf5c19a05713cb9b2c59a57cd79e85ab8d2ffd'
   New-Item -ItemType Directory -Force "$dst\$snap" | Out-Null
   Copy-Item "$src\$snap\Rune-26B-A4B-v3-Q8_0.gguf" "$dst\$snap\"      # 25 GB
   icacls $dst /grant "AMDHALO-CT3\svc-decision:(OI)(CI)M"            # service account can write logs
   ```

4. **Register the task for the service account.** Pick one:
   - At boot, with no logon (Option 2 in A2, untested GPU access):

     ```powershell
     cd C:\local-decision-model
     .\scripts\install-task.ps1 -RunAs AMDHALO-CT3\svc-decision -AtStartup -StartNow
     ```

   - At that account's logon, combined with auto-logon of `svc-decision` (Option 1):

     ```powershell
     .\scripts\install-task.ps1 -RunAs AMDHALO-CT3\svc-decision
     ```

5. **Verify** with `.\scripts\smoke.ps1` (from `C:\local-decision-model`) and a request from
   another machine.
6. **Optionally** delete the old folder once satisfied (or keep it as a backup), and update the
   Datadog log path (A7, if you use Datadog) to `C:\local-decision-model\state\logs\rune.log`.

`git pull` in the new folder still works for updates, since `.git` was copied. To re-run the
download or setup scripts there, install Python 3.13 and `uv` for the account doing it
([B1](#b1-tools)) and run `uv sync` first. Laya is different: its Python environments must be
rebuilt in the new folder (README, "Optional: Laya").

### A7. Monitoring with Datadog (optional)

> **Optional.** Skip this section until the organization is onboarded to Datadog. Nothing else depends on it: the service runs the same without an Agent, and Rune's `/metrics` page (on by default, behind the API key) just goes unread.

Ready-made Agent configs are in the repo under
[`monitoring\datadog\conf.d\`](../monitoring/datadog/conf.d). Together they cover four things:

| what | Datadog check | config file | key signals |
| --- | --- | --- | --- |
| Is Rune up and ready? | HTTP check | `http_check.d\conf.yaml` | `http.can_connect` / service check on `/health` (no key needed) |
| Is the process alive, and its CPU/RAM? | Process check | `process.d\conf.yaml` | `llama-server.exe` running, CPU, memory |
| Load and throughput | OpenMetrics check | `openmetrics.d\conf.yaml` | `llamacpp:requests_processing`, `requests_deferred` (queue), `prompt_tokens_total`, `prompt_tokens_seconds` |
| GPU memory and load | Windows performance counters (Agent 7.33+) | `windows_performance_counters.d\conf.yaml` | GPU dedicated memory (about 27 GB normal), GPU engine utilization |
| Errors | Log collection | `local_decision_model.d\conf.yaml` | `rune.log` lines containing `ErrorDeviceLost` or `exited (` |

Datadog's built-in GPU monitoring targets NVIDIA. For this AMD Radeon, the Windows performance
counters are the source; they're the same numbers Task Manager shows.

**Steps (elevated PowerShell):**

1. **Install the Agent** using your org's API key and Datadog site:

   ```powershell
   Start-Process msiexec -Wait -ArgumentList '/qn','/i','https://s3.amazonaws.com/ddagent-windows-stable/datadog-agent-7-latest.amd64.msi','APIKEY="<DATADOG_API_KEY>"','SITE="<datadoghq.com or your site>"'
   ```

   If your org deploys the Agent with SCCM or Intune, use that instead.
2. **Turn on Rune's metrics endpoint.** It's on by default in `.env` (`RUNE_METRICS=1`); restart
   with `.\scripts\stop.ps1; Start-ScheduledTask RuneServe` if you changed it.
3. **Copy the configs:**

   ```powershell
   Copy-Item -Recurse -Force <install folder>\monitoring\datadog\conf.d\* C:\ProgramData\Datadog\conf.d\
   ```

   Then edit them in `C:\ProgramData\Datadog\conf.d\`:
   - `openmetrics.d\conf.yaml`: replace `<RUNE_API_KEY>` with the key from `.env`. Remove the
     `headers` block if no key is set.
   - `local_decision_model.d\conf.yaml`: set the log path to your install folder. The file
     assumes `C:\local-decision-model` (after A6). As delivered it's
     `C:\Users\kghosh\projects\local-decision-model\state\logs\rune.log`.
4. **Enable log collection.** In `C:\ProgramData\Datadog\datadog.yaml`, set `logs_enabled: true`.
   Then give the Agent's account read access to the logs folder:

   ```powershell
   icacls <install folder>\state\logs /grant "ddagentuser:(OI)(CI)R"
   ```

   Under `C:\Users\kghosh\...` the Agent can't read files without this grant. That's another
   reason to move the install (A6).
5. **Restart the Agent and check:**

   ```powershell
   & "$env:ProgramFiles\Datadog\Datadog Agent\bin\agent.exe" restart-service
   & "$env:ProgramFiles\Datadog\Datadog Agent\bin\agent.exe" status    # look for http_check, openmetrics, process, windows_performance_counters, logs
   ```

**Suggested monitors:**

| monitor | condition | action |
| --- | --- | --- |
| Rune down | HTTP check on `/health` failing for 2+ minutes | Check the task and `rune.log`. The supervisor normally restarts it within ~30 s. |
| GPU fault | log contains `ErrorDeviceLost` | **Reboot the machine.** Both models stop answering until the GPU is reset. |
| Restart loop | more than 3 `exited (` log lines in 15 minutes | Check `rune.log`; usually the GPU fault above |
| Backlog | `requests_deferred` > 0 for 5+ minutes | Clients are sending faster than ~0.5 requests/s. Rate-limit in TrueFoundry. |
| GPU memory | dedicated usage > 85 GB | Something else is using the GPU, or a second model server is running |

### Backups

Everything except `state\` and `vendor\` is in Git. Back up `state\hf` (and `.env`, which holds
your API key) if you want a restore without re-downloading.
- `Rune-26B-A4B-v3-Q8_0.gguf` (25 GB) is the file that matters.
- The `BF16` file (47 GB) is unused and can be deleted to save space.

---

## Scenario B: rebuild from scratch

Use this if the disk was wiped or the install is broken beyond the
[Troubleshooting](#troubleshooting) fixes. All commands are PowerShell. Steps 0–2 need admin
rights only where noted.

### B0. Machine settings

1. **AMD Software (Adrenalin) → Performance → Tuning → Variable Graphics Memory:** set to
   **96 GB**, then reboot. This can't be set by script.
2. **Graphics driver:** 32.0.31041.1004 is known good. Newer drivers are probably fine; verify
   with the smoke test.
3. **Power plan:** High performance, sleep and hibernate never.

   ```powershell
   powercfg /setactive SCHEME_MIN
   powercfg /change standby-timeout-ac 0
   powercfg /change hibernate-timeout-ac 0
   ```

4. **Network:** wired with a reserved IP, if possible.

### B1. Tools

```powershell
winget install --id Python.Python.3.13 -e        # Python 3.13 (the project requires 3.13)
winget install --id astral-sh.uv -e              # uv (Python package/env manager)
winget install --id Git.Git -e                   # git
# open a NEW PowerShell window so PATH picks these up
```

### B2. Get the code

```powershell
mkdir C:\Users\<user>\projects -Force; cd C:\Users\<user>\projects
git clone https://github.com/skiingfalcon/local-decision-model-halo local-decision-model
cd local-decision-model
```

Keep the folder path **short**. This matters for the optional Laya GPU setup (see
Troubleshooting), and costs nothing for Rune.

### B3. Install and configure

```powershell
uv sync                                    # Python environment for the download helpers
.\scripts\setup-tls.ps1                    # trust bundle for the corporate proxy (see note below)
Copy-Item .env.example .env                # then set RUNE_HOST / RUNE_API_KEY as in A3
.\scripts\setup-llama.ps1                  # downloads llama.cpp b11382 (Vulkan + ROCm builds, ~280 MB)
.\scripts\fetch-rune.ps1                   # downloads the Rune Q8_0 model, 25 GB (~20–30 min at 20 MB/s)
```

`setup-llama.ps1` should print `Vulkan0: AMD Radeon(TM) 8060S Graphics` for the Vulkan build.
The ROCm build listing `(none)` is expected and harmless.

**About the proxy.** This network runs Cisco Umbrella, which intercepts huggingface.co and
GitHub downloads. The scripts handle it on their own:
- a trust bundle containing Cisco's published root, fingerprint-checked,
- a small Python TLS adjustment,
- an automatic step through Umbrella's session redirect.

Nothing is added to the Windows certificate store. On a network without Umbrella the same
scripts work unchanged. If downloads still fail, see Troubleshooting.

**Shortcut:** if you have a backup of `state\hf`, copy it into the new folder and skip
`fetch-rune.ps1`.

### B4. Install the service and test

```powershell
.\scripts\install-task.ps1 -StartNow       # registers + starts the RuneServe scheduled task
.\scripts\smoke.ps1                        # expect: department = billing ...
```

Then continue with Scenario A: [A2](#a2-make-it-always-on) (always-on),
[A3](#a3-open-it-to-the-network-with-an-api-key) (network + key) and
[A4](#a4-connect-it-to-truefoundry) (TrueFoundry).

`make setup` runs B3 and B4 in one go, if `make` is installed.

---

## Troubleshooting

| symptom | likely cause | fix |
| --- | --- | --- |
| `/health` doesn't answer | Task not running, or nobody logged on (see A2) | `Start-ScheduledTask RuneServe`; check `state\logs\rune.log` |
| `/health` returns **503** | Model still loading (~20 s after start) | Wait and retry |
| `rune.log` shows `ErrorDeviceLost` | GPU driver fault (seen with the BF16 file) | Make sure `.env` has `RUNE_GGUF=Rune-26B-A4B-v3-Q8_0.gguf`, then **reboot** |
| Requests return **401** | Missing or wrong `Authorization: Bearer` header | Check the key in `.env` and the TrueFoundry header auth |
| Works on the box, not from the network | `RUNE_HOST` still `127.0.0.1`, or the firewall | A3 steps 2–4; `Test-NetConnection <host> -Port 8001` from the client side |
| `setup-llama.ps1` lists no Vulkan device | Driver or GPU-memory setting | Reinstall the AMD driver; check VGM (B0) |
| Downloads fail with certificate errors | Corporate proxy | Re-run `.\scripts\setup-tls.ps1`. Make sure `.env` exists (it holds the CA settings). |
| Downloads stop with "missing X-Repo-Commit" | Umbrella redirect not handled | Use the provided `fetch-*.ps1` scripts, not `huggingface-cli` directly |
| Second copy of the server won't start | Two servers can't write the same `rune.log` | Run only one RuneServe per machine |
| **Both** Rune (`ErrorDeviceLost` in `rune.log`) **and** Laya (crash `0xC0000005` in `amdhip64_7.dll` in `laya.log`) fail; `/health` may still say ok | The GPU driver lost the device and stays in that state | **Reboot.** Seen on 2026-10-04 after extra test copies of llama-server were started next to the service and force-stopped. Run one Rune server per machine, and restart it (`stop.ps1`, then `Start-ScheduledTask RuneServe`) only when no requests are in flight. |

## Optional: Laya

Laya is a second, much smaller decision model on port 8000 (task `LayaServe`). It's about 8×
faster than Rune but noticeably less accurate, so TrueFoundry doesn't need it. It's currently
installed and running on this machine.
- To turn it off: `.\scripts\stop.ps1 -Model laya`, then
  `.\scripts\install-task.ps1 -Model laya -Remove`. That frees ~7–60 GB of GPU memory.
- To rebuild it, see "Optional: Laya" in the [README](../README.md).

## Appendix: the API in one example

Request:

```json
POST /v1/systemone
{
  "state": {"subject": "Duplicate charge", "body": "We were billed twice for March. Please refund the duplicate today or we will cancel."},
  "questions": {
    "department": {"type": "choice", "instructions": "Which team should handle this request?",
                   "criteria": {"billing": "invoices, payments, refunds", "technical": "bugs, outages, errors", "other": "everything else"}},
    "urgency":    {"type": "score",  "instructions": "How urgent is the request?", "criteria": ["routine", "soon", "blocking"]},
    "churn_risk": {"type": "noul",   "instructions": "Does the customer explicitly threaten to cancel?"}
  }
}
```

Response (real output from this machine, numbers rounded):

```json
{
  "model": "C:\\Users\\kghosh\\...\\Rune-26B-A4B-v3-Q8_0.gguf",
  "answers": {
    "department": {"type": "choice", "choice": "billing",
                   "probabilities": {"billing": 0.986, "other": 0.013, "technical": 0.001}, "confidence": 0.979},
    "urgency":    {"type": "score", "score": 1.32, "legend": {"0": "routine", "1": "soon", "2": "blocking"},
                   "probabilities": {"0": 0.035, "1": 0.607, "2": 0.358}, "confidence": 0.41},
    "churn_risk": {"type": "noul", "noul": 0.995}
  },
  "usage": {"input_tokens": 428, "output_tokens": 0}
}
```

The `model` field contains the model file's full local path. If you'd rather not expose a
Windows username to API clients, strip it in TrueFoundry or move the install out of the user
profile.

The three question types:
- `choice`: pick one of the listed options.
- `score`: a level on an ordered scale, reported as a weighted average of the levels.
- `noul`: the probability that a statement is true.

The full benchmark and model comparison are in
[jev-email-cascade/docs/decision-models.md](https://github.com/skiingfalcon/jev-email-cascade/blob/25ae95d8b6f9c1cb9c64b560163133117b57e44b/docs/decision-models.md).
