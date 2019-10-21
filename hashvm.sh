#!/bin/sh
# Detect which files have been changed and/or added to a VBox VM image. Useful for manual malware detection in a virtual environment
# Prerequisites: VirtualBox with vboximg-mount, hashdeep, Optional: NTFS-3G for NTFS support and ext4fuse for EXT support.
# This version only works on MacOS due to vboximg-mount is only available on that platform currently ..
# v1.0 - mikael keri / @nsmfoo

echo "
██╗  ██╗ █████╗ ███████╗██╗  ██╗ ██╗   ██╗███╗   ███╗  
██║  ██║██╔══██╗██╔════╝██║  ██║ ██║   ██║████╗ ████║   
███████║███████║███████╗███████║ ██║   ██║██╔████╔██║   
██╔══██║██╔══██║╚════██║██╔══██║ ╚██╗ ██╔╝██║╚██╔╝██║   
██║  ██║██║  ██║███████║██║  ██║  ╚████╔╝ ██║ ╚═╝ ██║   
╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝   ╚═══╝  ╚═╝     ╚═╝   v1.0 (MacOS & VBox only ..)
@nsmfoo                                                                        "
echo

# Variables
max_size=500m
hash=sha256

if [ $USER != 'root' ] ; then
  echo "- You need to run this script as root!"
  exit 
fi

usage () {
   echo "usage: $0 -i image_name (inkl path) -m mount_dir -a <check|update> (optional) -e exclude regexp(ex: '^\/Users\/')"
  }

image_name=""
mount_dir=""
while getopts ":i:m:h:a:e:" option; do
  case $option in
    i)  image_name="$OPTARG" ;;
    m)  mount_dir="$OPTARG" ;;
    a)  hashdb="$OPTARG" ;;
    e)  exclude_file="$OPTARG" ;;
    h)  usage
        exit 0
        ;;
    :)  echo "Error: requires an argument: $options"
        usage
        exit 1
        ;;
    ?)  echo "Error: unknown option: $options"
        usage
        exit 1
        ;;
  esac
done

# Check dependencies 
if [ ! -f /usr/local/bin/vboximg-mount ]; then
  echo "Missing vboximg-mount, please install Virtualbox"
  exit 1
fi

if [ ! -f /usr/local/bin/hashdeep ]; then
  echo "Missing hashdeep, please install"
  exit 1
fi

if [ -z "$image_name" ]; then
  echo "No image defined, please supply full path! "
  usage
  exit 1
fi

if [ -z "$mount_dir" ]; then
  echo "No mount directory defined"
  usage
  exit 1
fi

if [ -z "$hashdb" ]; then
  echo "No Hashdeep command defined - valid values are check or update"
  usage
  exit 1
fi

if [ $hashdb != "update" -a $hashdb != "check" ]; then
 echo "Valid arguments are either update or check"
 usage
 exit 1
fi

# Remove trailing slash
mount_dir="${mount_dir%/}"

# Mount image. It's a two step thingy 
mount1_dir="/var/lib/temp_mount"
if [ ! -d "$mount1_dir" ]; then
  printf "* Creating temp mount dir directory.. "
  mkdir $mount1_dir
  printf "finished!\n"
fi

# Mounting time! Not Mountain Time, that would make no sense ...
party_list=$(vboximg-mount --image="$image_name" --list)
if [[ $party_list == *"(2)"* ]]; then
  part_list_name=($(vboximg-mount --image="$image_name" --list | grep -v -E '\*|#|Vir|UUID|Partition|^$' | grep -o '.*)'))
  part_list_size=($(vboximg-mount --image="$image_name" --list | grep -v -E '#|Vir|UUID|Partition|\*|^$' | awk {'print $2'}))
  part_list="$part_list_name:$part_list_size"
else
  part_list_name=$(vboximg-mount --image="$image_name" --list | grep -v -E '#|Vir|UUID|Partition|^$' | grep -o '.*)')
  part_list="$part_list_name:2048"
fi
part_array=$(echo $part_list | tr " " "\n")

if [[ $party_list == *"NTFS"* ]]; then
   if [ ! -f /usr/local/bin/ntfs-3g ]; then
     printf "Missing NTFS-3G, please install it\n"
     exit 1
   fi
fi

if [[ $party_list == *"Linux"* ]]; then
   if [ ! -f /usr/local/bin/ext4fuse ]; then
     printf "Missing ext4fuse, please install it\n"
     exit 1
   fi
fi

# Fix for Windows VMs
if [[ $part_array =~ [a-zA-Z] ]]; then
 part_array=($(echo $part_array | sed 's/.*(\(.*\))/\1/'))
fi

for x in "${part_array[@]}"
do
   printf "Mounting image..\n"
   part_number=$(echo $x | cut -d':' -f1)
   vboximg-mount --image="$image_name" -p $part_number $mount1_dir

   # Depending on the filesystem use different "tools" to mount
   if [[ $party_list == *"NTFS"* ]]; then
    printf "NTFS it is!\n"
    /usr/local/bin/ntfs-3g $mount1_dir/vhdd $mount_dir 
   fi
  
   if [[ $party_list == *"Linux"* ]]; then
    printf "EXT it is!\n"
    /usr/local/bin/ext4fuse $mount1_dir/vhdd $mount_dir 
   fi  
done

# Init the hashdeep db if it does not exist
hash_dir="/var/lib/hash_dir/"
if [ ! -d "$hash_dir" ]; then
  printf "* Setting up db directory... "
  mkdir $hash_dir
  printf "finished!\n"
fi

logfile=$(echo "$image_name" | sed "s/.*\///")
if [ ! -f "$hash_dir$logfile" ]; then
  printf "A hashdb does not exist for this image. First run, this will take some time...\n"
  hashdeep -s -o fe -c $hash -r -I $max_size -W "$hash_dir$logfile" "$mount_dir"  
fi

# Check for changes
if [ "$hashdb" = "check" ]; then
   printf "Checking for changes.. \n"
   hashdeep -a -k "$hash_dir$logfile" -I $max_size -v -v -s -o fe -r $mount_dir | sed 's/^\'$mount_dir'//' > "$hash_dir$logfile"_diff.log
  
   if [ ! -z "$exclude_file" ]; then
    rm "$hash_dir$logfile"_excluded_diff.log
    printf "Changes, excluding the directories in the exclusion list are written to: "$hash_dir$logfile"_excluded_diff.log\n"
    
    while read x; do 
        if [[ ! "$x" =~ $exclude_file ]]; then
            if [[ "$x" =~ ^\/ ]]; then
             echo $x >> "$hash_dir$logfile"_excluded_diff.log
            fi
        fi
    done <  "$hash_dir$logfile"_diff.log
    
   else
    all_changes=$(grep '^\/' "$hash_dir$logfile"_diff.log)
    if [ -z "$all_changes" ]; then
     printf "No changes recorded!\n" 
    else
     printf "All changes are written to: " 
     printf "$hash_dir$logfile"_diff_all.log
     echo "$all_changes" > "$hash_dir$logfile"_diff_all.log
    fi
   fi
fi

if [ "$hashdb" = "update" ]; then
   printf "Updating Hashdb.. this will take some time.. "
   hashdeep -s -o fe -c $hash -r -I $max_size -W "$hash_dir$logfile" "$mount_dir"
   printf "finished!\n"
fi

# Umount x 2
printf "\nCleaning.. "
umount $mount_dir
umount $mount1_dir
printf "finished!\n"
