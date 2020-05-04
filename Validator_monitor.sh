#!/bin/bash
INPUT=validator_list.csv
TELEGRAM_DETAILS=telegram.txt
MONITOR_SETTINGS=monitor_settings.txt
REPORT_FILE=monitorReport.csv #CPU,RAM,HDD,ETH,Dockers
TELEGRAM_CHAT_ID=''
TELEGRAM_BOT_KEY=''
OLDIFS=$IFS
IFS=','
LASTVALIDATORINLIST=''
IP=''
USER='ubuntu'
PASSWORD='ChangeMe'
USE_TELEGRAM_BOT='no'

#Thresholds
CPU_THRESHOLD=''
HDD_THRESHOLD=''
RAM_THRESHOLD=''
ETH_THRESHOLD=''
RUN_EVERY=''

DOCKER_LIST=("fuseoracle-signature-request" "fuseoracle-redis" "fuseoracle-initiate-change" "fuseoracle-collected-signatures" "fuseoracle-rewarded-on-cycle" "fuseoracle-rabbitmq" "fuseoracle-affirmation-request" "fuseoracle-sender-home" "fuseoracle-sender-foreign" "fuseapp" "fusenet" "fusenetstat")


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
  fi

  if [[ $TELEGRAM_CHAT_ID != '' && $TELEGRAM_BOT_KEY != '' ]];
  then
    echo "BOT configured"
    USE_TELEGRAM_BOT='yes'
  else
    echo "No telegram settings"
    exit 1
  fi
}

function parseThresholds()
{
  if [[ ! -f $MONITOR_SETTINGS ]];
  then
    echo "Need to grab a new settings file"
    wget -O $MONITOR_SETTINGS https://raw.githubusercontent.com/Andrew-Pohl/FUSE_KVM_Manager/monitor/monitor_settings.txt
  fi

  echo -e "\nreading monitor settings\n"
  SAVEIFS=$IFS   # Save current IFS
  IFS="="
  Monitor_keys=()
  Monitor_values=()
  Monitor_line=()
  settings="Setting up the monitor with the following settings%0A"
  while read -r key value
    do
      settings="${settings}$key=$value%0A"
      if [[ $key == "CPU" ]];
      then 
        CPU_THRESHOLD=$value
      elif [[ $key == "RAM" ]];
      then
        RAM_THRESHOLD=$value
      elif [[ $key == "HDD" ]];
      then
        HDD_THRESHOLD=$value
      elif [[ $key == "ETHBalance" ]];
      then
        ETH_THRESHOLD=$(bc <<< "scale = 0; ($value * 1000000000000000000 )")
      elif [[ $key == "RunEvery" ]];
      then
        RUN_EVERY=$value
      fi        
    done < $MONITOR_SETTINGS
  IFS=$SAVEIFS   # Restore IFS
  
  telegramSendMessage $settings
}

function createReportFile()
{
  rm -f $REPORT_FILE
  
  #create a new report file for each KVM this will be used to keep track of when alerts we're sent to aviod spamming
  [ ! -f $INPUT ] && { echo "$INPUT file not found"; exit 99; }
  while read validator ip ethaddr defaultPassword
  do
    currentValidator=$validator
    echo "$currentValidator,0,0,0,0,0" >> $REPORT_FILE
  done < $INPUT
}

function setup()
{
  configureTelegramBot
  parseThresholds
  createReportFile
  SAVEIFS=$IFS
  IFS=$'\n' 
  DOCKER_LIST=($(sort <<<"${DOCKER_LIST[*]}"))
  IFS=$SAVEIFS
}

