#!/bin/bash

dev=
mac=
ip=
gw=
net=
prefix=
__prefix=

ip_to_int() {
  IFS=. read -r i j k l <<< "$1"
  printf "%d" $(((i << 24) + (j << 16) + (k << 8) + l))
}

int_to_ip() {
  printf "%d.%d.%d.%d" \
    $((($1 >> 24) % 256)) $((($1 >> 16) % 256)) $((($1 >> 8) % 256)) $(($1 % 256))
}

get_prefix_from_fib() {
  _IFS=${IFS}
  IFS=$'\n'
  mapfile -t fib < <(cat /proc/net/fib_trie)
  IFS=${_IFS}
  for ((((idx = ${#fib[@]} - 1)); idx >= 0; )); do
    line="${fib[idx]}"
    if [[ ! ${line##*"/32 host LOCAL"*} ]]; then
      ((idx--))
      read -ra fields <<< "${fib[idx]}"
      if [ "${fields[1]}" = "${ip}" ]; then
        break
      fi
    fi
    ((idx--))
  done

  for (( ; idx >= 0; )); do
    line="${fib[idx]}"
    if [[ ! ${line##*"/0"*} ]]; then
      break
    elif [[ ! ${line##*"+--"*} ]]; then
      last_line=${line}
    fi
    ((idx--))
  done
  read -r prefix <<< "$(grep -Po '(?<=/)(\d)+' <<< "${last_line}")"
}

get_net_info() {
  read -ra route <<< "$(ip -o r get 8.8.8.8)"
  if [ "${route[1]}" = "via" ]; then
    gw="${route[2]}"
    dev="${route[4]}"
    ip="${route[6]}"
  else
    gw="openvz"
    dev="${route[2]}"
    ip="${route[4]}"
    echo "Can not get gateway."
    exit 1
  fi
  read -ra link <<< "$(ip -o l | grep "${dev}")"
  read -r mac <<< "$(grep -Po '..:..:..:..:..:..' <<< "${link[@]}")"
  read -ra address <<< "$(ip -o -4 a | grep "${ip}")"
  IFS="/" read -r dummy prefix <<< "${address[3]}"
  [ -z "$prefix" ] && __prefix=32 || __prefix=$prefix
  if [ "$prefix" = 32 ] || [ -z "$prefix" ]; then
    get_prefix_from_fib
  fi
  v=$((0xffffffff ^ ((1 << (32 - prefix)) - 1)))
  msk="$(((v >> 24) & 0xff)).$(((v >> 16) & 0xff)).$(((v >> 8) & 0xff)).$((v & 0xff))"
  msk_int=$(ip_to_int "$msk")
  ip_int=$(ip_to_int "$ip")
  net_int=$((msk_int & ip_int))
  net=$(int_to_ip "$net_int")
  echo
  echo "============================================================================================"
  echo "Interface: $dev"
  echo "      MAC: $mac"
  echo "  IP Addr: $ip"
  echo " Net Mask: $msk"
  echo "  Gateway: $gw"
  echo "     CIDR: $ip/$prefix"
  echo "   Subnet: $net/$prefix"
  echo "============================================================================================"
  echo
  echo "For https://moeclub.org/attachment/LinuxShell/InstallNET.sh"
  echo
  echo "--ip-addr $ip --ip-gate $gw --ip-mask $msk"
  echo
  echo "For https://raw.githubusercontent.com/bohanyang/debi/master/debi.sh"
  echo
  echo "--ip $ip --gateway $gw --netmask $msk"
  echo
}

test_net_info() {
  trap "" INT
  echo "Start test ..."
  IFS=$'\n' mapfile -t orig_route < <(ip r)
  ip a del "$ip" dev "$dev" > /dev/null 2>&1
  ip r flush table main > /dev/null 2>&1
  ip r flush cache > /dev/null 2>&1
  ip a add "$ip/$prefix" dev "$dev" > /dev/null 2>&1
  ip a flush "$ip/$prefix" dev "$dev" > /dev/null 2>&1
  ip r add "$net/$prefix" dev "$dev" scope link src "$ip" > /dev/null 2>&1
  ip r add default via "$gw" dev "$dev" src "$ip" > /dev/null 2>&1
  if ping -c 1 -w 10 -q 8.8.8.8 > /dev/null 2>&1; then
    echo "Test OK."
  else
    echo "Test failed. Restore ip and route ..."
    ip a del "$ip" dev "$dev" > /dev/null 2>&1
    ip r flush table main > /dev/null 2>&1
    ip r flush cache > /dev/null 2>&1
    ip a add "${ip}/${__prefix}" dev "$dev" > /dev/null 2>&1
    for ((((idx = ${#orig_route[@]} - 1)); idx >= 0; )); do
      line="${orig_route[idx]}"
      ip r add "${line}"
      ((idx--))
    done
  fi
}

main() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root." >&2
    exit 1
  fi

  get_net_info

  if [ "${__prefix}" = 32 ]; then
    read -r -p "Do you want to test information [y/N]? " answer
    case ${answer:0:1} in
      y | Y) test_net_info ;;
    esac
  fi
}

main "$@"
