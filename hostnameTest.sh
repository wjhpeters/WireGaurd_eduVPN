ipadresses=`hostname -i`
IFS=' ' read -r -a array <<< "$ipadresses"
ipv6=`echo "${array[0]}"`
ipv4=`echo "${array[1]}"`

echo $ipv6
echo "______________"
echo $ipv4