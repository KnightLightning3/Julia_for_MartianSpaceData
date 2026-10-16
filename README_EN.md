<div align="center">

# Mars Space Data Processing & Scientific Computing Toolkit

</div>

[简体中文](README.md) · [Documenter docs](docs/src/index.md)

This repository contains download, reading, and processing tools for MAVEN, MGS, and Tianwen-1 data, together with Mars space-environment and plasma calculations. Julia is used for data processing, scientific computing, and plotting; Python is used for MAVEN downloads and local file maintenance. See the directory map and documentation links below for current entry points.

## Current layout

| Path | Contents |
| --- | --- |
| `src/`, `Project.toml` | Julia package `MarsData`: path/index API, plotting, and module loader |
| `MAVEN_data/` | MAVEN readers, STATIC/SWIA/SWEA processing, plotting primitives, and product registry |
| `MGS_data/`, `TW_data/` | MGS and Tianwen-1 readers and instrument processing |
| `common/` | Shared constants, paths, data keys, coordinates, and physics utilities |
| `models/` | Mars environment, IGRF, dispersion, distribution-fitting, and particle-orbit models |
| `models/extras/` | Standalone Graham and Octree experimental code |
| `analysis/` | Event-analysis scripts, including `Pickup_ion.jl` |
| `support_data/` | Readers for external support data such as OMNI |
| `download_data/`, `martian_pipeline/` | Python download, scan, index, and file-maintenance tools |
| `config/`, `tools/` | TOML configuration, scan/API/Wiki tools |
| `example/` | Examples; some read data, write files, or load DLLs, so inspect script settings before running |
| `docs/` | Documenter sources, Wiki pages, references, and historical reports |

## Julia package and shared capabilities

Julia 1.10 or later is required. `using MarsData` initializes the plotting stack (CairoMakie/Makie) and preloads the plotting submodule. The path, product-registry, and index APIs do not load scientific-data readers and do not require local observation data or the IGRF DLL.

Before the first `using MarsData` on a fresh clone, create the settings file and edit its three data roots. Otherwise package loading stops because `config/settings.toml` is missing:

```bash
python download_data/initialize_download_parameters.py
# Edit [paths] in config/settings.toml with your text editor
```

Set `paths.maven_data_root`, `tw_data_root`, and `mgs_data_root` to local directories before starting Julia.

Preloaded package instances include `MarsData.MarsCommon`, `MarsData.MarsEnvironment`, `MarsData.MAVEN_plot`, `MarsData.Paths`, and `MarsData.DataKeys`. Package initialization creates these instances, and the loader reuses them. The package does not re-export every API name as a bare identifier; prefer explicit qualification such as `MarsData.project_root()` and `MarsData.DataKeys.ENERGY`.

`common/MarsCommon.jl` splits shared capabilities into `common/marscommon/`:

| File | Capability |
| --- | --- |
| `statistics.jl` | Statistics and distribution calculations |
| `geometry.jl` | Coordinate transforms, positions, and magnetic-field geometry |
| `numerics.jl` | Numerical fitting and general numerical utilities |
| `cyclotron.jl` | Cyclotron and wave-particle calculations |

`common/constants.jl` provides shared physical constants; `common/paths.jl` resolves repository and data paths; `common/data_keys.jl` centralizes Symbol-key contracts for data dictionaries. `DataKeys.MASS` is the shared proton rest-mass reference in STATIC/SWIA data packages, in `eV/(km/s)^2`; it is distinct from the mass axis `MASS_ARR` and the mass-to-charge parameter `m_int`.

Element-wise mathematical functions in MarsCommon take scalar inputs. Use Julia's broadcast dot for arrays, for example `MarsData.MarsCommon.ion_energy2v.(energy, 16)`. Position batching, matrix rotation, in-place dictionary processing, and time-axis nearest-neighbor lookup are array or matrix interfaces; see the [API index](docs/src/api.md) for signatures.

### 3D points and coordinate rotations

General point-coordinate conversions live in the unregistered `FunctionCoordinate` module. Include it explicitly and call it by module qualification. Prefer `SVector{3}` for a single point; a length-3 `AbstractVector{<:Real}` is also accepted as an adapter input, and the result is an `SVector{3}`. Batch independent points with `f.(points)`. For row-stored `N×3` points, call the scalar function once per row with `map`; do not broadcast the three coordinates inside a point:

