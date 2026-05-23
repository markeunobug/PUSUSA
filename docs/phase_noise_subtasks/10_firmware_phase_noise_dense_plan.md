# 子任务 10：固件相噪 offset 点表加密与上限评估

## 目标

让固件相噪引擎支持更密集的 offset 点表，并清楚处理点数上限、截断和性能风险。

## 先读

1. `docs/phase_noise_dense_points_plan.md`
2. `docs/phase_noise_protocol.md`
3. `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.c`
4. `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.h`
5. `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c`
6. `code/pusu_20260516/vitis/pusu_20260516/src/app_config.h`

## 修改范围

优先修改：

- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.c`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_plan.h`
- `code/pusu_20260516/vitis/pusu_20260516/src/phase_noise_engine.c/.h`
- 必要时更新 `docs/phase_noise_protocol.md`

不要修改：

- Vivado/Vitis `Debug/Release` 生成 makefile，除非用户明确要求。
- 旧工程 `code/pusu_test`。

## 实现要求

1. 评估是否把 `PHASE_NOISE_PLAN_MAX_POINTS` 从 `256` 提高到 `384`。
   - 说明 `phase_noise_plan_t.points[]` 和 `average_noise_mw[]` 的内存变化。
   - 如果内存可接受，直接提升上限。
   - 如果不提升，文档说明 Normal/Fine 的限制。
2. `phase_noise_plan_build()` 对点数截断必须可观测。
   - 当前只静默截断到 `PHASE_NOISE_PLAN_MAX_POINTS`。
   - 建议在 plan 中增加 `truncated` 或 warning 标志。
   - status 或 warning code 能让 Host 知道实际点数小于计划点数。
3. `points_per_decade` 校验保持清晰：
   - 当前上限为 `100`。
   - 若点数上限提高，仍建议保留 `100` 作为防误操作限制。
4. 维持 offset 对数分布和单调递增。
5. 不改变 `PHASE_NOISE_DATA(0x86)` 和 `PHASE_NOISE_STATUS(0x87)` 固定 payload 长度。

## 性能说明

在完成汇报中估算：

- 1 kHz 到 1 MHz：
  - 30 pts/dec -> 91 点
  - 60 pts/dec -> 181 点
  - 90 pts/dec -> 271 点
- 每点单帧 UART 回传，包数等于点数乘 average 轮次。
- 点数提高对测量耗时近似线性影响。

## 验收

运行固件语法检查：

```powershell
& 'C:\software\Xilinx\Vitis\2021.1\gnu\aarch32\nt\gcc-arm-none-eabi\bin\arm-none-eabi-gcc.exe' -mcpu=cortex-a9 -mfpu=vfpv3 -mfloat-abi=hard -Icode\pusu_20260516\vitis\pusu_20260516\src -Icode\pusu_20260516\vitis\pusu_20260516\mylib -Icode\pusu_20260516\vitis\pusu_20260516\mylib\dsp -Icode\pusu_20260516\vitis\system_wrapper\export\system_wrapper\sw\system_wrapper\standalone_ps7_cortexa9_0\bspinclude\include -Wall -Werror=implicit-function-declaration -O0 -fsyntax-only code\pusu_20260516\vitis\pusu_20260516\src\phase_noise_plan.c code\pusu_20260516\vitis\pusu_20260516\src\phase_noise_engine.c code\pusu_20260516\vitis\pusu_20260516\src\device_protocol.c code\pusu_20260516\vitis\pusu_20260516\src\main.c code\pusu_20260516\vitis\pusu_20260516\src\signal_processing.c code\pusu_20260516\vitis\pusu_20260516\src\sweep_plan.c
```

验收点：

- `points_per_decade=60`、`1 kHz..1 MHz` 应生成 `181` 点。
- 若支持 Fine，`points_per_decade=90` 应生成 `271` 点或明确 warning 截断。
- offset 单调递增。

## 完成汇报

汇报：

- 是否提升 `PHASE_NOISE_PLAN_MAX_POINTS`。
- 内存和耗时评估。
- 截断/警告机制。
- 已运行命令和结果。
