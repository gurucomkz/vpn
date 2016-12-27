#!/bin/bash

pip=`ifconfig eth0 2>/dev/null|awk '/inet addr:/ {print $2}'|sed 's/addr://'`
aptitude install -y racoon xl2tpd iptables
lip="10.1.0.0"
psk=`date +%s | sha256sum | base64 | head -c 20;`



cat << EOF > /etc/racoon/psk.txt
*	$psk
EOF

cat << EOF > /etc/racoon/racoon.conf
log notify;
path pre_shared_key "/etc/racoon/psk.txt";
path certificate "/etc/racoon/certs";

remote anonymous {
        exchange_mode main;
        generate_policy on;
        nat_traversal on;
        lifetime time 24 hour ;

        dpd_delay 20;

        proposal {
                # Win7 pararmeters.
                encryption_algorithm 3des;
                hash_algorithm sha1;
                authentication_method pre_shared_key;
                dh_group modp1024;
        }

        proposal {
                # WinXP pararmeters.
                encryption_algorithm 3des;
                hash_algorithm md5;
                authentication_method pre_shared_key;
                dh_group modp1024;
        }

        proposal {
                encryption_algorithm aes;
                hash_algorithm md5;
                authentication_method pre_shared_key;
                dh_group modp1024;
        }

}
sainfo anonymous {
        lifetime time 12 hour ;
        encryption_algorithm aes, 3des;
        authentication_algorithm hmac_sha1, hmac_md5;
        compression_algorithm deflate;
}
EOF

cat << EOF > /etc/xl2tpd/xl2tpd.conf
[global]
access control = no
debug avp = yes
debug network = yes
debug state = yes
debug tunnel = yes

[lns default]
ip range = 10.1.0.100-10.1.0.150
local ip = 10.1.0.1
require authentication = yes
require chap = yes
refuse pap = yes
length bit = yes
name = l2tpd
pppoptfile = /etc/ppp/xl2tpd-options
ppp debug = yes
bps = 1000000

EOF

cat << EOF > /etc/ppp/chap-secrets
#Example:
#login             l2tpd   password         *
EOF


cat << EOF > /etc/ppp/xl2tpd-options
auth
debug
nodefaultroute
lock
proxyarp
require-chap
idle 18000
mtu 1200
mru 1200
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF

#network
echo 1 > /proc/sys/net/ipv4/ip_forward
sed -i -e "s/#net.ipv4.ip_forward/net.ipv4.ip_forward/g" /etc/sysctl.conf

/sbin/iptables -t nat -A POSTROUTING -o eth0 -s $lip/24 -j MASQUERADE
/sbin/iptables -t nat -A POSTROUTING -s $lip/24 -j SNAT --to-source $pip
/sbin/iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
/sbin/iptables -A INPUT -p udp --dport 500 -j ACCEPT
/sbin/iptables -A INPUT -p udp --dport 4500 -j ACCEPT
/sbin/iptables -A INPUT -p esp -j ACCEPT
/sbin/iptables -A INPUT -p udp -m policy --dir in --pol ipsec -m udp --dport 1701 -j ACCEPT


cat << EOF > /etc/ipsec-tools.d/l2tp.conf
spdadd $pip[l2tp] 0.0.0.0/0 udp -P out ipsec
        esp/transport//require;
spdadd 0.0.0.0/0 $pip[l2tp] udp -P in ipsec
        esp/transport//require;
EOF


/etc/init.d/setkey start
/etc/init.d/racoon restart
/etc/init.d/xl2tpd restart


echo
echo
echo "NOW, Edit /etc/ppp/chap-secrets and add users"
echo "Your PSK key $psk"