function getEthBalance()
{
  local addr=$1
  
  ETH_API_CALL="https://blockscout.com/eth/mainnet/api?module=account&action=eth_get_balance&address="
  ETH_API_CALL="${ETH_API_CALL}$addr"
  ethAPIOutput="$(curl -s $ETH_API_CALL)"

  IFS=',' read -ra eth_array <<< "$ethAPIOutput"

  ETHBALANCE='0'
  #Pull appart the json returns and pull out the current block numbers for fuse and eth
  for i in "${eth_array[@]}"
  do
    #look for the result in the json return
    if [[ $i == *"result"* ]]; then
      #remove the first the key and :
      stripped=${i#*:}
      #strip the white space and 0x and trailing "
      stripped="${stripped:3:-1}"
      #convert from hex to decimal
      ETHBALANCE=$((16#$stripped))
    fi
  done

  #ETHBALANCE=$(bc <<< "scale = 10; ($ETHBALANCE / 1000000000000000000 )")
  echo "$ETHBALANCE"
}

function CheckValidatiors()
{
  local currentValidator=$1

    	#currentValidator=$validator
    	echo "running for $currentValidator"
	getIP $currentValidator
    	freeDriveSpaceBytes=''
    	ethAddr=''
    	freeMemory=''
   	CPU_USAGE=''

   	#check when we last sent an error, if over one hour then see if we have broken any thresholds and send errors
   	line=$(grep "$currentValidator" $REPORT_FILE)

   	IFS=',' read -ra timeStampArray <<< "$line"

      
   	CPU_MON_TIME=${timeStampArray[1]}
   	RAM_MON_TIME=${timeStampArray[2]}
   	HDD_MON_TIME=${timeStampArray[3]}
   	ETH_MON_TIME=${timeStampArray[4]}
   	DOCKER_MON_TIME=${timeStampArray[5]}

   	currentTime=$(date +%s )
   	timeDif=$(( $currentTime - ${timeStampArray[1]} )) 
 	if (( timeDif > 3600 ))
	then
		echo "$currentValidator checking cpu"
		CPU_USAGE=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" top -b -n2 -p 1 | fgrep "Cpu(s)" | tail -1 | awk -F'id,' -v prefix="$prefix" '{ split($1, vs, ","); v=vs[length(vs)]; sub("%", "", v); printf "%s%.1f%%\n", prefix, 100 - v }')
		CPU_USAGE="${CPU_USAGE//%}"   
		#round up to int
		CPU_USAGE=$(printf '%.*f\n' 0 "$CPU_USAGE")
		#CPU threshold
		if (( CPU_USAGE > CPU_THRESHOLD )) 
		then
			CPU_MON_TIME=$currentTime
			telegramSendMessage "ALERT!: $currentValidator CPU USAGE = $CPU_USAGE%"
		fi
   	fi

	timeDif=$(( $currentTime - ${timeStampArray[2]} ))
	if (( timeDif > 3600 ))
	   then
		echo "$currentValidator checking ram"
		freeMemory=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" "free -m  | grep Mem")   
		freeMemory="$((  $(echo $freeMemory | awk '{print $2}') -  $(echo $freeMemory | awk '{print $3}') ))"   
		#RAM threshold
		if (( freeMemory < RAM_THRESHOLD ))
		then
                	RAM_MON_TIME=$currentTime
                	telegramSendMessage "ALERT!: $currentValidator Free ram = $freeMemory MB"
        	fi
   	fi

	timeDif=$(( $currentTime - ${timeStampArray[3]} ))
	if (( timeDif > 3600 ))
	   then
		   echo "$currentValidator checking HDD"

		freeDriveSpaceBytes=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" "df -k --output=avail /home/ubuntu  | tail -n1")
		freeDriveSpaceMB="$(( freeDriveSpaceBytes / 1024 ))"
	   
		#HDD Threshold
		if (( freeDriveSpaceMB < HDD_THRESHOLD ))
		then
			HDD_MON_TIME=$currentTime
                	telegramSendMessage "ALERT!: $currentValidator HDD space = $freeDriveSpaceMB MB"
        	fi
   	fi

	timeDif=$(( $currentTime - ${timeStampArray[4]} ))
	if (( timeDif > 3600 ))
	then
		echo "$currentValidator checking ETH"

		ethAddr=$(sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" 'cat /home/"$USER"/fuse-validator/fusenet/config/address')   
		Balance=$(getEthBalance $ethAddr)   
		#ETH Threshold
		ETH_THRESHOLD=$(printf '%.*f\n' 0 "$ETH_THRESHOLD")
		if (( Balance < ETH_THRESHOLD ))
		then
                	ETH_MON_TIME=$currentTime
			Balance=$(bc <<< "scale = 10; ($Balance / 1000000000000000000 )")
                	telegramSendMessage "ALERT!: $currentValidator Eth balance = $Balance ETH"
        	fi
   	fi

	timeDif=$(( $currentTime - ${timeStampArray[5]} ))
	if (( timeDif > 3600 ))
	then
		echo "$currentValidator checking docker"
                sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" >/dev/null  << EOF
   		 echo "$PASSWORD" | sudo -S docker ps > dockerOutput.txt;
EOF
		sshpass -p "$PASSWORD" scp "$USER"@"$IP":/home/"$USER"/dockerOutput.txt dockerOutput.txt
		sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no "$USER"@"$IP" 'rm -f dockerOutput.txt'
		temp=$(cat dockerOutput.txt)
		containers=$(awk '{if(NR>1) print $NF}' dockerOutput.txt)

		SAVEIFS=$IFS   # Save current IFS
		IFS=$'\n'      # Change IFS to new line
		containers=($containers) # split to array $names
		IFS=$SAVEIFS   # Restore IFS

		Balance=$(getEthBalance $ethAddr)
		echo "$Balance"

		SAVEIFS=$IFS
		IFS=$'\n'
		containers=($(sort <<<"${containers[*]}"))
		IFS=$SAVEIFS

		got=${containers[@]}
		expected=${DOCKER_LIST[@]}
	   
		#Dockers running
        	if [ "$got" != "$expected" ]
   		then
          		DOCKER_MON_TIME=$currentTime
          		telegramSendMessage "ALERT!: $currentValidator Some dockers not running running container = $got"
        	fi
   	fi

  sed -i "s/^$currentValidator.*/$currentValidator,$CPU_MON_TIME,$RAM_MON_TIME,$HDD_MON_TIME,$ETH_MON_TIME,$DOCKER_MON_TIME/" "$REPORT_FILE"
  IFS=','
}



setup
while true; do
	validatorsARR=()
	while read validator ip ethaddr defaultPassword
  	do
		if [ "$defaultPassword" == "yes" ]
		then
			#currently only supports deault passwords
			validatorsARR=("$validator" "${validatorsARR[@]}")
		fi
  	done < $INPUT

	for i in "${validatorsARR[@]}"
	do
		CheckValidatiors "$i"
	done
  
	sleep "$RUN_EVERY"
done
