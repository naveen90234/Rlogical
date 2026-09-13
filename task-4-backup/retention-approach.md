# Backup Retention Approach

## Decision: AWS S3 Lifecycle Policy (Primary)

### Why S3 Lifecycle Policy over Script-Based Deletion

| Factor | S3 Lifecycle Policy | Script-Based Deletion |
|---|---|---|
| Reliability | Managed by AWS — always runs | Depends on cron + script succeeding |
| Cost | Free AWS feature | Requires compute time |
| Maintenance | Zero maintenance | Script must be maintained |
| Race conditions | None | Possible if script runs during upload |
| Audit trail | S3 event logs | Requires separate logging |
| Failure impact | AWS retries internally | Silent failure if cron/script fails |

The S3 Lifecycle Policy is the preferred approach because it is fully managed, runs independently of the backup server, and requires no additional maintenance. Script-based retention is included in `backup.sh` as a **fallback only** for environments where Lifecycle Policies cannot be configured.

---

## S3 Lifecycle Policy Configuration

### What It Does
- Automatically deletes objects under the `mysql-backups/` prefix after **7 days**.
- Applied at the bucket level — no ongoing management required.

### JSON Configuration

Save the following as `lifecycle-policy.json` and apply it to your S3 bucket:

```json
{
  "Rules": [
    {
      "ID": "mysql-backup-7day-retention",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "mysql-backups/"
      },
      "Expiration": {
        "Days": 7
      },
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 1
      }
    }
  ]
}
```

### Apply the Policy via AWS CLI

```bash
aws s3api put-bucket-lifecycle-configuration \
  --bucket <YOUR_S3_BUCKET_NAME> \
  --lifecycle-configuration file://lifecycle-policy.json \
  --region <YOUR_AWS_REGION>
```

Replace `<YOUR_S3_BUCKET_NAME>` and `<YOUR_AWS_REGION>` with your actual values.

### Verify the Policy Was Applied

```bash
aws s3api get-bucket-lifecycle-configuration \
  --bucket <YOUR_S3_BUCKET_NAME> \
  --region <YOUR_AWS_REGION>
```

### Apply via AWS Console

1. Go to **S3 → Your Bucket → Management → Lifecycle rules**.
2. Click **Create lifecycle rule**.
3. Rule name: `mysql-backup-7day-retention`
4. Prefix filter: `mysql-backups/`
5. Under **Lifecycle rule actions**, select **Expire current versions of objects**.
6. Set **Days after object creation**: `7`
7. Save the rule.

---

## Script-Based Retention (Fallback)

The `backup.sh` script includes an `enforce_retention_script()` function that:

1. Lists all objects under `mysql-backups/<database>/` in S3.
2. Filters objects with a `LastModified` date older than 7 days.
3. Deletes each expired object using `aws s3 rm`.

This runs automatically at the end of every backup execution.

### When to Use Script-Based Retention
- Environments where S3 Lifecycle Policies are restricted by IAM policy.
- Testing and development environments.
- When fine-grained per-database retention rules are needed without multiple lifecycle rules.

### Required IAM Permission for Script-Based Deletion

In addition to the standard backup permissions, the IAM role also needs:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::<YOUR_S3_BUCKET_NAME>",
    "arn:aws:s3:::<YOUR_S3_BUCKET_NAME>/mysql-backups/*"
  ]
}
```

---

## Recommended IAM Policy for the EC2 Instance Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "MySQLBackupS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::<YOUR_S3_BUCKET_NAME>",
        "arn:aws:s3:::<YOUR_S3_BUCKET_NAME>/mysql-backups/*"
      ]
    }
  ]
}
```

No AWS Access Keys or Secret Keys are stored on the server. Authentication is handled entirely through the EC2 IAM Instance Profile.
