# Task 4 — MySQL Backup Automation to AWS S3

## Overview

Bash script that takes a MySQL database backup, compresses it with gzip, uploads it to AWS S3, and enforces a 7-day retention policy. AWS authentication uses the EC2 IAM Instance Role — no credentials are hard-coded.

## Files

| File | Description |
|---|---|
| `backup.sh` | Main backup script — dump, compress, upload, retain |
| `retention-approach.md` | S3 Lifecycle Policy design decision and IAM policy |
| `lifecycle.json` | S3 Lifecycle Policy JSON ready to apply |

## Required Environment Variables

| Variable | Default | Required | Description |
|---|---|---|---|
| `MYSQL_HOST` | `localhost` | No | MySQL server hostname or IP |
| `MYSQL_PORT` | `3306` | No | MySQL port |
| `MYSQL_DATABASE` | — | **Yes** | Database name to back up |
| `MYSQL_USER` | — | **Yes** | MySQL username |
| `MYSQL_PASSWORD` | — | **Yes** | MySQL password |
| `S3_BUCKET` | — | **Yes** | S3 bucket name |
| `AWS_REGION` | `us-east-1` | No | AWS region |
| `BACKUP_DIR` | `/tmp/db_backups` | No | Local staging directory |

## Required Dependencies

```bash
sudo apt-get update
sudo apt-get install -y mysql-client gzip

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
```

## Required IAM Permissions (EC2 Instance Role)

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ],
    "Resource": [
      "arn:aws:s3:::YOUR_BUCKET_NAME",
      "arn:aws:s3:::YOUR_BUCKET_NAME/mysql-backups/*"
    ]
  }]
}
```

No AWS Access Key or Secret Key is stored. Authentication is via the EC2 IAM Instance Profile.

## Configure the Script

```bash
export MYSQL_HOST="localhost"
export MYSQL_PORT="3306"
export MYSQL_DATABASE="myappdb"
export MYSQL_USER="backup_user"
export MYSQL_PASSWORD="your_password"
export S3_BUCKET="your-backup-bucket"
export AWS_REGION="us-east-1"
```

## Execute the Script

```bash
chmod +x task-4-backup/backup.sh
./task-4-backup/backup.sh
```

## Automate with Cron (Daily at 2 AM)

```bash
crontab -e
# Add the following line:
0 2 * * * /opt/scripts/backup.sh >> /var/log/mysql-backup.log 2>&1
```

## Verify Backup Was Created

```bash
# List backups in S3
aws s3 ls s3://your-backup-bucket/mysql-backups/myappdb/ --region us-east-1
```

## Verify Backup Was Uploaded to S3

```bash
aws s3api head-object \
  --bucket your-backup-bucket \
  --key "mysql-backups/myappdb/myappdb_20260913_020000.sql.gz" \
  --region us-east-1
```

## Verify Backup is Valid

```bash
# Download and inspect
aws s3 cp s3://your-backup-bucket/mysql-backups/myappdb/<filename>.sql.gz /tmp/
gunzip -c /tmp/<filename>.sql.gz | head -20
# Expected: -- MySQL dump 10.x header lines
```

## Backup Retention (7 Days)

Preferred approach: **S3 Lifecycle Policy** — fully managed by AWS, zero maintenance.

```bash
# Apply lifecycle policy
aws s3api put-bucket-lifecycle-configuration \
  --bucket your-backup-bucket \
  --lifecycle-configuration file://task-4-backup/lifecycle.json \
  --region us-east-1
```

See `retention-approach.md` for full details and the script-based fallback.

## Failure Handling

- `set -euo pipefail` — exits immediately on any unhandled error
- Partial dump files are deleted on failure
- Each critical step (dump, upload) has explicit error checking
- Non-zero exit code returned on any critical failure
- Cron output captured in log file for auditing
