#!/bin/bash
mkdir /home/ubuntu/backups
chmod a+w /home/ubuntu/backups
(crontab -l ; echo "*/5 * * * * mongodump --uri "mongodb://localhost:27017/" --archive="/home/ubuntu/backups/mongodb-backup-'$(date +\%Y-\%m-\%d_\%H-\%M-\%S)'.gz) | crontab -
(crontab -l ; echo "*/5 * * * * aws s3 sync /home/ubuntu/backups/ s3://${bucket}/mongo-backups") | crontab -
