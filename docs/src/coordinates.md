# 坐标转换与旋转

本页区分单点坐标转换、坐标系旋转和仪器角接口。名称相近不代表轴定义、角度单位或退化行为相同；使用前先确定输入表示什么、输出属于哪个坐标系。

## 通用三维点接口

`FunctionCoordinate` 定义于 `common/function_coordinate.jl`，**不在 `MarsData` 模块注册表中**。显式 include 后使用限定名：

```julia
using MarsData, StaticArrays
include(joinpath(MarsData.project_root(), "common", "function_coordinate.jl"))
FC = FunctionCoordinate

p = SVector(1.0, 2.0, 3.0)
s = FC.pc2sphere(p)
p2 = FC.sphere2pc(s)
```

`pc2sphere`、`sphere2pc` 的单点主接口分别接收和返回 `SVector{3}`；长度为 3 的 `AbstractVector{<:Real}` 可作适配输入，结果仍为 `SVector{3}`。长度不等于 3 时抛出 `DimensionMismatch`。这只是单点向量适配，不意味着接口接受一组普通数组坐标列。

同一单点输入/输出形状也适用于 `MAVEN_sphere2xyz`、`MAVEN_xyz2sphere`、`pa_xyz2sphere`、`pa_sphere2xyz`、`MINPA_sphere2xyz` 和 `MINPA_xyz2sphere`：主接口接收并返回 `SVector{3}`，长度恰为 3 的 `AbstractVector{<:Real}` 可作适配输入，长度不为 3 时抛出 `DimensionMismatch`。它们各自保留下面说明的角度、仪器方向和退化点约定。

点集合可在调用端逐点广播：

```julia
points = [SVector(1.0, 0.0, 0.0), SVector(0.0, 1.0, 0.0)]
spherical_points = FC.pc2sphere.(points)
```

每行一个点的 `N×3` 矩阵，用行循环或 `map` 将每行作为一个整体传入：

```julia
P = [1.0 0.0 0.0; 0.0 1.0 0.0]
spherical_rows = map(i -> FC.pc2sphere(view(P, i, :)), axes(P, 1))
```

不要写成 `FC.pc2sphere.(P[:, 1], P[:, 2], P[:, 3])`：函数的实参是一个三维点，而不是三个坐标列。

## 四套球坐标定义

### `FunctionCoordinate.pc2sphere` / `sphere2pc`

这对函数转换通用行星笛卡尔点和标准球坐标，角度为**弧度**。`pc2sphere` 返回 `(r, θ, ϕ)`：`θ` 是从 `+Z` 轴量起的余纬，`ϕ` 是 XY 平面内从 `+X` 朝 `+Y` 的方位角。半径使用 `hypot(x, y, z)`，角度分别使用 `acos(z/r)` 与 `atan(y, x)`；原点返回 `(0, NaN, 0)`，即余纬未定义、方位角沿用 `atan(0,0)` 的结果。逆变换按 `x = r sinθ cosϕ`、`y = r sinθ sinϕ`、`z = r cosθ` 计算。`hypot` 避免直接平方求和在极大或极小输入下上溢/下溢；相较平方和再开方，末位结果可能不同，不承诺逐位一致。

```julia
p = SVector(1.0, 0.0, 0.0)
s = FC.pc2sphere(p)          # (1, π/2, 0)
FC.sphere2pc(s)               # 回到 +X 方向
FC.pc2sphere([1.0, 0.0, 0.0]) # 普通长度 3 向量适配
```

它与 IGRF 模块内部标量 `pc2sphere(x, y, z)` / `sphere2pc(r, θ, ϕ)` 的公式与顺序一致，但公开入口不同：两个标量辅助函数不 `export`，也不在 `@load IGRF_calculate` 的 `allow` 白名单中；白名单只开放 `IGRF_pc`。用户通用点转换应使用 `FunctionCoordinate` 版本。`IGRF_pc` 需要外部 Fortran 运行资源，本页示例不加载它。

### `pa_xyz2sphere` / `pa_sphere2xyz`

这对俯仰角（投掷角 Pitch Angle）球坐标函数使用**角度制**。`θ` 是向量与 `+X` 轴的夹角，定义范围为 0° 至 180°；`ϕ` 是 Y-Z 平面内从 `+Y` 朝 `+Z` 量起的角。反算关系为 `x = r cosd(θ)`、`y = r sind(θ) cosd(ϕ)`、`z = r sind(θ) sind(ϕ)`。零向量正算返回 `(0, 0, 0)`。

```julia
pa = FC.pa_xyz2sphere(SVector(1.0, 0.0, 0.0)) # (1, 0°, 0°)
FC.pa_sphere2xyz(pa)
```

不要把这对函数与标准余纬定义互换；同一个角三元组通常代表不同方向。

### `MAVEN_sphere2xyz` / `MAVEN_xyz2sphere`

这对 MAVEN 仪器球坐标接口使用**角度制**，顺序为 `(r, theta, phi)`。`theta` 是从 XY 平面量起的仰角，`phi` 是 XY 平面内从 `+X` 朝 `+Y` 的方位角；正算为 `x = r cosd(theta) cosd(phi)`、`y = r cosd(theta) sind(phi)`、`z = r sind(theta)`。这组约定不同于标准 `pc2sphere` 的弧度制余纬，也不同于 PA 和 MINPA。

```julia
maven_xyz = FC.MAVEN_sphere2xyz(SVector(1.0, 0.0, 0.0)) # (1, 0°, 0°) -> +X
FC.MAVEN_xyz2sphere(maven_xyz)
FC.MAVEN_sphere2xyz([1.0, 0.0, 0.0]) # 普通长度 3 向量适配
```

