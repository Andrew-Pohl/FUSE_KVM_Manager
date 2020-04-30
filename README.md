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
 