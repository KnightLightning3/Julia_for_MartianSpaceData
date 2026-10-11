# 基于Properties of Electron Distributions in the Martian Space Environment, Andreone, 2022的电子修正

前提: 
> Secondary electron contamination (electrons ejected when a high energy electron impacts an instrument or spacecraft surface) proves more difficult to remove since the population is a function of the instrument and spacecraft itself, and can overlap the primary population in energy. The interaction of energetic electrons with metal surfaces has been well documented, both experimentally and theoretically (Bouchard & Carette, 1980; Scholtz et al., 1996).

修正假设:
1. 总数和电子温度有关
   > The first assumption (deduced from SWEA measurements) is the total number of secondaries produced is directly correlated to the temperature of the ambient electron population. Thus a hotter plasma will produce more secondaries (which occurs in the Martian magnetosheath). This assumption is implemented in our algorithm through the secondary electron yield function, which quantifies how likely ambient electrons are at liberating secondary electrons from a given surface.  
   >第一个假设（从 SWEA 测量中推断出来）是产生的二次总数与环境电子群的温度直接相关。因此，较热的等离子体将产生更多的二次离子体（发生在火星磁层中）。这个假设在我们的算法中通过二次电子yield function实现，该函数量化了环境电子从给定表面释放二次电子的可能性。
2. 二级电子的能谱形状仅仅取决于散射表面,忽略背景散射电子
    > The second assumption is that the shape (how wide and where the peak energy is located, quantified through the secondary shape function S[E]) of the secondary spectrum depends only on the material of the surfaces emitting the secondaries (this assumption ignores backscattered electrons).


处理算法:  
1.  ---
对于特定温度, 二级电子的总数 $\propto$ total ambient differential electron flux $F = \int^{E_{max}}_{E_{e\phi_{sc}}}F_E(E')dE'$

$F_E$ : differential electron flux over energy

However, this expression should be modified since electrons at certain energies are more efficient at producing secondary electrons than other energies. The yield is a measure of this efficiency

加入一个屈服函数yield function $\delta(E')$来修正之

So the modified total flux is
$$
F = \int^{E_{max}}_{E_{e\phi_{sc}}}F_M(E')\delta(E')dE'
$$
$F_M$: original measured differential electron flux

此时二级电子的微分通量为:
$$
F_s= \epsilon FS(E)
$$

- $\epsilon$ : free parameter in the presented algorithm and is a  representation of how well we chose the yield.  
- S(E): secondary shape function. The functional form of S(E) is chosen so that $\int^{E_{max}}_{E_{e\phi_{sc}}}S(E')dE' = 1$  (normalized to unity). 

最终效果: 猜测一个二级电子的通量$F_S$, 然后从测量总通量$F_M$中减去, 得到结果 $F_a$

重复方法, 修正$F_s$, 直到 $F_a\sim F_{Mnew} = F_M + F_s$

注: 所有电子微分通量是能量的方程

We used a yield with a peak at 300 eV, which was decided upon after implementing the algorithm with different peak yield energies and determining which separated the ambient and secondary spectra most cleanly.

1. Make an initial guess at an energy that provides an approximate separation between ambient and secondary populations (which is denoted by $E_{cut}$)
2. Calculate $F_a = F_M - F_{0s}$
   1. where $F_{0s} = \epsilon S(E) \int^{E_{max}}_{E_{e\phi_{sc}}}F_M(E')\delta(E')dE'$ is the initial guess for the secondary differential electron flux integrated from $E_{cut}$
3. Next calculate $F_{M new} = F_a + F_s$
   1. If $F_{M new}$ < $F_M$ for all energies, then the algorithm has underestimated the secondary electron population and ε is increased. 
   2. Otherwise, the algorithm has overestimated the secondary population and ε is decreased.
4. Next calculate $F_{a} = F_M + F_s$
5. Repeat step 3, adjust the $\epsilon$ factor depending on whether the current secondary spectra is an over- or under-estimate of $F_s$
6. Repeat steps 4 and 5 until $Max(|F_{M new} − F_M|)$, the maximum difference between these two quantities, is below some threshold (for this study it was $10^3\ 1/(eVcm^{2}srs)$)