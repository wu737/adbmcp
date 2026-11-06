"""
构建 PyPI 发布产物 + install/bundle.zip (供 bootstrap.sh 一行安装使用)

用法:
    python tools/build_release.py

产物:
    dist/adbmcp-<ver>-py3-none-any.whl
    dist/adbmcp-<ver>.tar.gz
    install/bundle.zip      ← bootstrap.sh 下载的就是它
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIST = os.path.join(REPO, "dist")
INSTALL = os.path.join(REPO, "install")
TEXT_EXT = (".sh", ".py", ".md", ".json", ".txt", "")


def version() -> str:
    pyproject = os.path.join(REPO, "pyproject.toml")
    with open(pyproject, encoding="utf-8") as fh:
        m = re.search(r'^version = "([^"]+)"', fh.read(), re.M)
    if not m:
        raise SystemExit("无法从 pyproject.toml 解析版本号")
    return m.group(1)


def to_lf(path: str) -> None:
    """把文本文件的 CRLF 转成 LF。"""
    with open(path, "rb") as fh:
        data = fh.read()
    if b"\r\n" in data:
        with open(path, "wb") as fh:
            fh.write(data.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))


def normalize_line_endings() -> int:
    """构建前把仓库里所有文本文件统一成 LF。

    Python 写文件默认用 CRLF, 在 Windows 上编辑脚本很容易引入。
    Termux 下 CRLF 会导致 "bad interpreter: /bin/bash^M", 必须在打包前兜住。
    """
    import glob
    patterns = ["scripts/*", "install/*.sh", "src/adbmcp/*.py", "tools/*.py"]
    fixed = 0
    for pat in patterns:
        for path in glob.glob(os.path.join(REPO, pat)):
            if not os.path.isfile(path):
                continue
            with open(path, "rb") as fh:
                data = fh.read()
            if b"\r\n" in data:
                with open(path, "wb") as fh:
                    fh.write(data.replace(b"\r\n", b"\n").replace(b"\r", b"\n"))
                fixed += 1
                print(f"  · 已转 LF: {os.path.relpath(path, REPO)}")
    return fixed


def build_sdist_wheel() -> None:
    print("=== 统一换行符 ===")
    n = normalize_line_endings()
    print(f"  {'✓ 无需处理' if n == 0 else f'✓ 已修正 {n} 个文件'}")

    print("\n=== 构建 sdist + wheel ===")
    shutil.rmtree(DIST, ignore_errors=True)
    r = subprocess.run([sys.executable, "-m", "build"],
                       cwd=REPO, capture_output=True, text=True, timeout=900)
    if r.returncode != 0:
        print(r.stdout[-2000:])
        print(r.stderr[-2000:])
        raise SystemExit("构建失败")
    for f in sorted(os.listdir(DIST)):
        print(f"  {f}")


def build_bundle() -> str:
    """打包 install/bundle.zip —— bootstrap.sh 用它做一行安装。"""
    print("\n=== 生成 install/bundle.zip ===")
    out = os.path.join(INSTALL, "bundle.zip")
    if os.path.exists(out):
        os.remove(out)

    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for sub in ("scripts", "install"):
            src = os.path.join(REPO, sub)
            if not os.path.isdir(src):
                continue
            for root, dirs, files in os.walk(src):
                dirs[:] = [d for d in dirs if d != "__pycache__"]
                for fn in sorted(files):
                    if fn == "bundle.zip":      # 别把自己打包进去
                        continue
                    p = os.path.join(root, fn)
                    rel = os.path.relpath(p, REPO).replace("\\", "/")
                    to_lf(p)
                    z.write(p, rel)
                    count += 1
        for f in ("README.md", "README.en.md", "LICENSE"):
            p = os.path.join(REPO, f)
            if os.path.isfile(p):
                z.write(p, f)
                count += 1

    print(f"  bundle.zip: {os.path.getsize(out)} bytes, {count} 个文件")
    return out


def verify(bundle: str) -> None:
    print("\n=== 校验 ===")
    errors = []
    with zipfile.ZipFile(bundle) as z:
        names = z.namelist()
        crlf = [n for n in names
                if n.endswith((".sh", ".py")) and b"\r\n" in z.read(n)]
        if crlf:
            errors.append(f"CRLF 文件: {crlf}")
        for req in ("scripts/adbmcp", "install/install-adbmcp.sh",
                    "install/bootstrap.sh"):
            if req not in names:
                errors.append(f"缺少 {req}")
        adm = z.read("scripts/adbmcp").decode()
        for token in ("connect_devices", "fix_crlf"):
            if token not in adm:
                errors.append(f"主脚本缺少 {token}")
    if errors:
        for e in errors:
            print(f"  ❌ {e}")
        raise SystemExit(1)
    print("  ✓ bundle 校验通过")


if __name__ == "__main__":
    v = version()
    print(f"adbmcp {v}\n")
    build_sdist_wheel()
    b = build_bundle()
    verify(b)
    print(f"\n✅ 完成 (版本 {v})")
