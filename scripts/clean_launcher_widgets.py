#!/usr/bin/env python3
"""精准清理 BBK 学习桌面 launcher.db 里的残留 appwidget 记录。

在电脑端运行，操作对象是 adb pull 出来的 launcher.db 副本。
默认只删除 appWidgetProvider 指向「已卸载学习包」的 widget；
--all-widgets 会删除四张学段表里全部 itemType=4 记录。

用法：
    python3 clean_launcher_widgets.py launcher.db --list
    python3 clean_launcher_widgets.py launcher.db
    python3 clean_launcher_widgets.py launcher.db --all-widgets
    python3 clean_launcher_widgets.py launcher.db --package com.example.foo

安全设计：先只读体检并打印待删清单，备份后才写，写完做 integrity_check。
推回设备后必须另外执行 chown / chmod / chcon，见 references/launcher-db.md。
"""

import argparse
import shutil
import sqlite3
import sys
from pathlib import Path

TABLES = (
    "PreschoolFavorites",
    "JuniorFavorites",
    "SeniorFavorites",
    "OnlineClassFavorites",
)

# 实机确认已卸载的学练机包，其 widget 一定是不可能显示的空壳。
DEFAULT_GONE_PACKAGES = (
    "com.eebbk.aimathlearning",
    "com.eebbk.synstudy",
    "com.eebbk.vtraining",
    "com.eebbk.synchinese",
    "com.eebbk.syncenglish",
    "com.eebbk.tutoringonline",
)


def inspect(db: sqlite3.Connection, all_widgets: bool, gone: tuple[str, ...]):
    """返回 {表名: [(id, screen, provider, title), ...]} 待删清单。"""
    cur = db.cursor()
    plan = {}
    for table in TABLES:
        try:
            cur.execute(
                f"SELECT _id, screen, appWidgetProvider, title FROM {table} "
                "WHERE itemType = 4 ORDER BY screen, _id"
            )
            rows = cur.fetchall()
        except sqlite3.Error as exc:
            print(f"[跳过] {table}: {exc}", file=sys.stderr)
            continue
        killed = []
        for row_id, screen, provider, title in rows:
            provider = provider or ""
            if all_widgets or any(pkg in provider for pkg in gone):
                killed.append((row_id, screen, provider, title))
        plan[table] = killed
    return plan


def main() -> int:
    ap = argparse.ArgumentParser(description="清理 BBK 学习桌面残留 widget")
    ap.add_argument("db", type=Path, help="从设备 pull 出来的 launcher.db 路径")
    ap.add_argument("--list", action="store_true", help="只打印待删清单，不修改文件")
    ap.add_argument("--all-widgets", action="store_true", help="删除四张表里全部 itemType=4 记录")
    ap.add_argument("--package", action="append", default=[],
                    help="追加视为已卸载的包名（可重复）；覆盖默认列表")
    ap.add_argument("--no-backup", action="store_true", help="不生成 .BACKUP（不推荐）")
    args = ap.parse_args()

    if not args.db.is_file():
        print(f"[错误] 找不到文件：{args.db}", file=sys.stderr)
        return 2
    gone = tuple(args.package) if args.package else DEFAULT_GONE_PACKAGES

    db = sqlite3.connect(str(args.db))
    try:
        before = db.execute("PRAGMA integrity_check").fetchone()[0]
        if before != "ok":
            print(f"[错误] 源文件完整性异常：{before}", file=sys.stderr)
            return 3
        plan = inspect(db, args.all_widgets, gone)

        total = sum(len(v) for v in plan.values())
        print(f"=== 体检：源文件完整性 {before}，模式 "
              f"{'清空全部 widget' if args.all_widgets else '仅删已卸载包的 widget'} ===")
        for table, rows in plan.items():
            print(f"-- {table}: 待删 {len(rows)} 条")
            for row_id, screen, provider, title in rows:
                print(f"   id={row_id:>4} screen={screen} title={title!r} provider={provider}")
        if total == 0:
            print("没有需要删除的记录，文件未改动。")
            return 0
        if args.list:
            print(f"[只预览] 共 {total} 条待删，文件未改动。")
            return 0

        if not args.no_backup:
            backup = args.db.with_suffix(args.db.suffix + ".BACKUP")
            if backup.exists():
                print(f"[错误] 备份已存在，请先处理：{backup}", file=sys.stderr)
                return 4
            shutil.copy2(args.db, backup)
            print(f"[备份] {backup}")

        cur = db.cursor()
        for table, rows in plan.items():
            for row_id, *_ in rows:
                cur.execute(f"DELETE FROM {table} WHERE _id = ?", (row_id,))
        db.commit()

        after = db.execute("PRAGMA integrity_check").fetchone()[0]
        print(f"=== 已删除 {total} 条，完整性 {after} ===")
        for table in TABLES:
            try:
                left = db.execute(
                    f"SELECT count(*) FROM {table} WHERE itemType = 4"
                ).fetchone()[0]
                rows = db.execute(f"SELECT count(*) FROM {table}").fetchone()[0]
                print(f"-- {table}: 总记录 {rows}，剩余 widget {left}")
            except sqlite3.Error:
                pass
        print("\n下一步（在 recovery 下，务必原样恢复元数据）：")
        print("  adb -d push launcher.db /data/user_de/0/com.bbk.studyos.launcher/databases/launcher.db")
        print("  adb -d shell 'chown 10085:10085 <路径>; chmod 0660 <路径>; "
              "chcon u:object_r:app_data_file:s0:c512,c768 <路径>'")
        return 0 if after == "ok" else 5
    finally:
        db.close()


if __name__ == "__main__":
    raise SystemExit(main())
