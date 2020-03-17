#!/bin/bash
INPUT=validator_list.csv
OLDIFS=$IFS
IFS=','
LASTVALIDATORINLIST=''

#download script depends
sudo apt-get install -y virt-manager
sudo apt-get install -y sshpass

#look through the list and take the last kvm name
[ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }
while read validator ip ethaddr
do
	LASTVALIDATORINLIST=$validator
done < $INPUT
IFS=$OLDIFS

echo "The last validator in the list $LASTVALIDATORINLIST"

#strip the v off the front of the kvm name
stripped="${LASTVALIDATORINLIST:1:${#LASTVALIDATORINLIST}-1}"

new="v$((stripped + 1))"

echo "new vlaidator KVM: $new"

#install the new kvm
virt-install \
--name "$new" \
--ram 2048 \
--disk path=/var/lib/libvirt/images/"$new".img,size=25 \
--vcpus 3 \
--virt-type kvm \
--os-type linux \
--os-variant ubuntu18.04 \
--graphics none \
--location 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/' \
--noautoconsole \
--wait=-1 \
--initrd-inject=ks-1804-minimalvm.cfg \
--extra-args "ks=file:/ks-1804-minimalvm.cfg console=tty0 console=ttyS0,115200n8"

#pull the ip address from the mac address of the new vm
MAC=$(virsh domiflist $new | awk '{ print $5 }' | tail -2 | head -1)
IP=$(arp -a | grep $MAC | awk '{ print $2 }' | sed 's/[()]//g')

echo "IP OF $new IS $IP"

USER='ubuntu'
PASSWORD='ChangeMe'

#ssh onto the new kvm and set it up
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" << EOF
echo "$PASSWORD" | sudo -S apt-get update;
echo "$PASSWORD" | sudo -S apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common;
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -;
echo "$PASSWORD" | sudo -S apt-key add -;
echo "$PASSWORD" | sudo -S apt-key fingerprint 0EBFCD88;
echo "$PASSWORD" | sudo -S add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable";
echo "$PASSWORD" | sudo -S apt-get update;
echo "$PASSWORD" | sudo -S apt-get install -y docker-ce;
echo "$PASSWORD" | sudo -S docker run hello-world;
echo "$PASSWORD" | sudo -S curl -L "https://github.com/docker/compose/releases/download/1.25.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose;
echo "$PASSWORD" | sudo -S chmod +x /usr/local/bin/docker-compose;
docker-compose --version;
mkdir fuse-validator;
cd fuse-validator;
echo "$PASSWORD" | sudo -S wget -O /home/"$USER"/fuse-validator/quickstart.sh https://raw.githubusercontent.com/fuseio/fuse-network/master/scripts/quickstart.sh;
echo "$PASSWORD" | sudo -S chmod 777 /home/"$USER"/fuse-validator/quickstart.sh;
ls;
EOF

#send over your .env file to the kvm
sshpass -p "$PASSWORD" scp .env "$USER"@"$IP":/home/"$USER"/fuse-validator

#start the quickstart
sshpass -p "$PASSWORD" ssh -T "$USER"@"$IP" << EOF
cd fuse-validator; 
echo "$PASSWORD" | sudo -S /home/"$USER"/fuse-validator/quickstart.sh;
echo "$PASSWORD" | sudo -S /home/"$USER"/fuse-validator/quickstart.sh;
EOF

echo ""$new","$IP",0" >> $INPUT