```julia
using MarsData, StaticArrays, Rotations
include(joinpath(MarsData.project_root(), "common", "function_coordinate.jl"))
FC = FunctionCoordinate

p = SVector(1.0, 2.0, 3.0)
spherical = FC.pc2sphere(p)       # (r, colatitude θ, azimuth ϕ), angles in radians
p_back = FC.sphere2pc(spherical)
FC.pc2sphere([1.0, 2.0, 3.0])     # a regular length-3 vector is accepted too
FC.MAVEN_sphere2xyz(SVector(1.0, 0.0, 0.0)) # MAVEN angles are degrees: elevation from XY, azimuth from +X toward +Y

points = [SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0)]
spheres = FC.pc2sphere.(points)   # one scalar call per point
P = [1.0 0.0 0.0; 0.0 1.0 0.0] # each row is one point
P_spherical = map(i -> FC.pc2sphere(view(P, i, :)), axes(P, 1))

θ = π / 2
q = Rotations.QuatRotation(cos(θ / 2), 0.0, 0.0, sin(θ / 2))
v = SVector(1.0, 0.0, 0.0)
v_rotated = q * v                # active +90° rotation about +Z
v_restored = inv(q) * v_rotated
R = Rotations.RotMatrix(q)       # static 3×3 matrix for the same rotation
v_matrix = R * v                 # matrix acting on a column vector
```

`q * v` and `R * v` act on column vectors. A coordinate transformation should state that `R_source_to_target` maps components from the source basis to the target basis; multiplication syntax alone does not establish its direction. For row-stored `N×3` points, if the column-vector relation is `p_target = R_source_to_target * p_source`, then `P_target = P_source * transpose(R_source_to_target)`; the inverse is `P_source = P_target * R_source_to_target` for a real orthogonal rotation. Standard `pc2sphere` uses radian colatitude; MAVEN instrument spherical coordinates use degree elevation. See the [coordinate conversions guide](docs/src/coordinates.md) for all conventions.

The package metadata entry points can be used without loading the MAVEN reader:

```julia
using MarsData
MarsData.project_root()
MarsData.maven_data_root()
MarsData.data_model()     # MAVEN product registry
MarsData.load_index()     # returns an empty dictionary if the index is absent
```

Call these functions with the `MarsData.` qualifier. Data roots come from configuration; the product registry is `MAVEN_data/MAVEN_data_format.json`, and the file index is `MAVEN_data/filename_lists.json`.

## Configuration and data paths

Edit `config/settings.toml` as the shared Python and Julia path configuration; the full-parameter template is [`config/settings.example.toml`](config/settings.example.toml). The old `download_data/MAVEN_download_config.ini` is deprecated and is no longer read. To initialize a missing settings file, run `python download_data/initialize_download_parameters.py`; it creates the file only when absent and preserves existing settings. Python-only server, download mode, thread count, and date-window options also live in this TOML, and are used only by Python download workflows.

Set non-empty `paths.maven_data_root`, `tw_data_root`, and `mgs_data_root`. Values containing only whitespace are rejected; other path values retain leading and trailing spaces. Absolute paths retain their platform meaning; relative paths are resolved from the repository root, independent of the process working directory. The optional `fortran_dll_dir` defaults to the repository root when empty. Julia reads and caches settings when the Paths module loads; if `settings.toml` is missing, it reports the initialization command instead of choosing a machine-specific drive.

Python 3.11 or later is required. Python runtime and optional build dependencies are listed in `pyproject.toml`; `spacepy` is optional for derived CDF building. See the [project workflow](docs/src/pipeline.md) for configuration, downloads, and indexing.

Julia's `Project.toml` lists direct dependencies of the main `MarsData` environment, including the plotting stack. `Pkg.instantiate()` installs dependencies for that project environment; it does not automatically provide every external reader, plugin, or standalone extra dependency. The full MAVEN reader requires its runtime environment to resolve packages such as `CommonDataFormat`, `JLD2`, and `FortranFiles`. Instrument-processing modules also use packages such as `TimesDates`, `DataInterpolations`, and `Rotations`. Prepare dependencies for the modules you use; successful package loading does not imply that every module dependency is installed.

The current `MAVEN_STATIC`, `MAVEN_SWIA`, and `MAVEN_SWEA` sources do not import `CommonDataFormat`; they can process an input data dictionary. The CDF-reading `MAVEN_load` module still needs the relevant CDF and file-format dependencies. `models/extras/Graham.jl` and `Octree.jl` are explicitly included standalone code; their external dependencies are listed in `models/CATALOG.toml` and are not part of the main MarsData dependency list.

## Minimal data-reading example

This example passes one `DateTime` (one day) and a currently registered product name. Before running it, configure the local data root, create or refresh the file index, and make the reader's external dependencies available in the Julia environment. It does not download data or validate a local DLL.

```julia
using Dates
using MarsData

MarsData.@load MAVEN_load
day = DateTime(2014, 12, 20)
data = MAVEN_load.load_MAVEN_data(day; model_index = ["MAG_pc1s_cdf"])
mag = data["MAG_pc1s_cdf"]

if get(mag, :data_load_flag, false)
    B = mag[:B]          # magnetic-field components, nT; product time axis is epoch
    t = mag[:epoch]      # DateTime time series
end
```

The reader returns one dictionary per product, with `:filename` and `:data_load_flag` on success; a missing or failed product has a failure flag. Product names, formats, and dictionary keys are described in the [data-reading guide](docs/src/data_reading.md) and [data-format reference](docs/src/data_format.md). General conventions: time axes are sorted time series; position is in km, magnetic field in nT, energy in eV, and mass axes in AMU. Coordinate frames and special field units follow the product and function; PC products must not be treated as MSO.

