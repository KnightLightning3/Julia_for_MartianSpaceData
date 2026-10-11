<!-- <div align="center"> -->
<!-- <img src="./docs/images/icon.svg" alt="icon"/> -->

<h1 align="center">Julia Pkg for Mars</h1>

# Table of Contents
- [Introduction](#introduction)
- [Project Structure](#project-structure)
- [Downloading Data](#downloading-data)
- [Reading Data](#reading-data)
- [Mars Magnetic Field Model](#mars-magnetic-field-model)
- [Custom Data Description](#custom-data-description)
- [MAVEN Data Tips](#maven-data-tips)
- [Program and Function Wiki](#program-and-function-wiki)
- [ToDo List](#todo-list)

# Introduction

English / [简体中文](README.md)

This project provides tools for downloading, reading, processing, and visualizing Mars space science data, as well as calculating physical models. Data processing and scientific computing are primarily written in Julia; Python is mainly used for downloads and file maintenance, with a Fortran shared library accelerating selected magnetic-field calculations.

## Project Structure

| Directory/file | Purpose |
| --- | --- |
| `MAVEN_data/` | MAVEN readers, instrument processing, plotting, and data-format definitions |
| `MGS_data/`, `TW_data/` | MGS and Tianwen data readers and instrument processing |
| `download_data/` | MAVEN downloading, file checks, compression, and cleanup |
| `models/`, `Magnetic_Model/` | Plasma, particle-orbit, magnetic-field, and related calculations |
| `common/`, `support_data/` | Shared coordinate/physics utilities and external support-data readers |
| `calculate/` | Model calculation workflows and composition entry points |
| `example/` | Plotting and data-analysis examples |
| `doc/wiki/` | Data guides, format references, instrument topics, and the [program/function Wiki](doc/wiki/程序与函数Wiki.md) |
| `requirements.txt`, `requirement.jl` | Python and Julia dependency references |

See the [program and function Wiki](doc/wiki/程序与函数Wiki.md) for file responsibilities and function descriptions.

# Downloading Data

Use the Python scripts to download and maintain MAVEN data. Create a virtual environment and install the dependencies in `requirements.txt`:

```
pip install -r requirements.txt
```


For the first download, **you need to generate the initial configuration file**:

Run `download_data\initialize_download_parameters.py`.

After initialization, configure the server, save directory, date range, and data products for your environment. The downloader reads `download_data/MAVEN_download_config.ini`; this is a local runtime configuration and may not be present in the repository.

`download_data/MAVEN_download.py` downloads data from the configured server. After downloading, use `download_data/check_exist_files.py` to check local files, `download_data/compress_cdf.py` to compress CDF files, or `download_data/clean_files.py` to remove incomplete downloads.

After updating downloaded data, rerun `download_data/check_exist_files.py` to verify the local file inventory.

Available MAVEN external servers (may require VPN):
- USTC source, fast on-campus speed, server may not always be running, data may be incomplete: http://222.195.76.155:8000/MAVEN/
- UCLA source, stable server, no NGIMS data: https://pds-ppi.igpp.ucla.edu/data/
- LASP source, stable server: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- Berkeley source, similar format to LASP, default server for SPADES library, requires account credentials for a significant portion of the data, not directly accessible: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

Note that the file structure of https://pds-ppi.igpp.ucla.edu/data/ differs from the latter two, and it does not contain NGIM data.

# Reading Data

```
Data_Dict = MAVEN_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

This program requires a specific file tree structure, which is shared with the download section.

To reference in Julia:

```
include("path/MAVEN_data/MAVEN_load.jl")
include("path/IGRF_calculate.jl")
import .MAVEN_data_load
import .IGRF_calculate
```

For specific reading methods, refer to: [MAVEN_data_format.md](doc/wiki/MAVEN_data_format.md)

## Program and Function Wiki

Browse program responsibilities, primary entry points, and function descriptions in the [program and function Wiki](doc/wiki/程序与函数Wiki.md). The [SWIA electron correction notes](doc/wiki/swia_electron_correlated.md) are also available in the Wiki.

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