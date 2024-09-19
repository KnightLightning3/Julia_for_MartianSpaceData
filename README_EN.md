<!-- <div align="center"> -->
<!-- <img src="./docs/images/icon.svg" alt="icon"/> -->

<h1 align="center">Julia Pkg for Mars</h1>

# Introduction

[English](README_EN.md) / 简体中文

Mars data processing package

The main data processing program is primarily in Julia code

The download program is primarily in Python

# Reading Data

MAVEN data reading MAVEN_data_load.jl,


```
Data_Dict = MAVEN_data_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```


This program requires a specific file tree format for reading,  
which is shared with the download section

In Julia, the import method is:

```
include("path/MAVEN_data_load.jl")
include("path/IGRF_calculate.jl")
import .MAVEN_data_load
import .IGRF_calculate
```


# Downloading Data

Use the Python program, the method of downloading files is the same as in Julia  
If you don't want to manually download the corresponding packages, it is recommended to use a virtual environment, requirements.txt

```
pip install -r requirements.txt
```


For the first download, **you need to generate the initialization settings file first**:

Run 'download_data\initialize_download_parameters.py'

After completing the initialization of the settings file, modify 'download_data\MAVEN_download_config.ini' to adjust the download mode. The default mode is to download all data from 2014-10 to 2023-02 from the USTC source

'download_data\MAVEN_download.py' will download data files from the specified server. It is recommended to download from the USTC source (Server_ind = 0)

In addition, 'download_data\磁场重构.jl' and 'download_data\KP 重构.jl' can convert MAVEN official magnetic field and KP files into Fortran binary and JULIA binary files for reading

Available MAVEN external servers (may require VPN):
- USTC source, fast on-campus speed, server may not be running, data may not be complete: http://222.195.76.155:8000/MAVEN/
- UCLA source, stable server, no NGIMS data: https://pds-ppi.igpp.ucla.edu/data/
- LASP source, stable server: https://lasp.colorado.edu/maven/sdc/public/data/sci/
- Berkeley source, similar format to LASP, default server for SPADES library, a significant portion of the data requires an account and password, not directly accessible: http://sprg.ssl.berkeley.edu/data/maven/data/sci/

The file tree of https://pds-ppi.igpp.ucla.edu/data/ is different from the latter two, and there is no NGIM data

# Mars Magnetic Field Model

IGRF_calculate.jl
Calculate Mars simulated magnetic field using the IGRF model

Model source: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)

# ToDo list

- [x] Cloud MAVEN data
- [ ] Read all instruments
- [ ] Overview event plotting example
- [ ] Optimize CDF reading to instrument-specific mode (write the required variable list for each data package, remove unnecessary readings and PyObject judgments)
- [X] Modify the download program to allow download_data\get_download_files.py to automatically read the file directory to generate a list file
- [X] The download program can check the data version
- [x] Simple Julia plotting package
- [x] External file tree reading
- [ ] More magnetic field models
- [x] Tianwen data
- [x] Magnetic field line tracing
- [x] Adapt file tree to SPEDAS structure
- [x] MAVEN STATIC
- [X] Add flowchart for project initialization and file processing flow
- [ ] The processing function of STATIC currently only works for 4D data (time, mass, azimuth, energy), update to perform array operations after reshaping all values into the highest dimension array
      Update as needed

# MAVEN Data Tips

## STATIC Data:

- STATIC returns a 3D matrix data of (azimuth, energy, ion mass number) for each moment, corresponding to the energy, phi, theta, mass_arr matrices
- Scanning mode: STATIC has multiple different scanning modes, corresponding to different energy ranges, determined by the swd_ind parameter [0-26], corresponding to the last dimension of the energy, phi, theta, mass_arr matrices. In Julia, which starts counting from 1, the swd_ind parameter needs to be incremented by one
- Attenuator: The attenuator will multiply the low energy segment STA data below 15eV by (1., 1/10, 1/100, 1/1000) to prevent saturation, the official claim is that the replacement time will not be less than 5 minutes, however, some data can be explained by temporary saturation, and there is a switch attenuator
- The theta and phi returned by STATIC correspond to 90-theta and phi in spherical coordinates, in the instrument reference frame. The quaternions quat_mso and quat_sc in the file can be used to project the instrument reference frame to the mso and sc reference frames.