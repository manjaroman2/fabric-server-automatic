#!/bin/sh 


rm fabric-server-*-launcher.*.jar # -mc.1.21.4-loader.0.16.9-      1.0.1
curl -OJ https://meta.fabricmc.net/v2/versions/loader/1.21.4/0.16.9/1.0.1/server/jar
# server_jar="$(ls -Art | tail -n 1)" 
server_jar="$(find -name fabric-server-*-launcher.*.jar)" 
echo $server_jar

ram_in_gb="$(awk '/MemFree/ { printf "%.3f \n", $2/1024/1024 }' /proc/meminfo)"

xmx="$(bc -l <<< "${ram_in_gb}*1000/2")"
xmx=${xmx%.*}
jargs="-Xmx${xmx}M"
echo $jargs 

echo "eula=true" > eula.txt 

echo "java ${jargs} -jar ${server_jar} nogui" > start-server.sh 
chmod +x start-server.sh 
# echo $ram_in_gb
# echo $((ram_in_gb*500))


