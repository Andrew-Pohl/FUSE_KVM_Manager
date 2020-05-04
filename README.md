# FUSE_KVM_Manager

# Description
The KVM Manager script allows a validator to easily control KVM instances to allow for multiple nodes on one machine 
with minimal effort.

```
The Manager allows the user to perform a number of task
• Create KVM instance, set them up and start validating - from one press.
• Update the quickstart/fuse enviroment for all running servers with one button press - this makes updating validators far easier.
• Create encrypted back up folders.
• Relaunch KVM instances from previous backups. This allows for much easier server migration and error recovery.
• List running KVM instances.
• Get IPs of running KVMs.
• Encrypt/Decrypt backup folders.
```

Make sure you give the script execute permissions

• sudo chmod 777 FUSE_KVM_Manager.sh

Then simply run the script with sudo privileges (the script pulls all dependencies on launch)

• sudo ./FUSE_KVM_creator.sh

Follow the on screen menus and away you go.

# Backup
To backup KVM instances run the script and press 3 - "Create KVM backup" when prompted. If this is the first backup encfs 
will do a first time config simply follow the on screen instruction. The script will then recurse into running KVMs and 
pull the config data from each and store it in the new encfs folder decryptedBackup. While the file system is still unencrypted
copy the folders contents to a cold storage or another machine (please ensure it is safe from prying eyes!) then re-encrypt
the folders on your host server press 8 - "Encrypt Backup" in the manager. 

To restore from a backup and create copied KVM instances on a new server run the manager script press 3 - "Create KVM 
backup" when prompted, this will create the folders copy across the previously backed up files to the decryptedBackup folder.
Then simply press 4 - "Restore from KVM backup" when prompted. This will recurse through the backed up files, create a KVM
instance with the backed up config and start them validating! - this can take upto 15mins per kvm. Once done re-encrypt
the folders on your new host server press 8 - "Encrypt Backup" in the manager. 

# Telegram Message Bot
The script can interact with the telegram API to send you handy status messages. On boot if not configured the script will
prompt you to set up a telegram bot (this is optional). To set up a new bot follow these instruction in Brice Johnsons blog
post [here](https://blog.bj13.us/2016/09/06/how-to-send-yourself-a-telegram-message-from-bash.html). It's simple!, once 
configured the script will store the bot and chat keys to a text file so they can be used again.

# How to use with KVMs setup outside the script
I have added a mechanisum to use the KVM manager on KVMs which have been configured outside of the script. Simply manual
add your KVMs to the list file:
```
KVM_NAME = the name used when configuring the KVM (virsh list will give you a complete list)
IP_ADDR & ETH_ADDR = just set these to 0 or 1... they are not currently used
DEFAULT_PASSWORD = Set this to "no" this will prompt the script to ask for the KVM user name and password when/if it needs them
```

Note: please leave the v0,1,1,yes line at the bottom!. These a bug in the script that means it won't be able to create new
KVMs without it. Will fix this shortly :)

# Monitoring
I have ported my monitoring python script to bash. The python script is now depricated and any further changes will be made here.
The monitor gets called by the manager as a nohup task the monitor takes user defined inputs stored in the monitor_settings.txt
file which gets populated by the manager. The monitor traverses into the KVMs and checks:
```
• CPU utalisation
• Avaliable RAM
• Avaliable Hard drive space
• Balance of eth
• All docker containers are currently running
```
If any of the thresholds are breached a telegram message will be sent to your bot. This should allow for easy monitoring 
and help detect any potential issues on your nodes.