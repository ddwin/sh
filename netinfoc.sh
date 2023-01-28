#!/bin/bash

dev=
mac=
ip=
gw=
net=
prefix=
__prefix=

# https://github.com/ppo/bash-colors
#
# x - Set  2x - Reset           3x - Foreground    4x - Backgroud
# [C]yan   [M]agenta  [Y]ellow  blac[K]   [W]hite  [R]ed  [G]reen  [B]lue
# bold([S]trong)      [I]talic  [U]nderline        blink([F]lash)  [N]egative
#
c() {
  if [ $# == 0 ]; then
    printf "\e[0m"
  else
    printf "%s" "$1" | sed \
      -e 's/\(.\)/\1;/g' \
      -e 's/\([SIUFN]\)/2\1/g' \
      -e 's/\([KRGYBMCW]\)/3\1/g' \
      -e 's/\([krgybmcw]\)/4\1/g' \
      -e 'y/SIUFNsiufnKRGYBMCWkrgybmcw/13457134570123456701234567/' \
      -e 's/^\(.*\);$/\\e[\1m/g'
  fi
}

cecho() {
  echo -e "$(c "$1")${2}\e[0m"
}

cecho_n() {
  echo -n -e "$(c "$1")${2}\e[0m"
}

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
  cecho G "============================================================================================"
  echo -n "Interface: "; cecho G "$dev"
  echo -n "      MAC: "; cecho G "$mac"
  echo -n "  IP Addr: "; cecho G "$ip"
  echo -n " Net Mask: "; cecho G "$msk"
  echo -n "  Gateway: "; cecho G "$gw"
  echo -n "     CIDR: "; cecho G "$ip/$prefix"
  echo -n "   Subnet: "; cecho G "$net/$prefix"
  cecho G "============================================================================================"
  echo
  cecho Y "For https://moeclub.org/attachment/LinuxShell/InstallNET.sh"
  echo
  cecho C "--ip-addr $ip --ip-gate $gw --ip-mask $msk"
  echo
  cecho Y "For https://raw.githubusercontent.com/bohanyang/debi/master/debi.sh"
  echo
  cecho C "--ip $ip --gateway $gw --netmask $msk"
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
    cecho_n Gk "Do you want to test information [y/N]? "
    read -r answer
    case ${answer:0:1} in
      y | Y) test_net_info ;;
    esac
  fi
}

main "$@"
