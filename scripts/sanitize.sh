#!/usr/bin/env bash
sed -E \
  -e 's/[A-Za-z0-9+\/]{43}=/<REDACTED-KEY>/g' \
  -e 's/(password|passwd|private-key|preshared-key|secret)=("[^"]*"|[^ ]+)/\1=<REDACTED>/Ig' \
  -e 's/\$6\$[A-Za-z0-9.\/$]+/<REDACTED-HASH>/g' \
  -e 's/ssh-(ed25519|rsa) [A-Za-z0-9+\/=]+( [^ ]+)?/ssh-\1 <REDACTED-PUBKEY>/g'
