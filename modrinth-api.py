import json
import sys
from pathlib import Path

if len(sys.argv) < 3:
    print("ERROR missing args")
    exit(1)

base_path = Path(__file__).parent
mods_path = base_path / "mods"
from modrinth import Project

mc_version = sys.argv[1]
slugs = list(sys.argv[2:])
not_available = {"filenotfound": [], "version_incompatible": []}

error = False
maxl = max([len(x) for x in slugs])
for slug in slugs:
    print(f"{slug:{maxl+1}}", end=" ", flush=True)
    try:
        if mc_version not in Project(slug).gameVersions:
            for gv in Project(slug).gameVersions:
                if len(gv) == len(mc_version) and mc_version[:3] == gv[:3]:
                    print(gv, end=" ", flush=True)
            # print("", flush=True)
            not_available["version_incompatible"].append(slug)
            error = True
    except FileNotFoundError:
        not_available["filenotfound"].append(slug)
        error = True
    print()
if error:
    print(json.dumps(not_available))
    exit(1)
import hashlib

from requests import get as r_get


# url = f'https://api.modrinth.com/v2/project/lmd/version?game_versions=["1.21.3"]'
# print(json.dumps(r_get(url).json()[0], indent=4))
def get_jars_with_deps(proj_id, version_id):
    url = f"https://api.modrinth.com/v2/project/{proj_id}/version/{version_id}"
    r = r_get(url)
    try:
        v = r.json()
    except json.JSONDecodeError:
        print(r, url)
        exit(1)
    yield from ((x["url"], x["hashes"]["sha512"]) for x in v["files"] if x["primary"] == True)
    for dep in v["dependencies"]:
        if dep["dependency_type"] == "optional" or dep["version_id"] == None:
            continue
        print(proj_id, v["dependencies"])
        yield from get_jars_with_deps(dep["project_id"], dep["version_id"])


import urllib.parse


def clear_directory(directory_path):
    directory = Path(directory_path)
    for file in directory.iterdir():
        if file.is_file():
            file.unlink()  # Remove the file
        elif file.is_dir():
            clear_directory(file)  # Recursively clear subdirectories
            file.rmdir()


print(f"clearing mods directory {mods_path}")
clear_directory(mods_path)
for slug in slugs:
    url = f'https://api.modrinth.com/v2/project/{slug}/version?game_versions=["{mc_version}"]'
    v = r_get(url).json()[0]

    req = []
    print(f"  > getting dependencies for {slug}")
    for dep in v["dependencies"]:
        if dep["dependency_type"] == "optional" or dep["version_id"] == None:
            continue
        for x in get_jars_with_deps(dep["project_id"], dep["version_id"]):
            req.append(x)

    # print(v["files"])
    for x in v["files"]:
        if x["primary"] == True:
            req.append((x["url"], x["hashes"]["sha512"]))
            break
    for url, sha512 in req:
        fn = urllib.parse.unquote_plus(url.split("/")[-1])
        print(f"    > {url} -> {fn}")
        c = r_get(url).content
        if hashlib.sha512(r_get(url).content).hexdigest() == sha512:
            (mods_path / fn).write_bytes(c)
        else:
            print(f"HASH ERROR: {url}")
            clear_directory(mods_path)
            exit(1)

exit(0)