同一输入 `SVector(1.0, 0.0, 0.0)` 经 MAVEN 正算得到 `(1, 0, 0)`，经 `MINPA_sphere2xyz` 则约为 `(0, 1, 0)`。两者不能合并为同一仪器接口。`MAVEN_xyz2sphere` 原点返回 `(0, NaN, 0)`（`phi` 按 `atan(0,0)` 为零）；MINPA 反算原点角度为 NaN，且 X 轴输入因横向投影为零而退化，轴上行为并不相同。

### `MINPA_sphere2xyz` / `MINPA_xyz2sphere`

这是天问一号 MINPA 仪器的视场/粒子速度约定，角度为**角度制**。正算先按视场定义作 `θ′ = 90° − θ`、`ϕ′ = 360° − ϕ` 镜像，再按函数中的分量符号反转得到粒子速度方向。它既不是标准余纬接口，也不等同于 `TW_data/TW_MINPA.jl` 的三标量弧度制接口。反算通过 X 轴投影 `r_st` 求角；输入在 X 轴上时 `r_st = 0`，计算会产生 NaN。这一退化行为保留，调用方应识别并过滤。

```julia
instrument = SVector(1.0, 45.0, 30.0) # (r, θ, ϕ)，仪器角为度
velocity_direction = FC.MINPA_sphere2xyz(instrument)
instrument_back = FC.MINPA_xyz2sphere(velocity_direction)
```

`TW_MINPA.MINPA_sphere2xyz(r, θ, ϕ)` 与 `TW_MINPA.MINPA_xyz2sphere(x, y, z)` 使用弧度；方向符号按该模块约定由调用方处理。不要把这些弧度接口与 `FunctionCoordinate.MINPA_*` 的角度制及内置符号处理混用。

## 旋转对象、矩阵与向量

`FunctionCoordinate.rotation_matrix(θ, φ)` 返回 `3×3 Matrix{Float64}`，构造 `Rz(φ)·Ry(θ)`，参数为弧度。`FunctionCoordinate.slice2d_cal_rot(v1, v2)` 返回 `RotMatrix{3}`，构造切片局部基底；其行列含义需结合函数定义的基底方向理解。这两个函数是**旋转矩阵构造器**，不是点转换函数，也不会仅凭返回类型声明 source/target 方向。

对列向量，旋转对象或矩阵可直接作用：

```julia
using Rotations, StaticArrays
θ = π / 2
q = Rotations.QuatRotation(cos(θ / 2), 0.0, 0.0, sin(θ / 2))
v = SVector(1.0, 0.0, 0.0)
v_rot = q * v                    # 绕 +Z 主动旋转 +90°，指向 +Y
v_back = inv(q) * v_rot         # 逆旋转

R = Rotations.RotMatrix(q)       # 同一旋转的静态 3×3 矩阵
R * v                            # 矩阵作用于列向量
transpose(R) * (R * v)          # 正交矩阵的逆作用
```

旧 `Quaternion_Rot` 与 `Quaternion_Rot_reverse` 包装已删除。直接使用 `Rotations.QuatRotation` 的 `q * v`、`inv(q) * v`，或用矩阵 `R * v`；不要继续调用已删除的包装名。

主动旋转描述向量相对固定基底转动；被动变换描述同一几何向量改用另一基底表达，二者可能使用互逆矩阵。具体方向由基底定义决定。请明确写出 `R_source_to_target` 并定义 `p_target = R_source_to_target * p_source`。不能只凭 `R*v`、`v*R` 或矩阵名称判断转换方向。

若列向量关系定义为 `p_target = R_source_to_target * p_source`，而点按行存于 `N×3` 矩阵，则：

```julia
P_source = [1.0 0.0 0.0; 0.0 1.0 0.0] # N×3
R_source_to_target = [0.0 -1.0 0.0; 1.0 0.0 0.0; 0.0 0.0 1.0]
P_target = P_source * transpose(R_source_to_target)
P_source_again = P_target * R_source_to_target
```

这里使用实数正交旋转的 `transpose(R) = inv(R)`。行存写法来自列向量关系的转置，不改变旋转本身的 source/target 定义。

## 静态类型与批量布局

`QuatRotation * SVector{3}` 和 `RotMatrix{3} * SVector{3}` 都可保持静态三维结果。若 `R` 是普通动态 `Matrix`，乘积可能返回动态向量；需要静态路径时，可用 `Rotations.RotMatrix(q)` 或在边界将已知的 3×3 数值矩阵转换成 `SMatrix{3,3}`。不要在逐点循环里重复构造相同的旋转。

批量结果可保留为 `Vector{SVector{3}}`；若已有下游 `N×3` 布局，可预分配输出并按行写入，避免反复切出动态小数组：

```julia
P = [1.0 2.0 3.0; -2.0 1.0 0.5]
output = similar(P)
for i in axes(P, 1)
    point = SVector(P[i, 1], P[i, 2], P[i, 3])
    result = FC.pc2sphere(point)
    output[i, 1] = result[1]
    output[i, 2] = result[2]
    output[i, 3] = result[3]
end
```

固定三维类型有助于编译器优化，但不意味着整个函数必然零分配。`pc2sphere`、`MAVEN_xyz2sphere`、`pa_xyz2sphere` 和 `MINPA_xyz2sphere` 用 `hypot` 计算半径，使平方求和易上溢/下溢的极值输入更稳健；与平方和再开方的路径相比，末位可能不同，不承诺逐位一致。`slice2d_cal_rot` 的叉积范数保持现有 `norm` 计算。分配量应在实际 Julia 版本、类型与调用方式下预热测量，不把返回静态向量等同于所有调用场景的性能保证。
