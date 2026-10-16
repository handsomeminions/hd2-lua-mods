# vendor/ —— 迁移所需的外部依赖（工作文件夹原本之外的东西）

这些本来是放在机器上的**固定位置**、或者需要联网/装 Go 才能重新获取的。
为了让「复制整个工作文件夹」就能在另一台机器接着干活，把它们收进来了。

脚本一律通过 `analysis/_env.py` **优先读这里**（其次读环境变量，最后才回落旧机器的绝对路径），
所以换机器、换盘符、换用户名都不影响。

| 目录 / 文件 | 是什么 | 体积 | 用途 |
| --- | --- | --- | --- |
| `hd2-lua-mod/` | **HD2 Lua Mod 技能包**（原在 `~/.workbuddy/skills/hd2-lua-mod`） | 196 KB | `tools/hd2_archive.py`（.patch 归档读写）、`tools/build_addon.py`（打包）、`tools/inspect_patch.py`、`references/`（大量实战案例与踩坑清单）、`SKILL.md` |
| `ref/` | 反编译产物 | 2.5 MB | `typelib_all.json`（全部类型的字段偏移/大小）、`typelib_all.json.enums`、`dl_type_names.txt`（类型哈希↔名字）、`dl_library.dl_typelib`（游戏自带类型库）、`parse_typelib.py`（生成上面几个的工具）、`datalib.go` |
| `filediver/datalibrary/` | **FileDiver 明文镜像**（原在某临时目录） | 7.4 MB | `*.go`（275 个，**每个组件每个字段的名字与注释**，由游戏 typelib 生成，是布局的权威）、`enum/`（枚举**名字**列表）、`generated_*.dl_bin`（19 个明文表：射弹/爆炸/伤害/…） |
| `community/data/` | **社区解好的 JSON**（shalzuth/HelldiversData） | 241 MB | `settings/`（战备/射弹/爆炸/伤害…已解成 JSON）、`entities/`（按组件类型分文件、键为实体哈希）、`enums/`、`components/`、`translations/English.json`（本地化字符串，用来把哈希翻成名字） |
| `community-data.zip` | 上面那 241 MB 的压缩包 | 7.8 MB | 迁移省体积用；`python vendor/restore.py` 还原 |
| `restore.py` | 还原脚本 | 4 KB | 把压缩副本解回 `community/data/` 与 `analysis/ref/generated_entities.dl_bin` |

> `generated_entities.dl_bin`（46 MB 的实体数据 blob）不在 vendor 里 —— 权威副本放在
> `analysis/ref/generated_entities.dl_bin`；它的压缩备份在
> `vendor/filediver/datalibrary/generated_entities.dl_bin.gz`（0.9 MB），
> 删掉前者后可用 `restore.py` 还原。

---

## 省体积迁移（可选）

想从 **314 MB** 压到 **~27 MB**：复制前删掉这两个（它们都有压缩替补）：

```
vendor/community/data/                        (241 MB → community-data.zip 7.8 MB)
analysis/ref/generated_entities.dl_bin        ( 45 MB → generated_entities.dl_bin.gz 0.9 MB)
```

到了新机器第一次使用前跑一次：

```bash
python vendor/restore.py          # 还原(已有则跳过)
python analysis/_env.py           # 自检：全部 OK 才算就绪
```

---

## 万一压缩包也丢了：怎么从上游重新拿

1. **FileDiver 明文镜像 + 字段名 Go 源码**（需要 Go）
   ```bash
   go mod download github.com/xypwn/filediver
   # 文件在 <GOMODCACHE>/github.com/xypwn/filediver@<ver>/datalibrary/
   #   generated_*.dl_bin        明文数据表(含 generated_entities.dl_bin)
   #   *.go                      每个组件的字段名与注释
   #   dl_library.dl_typelib     游戏自带的类型库
   ```
   再把 typelib 导成 JSON（`tools/dump_typelib/` 放进 FileDiver 源码树 `cmd/` 下跑）：
   ```bash
   go run ./cmd/dump_typelib -o typelib_all.json     # 注意: 别用 PowerShell 的 > 重定向(会写成 UTF-16)
   ```

2. **社区 JSON**（需要 git / 网络）
   ```bash
   git clone https://github.com/shalzuth/HelldiversData
   # 用 data/ 覆盖 vendor/community/data/
   ```

3. **技能包**：如果你在新账号里重新安装了这个技能，它会在 `~/.workbuddy/skills/hd2-lua-mod`；
   也可以直接继续用 `vendor/hd2-lua-mod/`（脚本已经优先指向它）。
