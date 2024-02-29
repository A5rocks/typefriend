# build backend for typefriend

# not so friendly :(
# but it meows

import os
import pathlib
import tomli
import tarfile
import subprocess
import sys
import tempfile
import shutil
import hashlib

# TODO: compatibility tags
# TODO: make sure I'm using the stable ABI
# TODO: why does py3 work but not cp3
COMPAT_TAG = "py3-abi3-win_amd64"

def get_version():
    with open(pathlib.Path(os.getcwd()) / "build.zig.zon") as f:
        return f.read().split('.version = "', 1)[1].split('"', 1)[0]

def get_project():
    with open(pathlib.Path(os.getcwd()) / "pyproject.toml", "rb") as f:
        project = tomli.load(f)['project']
        assert "version" not in project
        project['dynamic'].remove('version')
        project['version'] = get_version()
        return project

def prepare_metadata_for_build_wheel(metadata_directory, config_settings=None):
    print("aaaa AAAAA")
    return "aaaa"

def build_wheel(wheel_directory, config_settings=None, metadata_directory=None):
    assert metadata_directory is None

    zig = pathlib.Path(os.getcwd()) / "zig.exe"
    assert zig.exists(), "need `python -m build -w` until zig==0.12.0"

    project = get_project()

    with tempfile.TemporaryDirectory() as build_directory:
        build_path = pathlib.Path(build_directory)
        subprocess.check_call([
            str(zig),
            "build",
            "-Doptimize=ReleaseSafe",
            f"-Dpython-exe={sys.executable}",
            "--prefix-lib-dir",
            str(build_path)
        ])

        contents = build_path / "contents"
        contents.mkdir()

        # note: this is Windows-specific
        shutil.move(
            build_path / f"{project['name']}.dll",
            contents / f"{project['name']}.pyd"
        )

        # metadata
        dist_info = contents / f"{project['name']}-{project['version']}.dist-info"
        dist_info.mkdir()

        with open(dist_info / "WHEEL", "w", newline="\n") as f:
            f.write("Wheel-Version: 1.0\n")
            f.write("Generator: meow\n")
            f.write("Root-Is-Purelib: false\n")
            f.write(f"Tag: {COMPAT_TAG}\n")

        with open(dist_info / "METADATA", "w", newline="\n") as f:
            f.write("Metadata-Version: 2.3\n")
            f.write(f"Name: {project['name']}\n")
            f.write(f"Version: {project['version']}\n")
            # TODO: move over more fields, maybe?

        with open(dist_info / "RECORD", "w", newline="\n") as f:
            for file in contents.glob("**/*"):
                assert str(file).startswith(str(contents))
                filename = str(file).removeprefix(str(contents)).replace("\\", "/")

                if file == dist_info / "RECORD":
                    f.write(f"{filename},,\n")
                    continue

                if file.is_dir():
                    continue

                with open(file, "rb") as inner_file:
                    inner_contents = inner_file.read()
                    sha256 = hashlib.sha256(inner_contents)
                    f.write(f"{filename},sha256={sha256},{len(inner_contents)}\n")

        wheel_path = pathlib.Path(wheel_directory)
        wheel_path /= f"{project['name']}-{project['version']}-{COMPAT_TAG}.whl"

        shutil.make_archive(wheel_path, "zip", contents)
        shutil.move(f"{wheel_path}.zip", wheel_path)
    return str(wheel_path)

def build_sdist(sdist_directory, config_settings=None):
    project = get_project()

    sdist_name = f"{project['name']}-{project['version']}"

    def add_to_sdist(info):
        assert info.name.startswith(sdist_name)

        # root dir
        if info.isdir() and info.name == sdist_name:
            return info

        name = info.name.removeprefix(f"{sdist_name}/")

        # recursive include source directories
        if name.startswith("src"):
            print(f"adding {name} to sdist")
            return info

        # relevant build files
        if name in [
            "build.zig",
            "build.zig.zon",
            "pyproject.toml",
            "readme.md",
            "meow",
            "meow/backend.py"
        ]:
            print(f"adding {name} to sdist")
            return info

    sdist_filename = pathlib.Path(sdist_directory) / f"{sdist_name}.tar.gz"
    sdist = tarfile.open(sdist_filename, "w:gz")
    sdist.add(os.getcwd(), arcname=sdist_name, filter=add_to_sdist)
    return str(sdist_filename)

