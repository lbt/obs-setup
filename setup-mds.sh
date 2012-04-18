#!/bin/bash

# Mer Delivery System host:port
MDS="mer.dgreaves.com:8001"
VMS="obsfe:fe obsbe:be obsw1:worker"

OBSFE_INT="obsfe.dgreaves.com"
OBSBE_SRC="obsbe.dgreaves.com"


## Connect MDS

# Here we need to pull the pem and install it to this locn:

rm -rf ~/.config/osc .oscrc

mkdir -p ~/.config/osc/trusted-certs
openssl s_client  -tls1 -connect obsfe.dgreaves.com:443 2>/dev/null < /dev/null \
  | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' \
   > ~/.config/osc/trusted-certs/${OBSFE_INT}_444.pem

cat > ~/.oscrc <<EOF
[general]
gnome_keyring = 0
keyring = 0
use_keyring = 0
[https://${OBSFE_INT}:444]
user=Admin
pass=opensuse
EOF


osc -A https://${OBSFE_INT}:444 ls

osc -A https://${OBSFE_INT}:444 meta prj MerDS -F - <<EOF
<project name="MerDS">
 <title>Mer Delivery System</title>
 <description>A 'remote link' to the MDS API service running against a local copy of Mer
 </description>
 <remoteurl>http://${MDS}/public</remoteurl>
 <person userid="Admin" role="maintainer"/>
 <person userid="Admin" role="bugowner"/>
</project>
EOF

osc -A https://${OBSFE_INT}:444 meta prj MyMerUx -F - <<EOF
<project name="MyMerUx">
  <title>MyMerUx</title>
  <description>
  A UX building against Mer
  </description>
  <person userid="Admin" role="maintainer"/>
  <person userid="Admin" role="bugowner"/>
  <repository name="MyMerUX_Mer_Core_i586">
    <path repository="Core_i586" project="MerDS:Core:i586"/>
    <arch>i586</arch>
  </repository>
  <repository name="MyMerUX_Mer_Core_armv7hl">
    <path repository="Core_armv7hl" project="MerDS:Core:armv7hl"/>
    <arch>armv8el</arch>
  </repository>
</project>
EOF

osc -A https://${OBSFE_INT}:444 copypac MerDS:Core:i586 acl MyMerUx
