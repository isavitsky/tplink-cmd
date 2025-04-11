#!/usr/bin/env bash
#
# Script for TP-Link Esy Smart Switch port configuration
# Tested on TL-SG105E and TL-SG108PE.
#
# Speed:
# 1 - Auto
# 2 - 10MH
# 3 - 10MF
# 4 - 100MH
# 5 - 100MF
# 6 - 1000MF
#
# Extract lines between 2 tokens in a text file using bash:
# https://stackoverflow.com/questions/4857424/extract-lines-between-2-tokens-in-a-text-file-using-bash

CURL_OPTS="--connect-timeout 5 --max-time 6 --silent"

curl="curl $CURL_OPTS"
state=DISC
ip=""
login=""
passwd=""

function err () {
	[[ -n $1 ]] && echo ERR: $@
}

function cmd_help () {
cat << EOT
Available commands:
h : help
c : log in to switch
p : print switch ports
s : set port parameters
w : save config
r : reboot switch
q : quit
EOT
}

function curl_err () {
	[[ -z $1 ]] && return
	echo -n "ERR id $1" >&2
	[[ $1 == 2 ]] && echo -n ": Failed to initialize." >&2
	[[ $1 == 6 ]] && echo -n ": Could not resolve host." >&2
	[[ $1 == 7 ]] && echo -n ": Failed to connect to host." >&2
	[[ $1 == 28 ]] && echo -n ": Connection time-out." >&2
	echo >&2
}

function cmd_login () {
	local ret
	local rc
	local hcd

	echo -n "ip="
	read ip
	echo -n "login="
	read login
	echo -n "passwd="
	read -s passwd
	echo
	echo

	ret=$(batch_login)
	rc=$?

	case $ret in
		"200")
			echo Connected.
			;;
		"401")
			echo Login incorrect.
			return
			;;
		*)
			[[ -n $ret ]] && hcd=" (Curl HTTP code: $ret)"
			echo "Login error.$hcd"
			return
			;;
	esac

	$curl -so out.txt "http://$ip/SystemInfoRpm.htm" >/dev/null 2>&1
	echo
	echo Switch System Info:
	echo -------------------
	sed -n '/var info_ds = {/{:a;n;/};/b;p;ba}' out.txt 2>/dev/null | tr -d '\n' | sed 's/,/\n/g'
	echo
	echo
}

function send_login_data () {
	local rc

	[[ -z $ip ]] && return 255
	$curl -so /dev/null -X POST --data "username=${login}&password=${passwd}&cpassword=&logon=Login" http://${ip}/logon.cgi >/dev/null 2>&1
	rc=$?
	if [[ $rc -ne 0 ]]; then
		curl_err $rc
		return $rc
	fi
}

function check_access () {
	local rc
	local info_ds

	if [[ -z $ip ]]; then
		echo 000
		return 255
	fi

	rm -f out.txt
	$curl -so out.txt "http://$ip/SystemInfoRpm.htm" 2>/dev/null
	info_ds=$(sed -n '/var info_ds = {/{:a;n;/};/b;p;ba}' out.txt 2>/dev/null)
	rc=$?
	[[ $rc -ne 0 ]] && curl_err $rc
	[[ -z $info_ds ]] && echo 401 || echo 200
	return $rc
}

function batch_login () {
	local ret
	local rc

	ret=$(check_access)
	rc=$?
	[[ $rc -ne 0 ]] && return $rc
	if [[ $ret == "200" ]]; then
		echo $ret
	        return
	fi

	send_login_data
	rc=$?
	[[ $rc -ne 0 ]] && return $rc

	check_access
	return $?
}

