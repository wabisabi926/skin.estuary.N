# 皮肤 XML 扩展参数说明

本文列出本分支在 Kodi 基线上新增的皮肤 XML 标签、属性及用法。尺寸使用皮肤坐标，时间使用毫秒。

## 玻璃

玻璃属性写在 `image` 控件的 `<texture>` 或 `grouplist` 的 `<texturebackground>` 上。示例中的 `colors/white.png` 是皮肤自带的白色纹理。

```xml
<texture material="glass" glassstyle="regular" cornerradius="32">colors/white.png</texture>
```

### 玻璃类型

| `glassstyle` | 效果区别 |
| --- | --- |
| `clear` | 最清透，背景细节保留较多，玻璃感轻盈 |
| `regular` | 适度模糊与透色，兼顾通透感和玻璃质感 |
| `frosted` | 比 regular 更朦胧，略带烟灰感，背景细节更柔和 |
| `dialog` | 比 frosted 更深、更不透明，背景干扰更少 |

### 基础属性

| 参数 | 取值范围 | 作用 |
| --- | --- | --- |
| `material` | `glass` | 启用玻璃；省略则使用普通纹理 |
| `glassstyle` | `clear` / `regular` / `frosted` / `dialog` | 选择玻璃类型；省略或未知值使用 regular |
| `glassedge` | `standard` / `soft` | standard 边缘反光更明确，soft 更柔和；默认 standard |

### 可选调节属性

省略时使用所选玻璃类型的默认效果；填写后只覆盖对应项目。

| 参数 | 调节范围 | 作用 |
| --- | --- | --- |
| `blurradius` | 0–128 | 基础模糊程度，越大越模糊；单位为皮肤坐标，不是百分比 |
| `glassprogressiveblur` | 0–10 | 上强下弱的额外模糊；0 关闭此效果 |
| `glassbackgroundopacity` | 0–1 | 底色混合比例，越大底色越明显；不是整个控件的不透明度 |
| `glassrefractionlevel` | 0–2 | 整体折射强度，越大背景弯曲越明显；0 关闭折射 |
| `glassbodyrefraction` | 0–2 | 中央区域的扭曲强度；0 仅保留边缘折射，仍受整体折射强度控制 |
| `glassspecularopacity` | 0–1 | 边缘反光强度，越大越明显；0 关闭反光混色 |
| `glassspecularsaturation` | 0–10 | 反光区域的色彩饱和度；0 为灰度，1 不额外增强，大于 1 增强色彩 |

## 圆角、描边与发光

写在 `<texture>`、`<texturefocus>`、`<texturenofocus>` 等纹理标签上，以下属性默认均为 `0`。

| 属性 | 取值范围 | 作用 |
| --- | --- | --- |
| `cornerradius` | ≥ 0 | 圆角半径；0 为直角，有效半径不超过形状短边的一半。普通纹理和玻璃均可使用 |
| `cornerinset` | 0–128 | 圆角形状向内收缩的距离，不改变控件尺寸和点击范围；实际内缩不超过短边的一半 |
| `cornerborder` | ≥ 0 | 描边宽度；大于 0 且小于圆角半径时只绘制轮廓，否则仍为填充形状 |
| `cornerglow` | ≥ 0 | 描边外侧的柔和光晕宽度；0 关闭，实际宽度不超过控件短边的一半 |

`cornerinset`、`cornerborder`、`cornerglow` 仅用于普通纹理，要求 `cornerradius > 0`；发光还要求 `0 < cornerborder < cornerradius`。光晕在控件范围内绘制，需要在四周预留相应空间。颜色与透明度沿用 Kodi 原有的 `colordiffuse`。

```xml
<texture cornerradius="24" cornerinset="4">colors/white.png</texture>
<texture cornerradius="14" cornerborder="2" cornerglow="12" colordiffuse="80FFFFFF">colors/white.png</texture>
```

纹理设置了 `diffuse` 蒙版时，玻璃及上述圆角相关属性均不生效。

## 列表扩展

### 自适应背景

在 `<control type="grouplist">` 内加入 `<texturebackground>`，背景沿排列方向跟随可见子控件占用的长度，并受列表边界限制；属性与普通纹理标签相同：

```xml
<texturebackground material="glass" glassstyle="regular" cornerradius="30">colors/white.png</texturebackground>
```

### 滚动与稳定选择

以下标签写在列表容器的 `<control>` 内，可用于 `list`、`fixedlist`、`wraplist`、`panel`、`slotlist`。

| 标签／属性 | 取值范围与默认值 | 作用 |
| --- | --- | --- |
| `<selectionsettledelay>` | 整数 ≥ 0，默认 0 | 更新稳定选中项前的等待时间；0 表示直接跟随当前选中项 |
| 上述标签的 `mode` 属性 | `adaptive`，默认固定等待 | 自适应模式下，单次切换立即更新，连续快滚期间保留原项，停止后更新 |
| `<holdscrollmaxspeed>` | ≥ 0，默认 0 | 长按方向键的滚动速度上限；列表单位为项/秒，面板为行或列/秒；0 表示使用自动速度 |
| `<holdscrolltargettime>` | 整数 ≥ 0，默认 7000 | 长按达到全速后遍历列表的目标时间，越小越快，仍受速度上限约束；0 恢复默认值 |

