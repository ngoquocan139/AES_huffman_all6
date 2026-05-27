# GitHub Sync And Self-Hosted Runner Usage Spec

## 1. Purpose

Tai lieu nay huong dan cach dong bo repo local voi GitHub va cach dung GitHub
Actions de chay `make` tren 2 moi truong:

| Environment | Runs where | Purpose |
|---|---|---|
| GitHub-hosted runner | GitHub cloud Ubuntu runner | Check nhe: `make drc` bang Verilator |
| Self-hosted runner | May WSL local cua user | Full local flow: Questa simulation va Vivado Windows |

Repo GitHub hien tai:

```text
git@github.com:ngoquocan139/AES_huffman_all6.git
```

Local self-hosted runner:

```text
/mnt/h/Academic/senior_project/DATN/work/luc/github-runner-AES_huffman_all6
```

Runner name:

```text
An-WSL-Questa-Vivado
```

Runner labels:

```text
self-hosted, Linux, X64, wsl, questa, vivado
```

## 2. Git Sync Flow

### 2.1 Check local status

```bash
cd /mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6
git status
```

### 2.2 Commit local changes

```bash
git add <file_or_folder>
git commit -m "message"
```

Example:

```bash
git add .github/workflows/self-hosted-local.yml docs/github_sync_and_self_hosted_runner_usage_spec.md
git commit -m "add self-hosted runner usage spec"
```

### 2.3 Push to GitHub

```bash
git push origin main
```

### 2.4 Pull from GitHub

```bash
git pull origin main
```

## 3. What Should Be Versioned

Nen push len GitHub:

| Path | Reason |
|---|---|
| `rtl/` | RTL source |
| `tb/` | Testbench source |
| `testcase/` | C tests and testcase wrappers |
| `docs/` | Specs and report notes |
| `sim/Makefile` | Simulation/build flow |
| `sim/*.f` | File lists |
| `sim/run.csh`, `sim/report.csh` | Coverage regression scripts |
| `vivado/*.tcl`, `vivado/constraints/*.xdc` | FPGA build scripts and constraints |
| `.github/workflows/*.yml` | GitHub Actions workflows |

Khong nen push:

| Path / file type | Reason |
|---|---|
| `sim/work/`, `sim/work_*` | Questa build output |
| `sim/log/`, `sim/loopback/`, `sim/dmem_dump/` | Run output/generated reports |
| `*.ucdb` | Coverage database output |
| `vivado/build/` | Vivado generated project/build output |
| `sim/vivado_reports/`, `sim/vivado_bitstreams/` | Generated reports/bitstreams |
| `questasim/license.dat` | License file, machine-specific |
| `github-runner-*` | Runner install folder, not source code |

## 4. GitHub-Hosted CI

Workflow:

```text
.github/workflows/ci.yml
```

Purpose:

- runs on GitHub cloud Ubuntu runner;
- installs Verilator and Make;
- runs `make drc` in `sim/`.

This is safe for normal push/pull request because it does not need local
Questa/Vivado/license.

Current command:

```bash
cd sim
make drc
```

Limit:

- does not run `make all`;
- does not run Questa;
- does not run Vivado;
- does not use local Windows paths.

## 5. Self-Hosted Local Workflow

Workflow:

```text
.github/workflows/self-hosted-local.yml
```

Purpose:

- runs on the local WSL machine;
- can see local Questa installation and license;
- can call Windows Vivado through `cmd.exe`/`powershell.exe`;
- can run the same `make` commands as manual local use.

This workflow is intentionally `workflow_dispatch` only. It does not run
automatically on pull requests because self-hosted runners execute code on the
local machine.

## 6. Runner Service Control

Runner folder:

```bash
cd /mnt/h/Academic/senior_project/DATN/work/luc/github-runner-AES_huffman_all6
```

Check status:

```bash
printf '1412\n' | sudo -S ./svc.sh status
```

Start:

```bash
printf '1412\n' | sudo -S ./svc.sh start
```

Stop:

```bash
printf '1412\n' | sudo -S ./svc.sh stop
```

Restart:

```bash
printf '1412\n' | sudo -S ./svc.sh stop
printf '1412\n' | sudo -S ./svc.sh start
```

Expected good status:

```text
Active: active (running)
Listening for Jobs
```

## 7. Running The Local Workflow From GitHub

Steps:

1. Push `.github/workflows/self-hosted-local.yml` to GitHub.
2. Open GitHub repo.
3. Go to `Actions`.
4. Select `Local Self-Hosted Flow`.
5. Click `Run workflow`.
6. Choose inputs.

Default inputs:

| Input | Default | Meaning |
|---|---|---|
| `run_sim` | `true` | Run Questa simulation flow |
| `run_vivado` | `false` | Skip Vivado unless explicitly requested |
| `c_src` | `test_mmio_dma.c` | C source under `testcase/` |
| `testname` | `dma_compress_aes_input1` | Verilog testcase wrapper |
| `run_args` | `+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt` | Testbench plusargs |

