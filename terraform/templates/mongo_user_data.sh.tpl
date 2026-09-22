#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/user-data.log) 2>&1

# Ubuntu 20.04 went EOL in Apr 2025 and the normal mirrors no longer
# carry it. Without this rewrite every apt-get below fails with 404.
sed -i -e 's|archive.ubuntu.com|old-releases.ubuntu.com|g' \
       -e 's|security.ubuntu.com|old-releases.ubuntu.com|g' \
       /etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y gnupg curl awscli cron

# MongoDB 4.4, end of life Feb 2024
curl -fsSL https://www.mongodb.org/static/pgp/server-4.4.asc | apt-key add -
echo "deb [ arch=amd64 ] https://repo.mongodb.org/apt/ubuntu focal/mongodb-org/4.4 multiverse" \
  > /etc/apt/sources.list.d/mongodb-org-4.4.list
apt-get update
apt-get install -y mongodb-org

# xtrace off for everything that touches a password. With it on, set -x
# echoes the expanded command into /var/log/user-data.log, into
# cloud-init-output.log, and into the EC2 console output, which is readable
# through ec2:GetConsoleOutput from anywhere.
set +x

# The application password comes from SSM SecureString, fetched with the
# instance profile. It is never in terraform state and never in user_data.
APP_PWD=$(aws ssm get-parameter --name "${password_parameter}" --with-decryption \
  --region ${region} --query Parameter.Value --output text)
test -n "$APP_PWD" || { echo "FATAL: could not read ${password_parameter} from SSM"; exit 1; }

# The admin account is only used by the local backup script, so its password
# is generated here and never leaves the instance.
ADMIN_PWD=$(openssl rand -hex 24)

# Listen on all interfaces. The security group is what restricts access
# to the private subnets, not bindIp.
sed -i 's/^  bindIp:.*/  bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl enable mongod
systemctl start mongod

# mongod takes a few seconds to accept connections on first boot.
# Bounded so a dead mongod fails the bootstrap instead of hanging forever.
for i in $(seq 1 60); do
  mongo --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1 && break
  sleep 2
done
mongo --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1 || {
  echo "FATAL: mongod did not accept connections within 120s"; exit 1; }

# Users must be created BEFORE auth is switched on, otherwise the
# localhost exception closes and there is no way in.
# Passwords go through files, never through --eval string interpolation:
# a quote or backslash in the SSM value would otherwise break the JS or
# inject into it.
umask 077
printf '%s' "$APP_PWD"   > /tmp/.app_pwd
printf '%s' "$ADMIN_PWD" > /tmp/.admin_pwd

cat > /tmp/.createusers.js <<'JS'
db.getSiblingDB("admin").createUser({
  user: ADMIN_USER_PLACEHOLDER,
  pwd: cat("/tmp/.admin_pwd"),
  roles: ["root"]
});
db.getSiblingDB("notesapp").createUser({
  user: APP_USER_PLACEHOLDER,
  pwd: cat("/tmp/.app_pwd"),
  roles: [{ role: "readWrite", db: "notesapp" }]
});
JS
sed -i -e 's|ADMIN_USER_PLACEHOLDER|"${admin_user}"|' \
       -e 's|APP_USER_PLACEHOLDER|"${app_user}"|' /tmp/.createusers.js

mongo --quiet /tmp/.createusers.js
rm -f /tmp/.createusers.js

cat >> /etc/mongod.conf <<'CONF'
security:
  authorization: enabled
CONF
systemctl restart mongod

cat > /usr/local/bin/mongo-backup.sh <<'SCRIPT'
#!/bin/bash
set -euo pipefail
TS=$(date -u +%Y%m%d-%H%M%S)
ARCHIVE=/tmp/mongo-$TS.archive.gz
# password read from a root-only file, not passed on the command line
# where any local user could see it in ps
mongodump --username=ADMIN_USER --password="$(cat /root/.mongo_admin_pwd)" \
  --authenticationDatabase=admin --archive=$ARCHIVE --gzip
aws s3 cp $ARCHIVE s3://BUCKET_NAME/backups/ --region AWS_REGION
rm -f $ARCHIVE
SCRIPT

printf '%s' "$ADMIN_PWD" > /root/.mongo_admin_pwd
chmod 600 /root/.mongo_admin_pwd
rm -f /tmp/.app_pwd /tmp/.admin_pwd
unset APP_PWD ADMIN_PWD

# injected after the fact so the heredoc above stays literal
sed -i -e "s|ADMIN_USER|${admin_user}|" \
       -e "s|BUCKET_NAME|${bucket_name}|" \
       -e "s|AWS_REGION|${region}|" /usr/local/bin/mongo-backup.sh

chmod 700 /usr/local/bin/mongo-backup.sh
set -x

# EXERCISE REQUIREMENT: daily automated backup to the public bucket
echo "0 ${backup_hour} * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1" \
  > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup
systemctl enable cron && systemctl restart cron

# run once now so the bucket is not empty during the demo
/usr/local/bin/mongo-backup.sh || true
