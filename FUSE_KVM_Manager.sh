#!/bin/bash
INPUT=validator_list.csv
TELEGRAM_DETAILS=telegram.txt
TELEGRAM_CHAT_ID=''
TELEGRAM_BOT_KEY=''
OLDIFS=$IFS
IFS=','
LASTVALIDATORINLIST=''
IP=''
USER='ubuntu'
PASSWORD='ChangeMe'
DEFAULT_PASSWORD='ChangeMe'
DEFAULT_USER='ubuntu'
USE_TELEGRAM_BOT='no'

function telegramSendMessage()
{
  #expects one argument, of the message text
  local messageTxt=$1

  #first check we have our bot settings configured!
  if [[ $USE_TELEGRAM_BOT == 'yes' ]]
  then
    curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_KEY/sendMessage?chat_id=$TELEGRAM_CHAT_ID&text=$messageTxt" > /dev/null
  fi
}

function unencrypt()
{
  encfs "$PWD"/../encryptedBackup "$PWD"/../decryptedBackup
}

function encrypt()
{
  fusermount -u "$PWD"/../decryptedBackup
}

function getIP()
{
  local arg1=$1
  if [[ $arg1 != "" ]];
  then
    MAC=$(virsh domiflist $arg1 | awk '{ print $5 }' | tail -2 | head -1)
    IP=$(arp -a | grep $MAC | awk '{ print $2 }' | sed 's/[()]//g')
    retval="BASH function with variable"
  else
    echo "${FUNCNAME[0]} No Argument supplied"
  fi
}

function pullAndUpdateEnv()
{
  echo "initalising the .env file for new validator"
  wget -O .env https://raw.githubusercontent.com/fuseio/fuse-network/master/scripts/examples/.env.validator.example
  sed -i "s/^PERMISSION_PREFIX.*/PERMISSION_PREFIX=\"sudo\"/" ".env"
  read -p "please input your infura Eth endpoint KEY address (https://mainnet.infura.io/v3/<KEY>): " infura
  echo "$infura"
  infuraLink='https:\/\/mainnet.infura.io\/v3\/'
  sed -i "s/^FOREIGN_RPC_URL.*/FOREIGN_RPC_URL=$infuraLink$infura/" ".env"
}

function configureTelegramBot()
{
  if [[ -f $TELEGRAM_DETAILS ]];
  then
    echo "reading telegram bot settings"
    SAVEIFS=$IFS   # Save current IFS
    IFS="="
    while read -r key value
    do
       if [[ $key == "CHAT_ID" ]];
       then
         TELEGRAM_CHAT_ID=$value
       elif [[ $key == "BOT_KEY" ]];
       then
         TELEGRAM_BOT_KEY=$value
       fi
    done < $TELEGRAM_DETAILS
    IFS=$SAVEIFS   # Restore IFS
  else
    configBot="no"
    read -p "Do you want to configure you're telegram bot? [Y/N]" yn
    case $yn in
      [Yy]* ) configBot="yes"; break;;
      [Nn]* ) configBot="no"; break;;
      * ) echo "Please answer yes or no.";;
    esac
    if [[ $configBot == "yes" ]];
    then
      read -p "Please enter your bots chat key: " TELEGRAM_BOT_KEY
      read -p "Please enter your chat id: " TELEGRAM_CHAT_ID
      echo "CHAT_ID=$TELEGRAM_CHAT_ID" >> $TELEGRAM_DETAILS
      echo "BOT_KEY=$TELEGRAM_BOT_KEY" >> $TELEGRAM_DETAILS
      USE_TELEGRAM_BOT='yes'
      echo "I just sent you a message can you see it?"
      telegramSendMessage "HEY, thanks for configuring me we're going to be good friends! :)"
    fi
  fi

  if [[ $TELEGRAM_CHAT_ID != '' && $TELEGRAM_BOT_KEY != '' ]];
  then
    echo "BOT configured"
    USE_TELEGRAM_BOT='yes'
  fi
}

function setup()
{
  #download script depends
  sudo apt-get update

  sudo apt-get install -y virt-manager
  sudo apt-get install -y sshpass
  sudo apt-get install -y encfs
  
  configureTelegramBot
}