## 8. Example Runs

### 8.1 Main SoC TX/RX loopback

GitHub Actions inputs:

| Input | Value |
|---|---|
| `run_sim` | `true` |
| `run_vivado` | `false` |
| `c_src` | `test_mmio_dma.c` |
| `testname` | `dma_compress_aes_input1` |
| `run_args` | `+CASE_NAME=dma_compress_aes_input1 +INPUT_FILE=input1.txt` |

Equivalent local command:

```bash
cd sim
make compile C_SRC=test_mmio_dma.c
make drc
make all
```

### 8.2 Multi-record storage testcase

GitHub Actions inputs:

| Input | Value |
|---|---|
| `run_sim` | `true` |
| `run_vivado` | `false` |
| `c_src` | `test_mmio_dma_storage_table.c` |
| `testname` | `dma_storage_table_input1_then_input3` |
| `run_args` | `+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input3.txt` |

Equivalent local command:

```bash
cd sim
make compile C_SRC=test_mmio_dma_storage_table.c
make drc
make all TESTNAME=dma_storage_table_input1_then_input3 RUN_ARGS="+CASE_NAME=dma_storage_table_input1_then_input3 +INPUT_FILE=input1.txt +INPUT_FILE2=input3.txt"
```

### 8.3 Vivado bitstream flow

GitHub Actions inputs:

| Input | Value |
|---|---|
| `run_sim` | `false` |
| `run_vivado` | `true` |

Equivalent local full-SoC command:

```bash
cd sim
make vivado_flow_full
```

Equivalent local split command:

```bash
cd sim
make vivado_flow_split
```

This uses the default ZCU102 target. The external clock constraint is
`VIVADO_CLOCK_MHZ=300` on `clk_p_i`; the ZCU102 wrapper divides it to the
existing 50 MHz SoC/UART clock.

`make vivado_flow_full` runs:

```text
Full ZCU102 synth -> impl -> bitstream
```

`make vivado_flow_split` runs:

```text
TX-only synth -> impl -> bitstream
RX-only synth -> impl -> bitstream
```

## 9. Output Artifacts

The self-hosted workflow uploads generated outputs as GitHub Actions artifacts.

Simulation artifact:

```text
local-sim-<testname>
```

Contains:

| Path | Meaning |
|---|---|
| `sim/sim.log` | Latest simulation log |
| `sim/log/` | Per-test logs |
| `sim/loopback/` | Summary and compare files |
| `sim/dmem_dump/` | Source/TX/RX DMEM dumps |

Vivado artifact:

```text
local-vivado-split
```

Contains:

| Path | Meaning |
|---|---|
| `sim/vivado_reports/` | Collected Vivado reports |
| `sim/vivado_bitstreams/` | Generated `.bit` files |
| `vivado/build/*/*.runs/*/*.rpt` | Raw Vivado reports |
| `vivado/build/*/*.runs/*/*.bit` | Raw generated bitstreams |

## 10. Security Notes

Important rules:

- Do not commit `questasim/license.dat`.
- Do not commit runner credentials files such as `.runner`, `.credentials`,
  `.credentials_rsaparams`.
- Do not enable this self-hosted workflow on arbitrary pull requests.
- Treat `workflow_dispatch` as the safe default because the user chooses when
  local machine resources are used.
- Registration tokens from GitHub are short-lived; after a runner is configured,
  do not store or commit the token.

## 11. Troubleshooting

### 11.1 Runner offline

Check service:

```bash
cd /mnt/h/Academic/senior_project/DATN/work/luc/github-runner-AES_huffman_all6
printf '1412\n' | sudo -S ./svc.sh status
```

If stopped:

```bash
printf '1412\n' | sudo -S ./svc.sh start
```

### 11.2 Job waits forever

Causes:

- runner is offline;
- workflow asks for labels not present on runner;
- workflow file has not been pushed to GitHub yet.

Current labels required by local workflow:

```text
self-hosted, Linux, X64, wsl, questa
self-hosted, Linux, X64, wsl, vivado
```

### 11.3 Questa not found

Check:

```bash
/mnt/h/Academic/senior_project/DATN/work/luc/questasim/linux_x86_64/vsim -version
```

Service PATH is stored in runner folder:

```text
/mnt/h/Academic/senior_project/DATN/work/luc/github-runner-AES_huffman_all6/.path
```

### 11.4 Questa license failure

Run locally:

```bash
cd /mnt/h/Academic/senior_project/DATN/work/luc/AES_huffman_all6/sim
make license
```

Then rerun the GitHub workflow.

### 11.5 Vivado not found

Check Windows batch file:

```bash
test -f /mnt/h/From_software/Vivado/Vivado/Vivado/2024.2/bin/vivado.bat && echo OK
```

The Makefile uses:

```text
VIVADO_BAT ?= H:\From_software\Vivado\Vivado\Vivado\2024.2\bin\vivado.bat
```

If Vivado moved, update `sim/Makefile` or pass `VIVADO_BAT=...`.
