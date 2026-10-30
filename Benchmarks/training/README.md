# 棋形评估训练

运行时的 `InternationalDraughts/DraughtsPatterns.bin` 是本项目训练的 104,976 个 Int16 参数，209,952 字节。它拟合 16 个重叠 4×4 区域的普通子棋形；每个区域 8 个有效格，每格为空、白子、黑子，共 3^8 种配置。使用旋转并交换颜色后的特征做差，保证评分反对称。有王棋时仍使用手工评估。

教师为 [Scan 3.1](https://github.com/rhalbersma/scan)，固定提交 `7aae17e7b7bfc47744601afb1ee7655e18983ce5`。训练工具在本机运行该 GPLv3 引擎，生成约 50 万个局面及其**静态评分输出**；没有把 Scan 源码、二进制或原始权重文件复制到 App。学生模型的结构、拟合程序和运行时评估实现位于本项目。

`scan_samples.inc` 是仅供训练的适配代码，插入教师程序的初始化之后。固定随机种子 481516；每局前 8 半步随机走，此后 25% 随机走，其余从吃子静态搜索评分加噪声中选择。只记录无王且行棋方无强制吃子的局面。它是带探索的教师引导对弈采样，不是完整 Scan 比赛强度的自我对弈，也不是深度搜索标签。

拟合时删除重复棋盘，固定种子 90210 按唯一局面留出约 10% 作回归验证。训练目标为教师白方评分减去子力项，使用稀疏线性最小二乘、L2 正则和 120 次 LSMR 迭代。回归验证集与训练集没有完全相同的棋盘，但可能包含同局相邻位置；泛化棋力以另行生成的开局对战检验，不用回归误差宣称胜率。

拟合误差、数据与模型 SHA-256 见 [model-metadata.json](model-metadata.json)。评分单位中一普通子约为 100，模型导出时乘 20 并量化为小端 Int16，与 Swift 搜索的 2000 子力单位一致。

## 重现数据与模型

需要 clang++、Python、numpy、scipy。下面使用新的临时目录，不修改现有 App：

```sh
git clone https://github.com/rhalbersma/scan.git build/scan-reproduce
git -C build/scan-reproduce checkout 7aae17e7b7bfc47744601afb1ee7655e18983ce5
python3 Benchmarks/training/prepare_teacher.py build/scan-reproduce
make -C build/scan-reproduce/src -j8 CXX=clang++ \
  CXXFLAGS='-pthread -std=c++14 -fno-rtti -O3 -DNDEBUG' LDFLAGS='-pthread -O3'
(cd build/scan-reproduce && ./src/scan samples > ../scan-reproduced-samples.txt)
python3 Benchmarks/training/train_patterns.py \
  build/scan-reproduced-samples.txt build/reproduced-patterns.bin
```

训练耗时不计入每步预算。App 内仅加载本地约 205 KiB 的表并做整数查表求和，不需要 Python、Scan 或网络连接。不同数值库版本可能造成末位量化差异，重新训练后应重新执行拟合检查、单元测试和独立棋力验收，不能直接假定结果相同。
