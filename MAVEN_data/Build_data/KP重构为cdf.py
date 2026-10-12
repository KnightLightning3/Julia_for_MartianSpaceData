"""将 MAVEN 官方 KP 文本数据整理并转换为项目读取格式。"""

import os
import io
import re
from datetime import datetime, timedelta
import numpy as np
import pandas as pd
from spacepy import pycdf
import configparser
import json
from collections import defaultdict


# ==================================================
# 1. 基础配置与路径动态解析（你提供的代码段）
# ==================================================
def get_list_from_ini(input_string):
    if input_string == "Null":
        return []
    if input_string == "None":
        return None
    stripped_string = input_string.replace(" ", "")
    items = stripped_string.split(",")
    return items


# 获取项目根目录
project_path = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
print(project_path)
# 读取数据格式 JSON 文件
with open(os.path.join(project_path, "MAVEN_data", "MAVEN_data_format.json"), "r", encoding="utf-8") as file:
    json_data = json.load(file)
# 读取目录文件
with open(os.path.join(project_path, "MAVEN_data", "filename_lists.json"), "r", encoding="utf-8") as file:
    json_list_data = json.load(file)
# 1. 加载 KP_vars.json 配置文件
with open(os.path.join(project_path, "MAVEN_data", "KP_vars.json"), 'r', encoding='utf-8') as f:
    kp_vars_all = json.load(f)
# 读取下载配置文件 INI
config_file_path = os.path.join(
    project_path, "download_data", "MAVEN_download_config.ini"
)
config_data = configparser.ConfigParser()
config_data.optionxform = str
config_data.read(config_file_path, encoding="utf-8")

save_dir = config_data["DEFAULT"]["Save_dir"]

