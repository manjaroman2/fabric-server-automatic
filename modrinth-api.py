import json
import sys
import urllib.request
from pathlib import Path

if len(sys.argv) < 4:
    print("ERROR missing args")
    exit(1)

import hashlib
from urllib.parse import unquote_plus, urlencode
from urllib.request import urlopen


def r_get_content(url):
    with urlopen(url) as f:
        return f.read()


def r_get_json(url):
    with urlopen(url) as f:
        return json.loads(f.read().decode("utf-8"))


class Project:
    def __init__(self, id: str):
        try:
            data = r_get_json(f"https://api.modrinth.com/v2/project/{id}")
        except urllib.request.HTTPError as e:
            if e.code == 404:
                raise FileNotFoundError

        self.id = data["id"]
        self.gameVersions = data["game_versions"]
        self.modLoaders = data["loaders"]


base_path = Path(__file__).parent
mods_path = Path(sys.argv[2]) / "mods"

mc_version = sys.argv[1]
slugs = list(sys.argv[3:])
not_available = {"filenotfound": [], "version_incompatible": []}

e = False
error = False
maxl = max([len(x) for x in slugs])

slug = "Slug"
print(f"{slug:{maxl+1}} |  Did you mean?")
for slug in slugs:
    print(f"{slug:{maxl+1}} |", end="  ", flush=True)
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
    if error:
        e = True
        error = False
        print()
    else:
        print("✔️")
if e:
    print(json.dumps(not_available))
    exit(1)


def get_jars_with_deps(proj_id, version_id):
    url = f"https://api.modrinth.com/v2/project/{proj_id}/version/{version_id}"
    try:
        v = r_get_json(url)
    except json.JSONDecodeError:
        print(f"json error {url}")
        exit(1)
    yield from (
        (x["url"], x["hashes"]["sha512"]) for x in v["files"] if x["primary"] == True
    )
    for dep in v["dependencies"]:
        if dep["dependency_type"] == "optional" or dep["version_id"] == None:
            continue
        print(proj_id, v["dependencies"])
        yield from get_jars_with_deps(dep["project_id"], dep["version_id"])


def clear_directory(directory_path):
    directory = Path(directory_path)
    for file in directory.iterdir():
        if file.is_file():
            file.unlink() 
        elif file.is_dir():
            clear_directory(file) 
            file.rmdir()


print(f"clearing mods directory {mods_path}")
if not mods_path.exists():
    mods_path.mkdir()
clear_directory(mods_path)
print("downloading with dependencies:")
for slug in slugs:
    print(f"  {slug}")
    query_params = urlencode({"game_versions": f'["{mc_version}"]'})
    url = f"https://api.modrinth.com/v2/project/{slug}/version?{query_params}"

    v = None
    for x in r_get_json(url):
        if "fabric" in x["loaders"]:
            v = x
            break
    if v == None:
        print(f"Could not find fabric version of {slug}")
        exit(1)
    req = []
    for dep in v["dependencies"]:
        if dep["dependency_type"] == "optional":
            continue
        if dep["version_id"] == None:
            project_id = dep['project_id']
            url = f"https://api.modrinth.com/v2/project/{project_id}/version?{query_params}"
            vv = None
            for x in r_get_json(url):
                if "fabric" in x["loaders"]:
                    vv = x
                    break
            if vv == None:
                print(f"Could not find fabric version of project with id {project_id}")
                exit(1)
            for x in vv["files"]:
                if x["primary"]:
                    req.append((x["url"],x["hashes"]["sha512"]))
                    break
            continue
                
        for x in get_jars_with_deps(project_id, dep["version_id"]):
            req.append(x)

    for x in v["files"]:
        if x["primary"] == True:
            req.append((x["url"], x["hashes"]["sha512"]))
            break
    for url, sha512 in req:
        fn = unquote_plus(url.split("/")[-1])
        print(f"    > {url} -> {fn}")
        c = r_get_content(url)
        if hashlib.sha512(c).hexdigest() == sha512:
            nowrite = False
            if (mods_path / fn).exists() and hashlib.sha512(
                (mods_path / fn).read_bytes()
            ).hexdigest() == sha512:
                nowrite = True
            if not nowrite:
                (mods_path / fn).write_bytes(c)
        else:
            print(f"HASH ERROR: {url}")
            clear_directory(mods_path)
            exit(1)

exit(0)
