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

# Listen on all interfaces. The security group is what restricts access
# to the private subnets, not bindIp.
sed -i 's/^  bindIp:.*/  bindIp: 0.0.0.0/' /etc/mongod.conf

systemctl enable mongod
systemctl start mongod

# mongod takes a few seconds to accept connections on first boot
until mongo --quiet --eval 'db.runCommand({ping:1})' >/dev/null 2>&1; do sleep 2; done

# Users must be created BEFORE auth is switched on, otherwise the
# localhost exception closes and there is no way in.
mongo admin --quiet --eval 'db.createUser({user:"${admin_user}",pwd:"${admin_password}",roles:["root"]})'
mongo notesapp --quiet --eval 'db.createUser({user:"${app_user}",pwd:"${app_password}",roles:[{role:"readWrite",db:"notesapp"}]})'

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
mongodump --username=ADMIN_USER --password=ADMIN_PASSWORD \
  --authenticationDatabase=admin --archive=$ARCHIVE --gzip
aws s3 cp $ARCHIVE s3://BUCKET_NAME/backups/ --region AWS_REGION
rm -f $ARCHIVE
SCRIPT

# injected after the fact so the heredoc above stays literal
sed -i -e "s|ADMIN_USER|${admin_user}|" \
       -e "s|ADMIN_PASSWORD|${admin_password}|" \
       -e "s|BUCKET_NAME|${bucket_name}|" \
       -e "s|AWS_REGION|${region}|" /usr/local/bin/mongo-backup.sh

chmod 700 /usr/local/bin/mongo-backup.sh

# EXERCISE REQUIREMENT: daily automated backup to the public bucket
echo "0 ${backup_hour} * * * root /usr/local/bin/mongo-backup.sh >> /var/log/mongo-backup.log 2>&1" \
  > /etc/cron.d/mongo-backup
chmod 644 /etc/cron.d/mongo-backup
systemctl enable cron && systemctl restart cron

# run once now so the bucket is not empty during the demo
/usr/local/bin/mongo-backup.sh || true