## Module loading and whitelists

`MarsData.load_module(name)` loads a module from the registry. `MarsData.@load Name...` binds module names at the caller's top level. Ordinary modules are evaluated in a runtime carrier and then bound as aliases into `MarsData` or the caller's namespace; the source file is not directly included into `MarsData`. The loader prepares registered dependencies in order and reuses preloaded instances.

Only these names are imported into the caller as bare identifiers by the current `@load` whitelist:

| Module | Bare-name whitelist |
| --- | --- |
| `MarsCommon` | `searchsortednearest`, `e_energy2v`, `ion_energy2v` |
| `MAVEN_load` | `load_cdf`, `load_MAVEN_data` |
| `IGRF_calculate` | `IGRF_pc` |

Other modules have an empty whitelist: `@load` binds only the module name. A name being available through a fully qualified submodule path does not mean `@load` imports it as a bare identifier. Use `MarsData.MAVEN_plot.WaveSpectra_heatmap` with its full qualification. Inspect the registry with `MarsData.available_modules()`, `MarsData.module_info(:MAVEN_load)`, and `MarsData.validate_registry()`.

Common entries include `MAVEN_load`, `MAVEN_STATIC`, `MAVEN_SWIA`, `MAVEN_SWEA`, `IGRF_calculate`, `Cold_Plasma_Dispersion_Relation`, `Maxwellian_Distribution`, `Single_Particle_Orbit`, `MGS_load`, `TW_load`, `TW_MINPA`, and `SP_load`. Use `MarsData.available_modules()` as the authoritative list.

## MarsEnvironment, models, and standalone scripts

Mars environment geometry is implemented in `models/Mars_Environment.jl`; its module is `MarsEnvironment`. The canonical package instance is `MarsData.MarsEnvironment`, identical to `MarsData.MAVEN_plot.MarsEnvironment`. IGRF source is in `models/` (pure Julia, no external runtime dependency); the registered module is `IGRF_calculate`. The scientific-logic comparison baseline is `a09511aa7b88c874cefe8ca966c98aa267db9365`; this README does not claim that repository-wide behavior has been verified against it. Real-data validation is paused.

`analysis/Pickup_ion.jl` is the analysis-script entry point. Graham and Octree under `models/extras/` must be included explicitly as described for those standalone sources. They are not part of the general loader whitelist. Standalone scripts may depend on user-defined variables, specialized packages, or local data, so they are not no-side-effect quickstarts.

Removed entry points and renamed APIs are collected in the [migration guide](docs/src/migration.md). `CHANGELOG.md` and `docs/reports/` retain historical records and are not rewritten to follow path or API moves; historical reports are not the current interface specification. See the [architecture guide](docs/src/architecture.md) for module relationships and the [API index](docs/src/api.md) for source entry points.

## Plotting

The overview composition is `MarsData.plot_module`; common formatting helpers are `MarsData.TimeFormat` and `MarsData.remove_0_point!`. Plotting primitives live in `MarsData.MAVEN_plot`; use fully qualified names such as `MarsData.MAVEN_plot.sta_heatmap` and `MarsData.MAVEN_plot.WaveSpectra_heatmap`. Example sources are under `example/MAVEN_plot_sample/`; scripts may read local data and write images, so inspect their settings and side effects before running them.

The plotting API takes Makie figure objects and a loaded data dictionary. `using MarsData` does not re-export CairoMakie's `Figure`, `Axis`, or `save`:

```julia
using MarsData, CairoMakie
fig = Figure()
MarsData.plot_module(fig, time_range, data_dict)
save("overview.png", fig)
```

This snippet shows the call shape only. The plot requires a data dictionary with the products and keys expected by the function; consult the example source and [API index](docs/src/api.md) first.

## Documentation and generation

- [Documentation home](docs/src/index.md): Documenter page navigation.
- [Project workflow](docs/src/pipeline.md): environment, configuration, downloads, and indexing.
- [Data reading](docs/src/data_reading.md) · [Data format](docs/src/data_format.md): MAVEN reader and data structures.
- [Architecture](docs/src/architecture.md) · [Migration](docs/src/migration.md) · [API index](docs/src/api.md): module relationships, breaking migrations, and source entry points.
- [SWIA electron correction](docs/src/swia_electron.md): topic guide.

Documenter HTML and the Python Wiki are two outputs from the same `docs/src/` source set. Build the Documenter HTML with:

```bash
julia --project=docs docs/make.jl
```

Generate the API page source with:

```bash
julia --startup-file=no tools/generate_api.jl
```

Preview the Python Wiki output without publishing:

```bash
python3 tools/push_wiki.py --dry-run
```

See the [documentation maintenance guide](docs/README.md) for the separate documentation environment, generation checks, and publication steps.
