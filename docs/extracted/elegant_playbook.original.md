# Executive Summary

This document describes the controlled introduction of Kamailio as a SIP
routing layer in front of existing FusionPBX and FreeSWITCH servers,
followed by the migration of PBX workloads to new infrastructure without
interrupting active calls.\
\
FusionPBX serves as the configuration and management interface, while
FreeSWITCH performs the actual call handling. Kamailio will assume
responsibility for directing new SIP registrations and calls to the
appropriate PBX. This separation allows individual PBX servers to be
replaced while maintaining uninterrupted service.\
\
The process outlined here is designed for production environments and
assumes that the current PBX servers are publicly accessible and
actively handling live traffic.

# Target Architecture and Migration Philosophy

The migration introduces Kamailio as a stable and permanent entry point
for all SIP traffic. Once introduced, endpoints and carriers will
communicate exclusively with Kamailio, which will route requests to
backend FreeSWITCH servers.\
\
The guiding principle is simple:\
\
Existing calls remain anchored on the original PBX.\
New calls are directed to the replacement PBX.\
\
Because SIP sessions remain bound to the server that accepted them, this
approach allows traffic to move naturally without interruption.

# Stage 1 – Existing System Discovery

Before any change is made, the current system must be understood and
verified.\
\
Log into the existing PBX and confirm FreeSWITCH is healthy:\
\
systemctl status freeswitch\
\
Confirm active registrations:\
\
fs_cli -x "show registrations"\
\
Confirm active calls:\
\
fs_cli -x "show channels"\
\
Confirm SIP stack operation:\
\
fs_cli -x "sofia status"\
\
These commands establish confidence that the PBX is stable prior to
migration.

# Stage 2 – Deployment of Kamailio

Install Kamailio on a new Debian server:\
\
apt update\
apt install kamailio kamailio-extra-modules\
\
Kamailio will act as the single public SIP endpoint. Configure the
dispatcher module so Kamailio knows which PBX servers are available.\
\
Edit:\
\
/etc/kamailio/dispatcher.list\
\
Example:\
\
1 sip:PBX_PUBLIC_IP:5060\
\
Restart Kamailio:\
\
systemctl restart kamailio\
\
At this stage Kamailio is operational but not yet carrying production
traffic.

# Stage 3 – Introduction into Production

Kamailio must be introduced carefully so that no registrations or calls
are lost.\
\
If phones use hostnames, update DNS to point to Kamailio.\
\
If phones use IP addresses, update provisioning in FusionPBX so new
registrations use Kamailio.\
\
Carrier trunks should also be redirected to Kamailio.\
\
Once complete, Kamailio becomes the permanent SIP entry point.

# Stage 4 – Backup and Construction of Replacement PBX

From FusionPBX, create a backup:\
\
Advanced → Backup → Backup Now\
\
Install FusionPBX on the new server using the official installer and
restore the backup.\
\
After restore, validate FreeSWITCH:\
\
systemctl status freeswitch\
\
fs_cli -x "sofia status"\
\
This confirms the replacement PBX is fully functional.

# Stage 5 – Migration of Traffic

Update Kamailio dispatcher configuration to include both PBXs.\
\
Reload dispatcher:\
\
kamcmd dispatcher.reload\
\
Disable the original PBX in dispatcher configuration.\
\
New traffic will now flow to the replacement PBX while existing calls
continue on the original server.\
\
Monitor migration:\
\
fs_cli -x "show channels"\
\
When the original PBX has no active calls, migration is complete.

# Stage 6 – Validation

Place inbound and outbound calls.\
\
Verify:\
\
Audio quality\
Registration stability\
Voicemail operation\
Transfers\
\
This confirms the new PBX is operating normally.

# Stage 7 – Rollback Procedure

If any issue is detected, re‑enable the original PBX in the dispatcher
configuration and reload Kamailio.\
\
Traffic will immediately return to the original system.

# Stage 8 – Decommission

After sufficient validation, the original PBX can be shut down safely:\
\
systemctl stop freeswitch\
\
This completes the migration.
