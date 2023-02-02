
# Disk related functions

function check_disk_capacity() {
  dfOutput=`df -H -x tmpfs -x devtmpfs -x vfat -x squashfs`
  msg "    %s\n" "$dfOutput"
  currentDate=$(date -R)
  hostname=$(hostname -f)
  FAILMSG=""
  while read -r output; do
    usePercentage=$(echo $output | awk -F'%' '{ print $1}')
    partition=$(echo $output | awk '{ print $2 }' )
    if [ $usePercentage -ge 85 ]; then
      FAILMSG="${FAILMSG}\n    ${partition} is at ${usePercentage}% usage"
    fi
  done <<< $(awk 'NR != 1 { print $5 " " $1 }' <<<"$dfOutput")

  if [ "$FAILMSG" != "" ]; then
    error "Low disk space on ${hostname} at ${currentDate}:\n${RESET}${FAILMSG}\n"
    error "Please verify you've got enough disk space before continuing! Either prune images using 'docker image prune -a' or expand the volume!"
    return 1
  fi
}