```xml
<selectionsettledelay mode="adaptive">150</selectionsettledelay>
<holdscrollmaxspeed>20</holdscrollmaxspeed>
<holdscrolltargettime>7000</holdscrolltargettime>
```

稳定选中项通过 `Container(控件ID).ListItemSettled` 读取，例如 `$INFO[Container(501).ListItemSettled.Art(fanart)]`。普通 `ListItem` 仍实时跟随焦点；自适应模式中的数值用于停止快滚后的等待，并非每次切换都延迟。

### 自定义排列：slotlist

将列表设为 `<control type="slotlist">`，布局、内容与导航标签沿用 `fixedlist`，并在控件内定义 `<slots>`。每个 `<slot>` 指定某个相对位置的外观，切换时在这些位置之间过渡：

```xml
<slots>
  <slot offset="-1" centerx="220" centery="260" width="180" height="270" opacity="70" dim="20" zorder="0" />
  <slot offset="0" centerx="450" centery="250" width="240" height="360" zorder="1" />
  <slot offset="1" centerx="680" centery="260" width="180" height="270" opacity="70" dim="20" zorder="0" />
</slots>
```

| `<slot>` 属性 | 取值范围与默认值 | 作用 |
| --- | --- | --- |
| `offset` | 整数，必填且不可重复 | 0 为选中项，负数为前面的项目，正数为后面的项目；必须包含 0 |
| `x` / `y` | 数值，默认 0 | 相对容器的左上角坐标 |
| `centerx` / `centery` | 数值，默认不指定 | 相对容器的中心坐标，分别优先于 `x` / `y` |
| `width` / `height` | ≥ 0，默认 0 | 项目的显示尺寸；0 或省略时使用 `itemlayout` 对应尺寸 |
| `opacity` | 0–100，默认 100 | 整个项目的不透明度 |
| `dim` | 0–100，默认 0 | 压暗程度；0 不压暗，100 为全黑 |
| `zorder` | 数值，默认按距离排列 | 越大越靠前；默认离选中项越近越靠前 |

## 动画扩展

新增 `ImageChange` 和 `Follow` 两种动画类型；单效果写在 `<animation>` 的文本中，多效果写在 `type` 属性中。

| 类型／属性 | 取值 | 作用 |
| --- | --- | --- |
| `ImageChange` | 动画类型 | 指定的 `image` / `multiimage` 控件显示新图时触发动画；需指定 `source` |
| `Follow` | 动画类型 | 同步另一控件中指定动画的当前效果；需指定 `source` 和 `animation`，不另设效果或时长 |
| `id` | 非空名称，可省略 | 给源动画命名，供 `Follow` 引用；同一控件内避免重名 |
| `source` | 正整数控件 ID | 指定来源控件 |
| `sourcewindow` | 数字窗口 ID，默认当前窗口 | 指定来源控件所在窗口 |
| `animation` | 源动画的 `id` | 指定 `Follow` 跟随的动画 |

```xml
<animation source="5090" effect="fade" start="0" end="100" time="300">ImageChange</animation>
```

在源控件（例如 ID 为 9090）内命名动画，在另一个控件内引用：

```xml
<animation id="focus-zoom" effect="zoom" start="100" end="104" time="250">Focus</animation>
```

```xml
<animation source="9090" sourcewindow="10000" animation="focus-zoom">Follow</animation>
```

`ImageChange` 的 `condition` 决定是否响应本次换图；`Follow` 的 `condition` 决定是否跟随。`Follow` 的源和目标应使用一致的坐标与缩放中心，且只跟随指定动画。

## 动态内容扩展

以下属性写在列表的动态 `<content>` 标签上，均使用 `true` / `false`：

| 属性 | 默认值 | 作用 |
| --- | --- | --- |
| `playbacktarget` | `false` | 将目录解析为实际待播放的单个条目，而非列出整个目录；需启用扩展交互 |
| `checkautoplaynextitem` | `false` | 从该列表发起播放时，遵循用户的自动播放下一项设置；需启用扩展交互 |
| `loaditemdetails` | `true` | 是否补充加载条目的详情与图片信息；false 仍保留内容源原本返回的信息 |
| `focusplaying` | `false` | 加载播放列表时，默认定位到正在播放的条目 |

```xml
<content loaditemdetails="false" focusplaying="true">playlistmusic://</content>
```

扩展交互通过皮肤 XML 目录中的 `SkinExtended.xml` 启用，文件内容为 `<window />`；它同时启用本分支的详情页、播放及文件管理等扩展交互。玻璃、圆角、列表排列和动画属性无需此文件。
