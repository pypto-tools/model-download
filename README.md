# model-download

ModelScope 大模型下载 / 断点续传工具。共用一个独立 venv,幂等、断网自动重试、可定时。

## 安装

需要 Python 3.10+、`flock`，以及 GNU `coreutils`（定时窗口脚本还需要
`util-linux` 提供的 `ionice`）。

```bash
git clone https://github.com/doraemonmj/model-download.git
cd model-download
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## 目录内容

| 文件 | 说明 |
| ---- | ---- |
| `.venv/` | 独立 Python venv,装了 `modelscope`(不污染其它 conda env) |
| `download_model.sh` | **通用**下载脚本,任意模型复用(推荐) |
| `resume_deepseek_v4_flash.sh` | DeepSeek-V4-Flash 专用脚本(已配 02:00 cron) |
| `download-<slug>.log` | 每个模型独立日志 |
| `.download-<slug>.lock` | 每个模型独立 flock 锁,防重复跑 |

下载目标里会生成 `.download_complete` 标记,表示该模型已下完。

## 通用脚本用法

```bash
# 立刻下载(目标目录默认 /data/models/<模型名>)
./download_model.sh deepseek-ai/DeepSeek-V4-Flash

# 指定目标目录
./download_model.sh some-org/Some-Model /data/models/xxx
```

特性:

- **幂等续传** —— 已下完的文件跳过,只补缺失/残缺部分。
- **断网重试** —— 最多 20 次,每次间隔 60s。
- **单实例** —— 同一模型 flock 锁,手动跑和 cron 不会打架;不同模型可并行。
- **自动清理坑** —— 若下载目录里有别人(如 `yangyaodong`)以 `0600` 拥有、读写不了的 `.msc` 进度索引,会自动删除以便重建(modelscope 会重新校验已有文件,不会重下)。
- **完成标记** —— 全部下完写 `.download_complete`,再次运行直接空跑退出。

## 定时下载(cron)

```bash
crontab -e
# 加一行,例:每晚 02:30 续传直到下完
30 2 * * * /path/to/model-download/download_model.sh some-org/Some-Model
```

下完后记得删掉对应 cron 行。

## 校验完整性(下载完用)

```bash
# 完整校验:逐文件查"是否存在 + 大小 + sha256"(读全部字节,160GB 约几十分钟)
./verify_model.sh deepseek-ai/DeepSeek-V4-Flash

# 快速校验:只查存在性 + 大小(秒级)
./verify_model.sh deepseek-ai/DeepSeek-V4-Flash --quick
```

校验依据是 ModelScope 仓库 manifest 里每个文件的官方 `Size` / `Sha256`。
全部通过则退出码 0、打印 `OK: all N files present and verified.`;
有缺失 / 大小不符 / hash 不符则退出码 1 并逐条列出。建议下完先 `--quick`
扫一遍补齐缺失,再跑一次完整 sha256 校验确认无损坏。

## 看进度

```bash
tail -f download-<slug>.log          # slug = 模型 ID 把 / 和空格换成 _
# 例:tail -f download-deepseek-ai_DeepSeek-V4-Flash.log
```

## 注意事项

- **代理**:**下载不走代理**——modelscope.cn 是国内站,直连又通又快。脚本会清除 HTTP/HTTPS/ALL_PROXY 的大小写变量,设置 `NO_PROXY=*`,并把 endpoint 固定为 `https://modelscope.cn`。
- **公共读取**:通用下载脚本使用 `umask 0022`,下载到 `/data/models` 后所有本地用户都可读取模型文件。
- **磁盘**:模型下在 `/data`(7T,确认 `df -h /data` 有余量;V4-Flash 约 160 GB)。
- **速度**:使用 ModelScope 直连;160 GB 视带宽约需数小时到十几小时。
- **`.msc` 进度索引别乱删**:`<dest>/.msc` 是 modelscope 记录"哪些文件已下完"的索引(pickle 的 `[{Path,Revision},...]`)。删了它会导致**已完成的文件不被识别、全部重下**(那句 "re-validate" 提示只对索引里已有的条目生效)。只有当 `.msc` 属于别的用户、当前用户读写不了时才需要删,删后应按 final 目录里"大小==官方 Size"的文件重建索引,否则白下。
- **venv 维护**:升级 modelscope —— `source .venv/bin/activate && pip install -U modelscope`。

## 当前机器配置（2026-09-15）

- 仓库路径：`/home/pyptouser/mj/model-download`；使用本目录 `.venv`（ModelScope 1.37.0）。
- 模型来源：https://modelscope.cn/models/deepseek-ai/DeepSeek-V4.1-Flash
- 公共下载路径：`/srv/models/DeepSeek-V4.1-Flash`，所有本地用户可读取。
- 入口仍为 `download_deepseek_v4_flash_0731_window.sh`（保留旧文件名），
  调用现有 `download_model.sh`，北京时间 22:00 开始、08:00 停止，下一晚续传。
- 系统任务：`/etc/cron.d/model-download`，设置 `CRON_TZ=Asia/Shanghai`，
  内容为 `0 22 * * * mj /home/pyptouser/mj/model-download/download_deepseek_v4_flash_0731_window.sh`。
- 进度日志：仓库内 `download-deepseek-ai_DeepSeek-V4.1-Flash.log`；
  完成标记：下载目录内 `.download_complete`。
- 后续迁移只需调整夜间入口的 `MODEL`、`DEST`、`WINDOW_LOG` 和 cron 中的仓库路径；
  复用现有断点续传、重试和时间窗口逻辑。通用脚本默认仍为 `/data/models`，夜间入口显式传入上述公共路径。
