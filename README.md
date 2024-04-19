rat
===

Rat is a programmable network address translator (NAT) written in pure-ruby.
It is written as a TUN device.

## Features

- Supported...TCP, UDP, ICMP Echo Request/Reply (outbound ping), inbound ICMP Errors (Destination Unreachable, Time Exceeded, Packet Too Big(v6))
- Unsupported...IP fragment packet, SCTP, DCCP, static NAT, stateful inspection on TCP
- NAT tables (refer to RFC 4787 etc.)
  - Full Cone NAT
    - A simple 1:1 NAPT. The number of NAT mappings will be capped by the number of external ports (unlike others).
  - (quasi-) Restricted Cone NAT
    - Actually has "Address-Dependent" mapping, but tries to use the same port number for a same internal port, so behaves like EIM/ADF in most cases.
  - (quasi-) Port-Restricted Cone NAT
    - Similar as above. Much like netfilter's default SNAT/MASQUERADE behavior.
  - Symmetric NAT
    - The port number is always randomized, hence APDM/APDF. Much like netfilter's SNAT/MASQUERADE with `--random`.
- The status can be checked through Web interface (*:8080).
- May not work in Windows.

## Usage

```
ruby rat.rb
```

This creates a device "rat".

Packets sent to the device are NATted and then "returned" from it. The global (external) ip is hard-coded as `192.168.0.139`.

Some other parameters (NAT behavior, timeout, port range, etc.) are also hard-coded.

### Example settings with iproute2 and iptables

- `net.ipv4.ip_forward=1`
  - `accept_local` and `rp_filter` are not necessarily relevant
- `ip link set rat up`

- Assign IP addresses

  "internal" ip for rat
  ```
  sudo ip addr add 192.168.1.2/24 dev eno1 label eno1:rat
  ```
  "external" ip for rat
  ```
  sudo ip addr add 192.168.1.3/24 dev eno1 label eno1:rat2
  ```
  Note: Do NOT assign the global address (192.168.0.139) to ANY device.
- Policy-Based Routing
  - edit `/etc/iproute2/rt_tables`

  ```
  sudo ip route add default dev rat table rat
  sudo ip rule add from 192.168.1.2 lookup rat
  sudo ip rule add to 192.168.0.139 lookup rat
  ```

- Simple NAT between two external addresses
  ```
  sudo iptables -t nat -A POSTROUTING -o eno1 -s 192.168.0.139 -j SNAT --to-source 192.168.1.3
  sudo iptables -t nat -A PREROUTING -i eno1 -d 192.168.1.3 -j DNAT --to-destination 192.168.0.139
  ```
- (optional) ip rules
  ```
  sudo ip rule add from 192.168.2.0/24 lookup rat
  sudo ip rule add from 192.168.0.139 lookup some_vpn_table
  ```

- (optional) firewall rules
  ```
  sudo ufw route allow to 192.168.0.139
  sudo ufw allow in on rat
  sudo ufw route allow in on rat
  ```