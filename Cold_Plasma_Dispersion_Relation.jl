module Cold_Plasma_Dispersion_Relation

const me=9.10938215e-31  
const mp=1.672621637e-27
const RAD=1.0 / 180 * π
const eV=1.602176487e-19

global Nparticles
global Ω_n
global Π_2

function set_particles(ion_rate=[],ion_mass=[])
  ion_rate = ion_rate
  ion_mass = ion_mass
  particles= 1.0 ./ [1.0,ion_mass...]
  particles_rate = [1.0,ion_rate...]
  global Nparticles=length(particles)
  # 以电子回旋频率归一化  fce 为负值
  global Ω_n = fill(me/mp,Nparticles) ; Ω_n[1] = -1.0 ; Ω_n = Ω_n .* particles
  global Π_2 = fill(me/mp,Nparticles) ; Π_2[1] = 1.0 ; Π_2 = Π_2  .* particles_rate .* particles
end

function Dispersion_Relation(θ,freq,Πe,Ωe)  #返回波矢，与frep一一对应.

  Πe_n = Πe / (-Ωe)
  freq_n = freq ./ (-Ωe) 
  Π_2_local = Π_2 * Πe_n^2 
  
  Nf = length(freq_n)
  wave_vector=zeros(Nf)

  for j = 1:Nf
    #计算介电常数
    R=1.0
    L=1.0
    P=1.0
    for i=1:Nparticles
      R=R-Π_2_local[i]/freq_n[j]^2*( freq_n[j] / (freq_n[j]+Ω_n[i]) )
      L=L-Π_2_local[i]/freq_n[j]^2*( freq_n[j] / (freq_n[j]-Ω_n[i]) )
      P=P-Π_2_local[i]/freq_n[j]^2
    end
    
    S=(R+L)/2.
    A=S*sin(θ)^2+P*cos(θ)^2
    B=R*L*sin(θ)^2+P*S*(1+cos(θ)^2)
    C=P*R*L
    D=(R-L)/2.
    #计算折光率μ  (μ^2=real)
    F=sqrt(abs(B^2 - A*C*4.))
    μ=[B+F,B-F]/2.0/A
    index_polar=sortperm( (μ .- S ) ./D )
    μ=μ[index_polar][2]
    μ=real(sqrt(complex(μ,0)))
    wave_vector[j]=μ* freq[j] / 3e8
  end
  return wave_vector
end
function minimum_energy(θ,freq,Ωe,wave_vector,n)
    v_para = (freq-n*Ωe)/wave_vector/cos(θ)
    Emin   = 0.5 * me * v_para^2 / eV
    return Emin
end
function carculate_minimum_energy(θ,freq,Πe,Ωe,n)
  #默认所有输入皆为分度制
  # if degree_measure
  #   θ*=RAD
  #   freq =freq*2*π
  #   Πe   =Πe*2*π
  #   Ωe   =Ωe*2*π
  # end
  NΠ=length(Πe)
  Nf=length(freq)
  Emin=zeros(Nf,NΠ)
  for j=1:NΠ
      wave_vector= Dispersion_Relation(θ,freq,Πe[j],Ωe)
      Emin[:,j] = minimum_energy.(θ,freq,Ωe,wave_vector,n)
  end
  return Emin
end

end