function createAndRunKVM()
{
  #optional Arg arg1 = KVMname if being used to backup from a stored config
  local arg1=$1

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

  new=''
  if [[ $arg1 != "" ]];
  then
    new=$arg1
  else
    new="v$((stripped + 1))"
  fi

  echo "new vlaidator KVM: $new"

  cpuCores=$(nproc --all)
  echo "cores = $cpuCores"

  vcpus=3

  if [ "$cpuCores" -lt "$vcpus" ]; then
    vcpus=$cpuCores
  fi

  echo "using $vcpus cores"

  #install the new kvm
  virt-install \
  --name "$new" \
  --ram 2048 \
  --disk path=/var/lib/libvirt/images/"$new".img,size=25 \
  --vcpus "$vcpus" \
  --virt-type kvm \
  --os-type linux \
  --os-variant ubuntu18.04 \
  --graphics none \
  --location 'http://archive.ubuntu.com/ubuntu/dists/bionic/main/installer-amd64/' \
  --noautoconsole \
  --wait=-1 \
  --initrd-inject=ks-1804-minimalvm.cfg \
  --extra-args "ks=file:/ks-1804-minimalvm.cfg console=tty0 console=ttyS0,115200n8"

  sleep 1m

  #pull the ip address from the mac address of the new vm
  getIP $new

  echo "IP OF $new IS $IP"

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
  echo "$PASSWORD" | sudo -S curl -L "https://github.com/docker/compose/releases/download/1.23.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 
  echo "$PASSWORD" | sudo -S chmod +x /usr/local/bin/docker-compose;
  echo "$PASSWORD" | sudo -S ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  mkdir fuse-validator;
  cd fuse-validator;
  echo "$PASSWORD" | sudo -S wget -O /home/"$USER"/fuse-validator/quickstart.sh https://raw.githubusercontent.com/fuseio/fuse-network/master/scripts/quickstart.sh;
  echo "$PASSWORD" | sudo -S chmod 777 /home/"$USER"/fuse-validator/quickstart.sh;
  ls;
EOF

  #send over your .env file to the kvm
  sshpass -p "$PASSWORD" scp .env "$USER"@"$IP":/home/"$USER"/fuse-validator
  
  if [[ $arg1 != "" ]];
  then
    echo "Copy the backed up config across"
    sshpass -p "$PASSWORD" scp -r ../decryptedBackup/$arg1 "$USER"@"$IP":/home/"$USER"/fuse-validator/fusenet/config
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" << EOF
	 echo "$PASSWORD" | sudo -S mv /home/"$USER"/fuse-validator/fusenet/config/.env /home/"$USER"/fuse-validator/.env
EOF
  fi

  sshpass -p "$PASSWORD" ssh -t "$USER"@"$IP" "cd fuse-validator &&  sudo -S ./quickstart.sh"
  sshpass -p "$PASSWORD" ssh -t "$USER"@"$IP" "cd fuse-validator &&  sudo -S ./quickstart.sh"

  echo ""$new" has been setup and is validating"

  echo ""$new","$IP",0,yes" >> $INPUT

  telegramSendMessage "New KVM $new has been setup and started :)"
}

function updateKVMs()
{
  #this assumes that all KVMs have been setup with this script i.e. has the same file structure and usernames
  [ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }
  while read validator ip ethaddr defaultPassword
  do
    currentValidator=$validator
    getIP $currentValidator
    if [[ $defaultPassword == 'no' ]];
    then
      read -p "Please enter the username for $currentValidator: " tempUser
      read -p -s "Please enter the password for $currentValidator: " tempPass
      PASSWORD=$tempPass
      USER=$tempUser
    fi
    echo "IP OF $currentValidator IS $IP"
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" << EOF
      echo "$PASSWORD" | sudo -S wget -O /home/"$USER"/fuse-validator/quickstart.sh https://raw.githubusercontent.com/fuseio/fuse-network/master/scripts/quickstart.sh;
      echo "$PASSWORD" | sudo -S chmod 777 /home/"$USER"/fuse-validator/quickstart.sh;
      echo "$PASSWORD" | sudo -S ./quickstart.sh"
EOF
    PASSWORD=$DEFAULT_PASSWORD
    USER=$DEFAULT_USER
  done < $INPUT
  IFS=$OLDIFS
  telegramSendMessage "Finished updating all KVMs :)"
}

function grabNamesFromList()
{
  virsh list | awk '( $1 ~ /^[0-9]+$/ ) { print $2 }'
}

function listForKVMPrintIP()
{
  arr=( $( grabNamesFromList ) )
  SAVEIFS=$IFS   # Save current IFS
  IFS=$'\n'      # Change IFS to new line
  arr=($arr) # split to array $names
  IFS=$SAVEIFS   # Restore IFS 
  
  echo "Select a KVM"
  PS3="Select a KVM:"
  select opt in "${arr[@]}"; do 
    echo "picked $REPLY"
    value="$(($REPLY - 1))"
    echo "Getting IP of ${arr[$value]}"
    getIP "${arr[$value]}"
    echo "IP OF ${arr[$value]} IS $IP"
    break
  done
}

