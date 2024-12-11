#!/bin/bash

# --------- START OF EDIT ZONE ---------------

MODS="lithium ferrite-core modernfix krypton c2me-fabric noisium vmp-fabric no-chat-reports servercore worldedit"
# MODS="asguhoserver"  # Space seperated list of mods/modpacks by slug (i.e. https://modrinth.com/modpack/{slug}). If you create version conflicts, that's on you
# You could try this for performance in 1.21.1:
# MODS="lithium ferrite-core modernfix krypton c2me-fabric noisium vmp-fabric no-chat-reports servercore worldedit"

FRACTION_OF_RAM_USAGE=4 # 2 means half, 3 means third and so on...

# ---------- END OF EDIT ZONE ----------------
#
# ----------- NO EDIT ZONE --------------
# if you edit here, you're on your own

FABRIC_VERSIONS_URL="https://meta.fabricmc.net/v2/versions/"

PYTHON_VERSION=python3.8


if ! [ -x "$(command -v $PYTHON_VERSION)" ]; then
    echo "Error: $PYTHON_VERSION is not installed."
    exit 1
fi

echo "python version: $PYTHON_VERSION"

req_file_not_exists_or_old() {
    if [[ -f "$1" ]]; then
        if [[ $(find "$1" -mtime +7 -print) ]]; then
            echo "$1 is older than a week. Downloading again..."
            curl -o "$1" -J "$2"
        else
            echo "$1 is not older than a week. No need to download."
        fi
    else
        echo "$1 does not exist. Downloading..."
        curl -o "$1" -J "$2"
    fi
}

req_file_not_exists_or_old "fabric-versions.json" "$FABRIC_VERSIONS_URL"

stable_versions=$(jq -r '.game[] | select(.stable == true) | .version' fabric-versions.json)
IFS=$'\n' read -r -d '' -a stable_versions_array <<<"$stable_versions"

if [ -z "$1" ]; then
    printf "Available fabric versions:\n"
    printf "%s " "${stable_versions_array[@]}"
    echo
    exit 1
fi
if ! jq -r '.game[] | select(.stable == true) | .version' fabric-versions.json | grep -qFx "$1"; then
    echo -e "\e[32m$1\e[0m is NOT in the list of stable versions."
    echo "$stable_versions"
    exit 1
fi
echo "$1 is in the list of stable versions."
MINECRAFT_VERSION="$1"
echo "minecraft version: $MINECRAFT_VERSION"
SERVER_DIRECTORY="server_$MINECRAFT_VERSION"
if [ ! -d "$SERVER_DIRECTORY" ]; then
  mkdir "$SERVER_DIRECTORY"
fi
LOADER_VERSION=$(jq -r '.loader[0].version' fabric-versions.json)
echo "fabric loader: $LOADER_VERSION"
INSTALLER_VERSION=$(jq -r '.installer[0].version' fabric-versions.json)
echo "fabric installer: $INSTALLER_VERSION"

SERVER_JAR="fabric-server-mc.$MINECRAFT_VERSION-loader.$LOADER_VERSION-launcher.$INSTALLER_VERSION.jar"
SERVER_JAR_URL="https://meta.fabricmc.net/v2/versions/loader/$MINECRAFT_VERSION/$LOADER_VERSION/$INSTALLER_VERSION/server/jar"
req_file_not_exists_or_old "$SERVER_DIRECTORY/$SERVER_JAR" "$SERVER_JAR_URL"

ram_in_gb="$(awk '/MemFree/ { printf "%.3f \n", $2/1024/1024 }' /proc/meminfo)"

xmx="$(bc -l <<<"${ram_in_gb}*1000/${FRACTION_OF_RAM_USAGE}")"
xmx=${xmx%.*}
jargs="-Xmx${xmx}M"

echo "eula=true" >$SERVER_DIRECTORY/eula.txt

echo "java $jargs -jar $SERVER_JAR nogui" > $SERVER_DIRECTORY/start-server.sh

echo "checking mods compatiblity with version $MINECRAFT_VERSION"
$PYTHON_VERSION modrinth-api.py $1 $SERVER_DIRECTORY $MODS
retVal=$?
if [ $retVal -ne 0 ]; then
    echo -e "\e[31mError\e[0m"
    exit 1
fi
echo "  > No issues"
echo -e "Run \e[32m$SERVER_DIRECTORY/start-server.sh\e[0m to start the server"
chmod +x $SERVER_DIRECTORY/start-server.sh
