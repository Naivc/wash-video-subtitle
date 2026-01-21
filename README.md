# 🎬 Auto Subtitle Extractor & Sync (Emby Optimized)

这是一个专为 NAS 和媒体服务器（如 Emby/Plex/Jellyfin）设计的自动化脚本。它负责监控源目录，智能提取内封字幕，清洗视频流，并将处理后的“纯净版”同步到上传目录。

## ✨ 核心功能

* **🛡️ 非破坏性同步**：保留源文件不动，仅将处理后的文件生成到目标目录。
* **📥 智能字幕提取**：自动识别 MKV 内封字幕，按提取顺序重命名。
* **📝 严格命名规范**：生成的字幕严格遵循 `文件名.序号.语言.格式`（例如 `Movie.0.chi.ass`），确保播放器完美识别且不冲突。
* **🧹 视频物理清洗**：
    * **有内封字幕**：提取字幕 -> 剔除视频内的字幕流 -> 生成纯净 MKV。
    * **无内封字幕**：**直接硬链接 (Hard Link)**，极速同步，不占用额外空间。
* **🔗 外部字幕同步**：源目录已有的外挂字幕（.ass/.srt）会自动硬链接到目标目录。
* **🧠 智能防重复机制**：
    * 使用 `.processed_history.log` 记录已处理文件。
    * 即使目标目录文件被外部程序删除，脚本也不会重复处理源文件（防止死循环）。
* **🗑️ 自动清理**：自动清理目标目录中的空文件夹。

## 📂 目录结构示例

假设源文件为 `/source/Anime/Naruto.mkv` (内含 2 条中文字幕)：

**处理前 (Source):**
```text
/source
└── Anime
    └── Naruto.mkv (内封字幕)
```
**处理后 (Dest):**
```text
/dest
└── Anime
    ├── Naruto.mkv        (无内封字幕纯净版)
    ├── Naruto.0.chi.ass  (第1条提取出的字幕)
    └── Naruto.1.chi.ass  (第2条提取出的字幕)
```
## ⚙️ 配置说明
打开脚本 move_sync.sh 顶部的配置区域进行修改：
```text
# 源目录 (只读权限即可)
SOURCE_DIR="/source"

# 目标目录 (上传/播放目录)
DEST_DIR="/dest"

# 需要提取的语言代码 (ISO 639-2)
# 支持: chi (中文), zho (中文), eng (英文), spa (西语), es (西语), jpn (日文), kor (韩文)
TARGET_LANGS="chi zho eng spa es jpn kor"

# 扫描间隔 (秒)
INTERVAL=60
```
### 🏷️ 命名逻辑详解
为了解决特殊字符干扰和文件名冲突，本脚本采用严格序列命名法：

格式：`[文件名].[提取序号].[语言].[后缀]`

* **提取序号 (Order)：**从 `0` 开始递增。不依赖 MKV 原始轨道 ID，而是基于脚本提取的先后顺序。这保证了即使原始标题包含乱码或逗号，文件名依然清晰。

* **示例：**

  * 第一条中文字幕 -> `Filename.0.chi.ass`

  * 第二条西语字幕 -> `Filename.1.spa.srt`
### 🚀 部署与运行
* Linux 环境
* Docker compose
```text
version: "3"
services:
  move-worker:
    image: linuxserver/ffmpeg:latest
    container_name: sub_move_worker
    restart: unless-stopped
    entrypoint: /bin/bash /script/move_sync.sh
    environment:
      - PUID=0 #根据情况自行修改
      - PGID=0 #根据情况自行修改
      - TZ=Asia/Shanghai
    volumes:
      - /volume2/media/整理目录:/source #监控目录。请自行修改
      - /volume2/media/上传目录:/dest #目标目录。请自行修改
      - ./move_sync.sh:/script/move_sync.sh
```
### ⚠️ 注意事项
* **历史记录文件**： 脚本会在 /source/.processed_history.log 生成一个隐藏文件，用于记录哪些视频已经处理过。

不要随意删除，否则脚本会重新扫描处理所有视频。

如果你想强制重新处理某个视频，请手动编辑该文件，删除对应的路径行。

* **硬链接限制**： 脚本对无字幕视频使用硬链接优化。硬链接要求 SOURCE_DIR 和 DEST_DIR 必须位于同一个磁盘分区/挂载点。如果跨硬盘，脚本会自动回退到普通复制模式（速度较慢）。
* **支持的格式**： 目前仅针对 .mkv 容器进行内封提取。对于 .mp4 等其他格式，建议直接作为纯净视频处理
