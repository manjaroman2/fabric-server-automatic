#!/bin/bash

# --------- START OF EDIT ZONE ---------------

MODS="asguhoserver" # Space seperated list of mods/modpacks by slug (i.e. https://modrinth.com/modpack/{slug}). If you create version conflicts, that's on you
                    # You could try this for performance "lithium ferrite-core modernfix memoryleakfix krypton debugify lazydfu c2me-fabric noisium vmp-fabric fastload"

FRACTION_OF_RAM_USAGE=2 # 2 means half, 3 means third and so on...

# ---------- END OF EDIT ZONE ----------------
#
# ----------- NO EDIT ZONE --------------
# if you edit here, you're on your own

FABRIC_VERSIONS_URL="https://meta.fabricmc.net/v2/versions/"

if ! [ -x "$(command -v python3.12)" ]; then
    echo 'Error: python3.12 is not installed.' >&2
    exit 1
fi

if [ -z "$1" ]; then
    echo "Version? [1.21.4, 1.21.1]"
    exit 1
fi

cd modrinth.py/modrinth && cp ../../modrinth.py.patch .
if git apply --check "modrinth.py.patch" >/dev/null 2>&1; then
    echo "a"
    git apply modrinth.py.patch
else
    echo "patch does not apply to modrinth.py"
fi
rm modrinth.py.patch && cd ../..

MINECRAFT_VERSION="$1"
echo "minecraft version: $MINECRAFT_VERSION"

if [ ! -d ".env/" ]; then
    echo "creating python3.12 virtual enviroment at $PWD/.env/"
    python3.12 -m venv .env/
fi

source .env/bin/activate
export PYTHONPATH=$PWD/modrinth.py:$PYTHONPATH
echo "installing pip requirements"
pip install -r modrinth.py/requirements.txt >/dev/null 2>&1
if [[ -f "fabric-versions.json" ]]; then
    # Check if the file is older than 7 days
    if [[ $(find "fabric-versions.json" -mtime +7 -print) ]]; then
        echo "fabric-versions.json is older than a week. Downloading again..."
        curl -o "fabric-versions.json" -J "$FABRIC_VERSIONS_URL"
    else
        echo "fabric-versions.json is not older than a week. No need to download."
    fi
else
    echo "fabric-versions.json does not exist. Downloading..."
    curl -o "fabric-versions.json" -J "$FABRIC_VERSIONS_URL"
fi

if ! jq -r '.game[] | select(.stable == true) | .version' fabric-versions.json | grep -qFx "$1"; then
    echo -e "\e[32m$1\e[0m is NOT in the list of stable versions."
    exit 1
fi
echo "$1 is in the list of stable versions."

LOADER_VERSION=$(jq -r '.loader[0].version' fabric-versions.json)
echo "fabric loader: $LOADER_VERSION"
INSTALLER_VERSION=$(jq -r '.installer[0].version' fabric-versions.json)
echo "fabric installer: $INSTALLER_VERSION"

SERVER_JAR="fabric-server-mc.$MINECRAFT_VERSION-loader.$LOADER_VERSION-launcher.$INSTALLER_VERSION.jar"
SERVER_JAR_URL="https://meta.fabricmc.net/v2/versions/loader/$MINECRAFT_VERSION/$LOADER_VERSION/$INSTALLER_VERSION/server/jar"
if [[ -f "$SERVER_JAR" ]]; then
    # Check if the file is older than 7 days
    if [[ $(find "$SERVER_JAR" -mtime +7 -print) ]]; then
        echo "$SERVER_JAR is older than a week. Downloading again..."
        curl -o "$SERVER_JAR" -J "$SERVER_JAR_URL"
    else
        echo "$SERVER_JAR is not older than a week. No need to download."
    fi
else
    echo "$SERVER_JAR does not exist. Downloading..."
    curl -o "$SERVER_JAR" -J "$SERVER_JAR_URL"
fi

ram_in_gb="$(awk '/MemFree/ { printf "%.3f \n", $2/1024/1024 }' /proc/meminfo)"

xmx="$(bc -l <<<"${ram_in_gb}*1000/${FRACTION_OF_RAM_USAGE}")"
xmx=${xmx%.*}
jargs="-Xmx${xmx}M"

echo "eula=true" >eula.txt

echo "java $jargs -jar $SERVER_JAR nogui" >start-server.sh

echo "checking mods compatiblity with version $MINECRAFT_VERSION"
python modrinth-api.py $1 $MODS
retVal=$?
if [ $retVal -ne 0 ]; then
    echo -e "\e[31mError\e[0m"
    exit 1
fi
echo "  > No issues"
echo -e "Use \e[32m./start-server.sh\e[0m to start the server"
chmod +x start-server.sh