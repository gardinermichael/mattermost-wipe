#!/bin/bash

# ========================================================================
# README: Mattermost Retention Cleanup Script
#
# FILE NAME & LOCATION:
# - Save this script as: /app/data/mattermost_cleanup.sh
#
# ========================================================================
#
# PURPOSE:
# - Deletes Mattermost posts and files older than 3 years.
# - Queries the MySQL database for outdated entries and removes them.
# - Securely deletes associated files and cleans up empty directories.
# - Logs metadata (total files deleted, breakdown by extension).
#
# ========================================================================
#
# SETUP INSTRUCTIONS:
# 1. Save this file in /app/data/ as 'mattermost_cleanup.sh'
# 2. Grant execution permission:
#    chmod +x /app/data/mattermost_cleanup.sh
# 3. Run manually (optional):
#    /app/data/mattermost_cleanup.sh
#
# ========================================================================
#
# AUTOMATE USING CRON:
# - To run this script **daily at 6 AM**, add this line to crontab:
#   crontab -e
#   0 6 * * * /app/data/mattermost_cleanup.sh
# - To run this script daily at any available time, add this line to crontab:
#   crontab -e
#   @daily /app/data/mattermost_cleanup.sh
# - Verify the cron job is scheduled correctly:
#   crontab -l
# - Check cron logs:
#   grep CRON /var/log/syslog | tail -20
# - Set up a test cron job:
#   crontab -e
#   * * * * * date >> /tmp/cron_test.log
#   cat /tmp/cron_test.log
#
# ========================================================================
#
# LOGGING:
# - A timestamped folder is created each time the script runs:
#   /app/data/WipeLogs/YYYY-MM-DD/cleanup.log
#   /app/data/WipeLogs/YYYY-MM-DD/metadata.log
#
# ========================================================================
#
# TESTING & MONITORING COMMANDS:
# - Run manually:
#   /app/data/mattermost_cleanup.sh
# - Check logs:
#   tail -f "/app/data/WipeLogs/$(date +%Y-%m-%d)/cleanup.log"
# - Check metadata:
#   cat "/app/data/WipeLogs/$(date +%Y-%m-%d)/metadata.log"
#
# ========================================================================

# Set variables
delete_before=$(date --date="3 years ago" "+%s%3N") # Delete files older than 3 years
formatted_delete_before=$(date --date="3 years ago" "+%m/%d/%Y")
DATA_PATH="/app/data/files/"
LOG_PARENT="/app/data/WipeLogs"
LOG_PATH="$LOG_PARENT/$(date +%Y-%m-%d)"
TMP_LIST="/tmp/mattermost-paths.list"
LOG_FILE="$LOG_PATH/cleanup.log"
METADATA_FILE="$LOG_PATH/metadata.log"

# Create log directory
mkdir -p "$LOG_PATH"

echo ""
echo "===== Mattermost Cleanup Job Started at $(date) | Deleting before: $formatted_delete_before =====" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Generate File List
echo "Retrieving outdated file paths from database..." | tee -a "$LOG_FILE"
mysql --user=${CLOUDRON_MYSQL_USERNAME} --password=${CLOUDRON_MYSQL_PASSWORD} \
      --host=${CLOUDRON_MYSQL_HOST} ${CLOUDRON_MYSQL_DATABASE} -e \
      "SELECT path FROM FileInfo WHERE CreateAt < $delete_before;" > "$TMP_LIST"

mysql --user=${CLOUDRON_MYSQL_USERNAME} --password=${CLOUDRON_MYSQL_PASSWORD} \
      --host=${CLOUDRON_MYSQL_HOST} ${CLOUDRON_MYSQL_DATABASE} -e \
      "SELECT thumbnailpath FROM FileInfo WHERE CreateAt < $delete_before;" >> "$TMP_LIST"

mysql --user=${CLOUDRON_MYSQL_USERNAME} --password=${CLOUDRON_MYSQL_PASSWORD} \
      --host=${CLOUDRON_MYSQL_HOST} ${CLOUDRON_MYSQL_DATABASE} -e \
      "SELECT previewpath FROM FileInfo WHERE CreateAt < $delete_before;" >> "$TMP_LIST"

echo "File paths list created: $TMP_LIST" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"

# Delete from Database
echo "Deleting old posts from database..." | tee -a "$LOG_FILE"
mysql --user=${CLOUDRON_MYSQL_USERNAME} --password=${CLOUDRON_MYSQL_PASSWORD} \
      --host=${CLOUDRON_MYSQL_HOST} ${CLOUDRON_MYSQL_DATABASE} -e \
      "DELETE FROM Posts WHERE CreateAt < $delete_before;"
echo "Posts deleted from database." | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"

echo "Deleting old file records from database..." | tee -a "$LOG_FILE"
mysql --user=${CLOUDRON_MYSQL_USERNAME} --password=${CLOUDRON_MYSQL_PASSWORD} \
      --host=${CLOUDRON_MYSQL_HOST} ${CLOUDRON_MYSQL_DATABASE} -e \
      "DELETE FROM FileInfo WHERE CreateAt < $delete_before;"
echo "File records deleted from database." | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"

# Count total number of files
TOTAL_FILES=$(wc -l < "$TMP_LIST")
CURRENT_COUNT=0

# Initialize counters
declare -A EXT_COUNT

# Delete Files Securely & Log Metadata
echo "Deleting old files and collecting metadata..." | tee -a "$LOG_FILE"
while read -r fp; do
    if [ -n "$fp" ]; then
        # Display progress in terminal (overwrites previous output)
        ((CURRENT_COUNT++))
        PROGRESS=$(( CURRENT_COUNT * 100 / TOTAL_FILES ))
        printf "\rProcessing file %d of %d [%d%%]" "$CURRENT_COUNT" "$TOTAL_FILES" "$PROGRESS"
        
        FILE_PATH="$DATA_PATH$fp"
        if [ -f "$FILE_PATH" ]; then
            # Extract file extension (if missing, use "blob")
            EXT="${FILE_PATH##*.}"
            [[ "$FILE_PATH" == "$EXT" ]] && EXT="blob"

            ((EXT_COUNT[$EXT]++))
            
            # Delete file securely
            shred -u "$FILE_PATH"
        fi
    fi
done < "$TMP_LIST"

echo "" | tee -a "$LOG_FILE"
echo "File deletion complete. Total files deleted: $TOTAL_FILES" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Write metadata file
echo "===== Metadata Report for $(date) | Deleting before: $formatted_delete_before =====" > "$METADATA_FILE"
echo "Total files deleted: $TOTAL_FILES" >> "$METADATA_FILE"
echo "" >> "$METADATA_FILE"
echo "File Deletion Breakdown by Extension:" >> "$METADATA_FILE"
for ext in "${!EXT_COUNT[@]}"; do
    echo "  .$ext: ${EXT_COUNT[$ext]} files deleted" >> "$METADATA_FILE"
done

echo "Metadata recorded at: $METADATA_FILE" | tee -a "$LOG_FILE"

# Cleanup
echo "Removing empty directories..." | tee -a "$LOG_FILE"
find "$DATA_PATH" -type d -empty -delete
echo "Cleanup complete." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Remove temporary list from /tmp/
rm "$TMP_LIST"
echo "Temporary file list removed from /tmp/" | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "===== Mattermost Cleanup Job Finished at $(date) =====" | tee -a "$LOG_FILE"
echo ""

# Print metadata file contents to console
cat "$METADATA_FILE"
echo ""
exit 0
