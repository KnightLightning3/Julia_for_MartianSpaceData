module Cold_Plasma_Dispersion_Relation

const me=9.10938215e-31  
const mp=1.672621637e-27
const RAD=1.0 / 180 * π
const eV=1.602176487e-19
const c=3e8
global Nparticles
global Ω_n
global Π_2
# 暂时只支持单解的波
#默认所有输入皆为分度制
function set_particles(;ion_rate=[],ion_mass=[])
  ion_rate = ion_rate
  ion_mass = ion_mass
  particles= 1.0 ./ [1.0,ion_mass...]
  particles_rate = [1.0,ion_rate...]
  global Nparticles=length(particles)
  # 以电子回旋频率归一化  fce 为负值
  global Ω_n = fill(me/mp,Nparticles) ; Ω_n[1] = -1.0 ; Ω_n = Ω_n .* particles
  global Π_2 = fill(me/mp,Nparticles) ; Π_2[1] = 1.0 ; Π_2 = Π_2  .* particles_rate .* particles
end

# set_particles(ion_rate=[0.4,0.6],ion_mass=[16,32]) / 默认值

function get_Πe(Ne; unit="Hz")
  Πe = sqrt(Ne)*8890.0
  if unit == "Hz"
    return Πe
  else 
    return Πe * 2 * π
  end
end

function Dispersion_Relation(θ,freq,Πe,Ωe)  #返回折光率,与frep一一对应.

  Πe_n = Πe / (-Ωe)
  freq_n = freq / (-Ωe) 
  Π_2_local = Π_2 * Πe_n^2 

  #计算介电常数
  R=1.0
  L=1.0
  P=1.0
  for i=1:Nparticles
    R=R-Π_2_local[i]/freq_n^2*( freq_n / (freq_n+Ω_n[i]) )
    L=L-Π_2_local[i]/freq_n^2*( freq_n / (freq_n-Ω_n[i]) )
    P=P-Π_2_local[i]/freq_n^2
  end
  
  S=(R+L)/2.
  A=S*sin(θ)^2+P*cos(θ)^2
  B=R*L*sin(θ)^2+P*S*(1+cos(θ)^2)
  C=P*R*L
  D=(R-L)/2.
  #计算折光率μ  (μ^2=real)
  F=sqrt(abs(B^2 - A*C*4.))
  μ=[B+F,B-F]/2.0/A
  # polar=(μ .- S ) ./D
  μm=max(μ[1],μ[2])
  μ=real(sqrt(complex(μm,0)))
  return μ
end

function DR_wave_vector(μ , freq)
  wave_vector=μ* freq / c
  return wave_vector
end

function DR_phase_velocity(μ)
  phase_velocity = c / μ
  return phase_velocity
end

function carculate_minimum_energy(θ,freq,Πe,Ωe,n)
  # 默认所有输入皆为分度制
  # 单点计算
  # if degree_measure
  #   θ*=RAD
  #   freq =freq*2*π
  #   Πe   =Πe*2*π
  #   Ωe   =Ωe*2*π
  # end
  # NΠ=length(Πe)
  # Nf=length(freq)
  # Emin=zeros(Nf,NΠ)

  μ = Dispersion_Relation(θ,freq,Πe,Ωe)
  wave_vector = DR_wave_vector(μ , freq)
  v_para = (freq-n*Ωe)/wave_vector/cos(θ)
  Emin   = 0.5 * me * v_para^2 / eV
  return Emin
end

end # module Cold_Plasma_Dispersion_Relation