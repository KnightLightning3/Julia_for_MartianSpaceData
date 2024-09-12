# Introduction

English / [简体中文](README.md)

Mars Data Processing Program Package

The main data processing program is primarily in Julia code

The download program is primarily in Python

# Reading Data  
MAVEN data reading: MAVEN_data_load.jl,  


```
Data_Dict = MAVEN_data_load.data_get_from_date(Dates.format.(date, "yyyymmdd"), model_index = ["MAG_pc1s","LPW_wave"])
```

This program requires a specific file tree format for reading,  
which is shared with the download section  

In Julia, the reference method is:  
```
include("path/MAVEN_data_load.jl")  
include("path/IGRF_calculate.jl")  
import .MAVEN_data_load  
import .IGRF_calculate  
```



# Downloading Data  
Use the Python program, the download method is the same as in Julia  
If you don't want to manually download the corresponding packages, it is recommended to use a virtual environment, requirements.txt  
```
pip install -r requirements.txt
```
For the first download, **you need to generate the initialization settings file first**: 

Run 'download_data\initialize_download_parameters.py'

After completing the initialization of the settings file, modify 'download_data\MAVEN_download_config.ini' to adjust the download mode,  

'download_data\MAVEN_download_from_server.py' will download data files from the USTC server,  

'download_data\MAVEN_download.py' will download data files from the official MAVEN server,  

In addition, 'download_data\magnetic_field_reconstruction.jl' and 'download_data\KP_reconstruction.jl' can convert the magnetic field and KP files from the official MAVEN server into Fortran binary and JULIA binary files for reading  

# Mars Magnetic Field Model
IGRF_calculate.jl
Calculate the simulated Martian magnetic field using the IGRF model

Model source: [A Spherical Harmonic Martian Crustal Magnetic Field Model Combining Data Sets of MAVEN and MGS](https://agupubs.onlinelibrary.wiley.com/doi/10.1029/2021EA001860)  


# ToDo list
- [X]  Cloud MAVEN data  
- [ ]  Read all instruments  
- [ ]  Draw overview event example
- [ ]  Optimize CDF reading to instrument-specific mode (write the required variable list for each data package, remove unnecessary readings and PyObject judgments)
- [ ]  Modify the download program so that download_data\get_download_files.py can automatically read the file directory to generate a list file
- [X]  Simple Julia plotting package  
- [X]  External file tree reading  
- [ ]  More magnetic field models  
- [X]  TianWen data  
- [X]  Magnetic field line tracing  
- [X]  Adapt file tree to SPEDAS structure  
- [X]  MAVEN STATIC
- [ ] Add flowchart for project initialization and file processing flow
- [ ] The current processing function of STATIC can only work on 4D data (time, mass, azimuth, energy), it may need to be updated, but adding additional judgments or functions may affect readability, need to find a better way
Update as needed

# MAVEN Data Tips

## STATIC Data:
- STATIC returns a 3D matrix data of (azimuth, energy, ion mass number) at each moment, corresponding to the energy, phi, theta, mass_arr matrices
- Scanning mode: STATIC has multiple different scanning modes, corresponding to different energy ranges, determined by the swd_ind parameter [0-26], corresponding to the last dimension of the energy, phi, theta, mass_arr matrices. In Julia, a language that starts counting from 1, the swd_ind parameter needs to be incremented by one
- Attenuator: The attenuator will multiply the low energy segment STA data below 15eV by (1., 1/10, 1/100, 1/1000) to prevent saturation according to the specific situation. The official claim is that the replacement time will not be less than 5 minutes, but some data seems to be explained by temporary saturation
- The theta and phi returned by STATIC correspond to 90-theta and phi in spherical coordinates, under the instrument reference frame. The quaternions quat_mso and quat_sc in the file can be used to project the instrument reference frame to the mso and sc reference frames.er the instrument reference frame. The quaternions quat_mso and quat_sc in the file can be used to project the instrument reference frame to the mso and sc reference frames.