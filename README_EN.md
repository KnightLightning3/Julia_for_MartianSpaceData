<!-- <div align="center"> -->
<!-- <img src="./docs/images/icon.svg" alt="icon"/> -->

<h1 align="center">Julia Pkg for Mars</h1>

# Breaking Changes (Read First)

> ### ⚠️ `data_get_from_date` has been renamed to `load_MAVEN_data`
>
> **`MAVEN_load.data_get_from_date` has been removed, with no alias kept.**
> Any external script still using the old name now fails with
> `UndefVarError: data_get_from_date not defined`.
> **The signature, arguments and return value are unchanged** — a global rename is all you need:
>
> | Old name (removed) | New name |
> | --- | --- |
> | `MAVEN_load.data_get_from_date` | **`MAVEN_load.load_MAVEN_data`** |
> | `MarsCommon.electron_energy_to_speed` | **`MarsCommon.e_energy2v`** |
> | `MarsCommon.ion_energy_to_speed` | **`MarsCommon.ion_energy2v`** |
>
> ```diff
> - Data_Dict = MAVEN_load.data_get_from_date(date; model_index = ["MAG_pc1s", "LPW_wave"])
> + Data_Dict = MAVEN_load.load_MAVEN_data(date; model_index = ["MAG_pc1s", "LPW_wave"])
> ```
>
> Migration steps and scope: see the [breaking-change entry in the changelog](CHANGELOG.md) (top of the file).