function createBackupFolder()
{
  echo "Opening mounting the encrypted folder, if not created please follow trhe setup"
  unencrypt
  writeOver='no'
  read -p "Do you want to write over any stored configs? [Y/N]" yn
  case $yn in
      [Yy]* ) writeOver='yes'; break;;
      [Nn]* ) writeOver='no'; break;;
      * ) echo "Please answer yes or no.";;
  esac
  
  while read validator ip ethaddr defaultPassword
  do
    	  
    skip="no"
    currentValidator=$validator
    #check if the folder for this validator exsists
    dirExists='no'
    if [ -d "../decryptedBackup/$currentValidator" ]; then
      # Take action if $DIR exists. #
      echo "backup for $currentValidator already exsists"
      dirExists='yes'
      if [[ $writeOver == "yes" ]];
      then
        rm -rf "../decryptedBackup/$currentValidator"
      else
        skip="yes"
      fi 
    fi
    
    
    if [[ $skip != "yes" ]];
    then
      if [[ $defaultPassword == 'no' ]];
      then
        read -p "Please enter the username for $currentValidator: " tempUser
        read -p -s "Please enter the password for $currentValidator: " tempPass
        PASSWORD=$tempPass
        USER=$tempUser
      fi
	    
      getIP $currentValidator
      echo "IP OF $currentValidator IS $IP"
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" << EOF
    echo "$PASSWORD" | sudo -S cp -r /home/"$USER"/fuse-validator/fusenet/config /home/"$USER"/config
    echo "$PASSWORD" | sudo -S cp  /home/"$USER"/fuse-validator/.env /home/"$USER"/config/.env
    echo "$PASSWORD" | sudo -S chown -R "$USER":"$USER" /home/"$USER"/config
EOF

    sshpass -p "$PASSWORD" scp -r "$USER"@"$IP":/home/"$USER"/config ../decryptedBackup/$currentValidator
    
sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" << EOF
    echo "$PASSWORD" | sudo -S rm -r /home/"$USER"/config
EOF
    
    PASSWORD=$DEFAULT_PASSWORD
    USER=$DEFAULT_USER
    fi
  done < $INPUT
  
  IFS=$OLDIFS
  
}

function restoreFromBackup()
{
  unencrypt
  for d in ../decryptedBackup/*/ ; do
    d=${d//"../decryptedBackup/"}
    d=${d//"/"}
    createAndRunKVM "$d"
  done

  telegramSendMessage "All KVMs have been restored :)"
}

setup
while true; do
PS3='Please enter your choice: '
options=("Create a new KVM" "Update all KVMs" "Create KVM backup" "Restore from KVM backup" "List KVMs" "Get KVM IP" "Unencrypt Backup" "Encrypt Backup" "Quit")
select opt in "${options[@]}";
do
    case $opt in
        "${options[0]}")
            #create a new KVM
            echo "Creating a new KVM this may take upto 15 minutes"
            sleep 2s
            pullAndUpdateEnv
	    createAndRunKVM
            read -p "Do you want to create a backup? [Y/N]: " yn
	    case $yn in
	      [Y/y]* ) 
		      createBackupFolder; break;;
      		esac
	    break
	    ;;
        "${options[1]}")
            #update all KVMs
            echo "Creating a new KVM this may take a few minutes"
            sleep 2s
            updateKVMs
            break
	    ;;
        "${options[2]}")
            #Create KVM backup
            echo "Creating a backup folder"
            sleep 2s
            createBackupFolder
            break
	    ;;
        "${options[3]}")
            #Restore from KVM backup
            echo "Restoring from backup this can take upto 15 minutes per node please"
            restoreFromBackup
            break
	    ;;
        "${options[4]}")
            #List KVMs
            virsh list
            break
	    ;;
        "${options[5]}")
            #Get KVM IP
            listForKVMPrintIP
            break 
	    ;;
        "${options[6]}")
            #Unencrypt
            unencrypt
            echo "Backup Unencrypted back up files to a cold store somewhere off this machine, files found at ../decryptedBackup don't forget to re encrypt this folder!"
            break 
	    ;;
        "${options[7]}")
            #Encrypt
            encrypt
            break 
	    ;;
        "${options[8]}")
            #exit
	    read -p "Do you want to encrypt the backup folder? [Y/N]: " yn
            case $yn in
              [Y/y]* )
                      encrypt; break;;
	      [N/n]* )
		    echo "Dont forget to do it later!"; exit 1; break;;  
	      esac

            exit 0
            ;;
        *) echo "invalid option $REPLY";;
    esac
done
done