function print_port () {
	local mode
	local status
	local speed

	if [[ $1 -eq 1 ]]; then
		case $2 in
			1)
				mode="Auto"
				;;
			2)
				mode="10/Half"
				;;
			3)
				mode="10/Full"
				;;
			4)
				mode="100/Half"
				;;
			5)
				mode="100/Full"
				;;
			6)
				mode="1000/Full"
				;;
			*)
				mode="Unknown"
				;;
		esac
	else
		mode="Disabled"
	fi

	[[ $3 -ne 0 ]] && status="Up"
	[[ $3 -eq 0 ]] && status="Down"

	case $3 in
		0)
			speed="-"
			;;
		1)
			speed="Auto"
			;;
		2)
			speed="10/Half"
			;;
		3)
			speed="10/Full"
			;;
		4)
			speed="100/Half"
			;;
		5)
			speed="100/Full"
			;;
		6)
			speed="1000/Full"
			;;
		*)
			speed="Unknown"
			;;
	esac
	printf "%-05s%-10s%-11s%s\n" $4 $status $mode $speed
}

function cmd_ports () {
	local ret

	ret=$(batch_login)
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return
	fi

	$curl -s -o out.txt "http://$ip/PortSettingRpm.htm" 2>/dev/null
	port_str=$(sed -n 's/state:\[\([^"]*\)\],/\1/p' out.txt 2>/dev/null | tr ',' ' ')
	ports=($port_str)
	spdc_str=$(sed -n 's/spd_cfg:\[\([^"]*\)\],/\1/p' out.txt 2>/dev/null | tr ',' ' ')
	spdc=($spdc_str)
	spda_str=$(sed -n 's/spd_act:\[\([^"]*\)\],/\1/p' out.txt 2>/dev/null | tr ',' ' ')
	spda=($spda_str)
	echo Switch ports:
	echo -------------
	printf "%-05s%-10s%-11s%s\n" "#" "Status" "Op Mode" "Speed/Duplex"
	n=1
	for i in ${!ports[@]}; do
		print_port ${ports[$i]} ${spdc[$i]} ${spda[$i]} $n
		((n++))
	done
	echo $portstate
}

function cmd_setport () {
	local ret
	local port
	local state

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	echo Set port mode:
	echo -n port=
	read port
	echo Select mode: 0-Disabled 1-Auto 2-10/Half 3-10/Full
	echo "             4-100/Half 5-100/Full 6-1000/Full"
	echo -n mode=
	read mode
	[[ $mode -eq 0 ]] && state=0 || state=1

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	$curl -so /dev/null "http://$ip/port_setting.cgi?portid=${port}&state=${state}&speed=${mode}&flowcontrol=0&apply=Apply" 2>/dev/null
	rc=$?
	if [[ $rc -ne 0 ]]; then
		curl_err $rc
		return $rc
	fi
}

function cmd_save () {
	local ret
	local x

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	echo -n "Save current config (y/n): "
	read x
	[[ $x != "y" ]] && return

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	$curl -so /dev/null -X POST --data "action_op=save" http://${ip}/savingconfig.cgi >/dev/null 2>&1
	rc=$?
	if [[ $rc -ne 0 ]]; then
		curl_err $rc
		return $rc
	fi
}

function cmd_reboot () {
	local ret
	local x

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	echo -n "Reboot switch (y/n): "
	read x
	[[ $x != "y" ]] && return

	ret=$(batch_login)
	rc=$?
	if [[ $ret != "200" ]]; then
		echo Not logged in
		return $rc
	fi

	$curl -so /dev/null -X POST --data "reboot_op=reboot&save_op=false" http://${ip}/reboot.cgi >/dev/null 2>&1
	rc=$?
	if [[ $rc -ne 0 ]]; then
		curl_err $rc
		return $rc
	fi
}

echo "TP-Link Smart Switch port speed configurator"
echo "h: help"
echo
echo -n "> "
while read STR; do
	[[ $STR == "q" ]] && break
	[[ $STR == "h" ]] && cmd_help
	[[ $STR == "c" ]] && cmd_login
	[[ $STR == "p" ]] && cmd_ports
	[[ $STR == "s" ]] && cmd_setport
	[[ $STR == "w" ]] && cmd_save
	[[ $STR == "r" ]] && cmd_reboot
	echo -n "> "
done

rm -f out.txt