# Table of Contents
- [Breaking Changes (Read First)](#breaking-changes-read-first)
- [Introduction](#introduction)
- [Project Structure](#project-structure)
- [Project Execution Flow](#project-execution-flow)
- [Downloading Data](#downloading-data)
- [Reading Data](#reading-data)
- [Mars Magnetic Field Model](#mars-magnetic-field-model)
- [Custom Data Description](#custom-data-description)
- [MAVEN Data Tips](#maven-data-tips)
- [Plotting](#plotting)
- [Module Loading](#module-loading)
- [Program and Function Index](#program-and-function-index)
- [Documentation Build](#documentation-build)
- [ToDo List](#todo-list)

# Introduction

English / [简体中文](README.md)

This project provides tools for downloading, reading, processing, and visualizing Mars space science data, as well as calculating physical models. Data processing and scientific computing are primarily written in Julia; Python is mainly used for downloads and file maintenance, with a Fortran shared library accelerating selected magnetic-field calculations.

## Project Structure

| Directory/file | Purpose |
| --- | --- |
| `MAVEN_data/` | MAVEN readers, instrument processing, plotting, and data-format definitions |
| `MGS_data/`, `TW_data/` | MGS and Tianwen-1 data readers and instrument processing |
| `download_data/` | MAVEN downloading, integrity checks, compression, and cleanup |
| `config/` | Single configuration layer: `settings.example.toml` template + `config.py`/`paths.py`/`utils.py` |
| `martian_pipeline/` | Packaged entry point and unified CLI (`python -m martian_pipeline`) |
| `tools/` | Config migration `migrate_config.py`, scan/index `scan_and_index.py` |
| `tests/` | Regression tests on temporary directories / synthetic files (P0–P3 + packaging) |
| `models/`, `Magnetic_Model/` | Plasma, particle-orbit, magnetic-field, and related calculations |
| `common/`, `support_data/` | Shared coordinate/physics utilities and external support-data readers |
| `calculate/` | Model calculation workflows and composition entry points |
| `example/` | Plotting and data-analysis examples |
| `src/`, `Project.toml` | Julia package `MarsData`: lightweight public API + packaged plotting (`plot_module`, …) |
| `pyproject.toml` | Python runtime and optional dependency manifest |
| `docs/` | [Documenter documentation](docs/src/index.md): pipeline, reading/format, program index |

See the [program and function index](docs/src/api.md) for file responsibilities and function descriptions.

## Project Execution Flow

Full flow: [Project Execution Flow](docs/src/pipeline.md). Overview:

```
[0] Env setup  ->  [1] Config (TOML)  ->  [2] Download  ->  [3] Scan & Index
                                                                |
                        [6] Read & Compute  <-  [5] Derived Build -+
                                                                |
                        [7] Tests & Docs    <-  [4] Check & Maintain
```

Key commands:

```bash
python tools/migrate_config.py --apply      # config: INI -> TOML (dry-run by default)
python -m martian_pipeline scan             # scan local files and refresh the index
python -m martian_pipeline check            # file integrity check (report-only by default)
python -m martian_pipeline clean            # clean incomplete downloads (dry-run by default)
julia --project=docs docs/make.jl           # build this Wiki
```

# Downloading Data

Use the Python scripts to download and maintain MAVEN data. Create a virtual environment and install the runtime dependencies (manifest: `pyproject.toml`, with runtime and optional dependencies separated):

```
pip install -e .            # runtime: requests / beautifulsoup4 / tqdm / numpy / pandas / cdflib
pip install -e ".[build]"   # optional: derived CDF building needs spacepy (NASA CDF library)
```


For the first download, **you need to generate the initial configuration file**:

Run `download_data\initialize_download_parameters.py`.

After initialization, configure the server, save directory, date range, and data products for your environment. The downloader reads `download_data/MAVEN_download_config.ini`; this is a local runtime configuration and may not be present in the repository.

`download_data/MAVEN_download.py` downloads data from the configured server. After downloading, use the `martian_pipeline` CLI or the standalone scripts to maintain data:

```bash
python -m martian_pipeline scan      # scan local files and refresh the index
python -m martian_pipeline check     # file integrity check (report-only by default)
python -m martian_pipeline clean     # clean incomplete downloads (dry-run by default)
python download_data/compress_cdf.py                        # compress CDF in place (atomic replace)
python download_data/移除重复文件中的低版本文件.py --apply   # deduplicate old versions (dry-run by default)
```

Equivalent standalone scripts remain available: `download_data/check_exist_files.py` (scan) and `download_data/get_download_files.py` (index).

## Configuration

The single write end is **TOML** (`config/settings.toml`, not committed); the template is `config/settings.example.toml`, and the legacy INI (`download_data/MAVEN_download_config.ini`) remains a read-only compatible input. Migrate the legacy INI once:

```bash
python tools/migrate_config.py                    # dry-run: print the TOML that would be written (default)
python tools/migrate_config.py --apply            # actually write config/settings.toml
python tools/migrate_config.py --apply --force    # overwrite an existing settings.toml
```

The migration is idempotent, never moves any data directory, and never modifies the original INI. Read priority: `config/settings.toml` (TOML) -> legacy INI (read-only) -> built-in defaults.

## Requirements

- Python >= 3.11 (config reading relies on the standard-library `tomllib`).
- Julia >= 1.10 (standard-library `TOML`).
- On Windows, derived CDF building (`MAVEN_data/Build_data/`) needs the NASA CDF library (`spacepy.pycdf`); the magnetic-field model (`Magnetic_Model/IGRF_calculate.jl`) needs the corresponding C++/Fortran DLL.

Available MAVEN external servers (may require VPN):
- USTC source, fast on-campus speed, server may not always be running, data may be incomplete: http://222.195.76.155:8000/MAVEN/
- UCLA source, stable server, no NGIMS data: https://pds-ppi.igpp.ucla.edu/data/
- LASP source, stable server: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- Berkeley source, similar format to LASP, default server for SPADES library, requires account credentials for a significant portion of the data, not directly accessible: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

Note that the file structure of https://pds-ppi.igpp.ucla.edu/data/ differs from the latter two, and it does not contain NGIM data.

# Reading Data

## Lightweight public API (Julia package `MarsData`)

`src/MarsData.jl` exposes path resolution, the product registry, and index reading **without loading any scientific-data loader**, so it can be loaded with no local data and no Fortran DLL:

```julia
using Pkg; Pkg.instantiate()   # install dependencies from Project.toml + Manifest.toml
using MarsData
MarsData.project_root(); MarsData.maven_data_root(); MarsData.tw_data_root(); MarsData.mgs_data_root()
MarsData.index_path();   MarsData.data_model();      MarsData.load_index()
```

## Full reader entry point

```
Data_Dict = MAVEN_load.load_MAVEN_data(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

> ⚠️ **This entry point was previously named `data_get_from_date`; it has been removed with no alias.** Rename it globally in older scripts — see [Breaking Changes (Read First)](#breaking-changes-read-first).

This program requires a specific file tree structure, which is shared with the download section.

To reference in Julia:

```julia
include("path/MAVEN_data/MAVEN_load.jl")
include("path/Magnetic_Model/IGRF_calculate.jl")
import .MAVEN_load
import .IGRF_calculate
```

> Time-axis convention: the time axis of every loaded product is a **sorted time series** unless stated otherwise; nearest-neighbour lookups on the time axis use `MarsCommon.searchsortednearest` (binary search, `O(log N)`) rather than `findmin(abs.(x .- x0))` (linear scan). Non-time axes (energy, colour levels) still use `findmin`.

For specific reading methods, refer to: [MAVEN Data Format](docs/src/data_format.md)

Reading guide: [MAVEN Data Reading](docs/src/data_reading.md)

# Plotting

Plotting is now **packaged into `MarsData`** — no need to `include MAVEN_plot.jl` manually:

```julia
using MarsData          # provides plot_module / TimeFormat / remove_0_point!
using CairoMakie        # Figure / Axis / save

fig = Figure(; size=(2500, 2500))
fig, t0, xtimes = MarsData.plot_module(fig, time_range, data_dict; time_step=Dates.Minute(10))
save("overview.png", fig)
```

- **Implementation**: `src/plotting.jl` provides the overview composition (`plot_module` / `TimeFormat` / `remove_0_point!`), which `using MarsData` exports directly; the primitives live in `MAVEN_data/MAVEN_plot.jl`, loaded as the submodule `MarsData.MAVEN_plot`.
- **Accessing the primitives**: `using MarsData` does **not** make the primitives bare names — use `using MarsData.MAVEN_plot`, or qualify them as `MarsData.MAVEN_plot.time2x`. Primitives: `time2x`, `time_ticks`, `x_ticks`, `sta_heatmap`, `STA_2d_slip`, `SWEA_PAD_heatmap`, `WaveSpectra_heatmap`, `Orbit`, `PAD_slice`, `PAD_slice_polar`, `PAD_slice_velocity`.
- **Examples**: `example/MAVEN_plot_sample/MAVEN_overview_plot_sample.jl` (single interval) and `MAVEN_overview_cases.jl` (batch over 2-hour windows; output directory via `MAVEN_OVERVIEW_OUTDIR`).

# Module Loading

Heavy modules (`MAVEN_load`, `MAVEN_STATIC`, `MAVEN_SWIA`, `MAVEN_SWEA`, `IGRF_calculate`, `Cold_Plasma_Dispersion_Relation`, …) are **still include-based**, but a packaged loader is available: one call is equivalent to `include(the file)`.

```julia
using MarsData

MarsData.load_module(:MAVEN_load)        # ≡ include("MAVEN_data/MAVEN_load.jl") into MarsData
MarsData.MAVEN_load.load_MAVEN_data(date, model_index=["MAG_ss1s_cdf"])

MarsData.@load MAVEN_STATIC IGRF_calculate   # load and bind in the caller's scope
MAVEN_STATIC.static_c6_mass_mean(sta)

MarsData.available_modules()        # what can be loaded
MarsData.loaded_modules()           # what has been loaded
MarsData.module_info(:MAVEN_load)   # path / deps / whitelist / state
MarsData.validate_registry()        # self-check (paths, module names, dependency cycles)
```

- **Whitelist convention**: `@load` always uses per-name imports (`using .Mod: whitelist…`) and **never** a whole-module `using`. So whether a name becomes bare is decided solely by `ModuleSpec.allow` in the registry, independent of the module's own `export` (Julia's per-name import works for non-exported names too).
- **Open whitelists**:

  | Module | Bare names granted |
  | --- | --- |
  | `MarsCommon` | `searchsortednearest`, `e_energy2v`, `ion_energy2v` |
  | `MAVEN_load` | `load_cdf`, `load_MAVEN_data` |
  | `IGRF_calculate` | `IGRF_pc`, `pc2sphere`, `sphere2pc` |

  All other modules stay empty, so `@load` only binds the module name. Usage:

  ```julia
  MarsData.@load MarsCommon MAVEN_load IGRF_calculate
  searchsortednearest(time_axis, t)                       # bare name available
  Data = load_MAVEN_data(date; model_index=["MAG_ss1s_cdf"])
  x, y, z = pc2sphere(r, theta, phi)
  ```
- **Automatic dependency loading**: `ModuleSpec.deps` are loaded recursively into the same carrier **before** the target module, satisfying parent-relative references (`common/MarsCommon.jl` starts with `using ..constants`, so `constants` must already exist in the carrier).
- **Idempotent**: each module is included only once per process; repeated calls return the **same object**; `:preloaded` entries (`Paths`, `MAVEN_plot`) return the in-package instance.
- **Carrier mechanism**: modules are actually evaluated in a runtime *carrier* module (`MarsData._carrier()`) and then bound into `MarsData` as a `const` alias. Reason: Julia enforces strict dependency checks for `using` inside **package** modules — including `MAVEN_load.jl` directly into `MarsData` fails with `Package MarsData does not have CommonDataFormat in its dependencies`. A runtime carrier has no pkgid, so its `using` resolves through the `LOAD_PATH` fallback (same as `Main`), which means **none** of CommonDataFormat/JLD2/FortranFiles/Rotations/CSV/DifferentialEquations/LsqFit need to be declared in this package. Side effect: `parentmodule(MarsData.MAVEN_load)` is the carrier, not `MarsData`.

# Program and Function Index

Browse program responsibilities, primary entry points, and function descriptions in the [program and function index](docs/src/api.md). The [SWIA electron correction notes](docs/src/swia_electron.md) are also available.

# Documentation Build

The project Wiki is built with Julia's [Documenter](https://documenter.juliadocs.org/); sources live in `docs/src/`:

```bash
julia --project=docs docs/make.jl      # generate HTML into docs/build/
```

Pages: home, [Project Execution Flow](docs/src/pipeline.md), [MAVEN Data Reading](docs/src/data_reading.md), [MAVEN Data Format](docs/src/data_format.md), [SWIA Electron Correction](docs/src/swia_electron.md), [Program and Function Index](docs/src/api.md).

# Mars Magnetic Field Model

`IGRF_calculate.jl` uses the IGRF model to calculate the simulated magnetic field of Mars.

Model source: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)

# Custom Data Description

Some data has been adjusted for ease of use.

## KP_l3 Data
KP data is saved in JLD2 format as a dictionary, where `epoch` corresponds to time, and variable indices correspond to the numbers in the KP documentation. Additionally, the coordinate transformation matrix is saved as a list of 3x3 matrices.

Saved in `KP/l3/`.

## MAG_l3 Data
Magnetic field data is saved in Fortran77 unformatted format to reduce storage space and improve reading speed. Saved in `MAG/l3/`.

## VSC Data:
Spacecraft velocity, which can be calculated using the SPICE toolkit. However, there is a learning curve associated with it.

This dataset is obtained by fitting a quadratic function to the position data from MAG with 1-second precision.

Saved in `MAG/vsc/`, units in km/s.

## STATIC_d1_v4d Data
Based on the `v_4d` program in the SPEDAS library, using VSC data from MAG and potential corrections from STATIC.

Calculates the velocity `vel` (km/s), density `den` (cm⁻³), and flux for $\textsf H^+$, $\textsf O^+$, and $\textsf O_2^+$ across the full energy and angular range.

Saved in `STATIC/l3/`.

# MAVEN Data Tips

## STATIC Data:
- STATIC returns a 3D matrix of (azimuth, energy, ion mass) for each time point, corresponding to the `energy`, `phi`, `theta`, and `mass_arr` matrices.
- Scanning mode: STATIC has multiple scanning modes corresponding to different energy ranges, determined by the `swd_ind` parameter [0-26], which corresponds to the last dimension in the `energy`, `phi`, `theta`, and `mass_arr` matrices. In Julia, which uses 1-based indexing, the `swd_ind` parameter should be incremented by 1.
- Attenuator: The attenuator adjusts the low-energy STA data (<15eV) by multiplying it by (1., 1/10, 1/100, 1/1000) to prevent saturation. Officially, the attenuator is not changed more frequently than every 5 minutes, but some data suggests temporary saturation and attenuator switching.
- The `theta` and `phi` returned by STATIC correspond to 90-theta and phi in the spherical coordinate system, in the instrument reference frame. The `quat_mso` and `quat_sc` in the file are quaternions used to project the instrument reference frame to the MSO and SC reference frames.
- STATIC, SWEA, and SWIA use the spherical coordinate system's 90-theta and phi. Ref: `spedas_6_1\general\science\sphere_to_cart.pro`.

# ToDo List

- [x] Cloud MAVEN data
- [ ] Use SPEDAS's SPICE kernel to calculate coordinate transformation matrices for each instrument and save them as files
- [ ] Use SPEDAS's SPICE kernel to calculate spacecraft velocity, acceleration, orbital parameters, etc., and save them as files
- [ ] Full instrument reading
- [X] Calculate shape parameter / `projects\maven\swea\mvn_swe_calc_shape_arr.pro`
- [X] Example of overview event plotting
- [ ] Optimize CDF reading for instrument-specific modes (write variable lists for each data package, remove unused variable reads and PyObject checks)
- [X] Modify the download program so that `download_data\get_download_files.py` can automatically read the file directory to generate a list file
- [X] Download program can check data versions
- [x] Simple Julia plotting package
- [x] External file tree reading
- [ ] More magnetic field models
- [x] Tianwen data
- [x] Magnetic field line tracing
- [x] Adapt file tree to SPEDAS structure
- [x] MAVEN STATIC
- [X] Add flowcharts for project initialization and file processing
- [ ] STATIC processing functions currently only work on 4D data (time, mass, azimuth, energy). Update to reshape all values into the highest-dimensional array before performing array operations.

Updated as per the author's needs.