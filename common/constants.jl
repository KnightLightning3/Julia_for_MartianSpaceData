module constants

const e = 1.602176634e-19
const me = 9.1093837e-31
const mp = 1.67262192e-27
const μ0 = 4e-7 * π
const q2me = -e / me
const q2mp = e / mp

const RAD = π / 180.0
const RADG = 1.0 / RAD
const inv_RADG = RAD

const eV = e
const c = 3.0e8
const E0_electron_keV = 511.0
const KEV_PER_AMU = 938313.53
const AMU_TO_PROTON_MASS_RATIO = 1836.23
const me_eV_per_km_s2 = me * 1e6 / e
const mp_eV_per_km_s2 = mp * 1e6 / e
const mp_g = mp * 1e3
const erg_per_eV = e * 1e7

const G = 6.67430e-11
const k_B = 1.380649e-23
const M_Mars = 6.4169e23
const R_Mars = 3393.5
const inv_R_Mars = 1.0 / R_Mars

const M_to_Q_e = me / e
const M_to_Q_p = mp / e

end
