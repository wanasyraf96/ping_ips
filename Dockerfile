FROM alpine:latest

# Install cron and bash (if needed)
RUN apk add --no-cache curl bash busybox-suid

# Set working directory
WORKDIR /app

# Copy your script
COPY ping.sh .

# Make script executable
RUN chmod +x /app/ping.sh

# Add crontab entry
RUN echo "1/15 * * * * /app/ping.sh >> /var/log/cron.log 2>&1" > /etc/crontabs/root

# Start cron in foreground
CMD ["crond", "-f", "-L", "/var/log/cron.log"]
