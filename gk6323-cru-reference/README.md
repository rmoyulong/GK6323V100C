# GK6323V100C CRU（时钟复位控制器）参考资料

## 一、资料来源

- **海思 BSP 源码**：GitHub `84896150/HiSTBLinuxV100R005C00SPC060-Hi3798MV320`
  - `source/kernel/linux-4.4.y/drivers/hisilicon/clk/`
  - `source/kernel/linux-4.4.y/include/dt-bindings/clock/`
- **原厂设备树**：由真机 dtbo 分区镜像（DTB，9156 字节）反编译得到，非手工编写。

## 二、文件清单

| 文件 | 作用 |
| --- | --- |
| `clk-hisi.c` / `clk-hisi.h` | CRU 框架：把 CRG 偏移 + 门控位注册成标准 clock |
| `clk-hi3798mv310.c` | CRU 主表：逐项列出每个外设的 CRG 偏移 |
| `clk-hiusb2.c` | USB2 门控序列 + INNO USB PHY 初始化寄存器序列 |
| `clk-hifmc100.c` | FMC（NAND/eMMC 控制器）门控 |
| `reset-hisilicon.c` | 复位控制器：`<&cru 偏移 位>` 两参数的实现 |
| `hi3798mv310-clock.h` | CRG 寄存器偏移编号表（= 原厂时钟 ID） |
| `gk6323-stock.dts` | 原厂 GK6323V100C 设备树（反编译） |
| `dtb2dts.py` | 反编译脚本，可复用于其它原厂 dtbo |

## 三、核心结论

**GK6323V100C 的 CRU 与海思 Hi3798MV310 同源，寄存器偏移逐项一致，不需要"改成 GK6323 编号"。**

原厂 GK6323 设备树里每个外设引用的时钟 ID，与海思 `hi3798mv310-clock.h` 里的偏移完全相同：

| 外设 | 原厂 GK6323 设备树 | 海思 hi3798mv310 编号表 | 一致 |
| --- | --- | --- | --- |
| CRU 控制器 | `clock@f8a22000` | 基址 `f8a22000` | 是 |
| 红外 IR | `<0x3 0x384>` | `HIIR_CLK = 0x0384` | 是 |
| I2C0 | `<0x3 0x1ac>` | `HII2C_I2C0_CLK = 0x01AC` | 是 |
| I2C1 | `<0x3 0x1b0>` | `HII2C_I2C1_CLK = 0x01B0` | 是 |
| I2C2 | `<0x3 0x1b4>` | `HII2C_I2C2_CLK = 0x01B4` | 是 |
| SPI | `<0x3 0x70>` | `PERI_CRG28_SSP = 0x0070` | 是 |
| SPI 复位 | `resets = <0x3 0x70 0x1>` | `rstbit = BIT(1)` | 是 |

外设地址也一致：USB2 PHY `0xf9865000`、网卡 `0xf9c30000`、MDIO `0xf9c31100`、
串口 `0xf8b00000`、看门狗 `0xf8a2c000`。

## 四、USB2 门控位定义（可直接照抄）

**控制器寄存器 `PERI_CRG46_USB2CTRL`（偏移 0xB8）**

| 位 | 含义 |
| --- | --- |
| BIT(0) | USB2_BUS_CKEN 总线时钟门控 |
| BIT(1) | USB2_OHCI48M_CKEN |
| BIT(2) | USB2_OHCI12M_CKEN |
| BIT(3) | USB2_OTG_UTMI_CKEN |
| BIT(4) | USB2_HST_PHY_CKEN |
| BIT(5) | USB2_UTMI0_CKEN |
| BIT(6) | USB2_UTMI1_CKEN |
| BIT(12) | USB2_BUS_SRST_REQ 软复位请求 |
| BIT(13) | USB2_UTMI0_SRST_REQ |
| BIT(14) | USB2_UTMI1_SRST_REQ |
| BIT(16) | USB2_HST_PHY_SYST_REQ |
| BIT(17) | USB2_OTG_PHY_SYST_REQ |

**PHY 寄存器 `PERI_CRG47_USB2PHY`（偏移 0xBC）**

| 位 | 含义 |
| --- | --- |
| BIT(0) | USB2_PHY01_REF_CKEN 参考时钟 |
| BIT(4) | USB2_PHY01_SRST_REQ 掉电复位 |
| BIT(8) | USB2_PHY0_SRST_TREQ 端口0复位 |
| BIT(9) | USB2_PHY1_SRST_TREQ 端口1复位 |
| BIT(15) | USB2_PHY01_TEST_SRST_REQ |

**PHY 配置寄存器基址**：`0xf9865000`，端口 1 基址偏移 `+0x400`。
`clk-hiusb2.c` 里的 `inno_phy_config_2p()` 给出了完整的上电配置寄存器序列。

## 五、复位控制器格式

```
resets = <&cru 偏移 位>;
```

- `#reset-cells = <2>`
- 偏移取 16 位、位取 16 位
- assert（复位）= 该位置 1；deassert（解复位）= 该位清 0

## 六、注意

- 该 BSP 是 Hi3798MV320 的，不是 GK6323 的；能复用的是**时钟 IP 与编号体系**，
  芯片级差异（CPU 核、GIC、网卡地址）不可照搬。
- 门控位定义只有 SPI 复位位（BIT1）在原厂设备树里有直接佐证，其余位取自海思
  驱动源码；与 GK6323 逐位是否完全一致，需烧录后实测确认。