# 变量名称配置文件
KP_COLUMN_DEFS = {
    1: {'var_name': 'epoch', 'desc': 'Time (UTC/SCET)', 'unit': '', 'format': 'yyyy-mm-ddThh:mm:ss', 'cdf_type': 'epoch', 'note': 'Four- to eight-sec cadence, all parameters on uniform time grid established by SWEA/SWIA/STATIC/LPW'},
    2: {'var_name': 'lpw_electron_density', 'desc': 'LPW Electron Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Derived from the LP sweep and when available from the plasma line'},
    3: {'var_name': 'lpw_electron_density_quality', 'desc': 'LPW Quality', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Minimum value'},
    4: {'var_name': 'lpw_electron_density_quality', 'desc': 'LPW Quality', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Maximum value'},
    5: {'var_name': 'lpw_electron_temperature', 'desc': 'LPW Electron Temperature', 'unit': 'K', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Derived from the LP sweep'},
    6: {'var_name': 'lpw_electron_temperature_quality', 'desc': 'LPW Quality', 'unit': 'K', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Minimum value'},
    7: {'var_name': 'lpw_electron_temperature_quality', 'desc': 'LPW Quality', 'unit': 'K', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Maximum value'},
    8: {'var_name': 'lpw_spacecraft_potential', 'desc': 'LPW Spacecraft Potential', 'unit': 'V', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Measured from the probe potentials'},
    9: {'var_name': 'lpw_spacecraft_potential_quality', 'desc': 'LPW Quality', 'unit': 'V', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Minimum value'},
    10: {'var_name': 'lpw_spacecraft_potential_quality', 'desc': 'LPW Quality', 'unit': 'V', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Maximum value'},
    11: {'var_name': 'lpw_e_field_wave_power_2_100_hz', 'desc': 'LPW E-field wave power (2 - 100 Hz)', 'unit': '(V/m)^2/Hz', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Integrated wave power from the onboard calculated FFT, frequencies important for wave heating'},
    12: {'var_name': 'lpw_e_field_wave_power_2_100_hz_quality', 'desc': 'LPW Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Range: 0-100, where 100 is the highest confidence level, use data with quality flag of 50 or above.'},
    13: {'var_name': 'lpw_e_field_wave_power_100_800_hz', 'desc': 'LPW E-field wave power (100 - 800 Hz)', 'unit': '(V/m)^2/Hz', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Integrated wave power from the onboard calculated FFT'},
    14: {'var_name': 'lpw_e_field_wave_power_100_800_hz_quality', 'desc': 'LPW Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Range: 0-100, where 100 is the highest confidence level, use data with quality flag of 50 or above.'},
    15: {'var_name': 'lpw_e_field_wave_power_800_1000_hz', 'desc': 'LPW E-field wave power (800 - 1000 Hz)', 'unit': '(V/m)^2/Hz', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Integrated wave power from the onboard calculated FFT'},
    16: {'var_name': 'lpw_e_field_wave_power_800_1000_hz_quality', 'desc': 'LPW Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Range: 0-100, where 100 is the highest confidence level, use data with quality flag of 50 or above.'},
    17: {'var_name': 'lpw_euv_euv_irradiance_0_1_7_0_nm', 'desc': 'LPW-EUV EUV irradiance (0.1 - 7.0 nm)', 'unit': 'W/m^2', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'EUV irradiance in the 0.1-7.0 nm bandpass'},
    18: {'var_name': 'lpw_euv_euv_irradiance_0_1_7_0_nm_quality', 'desc': 'LPW-EUV Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': '0 = good solar, 1 = occultation, 2 = no pointing info, 3 = Sun NOT fully in FOV, 4 = Sun NOT in FOV, 5 = windowed, 6 = eclipse, 7 = spare'},
    19: {'var_name': 'lpw_euv_euv_irradiance_17_22_nm', 'desc': 'LPW-EUV EUV irradiance (17 - 22 nm)', 'unit': 'W/m^2', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'EUV irradiance in the 17-22 nm bandpass'},
    20: {'var_name': 'lpw_euv_euv_irradiance_17_22_nm_quality', 'desc': 'LPW-EUV Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': '0 = good solar, 1 = occultation, 2 = no pointing info, 3 = Sun NOT fully in FOV, 4 = Sun NOT in FOV, 5 = windowed, 6 = eclipse, 7 = spare'},
    21: {'var_name': 'lpw_euv_euv_irradiance_lyman_alpha', 'desc': 'LPW-EUV EUV irradiance (Lyman-alpha)', 'unit': 'W/m^2', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'EUV irradiance in the Lyman-alpha bandpass'},
    22: {'var_name': 'lpw_euv_euv_irradiance_lyman_alpha_quality', 'desc': 'LPW-EUV Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': '0 = good solar, 1 = occultation, 2 = no pointing info, 3 = Sun NOT fully in FOV, 4 = Sun NOT in FOV, 5 = windowed, 6 = eclipse, 7 = spare'},
    23: {'var_name': 'swea_solar_wind_electron_density', 'desc': 'SWEA Solar wind electron density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Density of solar wind or magnetosheath electrons based on moments of the electron distribution after correcting for the spacecraft potenti'},
    24: {'var_name': 'swea_solar_wind_electron_density_quality', 'desc': 'SWEA Quality', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    25: {'var_name': 'swea_solar_wind_electron_temperature', 'desc': 'SWEA Solar wind electron temperature', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Temperature solar wind or magnetosheath electrons based on moments of the electron distribution after correcting for the spacecraft potent'},
    26: {'var_name': 'swea_solar_wind_electron_temperature_quality', 'desc': 'SWEA Quality', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    27: {'var_name': 'swea_electron_parallel_energy_flux_5_100_ev', 'desc': 'SWEA Electron parallel energy flux (5 - 100 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux parallel to the magnetic field vector (0-90 degrees pitch angle)'},
    28: {'var_name': 'swea_electron_parallel_energy_flux_5_100_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    29: {'var_name': 'swea_electron_parallel_energy_flux_100_500_ev', 'desc': 'SWEA Electron parallel energy flux (100 - 500 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux parallel to the magnetic field vector (0-90 degrees pitch angle)'},
    30: {'var_name': 'swea_electron_parallel_energy_flux_100_500_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    31: {'var_name': 'swea_electron_parallel_energy_flux_500_1000_ev', 'desc': 'SWEA Electron parallel energy flux (500 - 1000 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux parallel to the magnetic field vector (0-90 degrees pitch angle)'},
    32: {'var_name': 'swea_electron_parallel_energy_flux_500_1000_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    33: {'var_name': 'swea_electron_anti_parallel_energy_flux_5_100_ev', 'desc': 'SWEA Electron anti-parallel energy flux (5 - 100 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux anti-parallel to the magnetic field vector (90-180 degrees pitch angle)'},
    34: {'var_name': 'swea_electron_anti_parallel_energy_flux_5_100_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    35: {'var_name': 'swea_electron_anti_parallel_energy_flux_100_500_ev', 'desc': 'SWEA Electron anti-parallel energy flux (100 - 500 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux anti-parallel to the magnetic field vector (90-180 degrees pitch angle)'},
    36: {'var_name': 'swea_electron_anti_parallel_energy_flux_100_500_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    37: {'var_name': 'swea_electron_anti_parallel_energy_flux_500_1000_ev', 'desc': 'SWEA Electron anti-parallel energy flux (500 - 1000 eV)', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Electron energy flux anti-parallel to the magnetic field vector (90-180 degrees pitch angle)'},
    38: {'var_name': 'swea_electron_anti_parallel_energy_flux_500_1000_ev_quality', 'desc': 'SWEA Quality', 'unit': 'eV/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Statistical uncertainty,  (1 sigma),  not including systematic error.'},
    39: {'var_name': 'swea_electron_spectrum_shape_parameter', 'desc': 'SWEA Electron spectrum shape parameter', 'unit': 'dimensionless', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Energy spectrum shape parameter used to distinguish between ionospheric photoelectrons and solar wind electrons'},
    40: {'var_name': 'swea_electron_spectrum_shape_parameter_quality', 'desc': 'SWEA Quality', 'unit': 'dimensionless', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Unused column'},
    41: {'var_name': 'swia_h_density', 'desc': 'SWIA H+ density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Total ion density from SWIA onboard moment calculation, assuming 100% protons'},
    42: {'var_name': 'swia_h_density_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    43: {'var_name': 'swia_h_flow_velocity_mso_x', 'desc': 'SWIA H+ flow velocity MSO X', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Bulk ion flow velocity X-component from SWIA onboard moment calculation, assuming 100% protons'},
    44: {'var_name': 'swia_h_flow_velocity_mso_x_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    45: {'var_name': 'swia_h_flow_velocity_mso_y', 'desc': 'SWIA H+ flow velocity MSO Y', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Bulk ion flow velocity Y-component from SWIA onboard moment calculation, assuming 100% protons'},
    46: {'var_name': 'swia_h_flow_velocity_mso_y_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    47: {'var_name': 'swia_h_flow_velocity_mso_z', 'desc': 'SWIA H+ flow velocity MSO Z', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Bulk ion flow velocity Z-component from SWIA onboard moment calculation, assuming 100% protons'},
    48: {'var_name': 'swia_h_flow_velocity_mso_z_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    49: {'var_name': 'swia_h_temperature', 'desc': 'SWIA H+ temperature', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Scalar ion temperature from SWIA onboard moment calculation, assuming 100% protons'},
    50: {'var_name': 'swia_h_temperature_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    51: {'var_name': 'swia_solar_wind_dynamic_pressure', 'desc': 'SWIA Solar wind dynamic pressure', 'unit': 'nPa', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Ion dynamic pressure computed on the SWIA ground from density and velocity moments, assuming 100% protons'},
    52: {'var_name': 'swia_solar_wind_dynamic_pressure_quality', 'desc': 'SWIA Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Quality flag (0 = bad, 1 = good) indicating whether the distribution is well-measured and decommutation parameters are definite'},
    53: {'var_name': 'static_static_quality_flag', 'desc': 'STATIC STATIC Quality Flag', 'unit': 'dimensionless', 'format': 'F16.0', 'cdf_type': 'float', 'note': 'Integer flag bits, Valid=0, Flag=1, See KP SIS for bit descriptions (formatted as a float in order to include NaN values for data gaps)'},
    54: {'var_name': 'static_h_density', 'desc': 'STATIC H+ density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'H+ number density below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    55: {'var_name': 'static_h_density_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    56: {'var_name': 'static_o_density', 'desc': 'STATIC O+ density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O+ number density below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    57: {'var_name': 'static_o_density_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    58: {'var_name': 'static_o2_density', 'desc': 'STATIC O2+ density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ number density below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    59: {'var_name': 'static_o2_density_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    60: {'var_name': 'static_h_temperature', 'desc': 'STATIC H+ temperature', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'H+ RAM temperature below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    61: {'var_name': 'static_h_temperature_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    62: {'var_name': 'static_o_temperature', 'desc': 'STATIC O+ temperature', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O+ RAM temperature below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    63: {'var_name': 'static_o_temperature_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    64: {'var_name': 'static_o2_temperature', 'desc': 'STATIC O2+ temperature', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ RAM temperature below TBD altitude determined from APID c6 (32 energy x 64 mass) while in Ram or Conic modes'},
    65: {'var_name': 'static_o2_temperature_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    66: {'var_name': 'static_o2_flow_velocity_maven_app_x', 'desc': 'STATIC O2+ flow velocity MAVEN_APP X', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MAVEN_APP X-component of velocity below TBD altitude determined from APID c6 while in Ram or Conic mode'},
    67: {'var_name': 'static_o2_flow_velocity_maven_app_x_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    68: {'var_name': 'static_o2_flow_velocity_maven_app_y', 'desc': 'STATIC O2+ flow velocity MAVEN_APP Y', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MAVEN_APP Y-component of velocity below TBD altitude determined from APID ca while in Ram or Conic mode'},
    69: {'var_name': 'static_o2_flow_velocity_maven_app_y_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    70: {'var_name': 'static_o2_flow_velocity_maven_app_z', 'desc': 'STATIC O2+ flow velocity MAVEN_APP Z', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MAVEN_APP Z-component of velocity below TBD altitude determined from APID c8 while in Ram or Conic mode'},
    71: {'var_name': 'static_o2_flow_velocity_maven_app_z_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    72: {'var_name': 'static_o2_flow_velocity_mso_x', 'desc': 'STATIC O2+ flow velocity MSO X', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MSO X-component of velocity below TBD altitude while in Ram or Conic mode'},
    73: {'var_name': 'static_o2_flow_velocity_mso_x_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    74: {'var_name': 'static_o2_flow_velocity_mso_y', 'desc': 'STATIC O2+ flow velocity MSO Y', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MSO Y-component of velocity below TBD altitude while in Ram or Conic mode'},
    75: {'var_name': 'static_o2_flow_velocity_mso_y_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    76: {'var_name': 'static_o2_flow_velocity_mso_z', 'desc': 'STATIC O2+ flow velocity MSO Z', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ MSO Z-component of velocity below TBD altitude while in Ram or Conic mode'},
    77: {'var_name': 'static_o2_flow_velocity_mso_z_quality', 'desc': 'STATIC Quality', 'unit': 'km/s', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    78: {'var_name': 'static_h_omni_directional_flux', 'desc': 'STATIC H+ omni-directional flux', 'unit': '(cm^2 s)^-1', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'H+ omni-directional flux above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    79: {'var_name': 'static_h_characteristic_energy', 'desc': 'STATIC H+ characteristic energy', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'H+ omni-directional characteristic energy above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    80: {'var_name': 'static_h_characteristic_energy_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    81: {'var_name': 'static_he_omni_directional_flux', 'desc': 'STATIC He++ omni-directional flux', 'unit': '(cm^2 s)^-1', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'He++ omni-directional flux above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    82: {'var_name': 'static_he_characteristic_energy', 'desc': 'STATIC He++ characteristic energy', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'He++ omni-directional characteristic energy above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    83: {'var_name': 'static_he_characteristic_energy_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    84: {'var_name': 'static_o_omni_directional_flux', 'desc': 'STATIC O+ omni-directional flux', 'unit': '(cm^2 s)^-1', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O+ omni-directional flux above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    85: {'var_name': 'static_o_characteristic_energy', 'desc': 'STATIC O+ characteristic energy', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O+ omni-directional characteristic energy above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    86: {'var_name': 'static_o_characteristic_energy_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    87: {'var_name': 'static_o2_omni_directional_flux', 'desc': 'STATIC O2+ omni-directional flux', 'unit': '(cm^2 s)^-1', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ omni-directional flux above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    88: {'var_name': 'static_o2_characteristic_energy', 'desc': 'STATIC O2+ characteristic energy', 'unit': 'eV', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'O2+ omni-directional characteristic energy above TBD altitude determined from APID c6 while in Pickup, Eclipse and Protect mode'},
    89: {'var_name': 'static_o2_characteristic_energy_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    90: {'var_name': 'static_h_characteristic_direction_mso_x', 'desc': 'STATIC H+ characteristic direction MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'H+ MSO X-direction of flux above TBD altitude determined from TBD APID while in Pickup and Scan mode'},
    91: {'var_name': 'static_h_characteristic_direction_mso_y', 'desc': 'STATIC H+ characteristic direction MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'H+ MSO Y-direction of flux above TBD altitude determined from TBD APID while in Pickup and Scan mode'},
    92: {'var_name': 'static_h_characteristic_direction_mso_z', 'desc': 'STATIC H+ characteristic direction MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'H+ MSO Z-direction of flux above TBD altitude determined from TBD APID while in Pickup and Scan mode'},
    93: {'var_name': 'static_h_characteristic_angular_width', 'desc': 'STATIC H+ characteristic angular width', 'unit': 'deg', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'H+ flux angular width above TBD altitude determined from TBD APID while in Pickup and Scan mode'},
    94: {'var_name': 'static_h_characteristic_angular_width_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    95: {'var_name': 'static_dominant_pickup_ion_characteristic_direction_mso_x', 'desc': 'STATIC Dominant pickup ion characteristic direction MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Dominant pickup ion MSO X-direction of flux above TBD altitude determined from  APID D0 and CE while in Pickup, Eclipse and Protect mode'},
    96: {'var_name': 'static_dominant_pickup_ion_characteristic_direction_mso_y', 'desc': 'STATIC Dominant pickup ion characteristic direction MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Dominant pickup ion MSO Y-direction of flux above TBD altitude determined from  APID D0 and CE while in Pickup, Eclipse and Protect mode'},
    97: {'var_name': 'static_dominant_pickup_ion_characteristic_direction_mso_z', 'desc': 'STATIC Dominant pickup ion characteristic direction MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Dominant pickup ion MSO Z-direction of flux above TBD altitude determined from  APID D0 and CE while in Pickup, Eclipse and Protect mode'},
    98: {'var_name': 'static_dominant_pickup_ion_characteristic_angular_width', 'desc': 'STATIC Dominant pickup ion characteristic angular width', 'unit': 'deg', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Dominant pickup ion flux angular width above TBD altitude determined from APID D0 and CE while in Pickup, Eclipse and Protect mode'},
    99: {'var_name': 'static_dominant_pickup_ion_characteristic_angular_width_quality', 'desc': 'STATIC Quality', 'unit': 'dimensionless', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Number of counts in the measurement'},
    100: {'var_name': 'sep_ion_flux_30_1000_kev_fov_1_f', 'desc': 'SEP Ion Flux (30-1000 keV), FOV 1-F', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of ions, integrated over the energy range 0.03-1.0 MeV'},
    101: {'var_name': 'sep_ion_flux_30_1000_kev_fov_1_f_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total ion flux, based on Poisson statistics'},
    102: {'var_name': 'sep_ion_flux_30_1000_kev_fov_1_r', 'desc': 'SEP Ion Flux (30-1000 keV), FOV 1-R', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of ions, integrated over the energy range 0.03-1.0 MeV'},
    103: {'var_name': 'sep_ion_flux_30_1000_kev_fov_1_r_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total ion flux, based on Poisson statistics'},
    104: {'var_name': 'sep_ion_flux_30_1000_kev_fov_2_f', 'desc': 'SEP Ion Flux (30-1000 keV), FOV 2-F', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of ions, integrated over the energy range 0.03-1.0 MeV'},
    105: {'var_name': 'sep_ion_flux_30_1000_kev_fov_2_f_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total ion flux, based on Poisson statistics'},
    106: {'var_name': 'sep_ion_flux_30_1000_kev_fov_2_r', 'desc': 'SEP Ion Flux (30-1000 keV), FOV 2-R', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of ions, integrated over the energy range 0.03-1.0 MeV'},
    107: {'var_name': 'sep_ion_flux_30_1000_kev_fov_2_r_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total ion flux, based on Poisson statistics'},
    108: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_1_f', 'desc': 'SEP Electron Flux (30 keV - 300 keV) - FOV 1-F', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of electrons, integrated over the energy range 30-300 keV'},
    109: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_1_f_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total electron flux, based on Poisson statistics'},
    110: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_1_r', 'desc': 'SEP Electron Flux (30 keV - 300 keV) - FOV 1-R', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of electrons, integrated over the energy range 30-300 keV'},
    111: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_1_r_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total electron flux, based on Poisson statistics'},
    112: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_2_f', 'desc': 'SEP Electron Flux (30 keV - 300 keV) - FOV 2-F', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of electrons, integrated over the energy range 30-300 keV'},
    113: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_2_f_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total electron flux, based on Poisson statistics'},
    114: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_2_r', 'desc': 'SEP Electron Flux (30 keV - 300 keV) - FOV 2-R', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Number flux of electrons, integrated over the energy range 30-300 keV'},
    115: {'var_name': 'sep_electron_flux_30_kev_300_kev_fov_2_r_quality', 'desc': 'SEP Quality', 'unit': '1/(cm^2 s sr)', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Standard uncertainty in total electron flux, based on Poisson statistics'},
    116: {'var_name': 'sep_look_direction_1_f_mso_x', 'desc': 'SEP Look direction 1-F MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of the center of the 1-F FOV, in MSO coordinates'},
    117: {'var_name': 'sep_look_direction_1_f_mso_y', 'desc': 'SEP Look direction 1-F MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of the center of the 1-F FOV, in MSO coordinates'},
    118: {'var_name': 'sep_look_direction_1_f_mso_z', 'desc': 'SEP Look direction 1-F MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of the center of the 1-F FOV, in MSO coordinates'},
    119: {'var_name': 'sep_look_direction_1_r_mso_x', 'desc': 'SEP Look direction 1-R MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of the center of the 1-R FOV, in MSO coordinates'},
    120: {'var_name': 'sep_look_direction_1_r_mso_y', 'desc': 'SEP Look direction 1-R MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of the center of the 1-R FOV, in MSO coordinates'},
    121: {'var_name': 'sep_look_direction_1_r_mso_z', 'desc': 'SEP Look direction 1-R MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of the center of the 1-R FOV, in MSO coordinates'},
    122: {'var_name': 'sep_look_direction_2_f_mso_x', 'desc': 'SEP Look direction 2-F MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of the center of the 2-F FOV, in MSO coordinates'},
    123: {'var_name': 'sep_look_direction_2_f_mso_y', 'desc': 'SEP Look direction 2-F MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of the center of the 2-F FOV, in MSO coordinates'},
    124: {'var_name': 'sep_look_direction_2_f_mso_z', 'desc': 'SEP Look direction 2-F MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of the center of the 2-F FOV, in MSO coordinates'},
    125: {'var_name': 'sep_look_direction_2_r_mso_x', 'desc': 'SEP Look direction 2-R MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of the center of the 2-R FOV, in MSO coordinates'},
    126: {'var_name': 'sep_look_direction_2_r_mso_y', 'desc': 'SEP Look direction 2-R MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of the center of the 2-R FOV, in MSO coordinates'},
    127: {'var_name': 'sep_look_direction_2_r_mso_z', 'desc': 'SEP Look direction 2-R MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of the center of the 2-R FOV, in MSO coordinates'},
    128: {'var_name': 'mag_magnetic_field_mso_x', 'desc': 'MAG Magnetic Field MSO X', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the X-direction in MSO coordinates'},
    129: {'var_name': 'mag_magnetic_field_mso_x_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    130: {'var_name': 'mag_magnetic_field_mso_y', 'desc': 'MAG Magnetic Field MSO Y', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the Y-direction in MSO coordinates'},
    131: {'var_name': 'mag_magnetic_field_mso_y_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    132: {'var_name': 'mag_magnetic_field_mso_z', 'desc': 'MAG Magnetic Field MSO Z', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the Z-direction in MSO coordinates'},
    133: {'var_name': 'mag_magnetic_field_mso_z_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    134: {'var_name': 'mag_magnetic_field_geo_x', 'desc': 'MAG Magnetic Field GEO X', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the X-direction in GEO coordinates'},
    135: {'var_name': 'mag_magnetic_field_geo_x_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    136: {'var_name': 'mag_magnetic_field_geo_y', 'desc': 'MAG Magnetic Field GEO Y', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the Y-direction in GEO coordinates'},
    137: {'var_name': 'mag_magnetic_field_geo_y_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    138: {'var_name': 'mag_magnetic_field_geo_z', 'desc': 'MAG Magnetic Field GEO Z', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Magnetic field vector component in the Z-direction in GEO coordinates'},
    139: {'var_name': 'mag_magnetic_field_geo_z_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    140: {'var_name': 'mag_magnetic_field_rms_deviation', 'desc': 'MAG Magnetic Field RMS Deviation', 'unit': 'nT', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Deviations from the mean magnitude of the magnetic field'},
    141: {'var_name': 'mag_magnetic_field_rms_deviation_quality', 'desc': 'MAG Quality', 'unit': 'dimensionless', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Unused column'},
    142: {'var_name': 'ngims_he_density', 'desc': 'NGIMS He Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    143: {'var_name': 'ngims_he_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    144: {'var_name': 'ngims_he_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    145: {'var_name': 'ngims_o_density', 'desc': 'NGIMS O Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    146: {'var_name': 'ngims_o_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    147: {'var_name': 'ngims_o_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    148: {'var_name': 'ngims_co_density', 'desc': 'NGIMS CO Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    149: {'var_name': 'ngims_co_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    150: {'var_name': 'ngims_co_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    151: {'var_name': 'ngims_n2_density', 'desc': 'NGIMS N2 Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    152: {'var_name': 'ngims_n2_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    153: {'var_name': 'ngims_n2_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    154: {'var_name': 'ngims_no_density', 'desc': 'NGIMS NO Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    155: {'var_name': 'ngims_no_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    156: {'var_name': 'ngims_no_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    157: {'var_name': 'ngims_ar_density', 'desc': 'NGIMS Ar Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    158: {'var_name': 'ngims_ar_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    159: {'var_name': 'ngims_ar_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    160: {'var_name': 'ngims_co2_density', 'desc': 'NGIMS CO2 Density', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    161: {'var_name': 'ngims_co2_density_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    162: {'var_name': 'ngims_co2_density_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'IV - Inbound Verified, IU - Inbound Unverified, OV - Outbound Verified, OU - Outbound Unverified, UR - Unreliable'},
    163: {'var_name': 'ngims_ion_density_amu_32', 'desc': 'NGIMS Ion Density - amu 32+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    164: {'var_name': 'ngims_ion_density_amu_32_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    165: {'var_name': 'ngims_ion_density_amu_32_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    166: {'var_name': 'ngims_ion_density_amu_44', 'desc': 'NGIMS Ion Density - amu 44+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    167: {'var_name': 'ngims_ion_density_amu_44_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    168: {'var_name': 'ngims_ion_density_amu_44_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    169: {'var_name': 'ngims_ion_density_amu_30', 'desc': 'NGIMS Ion Density - amu 30+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    170: {'var_name': 'ngims_ion_density_amu_30_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    171: {'var_name': 'ngims_ion_density_amu_30_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    172: {'var_name': 'ngims_ion_density_amu_16', 'desc': 'NGIMS Ion Density - amu 16+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    173: {'var_name': 'ngims_ion_density_amu_16_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    174: {'var_name': 'ngims_ion_density_amu_16_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    175: {'var_name': 'ngims_ion_density_amu_28', 'desc': 'NGIMS Ion Density - amu 28+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit of CO+ and N2+ are both mass 28, only combined density as key parameter'},
    176: {'var_name': 'ngims_ion_density_amu_28_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    177: {'var_name': 'ngims_ion_density_amu_28_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    178: {'var_name': 'ngims_ion_density_amu_12', 'desc': 'NGIMS Ion Density - amu 12+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    179: {'var_name': 'ngims_ion_density_amu_12_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    180: {'var_name': 'ngims_ion_density_amu_12_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    181: {'var_name': 'ngims_ion_density_amu_17', 'desc': 'NGIMS Ion Density - amu 17+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    182: {'var_name': 'ngims_ion_density_amu_17_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    183: {'var_name': 'ngims_ion_density_amu_17_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    184: {'var_name': 'ngims_ion_density_amu_14', 'desc': 'NGIMS Ion Density - amu 14+', 'unit': 'cm^-3', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Abundance or upper limit'},
    185: {'var_name': 'ngims_ion_density_amu_14_precision', 'desc': 'NGIMS Precision', 'unit': '%', 'format': 'E16.2', 'cdf_type': 'float', 'note': '% Error (1 sigma), if -1, the value is an upper limit'},
    186: {'var_name': 'ngims_ion_density_amu_14_quality', 'desc': 'NGIMS Quality', 'unit': '-', 'format': 'A16', 'cdf_type': 'char', 'note': 'SCP - SpaceCraft Potential available and used as computed by STATIC, SC0 - SpaceCraft potential not available'},
    187: {'var_name': 'spice_spacecraft_geo_x', 'desc': 'SPICE Spacecraft GEO X', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'X-component of spacecraft in GEO coordinates (same as IAU_MARS in SPICE)'},
    188: {'var_name': 'spice_spacecraft_geo_y', 'desc': 'SPICE Spacecraft GEO Y', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Y-component of spacecraft in GEO coordinates (same as IAU_MARS in SPICE)'},
    189: {'var_name': 'spice_spacecraft_geo_z', 'desc': 'SPICE Spacecraft GEO Z', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Z-component of spacecraft in GEO coordinates (same as IAU_MARS in SPICE)'},
    190: {'var_name': 'spice_spacecraft_mso_x', 'desc': 'SPICE Spacecraft MSO X', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'X-component of spacecraft in MSO coordinates (analogous to GSE coordinates at Earth)'},
    191: {'var_name': 'spice_spacecraft_mso_y', 'desc': 'SPICE Spacecraft MSO Y', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Y-component of spacecraft in MSO coordinates (analogous to GSE coordinates at Earth)'},
    192: {'var_name': 'spice_spacecraft_mso_z', 'desc': 'SPICE Spacecraft MSO Z', 'unit': 'km', 'format': 'E16.2', 'cdf_type': 'float', 'note': 'Z-component of spacecraft in MSO coordinates (analogous to GSE coordinates at Earth)'},
    193: {'var_name': 'spice_spacecraft_geo_longitude', 'desc': 'SPICE Spacecraft GEO Longitude', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': "Longitudinal component of MAVEN's location with respect to Mars"},
    194: {'var_name': 'spice_spacecraft_geo_latitude', 'desc': 'SPICE Spacecraft GEO Latitude', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': "Latitudinal (areodetic) component of MAVEN's location with respect to IAU Mars ellipsoid, equatorial radius of 3396.2 km, polar radius of"},
    195: {'var_name': 'spice_spacecraft_solar_zenith_angle', 'desc': 'SPICE Spacecraft solar zenith angle', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': "Angle measured from MAVEN to the geometric center of the Sun's disc, as described using a horizontal coordinate system"},
    196: {'var_name': 'spice_spacecraft_local_time', 'desc': 'SPICE Spacecraft local time', 'unit': 'hours', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'Local solar time of spacecraft location'},
    197: {'var_name': 'spice_spacecraft_altitude_w_r_t_ellipsoid', 'desc': 'SPICE Spacecraft altitude w.r.t. ellipsoid', 'unit': 'km', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'Altitude (areodetic) with respect to IAU Mars ellipsoid, equatorial radius of 3396.2 km, polar radius of 3376.2 km'},
    198: {'var_name': 'spice_spacecraft_attitude_geo_x', 'desc': 'SPICE Spacecraft attitude GEO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of spacecraft attitude (z-axis of MAVEN_SPACECRAFT frame) in GEO coordinates (same as IAU_MARS in SPICE)'},
    199: {'var_name': 'spice_spacecraft_attitude_geo_y', 'desc': 'SPICE Spacecraft attitude GEO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of spacecraft attitude (z-axis of MAVEN_SPACECRAFT frame) in GEO coordinates (same as IAU_MARS in SPICE)'},
    200: {'var_name': 'spice_spacecraft_attitude_geo_z', 'desc': 'SPICE Spacecraft attitude GEO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of spacecraft attitude (z-axis of MAVEN_SPACECRAFT frame) in GEO coordinates (same as IAU_MARS in SPICE)'},
    201: {'var_name': 'spice_spacecraft_attitude_mso_x', 'desc': 'SPICE Spacecraft attitude MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of spacecraft attitude  (z-axis of MAVEN_SPACECRAFT frame) in MSO coordinates (analogous to GSE coordinates at Earth)'},
    202: {'var_name': 'spice_spacecraft_attitude_mso_y', 'desc': 'SPICE Spacecraft attitude MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of spacecraft attitude  (z-axis of MAVEN_SPACECRAFT frame) in MSO coordinates (analogous to GSE coordinates at Earth)'},
    203: {'var_name': 'spice_spacecraft_attitude_mso_z', 'desc': 'SPICE Spacecraft attitude MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of spacecraft attitude  (z-axis of MAVEN_SPACECRAFT frame) in MSO coordinates (analogous to GSE coordinates at Earth)'},
    204: {'var_name': 'spice_app_attitude_geo_x', 'desc': 'SPICE APP Attitude GEO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in GEO coordinates'},
    205: {'var_name': 'spice_app_attitude_geo_y', 'desc': 'SPICE APP Attitude GEO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in GEO coordinates'},
    206: {'var_name': 'spice_app_attitude_geo_z', 'desc': 'SPICE APP Attitude GEO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in GEO coordinates'},
    207: {'var_name': 'spice_app_attitude_mso_x', 'desc': 'SPICE APP Attitude MSO X', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'X-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in MSO coordinates'},
    208: {'var_name': 'spice_app_attitude_mso_y', 'desc': 'SPICE APP Attitude MSO Y', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Y-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in MSO coordinates'},
    209: {'var_name': 'spice_app_attitude_mso_z', 'desc': 'SPICE APP Attitude MSO Z', 'unit': 'unit vector', 'format': 'F16.3', 'cdf_type': 'float', 'note': 'Z-component of pointing direction of Articulated Payload Platform (z-axis of MAVEN_APP_BP frame) in MSO coordinates'},
    210: {'var_name': 'spice_orbit_number', 'desc': 'SPICE Orbit Number', 'unit': 'dimensionless', 'format': 'I16', 'cdf_type': 'int', 'note': 'Orbit number increments each time MAVEN reaches geometric periapsis'},
    211: {'var_name': 'spice_inbound_outbound_flag', 'desc': 'SPICE Inbound/Outbound Flag', 'unit': 'dimensionless', 'format': 'A16', 'cdf_type': 'char', 'note': "Inbound ('I') is from geometric apoapsis to next geometric periapsis in time, outbound ('O') is the reverse"},
    212: {'var_name': 'spice_mars_season_ls', 'desc': 'SPICE Mars Season (Ls)', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'Martian solar longitude. Ls = 0 (northern spring equinox), Ls = 90 (northern summer solstice), etc.'},
    213: {'var_name': 'spice_mars_sun_distance', 'desc': 'SPICE Mars-Sun distance', 'unit': 'AU', 'format': 'F16.4', 'cdf_type': 'float', 'note': 'Distance from Mars to the Sun'},
    214: {'var_name': 'spice_subsolar_point_geo_longitude', 'desc': 'SPICE Subsolar Point GEO Longitude', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'GEO longitude of the sub-solar point'},
    215: {'var_name': 'spice_subsolar_point_geo_latitude', 'desc': 'SPICE Subsolar Point GEO Latitude', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'GEO latitude of the sub-solar point'},
    216: {'var_name': 'spice_sub_mars_point_on_the_sun_longitude', 'desc': 'SPICE Sub-Mars Point on the Sun, Longitude', 'unit': 'deg', 'format': 'F16.2', 'cdf_type': 'float', 'note': 'Solar longitude of the center of the Sun as seen from Mars'},
}
# kp_packed_groups.py
F32_MAX = np.finfo(np.float32).max
KP_PACKED_GROUPS = [
    # ---------- LPW 上下界（min / max） ----------
    {
        "var": "lpw_electron_density_quality",
        "cols": [3, 4],
        "sublabels": ["min", "max"],
        "desc": "LPW Electron Density Quality min/max",
        "unit": "cm^-3",
        "cdf_type": "float",
    },
    {
        "var": "lpw_electron_temperature_quality",
        "cols": [6, 7],
        "sublabels": ["min", "max"],
        "desc": "LPW Electron Temperature Quality min/max",
        "unit": "K",
        "cdf_type": "float",
    },
    {
        "var": "lpw_spacecraft_potential_quality",
        "cols": [9, 10],
        "sublabels": ["min", "max"],
        "desc": "LPW Spacecraft Potential Quality min/max",
        "unit": "V",
        "cdf_type": "float",
    },

    # ---------- SWIA H+ 速度三分量 ----------
    {
        "var": "swia_h_flow_velocity_mso",
        "cols": [43, 45, 47],
        "sublabels": ["x", "y", "z"],
        "desc": "SWIA H+ flow velocity MSO",
        "unit": "km/s",
        "cdf_type": "float",
    },
    {
        "var": "swia_h_flow_velocity_mso_quality",
        "cols": [44, 46, 48],
        "sublabels": ["x", "y", "z"],
        "desc": "SWIA H+ flow velocity MSO quality",
        "unit": "dimensionless",
        "cdf_type": "float",
    },

    # ---------- STATIC O2+ 速度三分量 ----------
    {
        "var": "static_o2_flow_velocity_maven_app",
        "cols": [66, 68, 70],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC O2+ flow velocity MAVEN_APP",
        "unit": "km/s",
        "cdf_type": "float",
    },
    {
        "var": "static_o2_flow_velocity_maven_app_quality",
        "cols": [67, 69, 71],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC O2+ flow velocity MAVEN_APP quality",
        "unit": "km/s",
        "cdf_type": "float",
    },
    {
        "var": "static_o2_flow_velocity_mso",
        "cols": [72, 74, 76],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC O2+ flow velocity MSO",
        "unit": "km/s",
        "cdf_type": "float",
    },
    {
        "var": "static_o2_flow_velocity_mso_quality",
        "cols": [73, 75, 77],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC O2+ flow velocity MSO quality",
        "unit": "km/s",
        "cdf_type": "float",
    },

    # ---------- STATIC 方向三分量 ----------
    {
        "var": "static_h_characteristic_direction_mso",
        "cols": [90, 91, 92],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC H+ characteristic direction MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "static_dominant_pickup_ion_characteristic_direction_mso",
        "cols": [95, 96, 97],
        "sublabels": ["x", "y", "z"],
        "desc": "STATIC dominant pickup ion characteristic direction MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },

    # ---------- SEP look direction 三分量 ----------
    {
        "var": "sep_look_direction_1_f_mso",
        "cols": [116, 117, 118],
        "sublabels": ["x", "y", "z"],
        "desc": "SEP look direction 1-F MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "sep_look_direction_1_r_mso",
        "cols": [119, 120, 121],
        "sublabels": ["x", "y", "z"],
        "desc": "SEP look direction 1-R MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "sep_look_direction_2_f_mso",
        "cols": [122, 123, 124],
        "sublabels": ["x", "y", "z"],
        "desc": "SEP look direction 2-F MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "sep_look_direction_2_r_mso",
        "cols": [125, 126, 127],
        "sublabels": ["x", "y", "z"],
        "desc": "SEP look direction 2-R MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },

    # ---------- MAG 磁场三分量 ----------
    {
        "var": "mag_magnetic_field_mso",
        "cols": [128, 130, 132],
        "sublabels": ["x", "y", "z"],
        "desc": "MAG magnetic field MSO",
        "unit": "nT",
        "cdf_type": "float",
    },
    {
        "var": "mag_magnetic_field_mso_quality",
        "cols": [129, 131, 133],
        "sublabels": ["x", "y", "z"],
        "desc": "MAG magnetic field MSO quality (unused)",
        "unit": "dimensionless",
        "cdf_type": "float",
    },
    {
        "var": "mag_magnetic_field_geo",
        "cols": [134, 136, 138],
        "sublabels": ["x", "y", "z"],
        "desc": "MAG magnetic field GEO",
        "unit": "nT",
        "cdf_type": "float",
    },
    {
        "var": "mag_magnetic_field_geo_quality",
        "cols": [135, 137, 139],
        "sublabels": ["x", "y", "z"],
        "desc": "MAG magnetic field GEO quality (unused)",
        "unit": "dimensionless",
        "cdf_type": "float",
    },

    # ---------- SPICE 飞船位置三分量 ----------
    {
        "var": "spice_spacecraft_geo",
        "cols": [187, 188, 189],
        "sublabels": ["x", "y", "z"],
        "desc": "Spacecraft position GEO",
        "unit": "km",
        "cdf_type": "float",
    },
    {
        "var": "spice_spacecraft_mso",
        "cols": [190, 191, 192],
        "sublabels": ["x", "y", "z"],
        "desc": "Spacecraft position MSO",
        "unit": "km",
        "cdf_type": "float",
    },

    # ---------- SPICE 飞船姿态三分量 ----------
    {
        "var": "spice_spacecraft_attitude_geo",
        "cols": [198, 199, 200],
        "sublabels": ["x", "y", "z"],
        "desc": "Spacecraft attitude GEO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "spice_spacecraft_attitude_mso",
        "cols": [201, 202, 203],
        "sublabels": ["x", "y", "z"],
        "desc": "Spacecraft attitude MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },

    # ---------- SPICE APP 姿态三分量 ----------
    {
        "var": "spice_app_attitude_geo",
        "cols": [204, 205, 206],
        "sublabels": ["x", "y", "z"],
        "desc": "APP attitude GEO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
    {
        "var": "spice_app_attitude_mso",
        "cols": [207, 208, 209],
        "sublabels": ["x", "y", "z"],
        "desc": "APP attitude MSO",
        "unit": "unit vector",
        "cdf_type": "float",
    },
]

PACKED_COLS = set()
for g in KP_PACKED_GROUPS:
    PACKED_COLS.update(g["cols"])

CDF_TYPE_TO_PYCDF = {
    "float": pycdf.const.CDF_FLOAT,
    "double": pycdf.const.CDF_DOUBLE,
    "int": pycdf.const.CDF_INT4,
    "char": pycdf.const.CDF_CHAR,
}

def download_model(model):
    """根据 KP 产品标识取得本地保存路径与文件名模式。"""
    global save_dir
    global json_data
    data_model = json_data["data_model"]
    model_key = {}
    for key, value in data_model.items():
        model_key[key] = value[:3]
    _, filename, pathname = model_key[model]
    save_path = save_dir + pathname
    return [save_path, filename]
def parse_kp_version(filename):
    """
    从 KP 文件名解析版本号字符串 (如 mvn_kp_insitu_20140318_v13_r03.tab -> '13')
    对应 Julia 中 file_in[end-9:end-8]
    """
    version_match = re.search(r'_v(\d+)_', filename)
    if version_match:
        return f"{int(version_match.group(1)):02d}"
    return "01"
def parse_kp_date(filename):
    """
    从 KP 文件名解析日期字符串 (如 mvn_kp_insitu_20140318_v13_r03.tab -> '20140318')
    """
    date_match = re.search(r'_(\d{8})_', filename)
    if date_match:
        return date_match.group(1)  # '20140318'
    return None

def pick_and_clean_kp_files(mode_kp_files, mode_cdf_files):
    """
    使用 json_list_data 中的文件列表，按日期比较 KP 源文件和 KP_cdf 的版本：
      - 同一日期下 KP 源文件有多个版本：保留最高版，删除其余低版源文件；
      - 对应日期的 KP_cdf 已存在且版本 >= KP版本：跳过该日期（不处理），打印 warning；
      - 对应日期的 KP_cdf 版本 < KP版本：删除旧 cdf，打印提示，继续生成；
      - 无对应 cdf：正常处理生成。
    mode_kp_files = json_list_data[key]  （KP 源文件完整路径列表）
    mode_cdf_files = json_list_data["KP_cdf"]  （已有 KP_cdf 文件完整路径列表）
    返回待处理的 KP 源文件完整路径列表。
    """
    kp_files = mode_kp_files
    cdf_files = mode_cdf_files

    # 按日期分组 KP 文件
    groups = defaultdict(list)
    no_date_files = []
    for f in kp_files:
        basename = os.path.basename(f)
        date_str = parse_kp_date(basename)
        if date_str:
            groups[date_str].append(f)
        else:
            no_date_files.append(f)

    selected = []
    for date_str, files in groups.items():
        # 按版本号排序，最高的排最后
        files_sorted = sorted(
            files,
            key=lambda f: int(parse_kp_version(os.path.basename(f)))
        )
        best_file = files_sorted[-1]
        best_ver = int(parse_kp_version(os.path.basename(best_file)))

        # 从 mode_cdf_files 中找出该日期对应的所有 cdf 文件
        cdf_files_for_date = [
            cdf_f for cdf_f in cdf_files
            if os.path.basename(cdf_f).endswith('.cdf') and f'_{date_str}_' in os.path.basename(cdf_f)
        ]

        should_process = True
        for cdf_path in cdf_files_for_date:
            cdf_basename = os.path.basename(cdf_path)
            existing_ver = int(parse_kp_version(cdf_basename))
            if existing_ver >= best_ver:
                # cdf 版本 >= KP 版本，跳过该日期
                print(
                    f"warning {date_str}日期的KP版本较低（v{best_ver:02d} - v{existing_ver:02d}）"
                )
                should_process = False
                break
            else:
                # cdf 版本 < KP 版本，删除旧 cdf
                os.remove(cdf_path)
                print(
                    f"{date_str}日期的cdf版本较低（v{existing_ver:02d} - v{best_ver:02d}）"
                )

        if not should_process:
            # 跳过该日期的处理，清理该日期所有 KP 源文件（包括最高版，因为 cdf 已是最新）
            for old_file in files_sorted:
                if os.path.exists(old_file):
                    os.remove(old_file)
                    print(f"  [删除低版本源文件] {os.path.basename(old_file)}")
            continue

        # 保留最高版本 KP 文件，删除同日期其他低版本源文件
        selected.append(best_file)
        for old_file in files_sorted[:-1]:
            if os.path.exists(old_file):
                os.remove(old_file)
                print(f"  [删除低版本源文件] {os.path.basename(old_file)}")

    selected.extend(no_date_files)
    return selected
def build_kp_colspecs(total_cols=235):
    """
    构建 235 列的固定宽度字符切片坐标区间 [start, end)
    """
    colspecs = [(0, 19)]  # 第 1 列: 时间列 (19 字符)
    for k in range(1, total_cols):
        start = 16 * k + 3
        end = 16 * k + 19
        colspecs.append((start, end))
    return colspecs

def convert_kp_to_cdf(kp_file_path, output_cdf_path, gzip_level=1):
    filename = os.path.basename(kp_file_path)
    version_str = parse_kp_version(filename)

    print(f"⚡ 正在解析 KP 文件 (版本 v{version_str}): {filename} ...", end="\r")

    colspecs = build_kp_colspecs(total_cols=235)
    df = pd.read_fwf(
        kp_file_path,
        colspecs=colspecs,
        comment='#',
        header=None,
        dtype=str
    )

    raw_time_series = pd.to_datetime(df[0].str.strip(), errors='coerce')
    time_series = [t.to_pydatetime() for t in raw_time_series]
    ntime = len(time_series)

    if os.path.exists(output_cdf_path):
        os.remove(output_cdf_path)

    print(f"🛠️  写入 CDF (GZIP Level {gzip_level}): {os.path.basename(output_cdf_path[:-15])} ...", end="\r")

    with pycdf.CDF(output_cdf_path, "") as cdf:
        # 全局属性
        cdf.attrs["TITLE"] = "MAVEN Key Parameters (KP) Data"
        cdf.attrs["SOURCE_FILE"] = filename
        cdf.attrs["KP_VERSION"] = version_str
        cdf.attrs["CREATED_TIME"] = datetime.now().isoformat() + "Z"

        # 时间轴
        cdf["epoch"] = time_series
        cdf["epoch"].attrs["FIELDNAM"] = "Time line"
        cdf["epoch"].attrs["UNITS"] = "ms"

        unix_timestamps = np.array([dt.timestamp() for dt in time_series], dtype=np.float64)
        cdf.new(
            name="time_unix",
            data=unix_timestamps,
            type=pycdf.const.CDF_DOUBLE,
            recVary=True,
            compress=pycdf.const.GZIP_COMPRESSION,
            compress_param=gzip_level
        )
        cdf["time_unix"].attrs["FIELDNAM"] = "Unix Timestamp"
        cdf["time_unix"].attrs["UNITS"] = "s"
        cdf["time_unix"].attrs["DEPEND_0"] = "epoch"

        # 维度辅助变量
        cdf["compno_3"] = np.array([0, 1, 2], dtype=np.int8)
        cdf["compno_3"].attrs["FIELDNAM"] = "compno_3"
        cdf["compno_3"].attrs["DICT_KEY"] = "number"

        cdf["compno_2"] = np.array([0, 1], dtype=np.int8)
        cdf["compno_2"].attrs["FIELDNAM"] = "compno_2"
        cdf["compno_2"].attrs["DICT_KEY"] = "number"

        # xyz / minmax 标签
        cdf.new(name="xyz_labl", data=["x", "y", "z"], type=pycdf.const.CDF_CHAR,
                recVary=False, dims=[3])
        cdf["xyz_labl"].attrs["FIELDNAM"] = "xyz_labl"
        cdf["xyz_labl"].attrs["VAR_TYPE"] = "metadata"

        cdf.new(name="minmax_labl", data=["min", "max"], type=pycdf.const.CDF_CHAR,
                recVary=False, dims=[2])
        cdf["minmax_labl"].attrs["FIELDNAM"] = "minmax_labl"
        cdf["minmax_labl"].attrs["VAR_TYPE"] = "metadata"

        # ---------- 1) 标量列 ----------
        for col in range(2, 217):
            if col in PACKED_COLS:
                continue
            info = KP_COLUMN_DEFS.get(col)
            if col in PACKED_COLS:  # 打包列
                continue
            if not info:
                continue

            var_name = info["var_name"]
            cdf_type = info["cdf_type"]
            # fmt = info["format"]
            desc = info["desc"]
            unit = info["unit"]

            raw_col = df[col - 1].str.strip()

            if cdf_type == "char":
                data_arr = raw_col.fillna("").tolist()
                pycdf_type = pycdf.const.CDF_CHAR
            elif cdf_type == "int":
                num_col = pd.to_numeric(raw_col, errors='coerce')
                data_arr = num_col.fillna(-9999).values.astype(np.int32)
                pycdf_type = pycdf.const.CDF_INT4
            elif cdf_type == "double":
                num_col = pd.to_numeric(raw_col, errors='coerce')
                data_arr = num_col.fillna(np.nan).values.astype(np.float64)
                pycdf_type = pycdf.const.CDF_DOUBLE
            else:  # float
                num_col = pd.to_numeric(raw_col, errors='coerce')
                # 关键步骤：在转 float32 之前，把 > 3.4e38 的异常填充值（如 9.99999E+38）清洗为 NaN
                num_col = num_col.mask(num_col.abs() > F32_MAX, np.nan)    
                data_arr = num_col.fillna(np.nan).values.astype(np.float32)
                pycdf_type = pycdf.const.CDF_FLOAT

            cdf.new(
                name=var_name,
                data=data_arr,
                type=pycdf_type,
                recVary=True,
                compress=pycdf.const.GZIP_COMPRESSION,
                compress_param=gzip_level
            )
            cdf[var_name].attrs["FIELDNAM"] = var_name
            cdf[var_name].attrs["CATDESC"] = desc
            cdf[var_name].attrs["UNITS"] = unit
            cdf[var_name].attrs["DEPEND_0"] = "epoch"

        # ---------- 2) 打包列 ----------
        for group in KP_PACKED_GROUPS:
            var_name = group["var"]
            cols = group["cols"]
            sublabels = group["sublabels"]
            desc = group["desc"]
            unit = group["unit"]

            data_cols = []
            for col in cols:
                raw_col = df[col - 1].str.strip()
                num_col = pd.to_numeric(raw_col, errors='coerce')
                data_cols.append(num_col.fillna(np.nan).values.astype(np.float32))

            data_arr = np.column_stack(data_cols).astype(np.float32)  # (N, len(cols))
            ndim = len(cols)

            cdf.new(
                name=var_name,
                data=data_arr,
                type=pycdf.const.CDF_FLOAT,
                recVary=True,
                dims=[ndim],
                compress=pycdf.const.GZIP_COMPRESSION,
                compress_param=gzip_level
            )
            cdf[var_name].attrs["FIELDNAM"] = var_name
            cdf[var_name].attrs["CATDESC"] = desc
            cdf[var_name].attrs["UNITS"] = unit
            cdf[var_name].attrs["DEPEND_0"] = "epoch"
            if ndim == 3:
                cdf[var_name].attrs["DEPEND_1"] = "compno_3"
                cdf[var_name].attrs["LABL_PTR_1"] = "xyz_labl"
            elif ndim == 2 and sublabels == ["min", "max"]:
                cdf[var_name].attrs["DEPEND_1"] = "compno_2"
                cdf[var_name].attrs["LABL_PTR_1"] = "minmax_labl"
            else:
                cdf[var_name].attrs["DEPEND_1"] = "compno_3"
                cdf[var_name].attrs["LABL_PTR_1"] = "xyz_labl"

        # ---------- 3) 旋转矩阵 ----------
        pc2ss_raw = df.iloc[:, 217:226].apply(pd.to_numeric, errors='coerce').values.astype(np.float32)
        pc2ss_matrix = pc2ss_raw.reshape(ntime, 3, 3)
        cdf.new(name="pc2ss_Matrix", data=pc2ss_matrix, type=pycdf.const.CDF_FLOAT,
                recVary=True, dims=[3, 3],
                compress=pycdf.const.GZIP_COMPRESSION, compress_param=gzip_level)
        cdf["pc2ss_Matrix"].attrs["FIELDNAM"] = "Planetocentric to MSO Matrix"
        cdf["pc2ss_Matrix"].attrs["DEPEND_0"] = "epoch"
        cdf["pc2ss_Matrix"].attrs["DEPEND_1"] = "compno_3"
        cdf["pc2ss_Matrix"].attrs["DEPEND_2"] = "compno_3"

        sc2ss_raw = df.iloc[:, 226:235].apply(pd.to_numeric, errors='coerce').values.astype(np.float32)
        sc2ss_matrix = sc2ss_raw.reshape(ntime, 3, 3)
        cdf.new(name="sc2ss_Matrix", data=sc2ss_matrix, type=pycdf.const.CDF_FLOAT,
                recVary=True, dims=[3, 3],
                compress=pycdf.const.GZIP_COMPRESSION, compress_param=gzip_level)
        cdf["sc2ss_Matrix"].attrs["FIELDNAM"] = "Spacecraft to MSO Matrix"
        cdf["sc2ss_Matrix"].attrs["DEPEND_0"] = "epoch"
        cdf["sc2ss_Matrix"].attrs["DEPEND_1"] = "compno_3"
        cdf["sc2ss_Matrix"].attrs["DEPEND_2"] = "compno_3"

    print(f"✅ 完成转换: {os.path.basename(output_cdf_path)}")

if __name__ == "__main__":

    key = "KP"
    if key in json_list_data:
        print(f"\n=====正在处理数据类别: {key}，共 {len(json_list_data[key])} 个文件=====",end="\r")
        mode_kp_dir,_ = download_model(key)
        mode_cdf_dir,_ = download_model("KP_cdf")

        mode_kp_files = json_list_data[key]
        mode_cdf_files = json_list_data["KP_cdf"]
        kp_files = pick_and_clean_kp_files(mode_kp_files, mode_cdf_files)
        count = 0
        for txt_file in kp_files:
            if txt_file[:-4] == ".cdf":
                continue
            count += 1
            print(f"处理文件{os.path.basename(txt_file)} {count}/{len(kp_files)}...", end="\r")
            output_cdf_path = os.path.join(mode_cdf_dir, txt_file[:-4] + "_compressed.cdf")
            new_file_path = os.path.join(mode_cdf_dir, txt_file[:-4] + ".cdf")

            if os.path.exists(new_file_path):
                continue
            if not os.path.exists(os.path.dirname(new_file_path)):
                os.makedirs(os.path.dirname(new_file_path))
            convert_kp_to_cdf(mode_kp_dir+txt_file, output_cdf_path, gzip_level=4)
            os.replace(output_cdf_path, new_file_path)